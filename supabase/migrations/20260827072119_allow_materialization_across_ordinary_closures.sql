do $do$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='activate_student_semester_plan'
    and pg_get_function_identity_arguments(p.oid)='p_plan_id uuid';

  v_new := replace(v_def,
$old$
      if exists (
        select 1 from public.closure_periods cp
        where cp.branch_id=v_plan.branch_id
          and cp.semester_id=v_plan.semester_id
          and cp.closure_kind='ordinary'::public.closure_kind
          and v_candidate.lesson_date between cp.starts_on and cp.ends_on
      ) then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_ON_ORDINARY_CLOSURE';
      end if;
$old$,
$new$
      -- Ordinary closures keep the entitlement but the lesson is
      -- auto-canceled by the deferred lesson trigger after materialization.
$new$);

  if v_new = v_def then
    raise exception 'activate_student_semester_plan ordinary-closure guard not found';
  end if;
  execute v_new;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='add_regular_schedule'
    and pg_get_function_identity_arguments(p.oid)='p_student_id uuid, p_teacher_id uuid, p_weekday smallint, p_start_time time without time zone, p_duration_minutes integer, p_effective_on date';

  v_new := replace(v_def,
$old$
      if exists (
        select 1 from public.closure_periods cp
        where cp.branch_id=v_student_branch_id
          and cp.semester_id=v_plan.semester_id
          and cp.closure_kind='ordinary'::public.closure_kind
          and v_candidate.lesson_date between cp.starts_on and cp.ends_on
      ) then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_ON_ORDINARY_CLOSURE',
          detail='date='||v_candidate.lesson_date::text;
      end if;
$old$,
$new$
      -- Ordinary closures keep the entitlement; the scheduled occurrence
      -- is auto-canceled after insert so the right becomes available.
$new$);

  if v_new = v_def then
    raise exception 'add_regular_schedule ordinary-closure guard not found';
  end if;
  execute v_new;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='rebuild_future_regular_semester'
    and pg_get_function_identity_arguments(p.oid)='p_semester_id uuid, p_branch_id uuid';

  v_new := replace(v_def,
$old$
            if exists (
              select 1 from public.closure_periods cp
              where cp.branch_id=p_branch_id
                and cp.semester_id=p_semester_id
                and cp.closure_kind='ordinary'::public.closure_kind
                and v_candidate.lesson_date between cp.starts_on and cp.ends_on
            ) then
              raise exception using errcode='P0001',message='FORESTRING_REGULAR_RECONCILIATION_ON_CLOSURE',detail='date='||v_candidate.lesson_date::text;
            end if;
$old$,
$new$
            -- If reconciliation lands on an ordinary closure, the deferred
            -- lesson trigger auto-cancels that default-following occurrence.
$new$);

  if v_new = v_def then
    raise exception 'rebuild_future_regular_semester ordinary-closure guard not found';
  end if;
  execute v_new;
end;
$do$;
