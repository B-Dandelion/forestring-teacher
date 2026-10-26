-- Backdated withdrawal is a separate, atomic path. The existing future
-- reservation/snapshot path and delayed cron finalizer retain their semantics.
-- Never infer attendance from status: historical lessons remain 'scheduled'.
create or replace function public.schedule_student_withdrawal(
  p_student_id uuid,
  p_withdrawal_date date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_branch_id uuid;
  v_status public.student_status;
  v_current_withdrawal_date date;
  v_today date;
  v_cutoff timestamptz;
  v_checked_at timestamptz;
  v_enrollment_start date;
  v_lesson_conflicts integer;
  v_assignment_conflicts integer;
  v_schedule_conflicts integer;
  v_completed_plan_conflicts integer;
  v_snapshot_conflicts integer;
  v_manual_right_conflicts integer;
  v_released_manual_right_count integer := 0;
  v_finalization jsonb;
  v_restore_before timestamptz;
  v_preclear jsonb := jsonb_build_object('deletedLessonCount', 0, 'deletedLessonIds', '[]'::jsonb);
  v_restore jsonb := jsonb_build_object('restoredLessonCount', 0, 'creditedLessonCount', 0, 'unrestoredLessonCount', 0);
begin
  v_actor_id := auth.uid();

  if v_actor_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_ACTIVE_USER_REQUIRED';
  end if;

  if v_actor_role not in ('master'::public.user_role, 'manager'::public.user_role) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN';
  end if;

  if p_withdrawal_date is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_WITHDRAWAL_DATE_REQUIRED';
  end if;

  v_today := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  -- Lesson insertion takes the same student lock in its withdrawal trigger.
  -- Validate history before changing either the date or enrollment periods.
  select p.branch_id, s.status, s.withdrawal_date
  into v_branch_id, v_status, v_current_withdrawal_date
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = p_student_id
  for update of s, p;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_branch_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_branch_id) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  -- A repeated backdated request, or an unchanged overdue reservation, uses
  -- the authoritative finalizer. Do not reinterpret delayed cleanup as a new
  -- retroactive date change or add a global now() guard to the finalizer.
  if p_withdrawal_date < v_today
     and v_current_withdrawal_date = p_withdrawal_date
     and v_status in ('active'::public.student_status, 'withdrawn'::public.student_status) then
    v_finalization := public.finalize_student_withdrawal(p_student_id);
    return v_finalization || jsonb_build_object(
      'previousWithdrawalDate', v_current_withdrawal_date,
      'finalized', true,
      'restoredLessonCount', 0,
      'creditedLessonCount', 0,
      'unrestoredLessonCount', 0
    );
  end if;

  if v_status <> 'active'::public.student_status then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_NOT_ACTIVE';
  end if;

  if p_withdrawal_date < v_today then
    if v_current_withdrawal_date is not null
       and v_current_withdrawal_date <= v_today then
      raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_WITHDRAWAL_ALREADY_EFFECTIVE';
    end if;

    begin
      select ep.starts_on
      into v_enrollment_start
      from public.student_enrollment_periods ep
      where ep.student_id = p_student_id
      order by ep.starts_on desc, ep.created_at desc
      limit 1
      for update nowait;

      if not found then
        raise exception using errcode = 'P0001', message = 'FORESTRING_ENROLLMENT_PERIOD_REQUIRED';
      end if;

      -- Withdrawal day is excluded from enrollment (ends_on = date - 1).
      if p_withdrawal_date <= v_enrollment_start then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_STUDENT_WITHDRAWAL_BEFORE_ENROLLMENT',
          detail = jsonb_build_object('earliestWithdrawalDate', v_enrollment_start + 1)::text;
      end if;

      v_cutoff := p_withdrawal_date::timestamp at time zone 'Asia/Seoul';

      -- Existing semester transition takes plan -> student locks. New
      -- backdated work already holds the student lock, so fail immediately on
      -- busy dependent rows instead of waiting in the opposite lock order.
      perform 1 from public.student_semester_plans sp
      where sp.student_id = p_student_id for update nowait;
      perform 1 from public.lessons l
      where l.student_id = p_student_id and l.starts_at >= v_cutoff for update nowait;
      perform 1 from public.teacher_student_assignments a
      where a.student_id = p_student_id for update nowait;
      perform 1 from public.lesson_series ls
      where ls.student_id = p_student_id for update nowait;
      perform 1 from public.regular_schedule_slots rs
      where rs.student_id = p_student_id for update nowait;
      perform 1 from private.student_withdrawal_lesson_snapshots snap
      where snap.student_id = p_student_id and snap.closed_at is null for update nowait;
      perform 1 from public.lesson_rights r
      where r.student_id = p_student_id for update nowait;

      -- now() is transaction-start time. A request can wait on the locks while
      -- a lesson begins; check the wall clock only after obtaining the locks.
      v_checked_at := pg_catalog.clock_timestamp();

      select count(*)::integer into v_lesson_conflicts
      from public.lessons l
      where l.student_id = p_student_id
        and l.starts_at >= v_cutoff
        and l.starts_at <= v_checked_at;

      -- A closed historical assignment must not be shortened, and a historical
      -- assignment starting after the cutoff must not be physically removed.
      -- An open current assignment may close at the requested withdrawal date.
      select count(*)::integer into v_assignment_conflicts
      from public.teacher_student_assignments a
      where a.student_id = p_student_id
        and (
          (a.starts_on >= p_withdrawal_date and a.starts_on <= v_today)
          or (a.starts_on < p_withdrawal_date and a.ends_on >= p_withdrawal_date and a.ends_on < v_today)
        );

      select count(*)::integer into v_schedule_conflicts
      from (
        select ls.id
        from public.lesson_series ls
        where ls.student_id = p_student_id
          and (
            (ls.effective_from >= p_withdrawal_date and ls.effective_from <= v_today)
            or (ls.effective_from < p_withdrawal_date and ls.effective_until >= p_withdrawal_date and ls.effective_until < v_today)
          )
        union all
        select rs.id
        from public.regular_schedule_slots rs
        where rs.student_id = p_student_id
          and (
            (rs.starts_on >= p_withdrawal_date and rs.starts_on <= v_today)
            or (rs.starts_on < p_withdrawal_date and rs.ends_on >= p_withdrawal_date and rs.ends_on < v_today)
          )
      ) history;

      select count(*)::integer into v_completed_plan_conflicts
      from public.student_semester_plans sp
      cross join lateral private.get_effective_semester_bounds(sp.branch_id, sp.semester_id) bounds
      where sp.student_id = p_student_id
        and sp.status = 'completed'::public.student_semester_plan_status
        and bounds.ends_on >= p_withdrawal_date;

      -- Previously precleared lessons can also carry historical identities.
      select count(*)::integer into v_snapshot_conflicts
      from private.student_withdrawal_lesson_snapshots snap
      where snap.student_id = p_student_id
        and snap.closed_at is null
        and snap.starts_at >= v_cutoff
        and snap.starts_at <= v_checked_at;

      select count(*)::integer into v_manual_right_conflicts
      from private.student_withdrawal_lesson_snapshots snap
      left join public.lesson_rights r on r.id = snap.manual_makeup_right_id
      where snap.student_id = p_student_id
        and snap.closed_at is null
        and snap.starts_at > v_checked_at
        and snap.manual_makeup_right_id is not null
        and snap.manual_makeup_right_snapshot ->> 'status' = 'consumed'
        and (
          r.id is null
          or r.student_id <> p_student_id
          or r.branch_id is distinct from v_branch_id
          or r.status <> 'consumed'::public.lesson_right_status
          or r.consumed_at is distinct from (snap.manual_makeup_right_snapshot ->> 'consumed_at')::timestamptz
          or r.reserved_at is distinct from (snap.manual_makeup_right_snapshot ->> 'reserved_at')::timestamptz
          or exists (
            select 1 from public.lessons l
            where l.lesson_right_id = r.id or l.manual_makeup_right_id = r.id
          )
          or exists (select 1 from public.lesson_rights child where child.source_right_id = r.id)
        );

      if v_lesson_conflicts + v_assignment_conflicts + v_schedule_conflicts
         + v_completed_plan_conflicts + v_snapshot_conflicts + v_manual_right_conflicts > 0 then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT',
          detail = jsonb_build_object(
            'lessonCount', v_lesson_conflicts,
            'assignmentCount', v_assignment_conflicts,
            'scheduleCount', v_schedule_conflicts,
            'completedSemesterCount', v_completed_plan_conflicts,
            'snapshotCount', v_snapshot_conflicts,
            'manualRightCount', v_manual_right_conflicts
          )::text;
      end if;

      update public.students
      set withdrawal_date = p_withdrawal_date
      where id = p_student_id;

      -- A prior FUTURE withdrawal may already have snapshotted a future manual
      -- lesson and retained its consumed right for reversal. Release only that
      -- unreferenced reservation so the finalizer revokes it as unused, rather
      -- than preserving a consumed right with no historical lesson.
      update public.lesson_rights r
      set status = 'available'::public.lesson_right_status,
          consumed_at = null,
          reserved_at = null
      where r.student_id = p_student_id
        and r.branch_id = v_branch_id
        and r.status = 'consumed'::public.lesson_right_status
        and exists (
          select 1
          from private.student_withdrawal_lesson_snapshots snap
          where snap.student_id = p_student_id
            and snap.closed_at is null
            and snap.starts_at > v_checked_at
            and snap.manual_makeup_right_id = r.id
            and snap.manual_makeup_right_snapshot ->> 'status' = 'consumed'
        )
        and not exists (
          select 1 from public.lessons l
          where l.lesson_right_id = r.id or l.manual_makeup_right_id = r.id
        );
      get diagnostics v_released_manual_right_count = row_count;

      insert into public.audit_events (
        subject_profile_id, branch_id, semester_id, event_type, effective_on, actor_id, details
      ) values (
        p_student_id, v_branch_id, null, 'STUDENT_WITHDRAWAL_SCHEDULED', p_withdrawal_date, v_actor_id,
        jsonb_build_object(
          'previousWithdrawalDate', v_current_withdrawal_date,
          'withdrawalDate', p_withdrawal_date,
          'backdated', true,
          'releasedFutureManualRightCount', v_released_manual_right_count
        )
      );

      -- Skip preclear here: the finalizer directly deletes only future actual
      -- lessons after the history check. Its existing delete trigger restores
      -- future manual rights before all unused rights are revoked. Any error
      -- rolls back the date, enrollment, rights, audit, and deletion together.
      v_finalization := public.finalize_student_withdrawal(p_student_id);
      return v_finalization || jsonb_build_object(
        'previousWithdrawalDate', v_current_withdrawal_date,
        'finalized', true,
        'restoredLessonCount', 0,
        'creditedLessonCount', 0,
        'unrestoredLessonCount', 0
      );
    exception
      when lock_not_available then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_STUDENT_SETTLEMENT_BUSY';
    end;
  end if;

  -- Existing today/future path, including snapshot restoration and audit.
  update public.students
  set withdrawal_date = p_withdrawal_date
  where id = p_student_id;

  if v_current_withdrawal_date is not null
     and p_withdrawal_date > v_current_withdrawal_date then
    v_restore_before := p_withdrawal_date::timestamp at time zone 'Asia/Seoul';
    v_restore := private.restore_student_withdrawal_snapshots(
      p_student_id, v_restore_before, v_actor_id, 'withdrawal_date_moved_later'
    );
  end if;

  v_preclear := private.preclear_student_withdrawal_lessons(p_student_id, p_withdrawal_date);

  if v_current_withdrawal_date is distinct from p_withdrawal_date then
    insert into public.audit_events (
      subject_profile_id, branch_id, semester_id, event_type, effective_on, actor_id, details
    ) values (
      p_student_id, v_branch_id, null, 'STUDENT_WITHDRAWAL_SCHEDULED', p_withdrawal_date, v_actor_id,
      jsonb_build_object(
        'previousWithdrawalDate', v_current_withdrawal_date,
        'withdrawalDate', p_withdrawal_date,
        'deletedLessonCount', coalesce((v_preclear ->> 'deletedLessonCount')::integer, 0),
        'deletedLessonIds', coalesce(v_preclear -> 'deletedLessonIds', '[]'::jsonb),
        'restoredLessonCount', coalesce((v_restore ->> 'restoredLessonCount')::integer, 0),
        'creditedLessonCount', coalesce((v_restore ->> 'creditedLessonCount')::integer, 0),
        'unrestoredLessonCount', coalesce((v_restore ->> 'unrestoredLessonCount')::integer, 0)
      )
    );
  end if;

  return jsonb_build_object(
    'changed', v_current_withdrawal_date is distinct from p_withdrawal_date,
    'studentId', p_student_id,
    'previousWithdrawalDate', v_current_withdrawal_date,
    'withdrawalDate', p_withdrawal_date,
    'finalized', false,
    'deletedLessonCount', coalesce((v_preclear ->> 'deletedLessonCount')::integer, 0),
    'revokedRightCount', 0,
    'restoredLessonCount', coalesce((v_restore ->> 'restoredLessonCount')::integer, 0),
    'creditedLessonCount', coalesce((v_restore ->> 'creditedLessonCount')::integer, 0),
    'unrestoredLessonCount', coalesce((v_restore ->> 'unrestoredLessonCount')::integer, 0)
  );
end;
$function$;

-- CREATE OR REPLACE retains existing ACLs; explicitly keep this privileged
-- RPC unavailable to unauthenticated callers on freshly reconstructed DBs.
revoke all on function public.schedule_student_withdrawal(uuid, date) from public, anon;
grant execute on function public.schedule_student_withdrawal(uuid, date) to authenticated;
