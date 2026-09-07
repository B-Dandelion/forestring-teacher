do $patch$
declare
  v_oid regprocedure;
  v_def text;
  v_new text;
begin
  v_oid := to_regprocedure('private.ensure_semester_plan_materialized(uuid,uuid)');
  v_def := pg_get_functiondef(v_oid);
  v_new := replace(
    v_def,
    $$  if v_withdrawal_date is not null and v_withdrawal_date <= v_semester_end then
    return jsonb_build_object(
      'studentId',p_student_id,'semesterId',p_semester_id,
      'changed',false,'skipped',true,'reason','withdrawal_within_semester'
    );
  end if;$$,
    $$  if v_withdrawal_date is not null and v_withdrawal_date <= v_semester_start then
    return jsonb_build_object(
      'studentId',p_student_id,'semesterId',p_semester_id,
      'changed',false,'skipped',true,'reason','withdrawal_before_semester'
    );
  end if;$$
  );
  if v_new = v_def then
    raise exception 'ensure_semester_plan_materialized withdrawal patch target not found';
  end if;
  execute v_new;

  v_oid := to_regprocedure('public.activate_student_semester_plan(uuid)');
  v_def := pg_get_functiondef(v_oid);
  v_new := replace(
    v_def,
    $$  v_student_status public.student_status;
  v_semester_start date;$$,
    $$  v_student_status public.student_status;
  v_withdrawal_date date;
  v_semester_start date;$$
  );
  if v_new = v_def then
    raise exception 'activate_student_semester_plan declaration patch target not found';
  end if;
  v_def := v_new;

  v_new := replace(
    v_def,
    $$  select p.branch_id, p.is_active, s.status
  into v_student_branch_id, v_student_profile_active, v_student_status$$,
    $$  select p.branch_id, p.is_active, s.status, s.withdrawal_date
  into v_student_branch_id, v_student_profile_active, v_student_status, v_withdrawal_date$$
  );
  if v_new = v_def then
    raise exception 'activate_student_semester_plan student select patch target not found';
  end if;
  v_def := v_new;

  v_new := replace(
    v_def,
    $$  if v_plan.student_type_snapshot <> 'regular'::public.student_type then
    raise exception using errcode='P0001', message='FORESTRING_UNKNOWN_STUDENT_TYPE';
  end if;

  select count(*)::integer into v_slot_count$$,
    $$  if v_plan.student_type_snapshot <> 'regular'::public.student_type then
    raise exception using errcode='P0001', message='FORESTRING_UNKNOWN_STUDENT_TYPE';
  end if;

  if v_withdrawal_date is not null then
    v_semester_end := least(v_semester_end, v_withdrawal_date - 1);
  end if;

  if v_semester_end < v_semester_start then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_ACTIVE_IN_SEMESTER';
  end if;

  select count(*)::integer into v_slot_count$$
  );
  if v_new = v_def then
    raise exception 'activate_student_semester_plan materialization end patch target not found';
  end if;
  execute v_new;

  v_oid := to_regprocedure('private.run_due_semester_automation(date)');
  v_def := pg_get_functiondef(v_oid);
  v_new := replace(v_def,$$  v_next_semester_id uuid;
  v_next_end date;$$,$$  v_next_semester_id uuid;
  v_next_start date;
  v_next_end date;$$);
  if v_new = v_def then raise exception 'run_due_semester_automation declaration patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,$$      v_next_semester_id := null;
      v_next_end := null;$$,$$      v_next_semester_id := null;
      v_next_start := null;
      v_next_end := null;$$);
  if v_new = v_def then raise exception 'run_due_semester_automation reset patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,$$      select sem.id,e.ends_on
      into v_next_semester_id,v_next_end$$,$$      select sem.id,e.starts_on,e.ends_on
      into v_next_semester_id,v_next_start,v_next_end$$);
  if v_new = v_def then raise exception 'run_due_semester_automation next bounds patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,$$      if v_student.withdrawal_date is not null and v_student.withdrawal_date <= v_next_end then$$,$$      if v_student.withdrawal_date is not null and v_student.withdrawal_date <= v_next_start then$$);
  if v_new = v_def then raise exception 'run_due_semester_automation withdrawal condition patch target not found'; end if;
  execute v_new;

  v_oid := to_regprocedure('public.set_next_semester_student_type(uuid,public.student_type,integer,integer,jsonb)');
  v_def := pg_get_functiondef(v_oid);
  v_new := replace(v_def,$$  v_next_start date;
  v_next_end date;$$,$$  v_next_start date;
  v_next_end date;
  v_next_active_end date;$$);
  if v_new = v_def then raise exception 'set_next_semester_student_type declaration patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,$$  if v_withdrawal_date is not null and v_withdrawal_date<=v_next_end then
    raise exception using errcode='P0001',message='FORESTRING_NEXT_TYPE_CHANGE_WITHDRAWAL_CONFLICT';
  end if;$$,$$  if v_withdrawal_date is not null and v_withdrawal_date<=v_next_start then
    raise exception using errcode='P0001',message='FORESTRING_NEXT_TYPE_CHANGE_WITHDRAWAL_CONFLICT';
  end if;
  v_next_active_end := least(v_next_end, coalesce(v_withdrawal_date - 1, v_next_end));$$);
  if v_new = v_def then raise exception 'set_next_semester_student_type withdrawal patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,'    and rs.starts_on<=v_next_end','    and rs.starts_on<=v_next_active_end');
  if v_new = v_def then raise exception 'set_next_semester_student_type schedule end patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,'        and (a.ends_on is null or a.ends_on>=v_next_end)','        and (a.ends_on is null or a.ends_on>=v_next_active_end)');
  if v_new = v_def then raise exception 'set_next_semester_student_type assignment coverage patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,'      if v_teacher_withdrawal_date is not null and v_teacher_withdrawal_date<=v_next_end then','      if v_teacher_withdrawal_date is not null and v_teacher_withdrawal_date<=v_next_active_end then');
  if v_new = v_def then raise exception 'set_next_semester_student_type teacher withdrawal patch target not found'; end if;
  execute v_new;

  v_oid := to_regprocedure('public.get_next_semester_student_type_plan(uuid)');
  v_def := pg_get_functiondef(v_oid);
  v_new := replace(v_def,$$  v_next_start date;
  v_next_end date;$$,$$  v_next_start date;
  v_next_end date;
  v_next_active_end date;$$);
  if v_new = v_def then raise exception 'get_next_semester_student_type_plan declaration patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,$$  if v_next_semester_id is null then
    raise exception using errcode='P0001',message='FORESTRING_NEXT_SEMESTER_NOT_FOUND';
  end if;

  select * into v_plan$$,$$  if v_next_semester_id is null then
    raise exception using errcode='P0001',message='FORESTRING_NEXT_SEMESTER_NOT_FOUND';
  end if;

  v_next_active_end := least(v_next_end, coalesce(v_withdrawal_date - 1, v_next_end));

  select * into v_plan$$);
  if v_new = v_def then raise exception 'get_next_semester_student_type_plan active end patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,'    and rs.starts_on<=v_next_end','    and rs.starts_on<=v_next_active_end');
  if v_new = v_def then raise exception 'get_next_semester_student_type_plan schedule end patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,'         (a.starts_on<=v_next_start and (a.ends_on is null or a.ends_on>=v_next_end))','         (a.starts_on<=v_next_start and (a.ends_on is null or a.ends_on>=v_next_active_end))');
  if v_new = v_def then raise exception 'get_next_semester_student_type_plan assignment coverage patch target not found'; end if;
  v_def := v_new;
  v_new := replace(v_def,$$    'canChange',v_today<v_next_start and (v_withdrawal_date is null or v_withdrawal_date>v_next_end)$$,$$    'canChange',v_today<v_next_start and (v_withdrawal_date is null or v_withdrawal_date>v_next_start)$$);
  if v_new = v_def then raise exception 'get_next_semester_student_type_plan canChange patch target not found'; end if;
  execute v_new;
end;
$patch$;
