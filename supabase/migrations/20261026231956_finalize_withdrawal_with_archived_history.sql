-- Terminal withdrawal: archive the removed operational records, then close
-- the student's bookings and usable rights without historical-conflict vetoes.
create table private.student_withdrawal_finalization_archives (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete restrict,
  withdrawal_date date not null,
  actor_id uuid,
  created_at timestamptz not null default pg_catalog.now(),
  student_snapshot jsonb not null,
  rights_snapshot jsonb not null,
  legacy_credits_snapshot jsonb not null,
  assignments_snapshot jsonb not null,
  series_snapshot jsonb not null,
  slots_snapshot jsonb not null,
  plans_snapshot jsonb not null
);
alter table private.student_withdrawal_finalization_archives enable row level security;
revoke all on private.student_withdrawal_finalization_archives
  from public, anon, authenticated, service_role;
create index student_withdrawal_finalization_archives_student_idx
  on private.student_withdrawal_finalization_archives(student_id, created_at);

alter table private.student_withdrawal_lesson_snapshots
  add column finalization_id uuid references private.student_withdrawal_finalization_archives(id)
    on delete restrict;
create index student_withdrawal_lesson_snapshots_finalization_idx
  on private.student_withdrawal_lesson_snapshots(finalization_id)
  where finalization_id is not null;

create function private.protect_withdrawal_finalization_archive()
returns trigger language plpgsql set search_path = '' as $archive_guard$
begin
  if tg_table_name = 'student_withdrawal_finalization_archives' then
    raise exception using errcode='P0001', message='FORESTRING_WITHDRAWAL_ARCHIVE_IMMUTABLE';
  end if;
  if old.finalization_id is not null then
    raise exception using errcode='P0001', message='FORESTRING_WITHDRAWAL_ARCHIVE_IMMUTABLE';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$archive_guard$;
revoke all on function private.protect_withdrawal_finalization_archive()
  from public, anon, authenticated, service_role;
create trigger protect_student_withdrawal_finalization_archive
  before update or delete on private.student_withdrawal_finalization_archives
  for each row execute function private.protect_withdrawal_finalization_archive();
create trigger protect_finalized_student_withdrawal_lesson_snapshot
  before update or delete on private.student_withdrawal_lesson_snapshots
  for each row execute function private.protect_withdrawal_finalization_archive();

create function private.archive_student_withdrawal_finalization(
  p_student_id uuid, p_withdrawal_date date, p_actor_id uuid
)
returns uuid language plpgsql security definer set search_path = '' as $archive$
declare v_id uuid;
begin
  insert into private.student_withdrawal_finalization_archives(
    student_id, withdrawal_date, actor_id, student_snapshot, rights_snapshot, legacy_credits_snapshot,
    assignments_snapshot, series_snapshot, slots_snapshot, plans_snapshot
  )
  select p_student_id, p_withdrawal_date, p_actor_id,
    jsonb_build_object(
      'student', to_jsonb(s),
      'profile', jsonb_build_object('id',p.id,'branch_id',p.branch_id,'is_active',p.is_active),
      'enrollmentPeriods', coalesce((select jsonb_agg(to_jsonb(ep) order by ep.starts_on,ep.id)
        from public.student_enrollment_periods ep where ep.student_id=p_student_id),'[]'::jsonb)
    ),
    coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from public.lesson_rights r
      where r.student_id=p_student_id),'[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(cr) order by cr.id) from public.lesson_rebooking_credits cr
      where cr.student_id=p_student_id),'[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(a) order by a.id) from public.teacher_student_assignments a
      where a.student_id=p_student_id),'[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(ls) order by ls.id) from public.lesson_series ls
      where ls.student_id=p_student_id),'[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(rs) order by rs.id) from public.regular_schedule_slots rs
      where rs.student_id=p_student_id),'[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(sp) order by sp.id) from public.student_semester_plans sp
      where sp.student_id=p_student_id),'[]'::jsonb)
  from public.students s join public.profiles p on p.id=s.id where s.id=p_student_id
  returning id into v_id;
  if v_id is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  -- Existing preclear snapshots are retained verbatim. They become finalized,
  -- never restored and never used to overwrite a right's current state.
  update private.student_withdrawal_lesson_snapshots
  set finalization_id=v_id, closed_at=pg_catalog.now(), resolution='finalized',
      resolution_detail='terminal_withdrawal_existing_reservation'
  where student_id=p_student_id and closed_at is null;

  insert into private.student_withdrawal_lesson_snapshots(
    student_id, lesson_id, withdrawal_date, starts_at, lesson_snapshot,
    lesson_right_id, lesson_right_snapshot, manual_makeup_right_id,
    manual_makeup_right_snapshot, closed_at, resolution, resolution_detail, finalization_id
  )
  select p_student_id,l.id,p_withdrawal_date,l.starts_at,to_jsonb(l),
    l.lesson_right_id,to_jsonb(r),l.manual_makeup_right_id,to_jsonb(mr),
    pg_catalog.now(),'finalized','terminal_withdrawal_removed_lesson',v_id
  from public.lessons l
  left join public.lesson_rights r on r.id=l.lesson_right_id
  left join public.lesson_rights mr on mr.id=l.manual_makeup_right_id
  where l.student_id=p_student_id
    and l.starts_at >= p_withdrawal_date::timestamp at time zone 'Asia/Seoul';
  return v_id;
end;
$archive$;
revoke all on function private.archive_student_withdrawal_finalization(uuid,date,uuid)
  from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.finalize_student_withdrawal(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_branch_id uuid;
  v_student_status public.student_status;
  v_withdrawal_date date;

  v_today date;
  v_cutoff timestamptz;
  v_finalization_id uuid;
  v_invalidated_consumed_right_count integer := 0;
  v_expired_legacy_credit_count integer := 0;

  v_future_lesson_ids uuid[] :=
    '{}'::uuid[];

  v_deleted_lesson_count integer := 0;
  v_actual_deleted_lesson_count integer := 0;

  v_preserved_cancellation_count integer := 0;
  v_deleted_legacy_credit_count integer := 0;

  v_consumed_right_count integer := 0;
  v_revoked_right_count integer := 0;

  v_closed_assignment_count integer := 0;
  v_deleted_future_assignment_count integer := 0;

  v_closed_series_count integer := 0;
  v_deleted_future_series_count integer := 0;
  v_tombstoned_future_series_count integer := 0;

  v_closed_slot_count integer := 0;
  v_tombstoned_future_slot_count integer := 0;
begin

  -- ==========================================================
  -- 1. ACTOR AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then

    if session_user <> 'postgres'
       or pg_catalog.current_setting(
            'forestring.system_withdrawal',
            true
          ) is distinct from 'cron' then

      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_AUTH_REQUIRED';

    end if;


    -- Reuse the existing master authorization branch without
    -- attributing the automated action to a human profile.
    v_actor_role :=
      'master'::public.user_role;

  else

    perform private.require_effective_actor(
      v_actor_id
    );


    select p.role
    into v_actor_role

    from public.profiles p

    where p.id =
          v_actor_id

      and p.is_active = true;


    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_ACTIVE_USER_REQUIRED';
    end if;


    if v_actor_role not in (
      'master'::public.user_role,
      'manager'::public.user_role
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN';

    end if;

  end if;


  -- ==========================================================
  -- 2. LOCK STUDENT + PROFILE
  --
  -- Subject profile may already be inactive on a repeated call,
  -- so do NOT filter p.is_active here.
  -- ==========================================================

  select
    p.branch_id,
    s.status,
    s.withdrawal_date

  into
    v_branch_id,
    v_student_status,
    v_withdrawal_date

  from public.students s

  join public.profiles p
    on p.id = s.id

  where s.id =
        p_student_id

  for update of s, p;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;


  if v_branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;


  -- ==========================================================
  -- 3. MANAGER BRANCH
  -- ==========================================================

  if v_actor_role =
     'manager'::public.user_role
     and not private.manager_has_branch(
       v_branch_id
     ) then

    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

  end if;


  -- ==========================================================
  -- 4. IDEMPOTENT ALREADY-WITHDRAWN CALL
  -- ==========================================================

  if v_student_status =
     'withdrawn'::public.student_status then

    return jsonb_build_object(
      'changed',
        false,

      'studentId',
        p_student_id,

      'withdrawalDate',
        v_withdrawal_date,

      'deletedLessonCount',
        0,

      'revokedRightCount',
        0
    );

  end if;


  if v_student_status <>
     'active'::public.student_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_WITHDRAWAL_INVALID_STATE';

  end if;


  -- ==========================================================
  -- 5. WITHDRAWAL MUST HAVE BEEN SCHEDULED
  -- ==========================================================

  if v_withdrawal_date is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_WITHDRAWAL_DATE_REQUIRED';
  end if;


  v_today :=
    (
      pg_catalog.now()
      at time zone 'Asia/Seoul'
    )::date;


  if v_withdrawal_date >
     v_today then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_WITHDRAWAL_NOT_READY';

  end if;


  -- 00:00 KST on the effective withdrawal date.
  --
  -- starts_at >= this timestamp is no longer a real lesson.
  v_cutoff :=
    (
      v_withdrawal_date::timestamp
      at time zone 'Asia/Seoul'
    );


  -- Keep the legacy actor/cron checks and response contract. Serialize new
  -- terminal work without reversing the existing plan -> student lock order.
  perform 1 from public.student_semester_plans sp
    where sp.student_id=p_student_id for update nowait;
  perform 1 from public.student_enrollment_periods ep
    where ep.student_id=p_student_id for update nowait;
  perform 1 from public.lessons l
    where l.student_id=p_student_id for update nowait;
  perform 1 from public.teacher_student_assignments a
    where a.student_id=p_student_id for update nowait;
  perform 1 from public.lesson_series ls
    where ls.student_id=p_student_id for update nowait;
  perform 1 from public.regular_schedule_slots rs
    where rs.student_id=p_student_id for update nowait;
  perform 1 from private.student_withdrawal_lesson_snapshots snap
    where snap.student_id=p_student_id and snap.closed_at is null for update nowait;
  perform 1 from public.lesson_rights r
    where r.student_id=p_student_id for update nowait;

  v_finalization_id := private.archive_student_withdrawal_finalization(
    p_student_id,v_withdrawal_date,v_actor_id
  );

  -- ==========================================================
  -- 6. LOCK FUTURE ACTUAL LESSONS
  --
  -- Actual starts_at is authoritative.
  -- occurrence_at is NOT used for withdrawal deletion.
  -- ==========================================================

  perform 1

  from public.lessons l

  where l.student_id =
        p_student_id

    and l.starts_at >=
        v_cutoff

  for update;


  select
    coalesce(
      array_agg(
        l.id
        order by l.starts_at, l.id
      ),
      '{}'::uuid[]
    ),

    count(*)::integer

  into
    v_future_lesson_ids,
    v_deleted_lesson_count

  from public.lessons l

  where l.student_id =
        p_student_id

    and l.starts_at >=
        v_cutoff;


  -- ==========================================================
  -- 7. REMOVE DEPENDENCIES OF FUTURE LESSONS
  --
  -- Cancellation ledger rows for lessons that are being
  -- physically removed are also removed.
  --
  -- Audit events remain immutable and untouched.
  -- ==========================================================

  select count(*)::integer
  into v_preserved_cancellation_count

  from public.lesson_cancellation_events e

  where e.lesson_id =
        any(v_future_lesson_ids);


  -- Cancellation events are immutable historical records.
  -- Their lesson_id remains as the deleted lesson's UUID.
  --
  -- Legacy compatibility table still has ON DELETE RESTRICT
  -- against lessons. Remove only rows whose source lesson is
  -- itself being removed by withdrawal.
  delete from public.lesson_rebooking_credits c

  where c.source_lesson_id =
        any(v_future_lesson_ids);


  get diagnostics
    v_deleted_legacy_credit_count =
      row_count;

  -- Deprecated credits can still exist as migration history. They must not
  -- remain available after the student's terminal withdrawal either.
  update public.lesson_rebooking_credits
  set status='expired'::public.rebooking_credit_status,
      expires_at=least(coalesce(expires_at,pg_catalog.now()),pg_catalog.now())
  where student_id=p_student_id and status='available'::public.rebooking_credit_status;
  get diagnostics v_expired_legacy_credit_count=row_count;


  -- ==========================================================
  -- 8. HARD DELETE FUTURE LESSONS
  -- ==========================================================

  delete from public.lessons l

  where l.id =
        any(v_future_lesson_ids);


  get diagnostics
    v_actual_deleted_lesson_count =
      row_count;


  -- Guard against concurrent / unexpected count mismatch.
  if v_actual_deleted_lesson_count <>
     v_deleted_lesson_count then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_WITHDRAWAL_LESSON_DELETE_COUNT_MISMATCH';

  end if;


  -- A past/manual lesson or a held preclear reservation may have marked a
  -- right consumed. If terminal withdrawal removes its only actual use,
  -- retire that right instead of retaining an orphaned consumption.
  update public.lesson_rights r
  set status='revoked'::public.lesson_right_status,
      reserved_at=null, consumed_at=null,
      revoked_at=coalesce(r.revoked_at,pg_catalog.now())
  where r.student_id=p_student_id
    and r.status='consumed'::public.lesson_right_status
    and exists (
      select 1 from private.student_withdrawal_lesson_snapshots snap
      where snap.finalization_id=v_finalization_id
        and (snap.lesson_right_id=r.id or snap.manual_makeup_right_id=r.id)
    )
    and not exists (
      select 1 from public.lessons l
      where l.student_id=p_student_id
        and l.status='scheduled'::public.lesson_status
        and l.starts_at < v_cutoff
        and (l.lesson_right_id=r.id or l.manual_makeup_right_id=r.id)
    );
  get diagnostics v_invalidated_consumed_right_count=row_count;

  -- ==========================================================
  -- 9. FINALIZE PAST RESERVED RIGHTS
  --
  -- A reserved entitlement with a remaining scheduled lesson
  -- before withdrawal represents a lesson that belongs to the
  -- preserved historical side of the boundary.
  --
  -- This mirrors semester finalization semantics.
  -- ==========================================================

  update public.lesson_rights r

  set
    status =
      'consumed'::public.lesson_right_status,

    consumed_at =
      coalesce(
        r.consumed_at,
        pg_catalog.now()
      )

  where r.student_id =
        p_student_id

    and r.status =
        'reserved'::public.lesson_right_status

    and exists (
      select 1

      from public.lessons l

      where l.lesson_right_id =
            r.id

        and l.student_id =
            p_student_id

        and l.status =
            'scheduled'::public.lesson_status

        and l.starts_at <
            v_cutoff
    );


  get diagnostics
    v_consumed_right_count =
      row_count;


  -- ==========================================================
  -- 10. REVOKE EVERY REMAINING ACTIVE ENTITLEMENT
  --
  -- After withdrawal:
  --   available -> cannot be used
  --   dangling/future reserved -> cannot be used
  --
  -- consumed / expired / already revoked remain historical.
  -- ==========================================================

  update public.lesson_rights r

  set
    status =
      'revoked'::public.lesson_right_status,

    reserved_at = null,

    revoked_at =
      coalesce(
        r.revoked_at,
        pg_catalog.now()
      )

  where r.student_id =
        p_student_id

    and r.status in (
      'available'::public.lesson_right_status,
      'reserved'::public.lesson_right_status
    );


  get diagnostics
    v_revoked_right_count =
      row_count;
  v_revoked_right_count := v_revoked_right_count + v_invalidated_consumed_right_count;


  -- ==========================================================
  -- 11. ASSIGNMENT HISTORY
  --
  -- Historical assignment before withdrawal remains.
  --
  -- Any assignment that had not even started yet is discarded.
  -- ==========================================================

  delete from public.teacher_student_assignments a

  where a.student_id =
        p_student_id

    and a.starts_on >=
        v_withdrawal_date;


  get diagnostics
    v_deleted_future_assignment_count =
      row_count;


  update public.teacher_student_assignments a

  set
    ends_on =
      v_withdrawal_date - 1

  where a.student_id =
        p_student_id

    and a.starts_on <
        v_withdrawal_date

    and (
      a.ends_on is null
      or a.ends_on >=
         v_withdrawal_date
    );


  get diagnostics
    v_closed_assignment_count =
      row_count;


  -- ==========================================================
  -- 12. REGULAR SERIES
  --
  -- Past/current recurring rules are closed the day before
  -- withdrawal.
  --
  -- Pure future versions with no remaining historical
  -- dependency are removed.
  -- ==========================================================

  update public.lesson_series ls

  set
    effective_until =
      v_withdrawal_date - 1

  where ls.student_id =
        p_student_id

    and ls.effective_from <
        v_withdrawal_date

    and (
      ls.effective_until is null
      or ls.effective_until >=
         v_withdrawal_date
    );


  get diagnostics
    v_closed_series_count =
      row_count;


  delete from public.lesson_series ls

  where ls.student_id =
        p_student_id

    and ls.effective_from >=
        v_withdrawal_date

    -- A one-off lesson moved to BEFORE withdrawal may still
    -- legitimately retain this historical series identity.
    and not exists (
      select 1
      from public.lessons l
      where l.series_id =
            ls.id
    )

    -- Temporary legacy compatibility safety.
    and not exists (
      select 1
      from public.lesson_rebooking_credits c
      where c.source_series_id =
            ls.id
    );


  get diagnostics
    v_deleted_future_series_count =
      row_count;


  -- Rare case:
  -- a future series survives because a preserved historical
  -- lesson/legacy row still references its identity.
  --
  -- Prevent it from remaining open-ended.
  update public.lesson_series ls

  set
    effective_until =
      ls.effective_from

  where ls.student_id =
        p_student_id

    and ls.effective_from >=
        v_withdrawal_date

    and (
      ls.effective_until is null
      or ls.effective_until >
         ls.effective_from
    );


  get diagnostics
    v_tombstoned_future_series_count =
      row_count;


  -- ==========================================================
  -- 13. LOGICAL REGULAR SLOTS
  --
  -- Existing slots close on withdrawal - 1.
  --
  -- Future slot rows may still be referenced by revoked rights,
  -- so they are retained as historical planned identities but
  -- bounded to one day rather than left open-ended.
  --
  -- Reactivation will create/select a fresh valid schedule
  -- instead of silently reviving these old plans.
  -- ==========================================================

  update public.regular_schedule_slots rs

  set
    ends_on =
      v_withdrawal_date - 1

  where rs.student_id =
        p_student_id

    and rs.starts_on <
        v_withdrawal_date

    and (
      rs.ends_on is null
      or rs.ends_on >=
         v_withdrawal_date
    );


  get diagnostics
    v_closed_slot_count =
      row_count;


  update public.regular_schedule_slots rs

  set
    ends_on =
      rs.starts_on

  where rs.student_id =
        p_student_id

    and rs.starts_on >=
        v_withdrawal_date

    and (
      rs.ends_on is null
      or rs.ends_on >
         rs.starts_on
    );


  get diagnostics
    v_tombstoned_future_slot_count =
      row_count;


  -- ==========================================================
  -- 14. STUDENT / PROFILE STATE
  -- ==========================================================

  update public.students
  set
    status =
      'withdrawn'::public.student_status

  where id =
        p_student_id;


  update public.profiles
  set
    is_active =
      false

  where id =
        p_student_id;


  -- ==========================================================
  -- 15. IMMUTABLE HIGH-LEVEL AUDIT
  --
  -- Lessons themselves are intentionally gone, but the admin
  -- action and deletion summary remain visible.
  -- ==========================================================

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    p_student_id,
    v_branch_id,
    null,
    'STUDENT_WITHDRAWAL_FINALIZED',
    v_withdrawal_date,
    v_actor_id,

    jsonb_build_object(
      'executionSource',
        case
          when v_actor_id is null then
            'system_cron'
          else
            'staff'
        end,

      'withdrawalDate',
        v_withdrawal_date,

      'deletedLessonCount',
        v_deleted_lesson_count,

      'deletedLessonIds',
        to_jsonb(
          v_future_lesson_ids
        ),

      'finalizationId', v_finalization_id,
      'invalidatedConsumedRightCount', v_invalidated_consumed_right_count,
      'expiredLegacyCreditCount', v_expired_legacy_credit_count,
      'preservedCancellationEventCount',
        v_preserved_cancellation_count,

      'deletedLegacyCreditCount',
        v_deleted_legacy_credit_count,

      'consumedHistoricalRightCount',
        v_consumed_right_count,

      'revokedRightCount',
        v_revoked_right_count,

      'closedAssignmentCount',
        v_closed_assignment_count,

      'deletedFutureAssignmentCount',
        v_deleted_future_assignment_count,

      'closedRegularSeriesCount',
        v_closed_series_count,

      'deletedFutureSeriesCount',
        v_deleted_future_series_count,

      'tombstonedFutureSeriesCount',
        v_tombstoned_future_series_count,

      'closedRegularSlotCount',
        v_closed_slot_count,

      'tombstonedFutureSlotCount',
        v_tombstoned_future_slot_count
    )
  );


  -- ==========================================================
  -- 16. RESULT
  -- ==========================================================

  return jsonb_build_object(
    'changed',
      true,

    'studentId',
      p_student_id,

    'withdrawalDate',
      v_withdrawal_date,

    'deletedLessonCount',
      v_deleted_lesson_count,

    'finalizationId', v_finalization_id,
      'invalidatedConsumedRightCount', v_invalidated_consumed_right_count,
      'expiredLegacyCreditCount', v_expired_legacy_credit_count,
      'preservedCancellationEventCount',
      v_preserved_cancellation_count,

    'deletedLegacyCreditCount',
      v_deleted_legacy_credit_count,

    'consumedHistoricalRightCount',
      v_consumed_right_count,

    'revokedRightCount',
      v_revoked_right_count,

    'closedAssignmentCount',
      v_closed_assignment_count,

    'deletedFutureAssignmentCount',
      v_deleted_future_assignment_count,

    'closedRegularSeriesCount',
      v_closed_series_count,

    'deletedFutureSeriesCount',
      v_deleted_future_series_count,

    'tombstonedFutureSeriesCount',
      v_tombstoned_future_series_count,

    'closedRegularSlotCount',
      v_closed_slot_count,

    'tombstonedFutureSlotCount',
      v_tombstoned_future_slot_count
  );

exception when lock_not_available then
  raise exception using errcode='P0001', message='FORESTRING_STUDENT_SETTLEMENT_BUSY';
end;
$function$
;

revoke all on function public.finalize_student_withdrawal(uuid) from public,anon;
grant execute on function public.finalize_student_withdrawal(uuid) to authenticated,service_role;

create or replace function public.schedule_student_withdrawal(
  p_student_id uuid, p_withdrawal_date date
)
returns jsonb language plpgsql security definer set search_path = '' as $schedule$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_branch_id uuid;
  v_status public.student_status;
  v_current_withdrawal_date date;
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_enrollment_start date;
  v_result jsonb;
  v_restore_before timestamptz;
  v_preclear jsonb := jsonb_build_object('deletedLessonCount',0,'deletedLessonIds','[]'::jsonb);
  v_restore jsonb := jsonb_build_object('restoredLessonCount',0,'creditedLessonCount',0,'unrestoredLessonCount',0);
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;
  perform private.require_effective_actor(v_actor_id);
  select p.role into v_actor_role from public.profiles p
    where p.id=v_actor_id and p.is_active=true;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_USER_REQUIRED';
  end if;
  if v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN';
  end if;
  if p_withdrawal_date is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_WITHDRAWAL_DATE_REQUIRED';
  end if;
  select p.branch_id,s.status,s.withdrawal_date
    into v_branch_id,v_status,v_current_withdrawal_date
  from public.students s join public.profiles p on p.id=s.id
  where s.id=p_student_id for update of s,p;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;
  if v_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;
  if v_actor_role='manager'::public.user_role and not private.manager_has_branch(v_branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;
  if v_status='withdrawn'::public.student_status
     and v_current_withdrawal_date=p_withdrawal_date and p_withdrawal_date<=v_today then
    return public.finalize_student_withdrawal(p_student_id)
      || jsonb_build_object('finalized',true,'previousWithdrawalDate',v_current_withdrawal_date);
  end if;
  if v_status<>'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_ACTIVE';
  end if;

  if p_withdrawal_date<=v_today then
    select ep.starts_on into v_enrollment_start
    from public.student_enrollment_periods ep where ep.student_id=p_student_id
    order by ep.starts_on desc,ep.created_at desc limit 1 for update nowait;
    if not found then
      raise exception using errcode='P0001', message='FORESTRING_ENROLLMENT_PERIOD_REQUIRED';
    end if;
    if p_withdrawal_date<=v_enrollment_start then
      raise exception using errcode='P0001', message='FORESTRING_STUDENT_WITHDRAWAL_BEFORE_ENROLLMENT',
        detail=jsonb_build_object('earliestWithdrawalDate',v_enrollment_start+1)::text;
    end if;
    -- No lesson/assignment/schedule/completed-semester history vetoes.
    -- Never restore old reservations on the terminal path.
    update public.students set withdrawal_date=p_withdrawal_date where id=p_student_id;
    if v_current_withdrawal_date is distinct from p_withdrawal_date then
      insert into public.audit_events(
        subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
      ) values (
        p_student_id,v_branch_id,null,'STUDENT_WITHDRAWAL_SCHEDULED',p_withdrawal_date,v_actor_id,
        jsonb_build_object('previousWithdrawalDate',v_current_withdrawal_date,
          'withdrawalDate',p_withdrawal_date,'policy','terminal_archived_history')
      );
    end if;
    v_result:=public.finalize_student_withdrawal(p_student_id);
    return v_result || jsonb_build_object('finalized',true,
      'previousWithdrawalDate',v_current_withdrawal_date,
      'restoredLessonCount',0,'creditedLessonCount',0,'unrestoredLessonCount',0);
  end if;

  -- Future withdrawal reservations retain their reversible preclear semantics.
  update public.students set withdrawal_date=p_withdrawal_date where id=p_student_id;
  if v_current_withdrawal_date is not null and p_withdrawal_date>v_current_withdrawal_date then
    v_restore_before:=p_withdrawal_date::timestamp at time zone 'Asia/Seoul';
    v_restore:=private.restore_student_withdrawal_snapshots(
      p_student_id,v_restore_before,v_actor_id,'withdrawal_date_moved_later'
    );
  end if;
  v_preclear:=private.preclear_student_withdrawal_lessons(p_student_id,p_withdrawal_date);
  if v_current_withdrawal_date is distinct from p_withdrawal_date then
    insert into public.audit_events(
      subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
    ) values (
      p_student_id,v_branch_id,null,'STUDENT_WITHDRAWAL_SCHEDULED',p_withdrawal_date,v_actor_id,
      jsonb_build_object('previousWithdrawalDate',v_current_withdrawal_date,
        'withdrawalDate',p_withdrawal_date,'deletedLessonCount',coalesce((v_preclear->>'deletedLessonCount')::integer,0),
        'deletedLessonIds',coalesce(v_preclear->'deletedLessonIds','[]'::jsonb),
        'restoredLessonCount',coalesce((v_restore->>'restoredLessonCount')::integer,0),
        'creditedLessonCount',coalesce((v_restore->>'creditedLessonCount')::integer,0),
        'unrestoredLessonCount',coalesce((v_restore->>'unrestoredLessonCount')::integer,0))
    );
  end if;
  return jsonb_build_object(
    'changed',v_current_withdrawal_date is distinct from p_withdrawal_date,
    'studentId',p_student_id,'previousWithdrawalDate',v_current_withdrawal_date,
    'withdrawalDate',p_withdrawal_date,'finalized',false,
    'deletedLessonCount',coalesce((v_preclear->>'deletedLessonCount')::integer,0),'revokedRightCount',0,
    'restoredLessonCount',coalesce((v_restore->>'restoredLessonCount')::integer,0),
    'creditedLessonCount',coalesce((v_restore->>'creditedLessonCount')::integer,0),
    'unrestoredLessonCount',coalesce((v_restore->>'unrestoredLessonCount')::integer,0));
exception when lock_not_available then
  raise exception using errcode='P0001', message='FORESTRING_STUDENT_SETTLEMENT_BUSY';
end;
$schedule$;
revoke all on function public.schedule_student_withdrawal(uuid,date) from public,anon;
grant execute on function public.schedule_student_withdrawal(uuid,date) to authenticated,service_role;
