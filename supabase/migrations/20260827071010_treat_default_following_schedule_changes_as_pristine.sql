create or replace function private.calendar_semester_is_materialized(
  p_semester_id uuid,
  p_branch_id uuid default null::uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_branch record;
  v_start date;
  v_has_materialized boolean;
begin
  if exists (
    select 1 from public.student_semester_plans sp
    where sp.semester_id = p_semester_id
      and sp.status = 'completed'::public.student_semester_plan_status
      and (p_branch_id is null or sp.branch_id = p_branch_id)
  ) then return true; end if;

  if exists (
    select 1 from public.lesson_rebooking_credits c
    where (c.source_semester_id = p_semester_id or c.usable_semester_id = p_semester_id)
      and (p_branch_id is null or coalesce(c.branch_id,(select p.branch_id from public.profiles p where p.id=c.student_id)) = p_branch_id)
  ) then return true; end if;

  for v_branch in
    select b.id from public.branches b
    where p_branch_id is null or b.id = p_branch_id
  loop
    select exists(
      select 1 from public.student_semester_plans sp
      where sp.semester_id=p_semester_id and sp.branch_id=v_branch.id
        and sp.status in ('active'::public.student_semester_plan_status,'completed'::public.student_semester_plan_status)
    ) or exists(
      select 1 from public.lesson_rights r
      where (r.source_semester_id=p_semester_id or r.usable_semester_id=p_semester_id)
        and r.branch_id=v_branch.id
    ) into v_has_materialized;

    if not v_has_materialized then continue; end if;

    select e.starts_on into v_start
    from private.get_effective_semester_bounds(v_branch.id,p_semester_id) e;

    if not found or v_start <= v_today then return true; end if;
  end loop;

  if exists (
    select 1 from public.lesson_rights r
    where r.source_semester_id=p_semester_id
      and (p_branch_id is null or r.branch_id=p_branch_id)
      and r.origin='regular_base'::public.lesson_right_origin
      and (
        r.status <> 'reserved'::public.lesson_right_status
        or exists(select 1 from public.lesson_cancellation_events ce where ce.lesson_right_id=r.id)
        or exists(select 1 from public.lesson_rights child where child.source_right_id=r.id)
        or exists(select 1 from public.lessons ml where ml.manual_makeup_right_id=r.id)
        or 1 <> (select count(*) from public.lessons l where l.lesson_right_id=r.id)
        or not exists (
          select 1 from public.lessons l
          where l.lesson_right_id=r.id
            and l.lesson_type='regular'::public.lesson_type
            and l.status='scheduled'::public.lesson_status
            and l.rescheduled_by is null
            and l.canceled_at is null
            and l.occurrence_at is not null
            and l.duration_minutes=r.duration_minutes
            and not exists(select 1 from public.lesson_rebooking_credits c where c.source_lesson_id=l.id)
        )
      )
  ) then return true; end if;

  if exists (
    select 1 from public.lesson_rights r
    where (r.source_semester_id=p_semester_id or r.usable_semester_id=p_semester_id)
      and (p_branch_id is null or r.branch_id=p_branch_id)
      and r.origin='flex_base'::public.lesson_right_origin
      and (
        r.status <> 'available'::public.lesson_right_status
        or exists(select 1 from public.lesson_rights child where child.source_right_id=r.id)
        or exists(select 1 from public.lessons l where l.lesson_right_id=r.id)
      )
  ) then return true; end if;

  if exists (
    select 1 from public.lesson_rights r
    where (r.source_semester_id=p_semester_id or r.usable_semester_id=p_semester_id)
      and (p_branch_id is null or r.branch_id=p_branch_id)
      and r.origin='carryover'::public.lesson_right_origin
  ) then return true; end if;

  return false;
end;
$function$;

create or replace function private.rebuild_future_regular_semester(
  p_semester_id uuid,
  p_branch_id uuid
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_start date;
  v_end date;
  v_plan record;
  v_rebuilt integer := 0;
begin
  select e.starts_on,e.ends_on into v_start,v_end
  from private.get_effective_semester_bounds(p_branch_id,p_semester_id) e;
  if not found then raise exception using errcode='P0001',message='FORESTRING_SEMESTER_NOT_FOUND'; end if;

  if not exists (
    select 1 from public.student_semester_plans sp
    where sp.semester_id=p_semester_id and sp.branch_id=p_branch_id
      and sp.status='active'::public.student_semester_plan_status
      and sp.student_type_snapshot='regular'::public.student_type
  ) then return 0; end if;

  if v_start <= v_today then
    raise exception using errcode='P0001',message='FORESTRING_CALENDAR_REBUILD_REQUIRES_FUTURE_SEMESTER';
  end if;

  for v_plan in
    select sp.id,sp.student_id
    from public.student_semester_plans sp
    where sp.semester_id=p_semester_id and sp.branch_id=p_branch_id
      and sp.status='active'::public.student_semester_plan_status
      and sp.student_type_snapshot='regular'::public.student_type
    order by sp.student_id
    for update
  loop
    if exists (
      select 1 from public.lesson_rights r
      where r.student_id=v_plan.student_id
        and r.source_semester_id=p_semester_id
        and r.branch_id=p_branch_id
        and r.origin='regular_base'::public.lesson_right_origin
        and (
          r.status <> 'reserved'::public.lesson_right_status
          or exists(select 1 from public.lesson_cancellation_events ce where ce.lesson_right_id=r.id)
          or exists(select 1 from public.lesson_rights child where child.source_right_id=r.id)
          or exists(select 1 from public.lessons ml where ml.manual_makeup_right_id=r.id)
          or 1 <> (select count(*) from public.lessons l where l.lesson_right_id=r.id)
          or not exists (
            select 1 from public.lessons l
            where l.lesson_right_id=r.id
              and l.lesson_type='regular'::public.lesson_type
              and l.status='scheduled'::public.lesson_status
              and l.rescheduled_by is null
              and l.canceled_at is null
              and l.occurrence_at is not null
              and l.duration_minutes=r.duration_minutes
              and not exists(select 1 from public.lesson_rebooking_credits c where c.source_lesson_id=l.id)
          )
        )
    ) then
      raise exception using errcode='P0001',message='FORESTRING_CALENDAR_REBUILD_BLOCKED_BY_USED_LESSON',detail='plan_id='||v_plan.id::text;
    end if;

    delete from public.lessons l
    using public.lesson_rights r
    where l.lesson_right_id=r.id
      and r.student_id=v_plan.student_id
      and r.source_semester_id=p_semester_id
      and r.branch_id=p_branch_id
      and r.origin='regular_base'::public.lesson_right_origin;

    delete from public.lesson_rights r
    where r.student_id=v_plan.student_id
      and r.source_semester_id=p_semester_id
      and r.branch_id=p_branch_id
      and r.origin='regular_base'::public.lesson_right_origin;

    update public.student_semester_plans
    set status='planned'::public.student_semester_plan_status,
        updated_by=coalesce(auth.uid(),updated_by)
    where id=v_plan.id;

    perform public.activate_student_semester_plan(v_plan.id);
    v_rebuilt := v_rebuilt + 1;
  end loop;

  return v_rebuilt;
end;
$function$;

revoke all on function private.rebuild_future_regular_semester(uuid,uuid) from public,anon,authenticated;
