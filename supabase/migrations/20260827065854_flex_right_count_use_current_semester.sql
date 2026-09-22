do $migration$
declare
  v_def text;
  v_old text := $old$select sp.*
  into v_plan
  from public.student_semester_plans sp
  where sp.student_id = p_student_id
    and sp.student_type_snapshot = 'flex'::public.student_type
    and sp.status = 'active'::public.student_semester_plan_status
  order by sp.updated_at desc, sp.created_at desc
  limit 1
  for update;$old$;
  v_new text := $new$select sp.*
  into v_plan
  from public.student_semester_plans sp
  cross join lateral private.get_effective_semester_bounds(
    sp.branch_id,
    sp.semester_id
  ) bounds
  where sp.student_id = p_student_id
    and sp.student_type_snapshot = 'flex'::public.student_type
    and sp.status = 'active'::public.student_semester_plan_status
    and (pg_catalog.now() at time zone 'Asia/Seoul')::date
        between bounds.starts_on and bounds.ends_on
  order by bounds.starts_on desc, sp.created_at desc
  limit 1
  for update of sp;$new$;
begin
  select pg_get_functiondef(p.oid)
  into v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='change_flex_base_right_count'
    and p.prokind='f'
    and pg_get_function_arguments(p.oid)='p_student_id uuid, p_new_base_right_count integer';

  if v_def is null then
    raise exception 'FORESTRING_CHANGE_FLEX_FUNCTION_NOT_FOUND';
  end if;

  if position(v_old in v_def)=0 then
    raise exception 'FORESTRING_CHANGE_FLEX_SELECTOR_SHAPE_CHANGED';
  end if;

  execute replace(v_def,v_old,v_new);
end;
$migration$;
