create or replace function private.cancel_lesson_for_closure(
  p_lesson_id uuid,
  p_closure_id uuid
)
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
  where l.id=p_lesson_id
  for update;

  if not found then
    raise exception using errcode='P0001',message='FORESTRING_LESSON_NOT_FOUND';
  end if;

  if v_lesson.status<>'scheduled'::public.lesson_status then
    return false;
  end if;

  if v_lesson.starts_at<=pg_catalog.now() then
    return false;
  end if;

  if v_lesson.lesson_right_id is not null then
    select * into v_right
    from public.lesson_rights r
    where r.id=v_lesson.lesson_right_id
    for update;

    if not found or v_right.status<>'reserved'::public.lesson_right_status then
      raise exception using errcode='P0001',message='FORESTRING_CLOSURE_AUTO_CANCEL_RIGHT_NOT_RESERVED';
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
      lesson_id,lesson_right_id,student_id,branch_id,origin,actor_id,
      counts_toward_limit,reason,lesson_starts_at,lesson_duration_minutes
    ) values (
      v_lesson.id,v_right.id,v_right.student_id,v_right.branch_id,
      'academy'::public.lesson_cancellation_origin,v_actor_id,false,
      v_marker,v_lesson.starts_at,v_lesson.duration_minutes
    ) returning id into v_event_id;

    insert into public.audit_events(
      subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
    ) values (
      v_lesson.student_id,v_lesson.branch_id,v_right.usable_semester_id,
      'LESSON_AUTO_CANCELED_FOR_CLOSURE',
      (v_lesson.starts_at at time zone 'Asia/Seoul')::date,
      v_actor_id,
      jsonb_build_object('lessonId',v_lesson.id,'rightId',v_right.id,'closureId',p_closure_id,'cancellationEventId',v_event_id)
    );

    return true;
  end if;

  if v_lesson.lesson_type='makeup'::public.lesson_type
     and v_lesson.series_id is null then
    if v_lesson.manual_makeup_right_id is not null then
      select * into v_right
      from public.lesson_rights r
      where r.id=v_lesson.manual_makeup_right_id
      for update;

      if not found or v_right.status<>'consumed'::public.lesson_right_status then
        raise exception using errcode='P0001',message='FORESTRING_CLOSURE_AUTO_CANCEL_MAKEUP_RIGHT_NOT_CONSUMED';
      end if;

      update public.lesson_rights
      set status='available'::public.lesson_right_status,
          consumed_at=null,
          reserved_at=null
      where id=v_right.id;
    end if;

    update public.lessons
    set status='canceled'::public.lesson_status,
        canceled_by=v_actor_id,
        canceled_at=pg_catalog.now(),
        cancellation_reason=v_marker
    where id=v_lesson.id;

    insert into public.audit_events(
      subject_profile_id,branch_id,event_type,effective_on,actor_id,details
    ) values (
      v_lesson.student_id,v_lesson.branch_id,'MAKEUP_LESSON_AUTO_CANCELED_FOR_CLOSURE',
      (v_lesson.starts_at at time zone 'Asia/Seoul')::date,
      v_actor_id,
      jsonb_build_object('lessonId',v_lesson.id,'closureId',p_closure_id,'manualMakeupRightId',v_lesson.manual_makeup_right_id)
    );

    return true;
  end if;

  raise exception using errcode='P0001',message='FORESTRING_CLOSURE_AUTO_CANCEL_UNSUPPORTED_LESSON',detail='lesson_id='||v_lesson.id::text;
end;
$function$;

create or replace function private.restore_lesson_from_closure(
  p_lesson_id uuid,
  p_closure_id uuid
)
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
begin
  select * into v_lesson
  from public.lessons l
  where l.id=p_lesson_id
  for update;

  if not found then return false; end if;
  if v_lesson.status<>'canceled'::public.lesson_status
     or v_lesson.cancellation_reason is distinct from v_marker then
    return false;
  end if;
  if v_lesson.starts_at<=pg_catalog.now() then return false; end if;

  if v_lesson.lesson_right_id is not null then
    select * into v_right
    from public.lesson_rights r
    where r.id=v_lesson.lesson_right_id
    for update;

    if not found or v_right.status<>'available'::public.lesson_right_status then
      raise exception using errcode='P0001',message='FORESTRING_CLOSURE_REVERSAL_BLOCKED_BY_USED_RIGHT',detail='lesson_id='||v_lesson.id::text;
    end if;

    if exists(
      select 1 from public.lessons other
      where other.lesson_right_id=v_right.id
        and other.id<>v_lesson.id
    ) then
      raise exception using errcode='P0001',message='FORESTRING_CLOSURE_REVERSAL_BLOCKED_BY_USED_RIGHT',detail='lesson_id='||v_lesson.id::text||', reason=other_lesson_exists';
    end if;

    update public.lesson_rights
    set status='reserved'::public.lesson_right_status,
        reserved_at=pg_catalog.now()
    where id=v_right.id;

  elsif v_lesson.lesson_type='makeup'::public.lesson_type
        and v_lesson.series_id is null
        and v_lesson.manual_makeup_right_id is not null then
    select * into v_right
    from public.lesson_rights r
    where r.id=v_lesson.manual_makeup_right_id
    for update;

    if not found or v_right.status<>'available'::public.lesson_right_status then
      raise exception using errcode='P0001',message='FORESTRING_CLOSURE_REVERSAL_BLOCKED_BY_USED_RIGHT',detail='lesson_id='||v_lesson.id::text;
    end if;

    if exists(
      select 1 from public.lessons other
      where other.manual_makeup_right_id=v_right.id
        and other.id<>v_lesson.id
    ) then
      raise exception using errcode='P0001',message='FORESTRING_CLOSURE_REVERSAL_BLOCKED_BY_USED_RIGHT',detail='lesson_id='||v_lesson.id::text||', reason=other_makeup_exists';
    end if;

    update public.lesson_rights
    set status='consumed'::public.lesson_right_status,
        consumed_at=pg_catalog.now(),
        reserved_at=null
    where id=v_right.id;
  end if;

  update public.lessons
  set status='scheduled'::public.lesson_status,
      canceled_by=null,
      canceled_at=null,
      cancellation_reason=null
  where id=v_lesson.id;

  insert into public.audit_events(
    subject_profile_id,branch_id,event_type,effective_on,actor_id,details
  ) values (
    v_lesson.student_id,v_lesson.branch_id,'LESSON_RESTORED_AFTER_CLOSURE_CHANGE',
    (v_lesson.starts_at at time zone 'Asia/Seoul')::date,
    v_actor_id,
    jsonb_build_object('lessonId',v_lesson.id,'closureId',p_closure_id,'rightId',v_lesson.lesson_right_id,'manualMakeupRightId',v_lesson.manual_makeup_right_id)
  );

  return true;
end;
$function$;

revoke all on function private.cancel_lesson_for_closure(uuid,uuid) from public,anon,authenticated;
revoke all on function private.restore_lesson_from_closure(uuid,uuid) from public,anon,authenticated;

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

create or replace function private.auto_cancel_default_regular_on_ordinary_closure()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_closure_id uuid;
begin
  if new.status<>'scheduled'::public.lesson_status
     or new.lesson_type<>'regular'::public.lesson_type
     or new.rescheduled_by is not null
     or new.starts_at<=pg_catalog.now() then
    return new;
  end if;

  select cp.id into v_closure_id
  from public.closure_periods cp
  where cp.branch_id=new.branch_id
    and cp.closure_kind='ordinary'::public.closure_kind
    and (new.starts_at at time zone 'Asia/Seoul')::date between cp.starts_on and cp.ends_on
  order by cp.starts_on,cp.id
  limit 1;

  if found then
    perform private.cancel_lesson_for_closure(new.id,v_closure_id);
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_00_reconcile_ordinary_closure on public.closure_periods;
create constraint trigger trg_00_reconcile_ordinary_closure
after insert or update or delete on public.closure_periods
deferrable initially deferred
for each row
execute function private.reconcile_ordinary_closure_change();

drop trigger if exists trg_auto_cancel_default_regular_on_ordinary_closure on public.lessons;
create constraint trigger trg_auto_cancel_default_regular_on_ordinary_closure
after insert or update on public.lessons
deferrable initially deferred
for each row
execute function private.auto_cancel_default_regular_on_ordinary_closure();
