create or replace function private.cancel_lesson_for_closure(p_lesson_id uuid, p_closure_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_lesson public.lessons%rowtype;
  v_right public.lesson_rights%rowtype;
  v_marker text := 'AUTO_CLOSURE:' || p_closure_id::text;
  v_event_id uuid;
begin
  select * into v_lesson
  from public.lessons l
  where l.id = p_lesson_id
  for update;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_LESSON_NOT_FOUND';
  end if;

  if v_lesson.status <> 'scheduled'::public.lesson_status
     or v_lesson.starts_at <= pg_catalog.now() then
    return false;
  end if;

  if v_lesson.lesson_type <> 'regular'::public.lesson_type
     or v_lesson.lesson_right_id is null
     or v_lesson.series_id is null
     or v_lesson.rescheduled_by is not null then
    return false;
  end if;

  select * into v_right
  from public.lesson_rights r
  where r.id = v_lesson.lesson_right_id
  for update;

  if not found
     or v_right.origin <> 'regular_base'::public.lesson_right_origin
     or v_right.status <> 'reserved'::public.lesson_right_status then
    raise exception using
      errcode='P0001',
      message='FORESTRING_CLOSURE_AUTO_CANCEL_RIGHT_NOT_RESERVED';
  end if;

  update public.lessons
  set status='canceled'::public.lesson_status,
      canceled_by=v_actor_id,
      canceled_at=pg_catalog.now(),
      cancellation_reason=v_marker
  where id=v_lesson.id;

  update public.lesson_rights
  set status='available'::public.lesson_right_status,
      reserved_at=null
  where id=v_right.id;

  insert into public.lesson_cancellation_events(
    lesson_id, lesson_right_id, student_id, branch_id, origin, actor_id,
    counts_toward_limit, reason, lesson_starts_at, lesson_duration_minutes
  ) values (
    v_lesson.id, v_right.id, v_right.student_id, v_right.branch_id,
    'academy'::public.lesson_cancellation_origin, v_actor_id, false,
    v_marker, v_lesson.starts_at, v_lesson.duration_minutes
  ) returning id into v_event_id;

  insert into public.audit_events(
    subject_profile_id, branch_id, semester_id, event_type,
    effective_on, actor_id, details
  ) values (
    v_lesson.student_id, v_lesson.branch_id, v_right.usable_semester_id,
    'LESSON_AUTO_CANCELED_FOR_CLOSURE',
    (v_lesson.starts_at at time zone 'Asia/Seoul')::date,
    v_actor_id,
    jsonb_build_object(
      'lessonId', v_lesson.id,
      'rightId', v_right.id,
      'closureId', p_closure_id,
      'cancellationEventId', v_event_id
    )
  );

  return true;
end;
$function$;

create or replace function private.restore_lesson_from_closure(p_lesson_id uuid, p_closure_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_lesson public.lessons%rowtype;
  v_right public.lesson_rights%rowtype;
  v_marker text := 'AUTO_CLOSURE:' || p_closure_id::text;
  v_skip_reason text;
begin
  select * into v_lesson
  from public.lessons l
  where l.id = p_lesson_id
  for update;

  if not found then
    return false;
  end if;

  if v_lesson.status <> 'canceled'::public.lesson_status
     or v_lesson.cancellation_reason is distinct from v_marker
     or v_lesson.starts_at <= pg_catalog.now() then
    return false;
  end if;

  if v_lesson.lesson_type <> 'regular'::public.lesson_type
     or v_lesson.lesson_right_id is null
     or v_lesson.series_id is null then
    return false;
  end if;

  select * into v_right
  from public.lesson_rights r
  where r.id = v_lesson.lesson_right_id
  for update;

  if not found then
    raise exception using
      errcode='P0001',
      message='FORESTRING_CLOSURE_REVERSAL_RIGHT_NOT_FOUND',
      detail='lesson_id=' || v_lesson.id::text;
  end if;

  if v_right.status <> 'available'::public.lesson_right_status then
    v_skip_reason := 'right_already_reused';
  elsif exists (
    select 1
    from public.lessons ml
    where ml.manual_makeup_right_id = v_right.id
      and ml.status = 'scheduled'::public.lesson_status
  ) then
    v_skip_reason := 'right_used_by_makeup';
  elsif exists (
    select 1
    from public.lessons other
    where other.id <> v_lesson.id
      and other.status = 'scheduled'::public.lesson_status
      and (
        other.student_id = v_lesson.student_id
        or other.teacher_id = v_lesson.teacher_id
      )
      and tstzrange(other.starts_at, other.ends_at, '[)')
          && tstzrange(v_lesson.starts_at, v_lesson.ends_at, '[)')
  ) then
    v_skip_reason := 'time_conflict';
  elsif exists (
    select 1
    from public.blocked_periods bp
    where bp.teacher_id = v_lesson.teacher_id
      and tstzrange(bp.starts_at, bp.ends_at, '[)')
          && tstzrange(v_lesson.starts_at, v_lesson.ends_at, '[)')
  ) then
    v_skip_reason := 'teacher_blocked';
  elsif exists (
    select 1
    from public.students s
    where s.id = v_lesson.student_id
      and s.withdrawal_date is not null
      and (v_lesson.starts_at at time zone 'Asia/Seoul')::date >= s.withdrawal_date
  ) then
    v_skip_reason := 'student_withdrawal_boundary';
  elsif exists (
    select 1
    from public.teachers t
    where t.id = v_lesson.teacher_id
      and t.withdrawal_date is not null
      and (v_lesson.starts_at at time zone 'Asia/Seoul')::date >= t.withdrawal_date
  ) then
    v_skip_reason := 'teacher_withdrawal_boundary';
  end if;

  if v_skip_reason is not null then
    insert into public.audit_events(
      subject_profile_id, branch_id, event_type,
      effective_on, actor_id, details
    ) values (
      v_lesson.student_id,
      v_lesson.branch_id,
      'LESSON_RESTORE_AFTER_CLOSURE_SKIPPED',
      (v_lesson.starts_at at time zone 'Asia/Seoul')::date,
      v_actor_id,
      jsonb_build_object(
        'lessonId', v_lesson.id,
        'closureId', p_closure_id,
        'rightId', v_right.id,
        'reason', v_skip_reason
      )
    );
    return false;
  end if;

  update public.lesson_rights
  set status='reserved'::public.lesson_right_status,
      reserved_at=pg_catalog.now()
  where id=v_right.id;

  begin
    update public.lessons
    set status='scheduled'::public.lesson_status,
        canceled_by=null,
        canceled_at=null,
        cancellation_reason=null
    where id=v_lesson.id;
  exception
    when exclusion_violation then
      update public.lesson_rights
      set status='available'::public.lesson_right_status,
          reserved_at=null
      where id=v_right.id;

      insert into public.audit_events(
        subject_profile_id, branch_id, event_type,
        effective_on, actor_id, details
      ) values (
        v_lesson.student_id,
        v_lesson.branch_id,
        'LESSON_RESTORE_AFTER_CLOSURE_SKIPPED',
        (v_lesson.starts_at at time zone 'Asia/Seoul')::date,
        v_actor_id,
        jsonb_build_object(
          'lessonId', v_lesson.id,
          'closureId', p_closure_id,
          'rightId', v_right.id,
          'reason', 'time_conflict'
        )
      );
      return false;
  end;

  insert into public.audit_events(
    subject_profile_id, branch_id, event_type,
    effective_on, actor_id, details
  ) values (
    v_lesson.student_id,
    v_lesson.branch_id,
    'LESSON_RESTORED_AFTER_CLOSURE_CHANGE',
    (v_lesson.starts_at at time zone 'Asia/Seoul')::date,
    v_actor_id,
    jsonb_build_object(
      'lessonId', v_lesson.id,
      'closureId', p_closure_id,
      'rightId', v_lesson.lesson_right_id
    )
  );

  return true;
end;
$function$;

create or replace function private.reconcile_ordinary_closure_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_old_ordinary boolean := false;
  v_new_ordinary boolean := false;
  v_lesson record;
begin
  if tg_op in ('UPDATE','DELETE') then
    v_old_ordinary := old.closure_kind='ordinary'::public.closure_kind;
  end if;
  if tg_op in ('UPDATE','INSERT') then
    v_new_ordinary := new.closure_kind='ordinary'::public.closure_kind;
  end if;

  if v_old_ordinary then
    for v_lesson in
      select l.id,l.starts_at
      from public.lessons l
      where l.branch_id=old.branch_id
        and l.status='canceled'::public.lesson_status
        and l.cancellation_reason='AUTO_CLOSURE:'||old.id::text
        and l.starts_at>pg_catalog.now()
        and (
          not v_new_ordinary
          or old.id is distinct from new.id
          or old.branch_id is distinct from new.branch_id
          or (l.starts_at at time zone 'Asia/Seoul')::date not between new.starts_on and new.ends_on
        )
      order by l.starts_at,l.id
    loop
      perform private.restore_lesson_from_closure(v_lesson.id,old.id);
    end loop;
  end if;

  if v_new_ordinary then
    for v_lesson in
      select l.id,l.starts_at
      from public.lessons l
      where l.branch_id=new.branch_id
        and l.status='scheduled'::public.lesson_status
        and l.lesson_type='regular'::public.lesson_type
        and l.lesson_right_id is not null
        and l.series_id is not null
        and l.rescheduled_by is null
        and l.starts_at>pg_catalog.now()
        and (l.starts_at at time zone 'Asia/Seoul')::date between new.starts_on and new.ends_on
      order by l.starts_at,l.id
    loop
      perform private.cancel_lesson_for_closure(v_lesson.id,new.id);
    end loop;
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;