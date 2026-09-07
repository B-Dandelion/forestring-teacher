create or replace function public.end_regular_schedule(
  p_schedule_slot_id uuid,
  p_effective_on date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_actor_branch_id uuid;
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  v_slot public.regular_schedule_slots%rowtype;
  v_student_active boolean;
  v_student_status public.student_status;
  v_item record;

  v_end_on date;
  v_deleted_lesson_count integer := 0;
  v_deleted_right_count integer := 0;
  v_revoked_right_count integer := 0;
  v_preserved_actual_count integer := 0;
  v_hard_deleted boolean := false;
  v_linked_right_count integer := 0;
  v_remaining_right_count integer := 0;
  v_has_cancellation_history boolean;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role,p.branch_id
  into v_actor_role,v_actor_branch_id
  from public.profiles p
  where p.id=v_actor_id and p.is_active=true;

  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  if p_effective_on is null or p_effective_on < v_today then
    raise exception using errcode='P0001', message='FORESTRING_BACKDATED_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  select rs.* into v_slot
  from public.regular_schedule_slots rs
  where rs.id=p_schedule_slot_id
  for update;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_SLOT_NOT_FOUND';
  end if;

  if v_actor_role='manager'::public.user_role
     and v_actor_branch_id is distinct from v_slot.branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select p.is_active,s.status
  into v_student_active,v_student_status
  from public.students s
  join public.profiles p on p.id=s.id
  where s.id=v_slot.student_id;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_student_active <> true or v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_slot.ends_on is not null and v_slot.ends_on < p_effective_on then
    return jsonb_build_object(
      'changed',false,
      'scheduleSlotId',v_slot.id,
      'effectiveOn',v_slot.ends_on+1,
      'canceledLessonCount',0,
      'revokedRightCount',0,
      'deletedLessonCount',0,
      'deletedRightCount',0,
      'preservedActualCount',0,
      'hardDeleted',false
    );
  end if;

  select count(*)::integer into v_linked_right_count
  from public.lesson_rights r
  where r.schedule_slot_id=v_slot.id;

  -- If the recurrence has not started yet, a completely pristine slot can be
  -- removed outright. History-bearing rights are intentionally not erased;
  -- the existing date-range model cannot represent a zero-length pre-start
  -- recurrence without corrupting downstream materialization, so that rare
  -- edge remains an explicit safety boundary instead of silently losing data.
  if p_effective_on <= v_slot.starts_on then
    if v_linked_right_count=0 then
      delete from public.lesson_series ls where ls.schedule_slot_id=v_slot.id;
      delete from public.regular_schedule_slots rs where rs.id=v_slot.id;
      v_hard_deleted := true;
    else
      if exists (
        select 1
        from public.lesson_rights r
        left join public.lessons l on l.lesson_right_id=r.id
        where r.schedule_slot_id=v_slot.id
          and not (
            private.regular_right_is_default_following(r.id,false)
            and not exists (
              select 1 from public.lesson_cancellation_events ce
              where ce.lesson_right_id=r.id
            )
            and l.starts_at > pg_catalog.now()
          )
      ) then
        raise exception using
          errcode='P0001',
          message='FORESTRING_REGULAR_SCHEDULE_PRESTART_HISTORY_PRESERVED';
      end if;

      delete from public.lessons l
      using public.lesson_rights r
      where l.lesson_right_id=r.id
        and r.schedule_slot_id=v_slot.id;
      get diagnostics v_deleted_lesson_count=row_count;

      delete from public.lesson_rights r
      where r.schedule_slot_id=v_slot.id;
      get diagnostics v_deleted_right_count=row_count;

      if v_deleted_right_count <> v_linked_right_count then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_UNDO_COUNT_MISMATCH';
      end if;

      delete from public.lesson_series ls where ls.schedule_slot_id=v_slot.id;
      delete from public.regular_schedule_slots rs where rs.id=v_slot.id;
      v_hard_deleted := true;
    end if;
  else
    v_end_on := p_effective_on - 1;

    -- End the recurring rule itself. Series rows still referenced by preserved
    -- concrete lessons remain as provenance, while empty future versions can
    -- disappear safely.
    update public.lesson_series ls
    set effective_until=v_end_on
    where ls.schedule_slot_id=v_slot.id
      and ls.effective_from < p_effective_on
      and (ls.effective_until is null or ls.effective_until >= p_effective_on);

    update public.regular_schedule_slots rs
    set ends_on=v_end_on
    where rs.id=v_slot.id;

    -- Remove only future default projections. Individual moves, student/admin
    -- cancellations, rebookings, carryover/makeup descendants and credits are
    -- preserved and no longer block ending the recurrence.
    for v_item in
      select
        r.id as right_id,
        l.id as lesson_id,
        r.status as right_status,
        l.status as lesson_status,
        l.cancellation_reason,
        l.rescheduled_by,
        l.occurrence_at,
        l.starts_at
      from public.lesson_rights r
      join public.lessons l on l.lesson_right_id=r.id
      where r.schedule_slot_id=v_slot.id
        and r.origin='regular_base'::public.lesson_right_origin
        and l.lesson_type='regular'::public.lesson_type
        and l.occurrence_at is not null
        and (l.occurrence_at at time zone 'Asia/Seoul')::date >= p_effective_on
        and l.starts_at > pg_catalog.now()
      order by l.occurrence_at,l.id
      for update of r,l
    loop
      if not private.regular_right_is_default_following(v_item.right_id,true) then
        v_preserved_actual_count := v_preserved_actual_count + 1;
        continue;
      end if;

      select exists (
        select 1
        from public.lesson_cancellation_events ce
        where ce.lesson_right_id=v_item.right_id
      ) into v_has_cancellation_history;

      if v_has_cancellation_history then
        -- AUTO_CLOSURE history is immutable, so the right cannot be deleted.
        -- Revoke the now-removed default entitlement while retaining the
        -- cancellation ledger row and audit trail.
        delete from public.lessons l where l.id=v_item.lesson_id;
        if not found then
          raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_UNDO_COUNT_MISMATCH';
        end if;
        v_deleted_lesson_count := v_deleted_lesson_count + 1;

        update public.lesson_rights
        set status='revoked'::public.lesson_right_status,
            reserved_at=null,
            consumed_at=null
        where id=v_item.right_id;
        v_revoked_right_count := v_revoked_right_count + 1;
      else
        delete from public.lessons l where l.id=v_item.lesson_id;
        if not found then
          raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_UNDO_COUNT_MISMATCH';
        end if;
        v_deleted_lesson_count := v_deleted_lesson_count + 1;

        delete from public.lesson_rights r where r.id=v_item.right_id;
        if not found then
          raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_UNDO_COUNT_MISMATCH';
        end if;
        v_deleted_right_count := v_deleted_right_count + 1;
      end if;
    end loop;

    delete from public.lesson_series ls
    where ls.schedule_slot_id=v_slot.id
      and ls.effective_from >= p_effective_on
      and not exists (select 1 from public.lessons l where l.series_id=ls.id);
  end if;

  select count(*)::integer into v_remaining_right_count
  from public.lesson_rights r
  where r.schedule_slot_id=v_slot.id;

  insert into public.audit_events(
    subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
  ) values (
    v_slot.student_id,v_slot.branch_id,null,'REGULAR_SCHEDULE_ENDED',p_effective_on,v_actor_id,
    jsonb_build_object(
      'scheduleSlotId',v_slot.id,
      'previousStartsOn',v_slot.starts_on,
      'previousEndsOn',v_slot.ends_on,
      'hardDeleted',v_hard_deleted,
      'canceledLessonCount',0,
      'revokedRightCount',v_revoked_right_count,
      'deletedLessonCount',v_deleted_lesson_count,
      'deletedRightCount',v_deleted_right_count,
      'preservedActualCount',v_preserved_actual_count,
      'remainingLinkedRightCount',v_remaining_right_count
    )
  );

  return jsonb_build_object(
    'changed',true,
    'scheduleSlotId',v_slot.id,
    'effectiveOn',p_effective_on,
    'canceledLessonCount',0,
    'revokedRightCount',v_revoked_right_count,
    'deletedLessonCount',v_deleted_lesson_count,
    'deletedRightCount',v_deleted_right_count,
    'preservedActualCount',v_preserved_actual_count,
    'hardDeleted',v_hard_deleted
  );
end;
$function$;