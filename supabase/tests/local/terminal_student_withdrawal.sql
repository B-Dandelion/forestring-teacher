-- LOCAL QA ONLY. Synthetic identities/calendar, no production-derived data.
-- Run with psql -v ON_ERROR_STOP=1 after local migrations. All work rolls back.
-- Current dates are derived in KST; no dependency on seeded account IDs.
begin;

create temporary table qa_backdate_context (
  branch_id uuid, other_branch_id uuid, manager_id uuid, semester_id uuid, today date
);

create function pg_temp.qa_profile(p_role public.user_role, p_branch uuid)
returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role, email)
  values (v_id, 'authenticated', 'authenticated', v_id::text || '@backdate-qa.invalid');
  insert into public.profiles (id, display_name, role, branch_id)
  values (v_id, 'Backdate QA ' || v_id::text, p_role, p_branch);
  if p_role = 'student'::public.user_role then
    insert into public.students (id, student_type) values (v_id, 'flex');
    update public.student_enrollment_periods
    set starts_on = (now() at time zone 'Asia/Seoul')::date - 60
    where student_id = v_id;
  elsif p_role in ('teacher'::public.user_role, 'manager'::public.user_role) then
    insert into public.teachers (id) values (v_id);
  end if;
  return v_id;
end;
$$;

create function pg_temp.qa_actor(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_id::text, ''), true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
end;
$$;

create function pg_temp.qa_right(p_student uuid, p_status public.lesson_right_status)
returns uuid language plpgsql as $$
declare v_id uuid; v_context pg_temp.qa_backdate_context%rowtype;
begin
  select * into v_context from pg_temp.qa_backdate_context;
  insert into public.lesson_rights (
    student_id, branch_id, source_semester_id, usable_semester_id,
    origin, sequence_no, duration_minutes, status, reserved_at, consumed_at
  ) values (
    p_student, v_context.branch_id, v_context.semester_id, v_context.semester_id,
    'flex_base', (select coalesce(max(r.sequence_no), 0) + 1 from public.lesson_rights r where r.student_id = p_student),
    30, p_status,
    case when p_status = 'reserved' then now() end,
    case when p_status = 'consumed' then now() end
  ) returning id into v_id;
  return v_id;
end;
$$;

create function pg_temp.qa_lesson(
  p_student uuid, p_date date, p_status public.lesson_status default 'scheduled',
  p_right uuid default null, p_manual boolean default true
)
returns uuid language plpgsql as $$
declare v_id uuid; v_teacher uuid; v_context pg_temp.qa_backdate_context%rowtype;
begin
  select * into v_context from pg_temp.qa_backdate_context;
  v_teacher := pg_temp.qa_profile('teacher', v_context.branch_id);
  insert into public.lessons (
    student_id, teacher_id, starts_at, duration_minutes, lesson_type, status,
    canceled_at, canceled_by, lesson_right_id, manual_makeup_right_id
  ) values (
    p_student, v_teacher, (p_date + time '12:00') at time zone 'Asia/Seoul', 30,
    case when p_right is not null and not p_manual then 'flex'::public.lesson_type else 'makeup'::public.lesson_type end,
    p_status, case when p_status = 'canceled' then now() end,
    case when p_status = 'canceled' then v_context.manager_id end,
    case when not p_manual then p_right end, case when p_manual then p_right end
  ) returning id into v_id;
  return v_id;
end;
$$;

create function pg_temp.qa_expect_error(p_student uuid, p_date date, p_message text)
returns void language plpgsql as $$
begin
  begin
    perform public.schedule_student_withdrawal(p_student, p_date);
    raise exception 'TEST_FAIL expected %', p_message;
  exception when others then
    if sqlerrm <> p_message then raise; end if;
  end;
end;
$$;

-- Independent branch and a 28-day semester override around the execution date.
-- Its global range is far beyond existing semesters, so seeded calendars stay
-- untouched. Only the synthetic branch uses the date override.
do $fixture$
declare
  v_branch uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_semester uuid := gen_random_uuid();
  v_global_start date;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_manager uuid;
begin
  insert into public.branches (id, name) values
    (v_branch, 'Backdate QA ' || v_branch::text), (v_other, 'Backdate QA ' || v_other::text);
  select greatest(coalesce(max(ends_on), v_today), v_today) + 3650 into v_global_start from public.semesters;
  insert into public.semesters (id, code, starts_on, ends_on)
  values (v_semester, 'backdate-qa-' || v_semester::text, v_global_start, v_global_start + 27);
  insert into public.branch_semester_overrides (branch_id, semester_id, starts_on, ends_on)
  values (v_branch, v_semester, v_today - 21, v_today + 6);
  v_manager := pg_temp.qa_profile('manager', v_branch);
  insert into pg_temp.qa_backdate_context values (v_branch, v_other, v_manager, v_semester, v_today);
  perform pg_temp.qa_actor(v_manager);
end;
$fixture$;


-- Past scheduled/canceled lessons, completed plans, and historical assignments
-- are no longer vetoes. Source rows are archived and usable rights reach zero.
do $terminal$
declare
  c pg_temp.qa_backdate_context%rowtype;
  s uuid; before_lesson uuid; past_lesson uuid; canceled_lesson uuid; future_lesson uuid;
  before_right uuid; past_right uuid; canceled_right uuid; future_right uuid; spare_right uuid;
  event_id uuid; event_before jsonb; past_before jsonb; plan_before jsonb;
  assignment_id uuid; slot_id uuid; teacher_id uuid; result jsonb; archive_id uuid; archive_count integer;
begin
  select * into c from pg_temp.qa_backdate_context;
  s:=pg_temp.qa_profile('student',c.branch_id);
  before_right:=pg_temp.qa_right(s,'reserved');
  past_right:=pg_temp.qa_right(s,'consumed');
  canceled_right:=pg_temp.qa_right(s,'available');
  future_right:=pg_temp.qa_right(s,'consumed');
  spare_right:=pg_temp.qa_right(s,'available');
  before_lesson:=pg_temp.qa_lesson(s,c.today-15,'scheduled',before_right,false);
  past_lesson:=pg_temp.qa_lesson(s,c.today-13,'scheduled',past_right,false);
  canceled_lesson:=pg_temp.qa_lesson(s,c.today-12,'canceled',canceled_right,false);
  future_lesson:=pg_temp.qa_lesson(s,c.today+1,'scheduled',future_right,true);
  select to_jsonb(l) into past_before from public.lessons l where id=past_lesson;
  insert into public.lesson_cancellation_events(
    lesson_id,lesson_right_id,student_id,branch_id,origin,actor_id,counts_toward_limit,reason
  ) values(canceled_lesson,canceled_right,s,c.branch_id,'academy',c.manager_id,false,'terminal QA')
  returning id into event_id;
  select to_jsonb(e) into event_before from public.lesson_cancellation_events e where id=event_id;
  insert into public.student_semester_plans(
    student_id,branch_id,semester_id,student_type_snapshot,status,flex_base_right_count,flex_duration_minutes
  ) values(s,c.branch_id,c.semester_id,'flex','completed',4,30);
  select to_jsonb(sp) into plan_before from public.student_semester_plans sp where student_id=s;
  teacher_id:=pg_temp.qa_profile('teacher',c.branch_id);
  insert into public.teacher_student_assignments(student_id,teacher_id,starts_on,ends_on)
  values(s,teacher_id,c.today-10,c.today-9) returning id into assignment_id;
  update public.students set student_type='regular' where id=s;
  insert into public.regular_schedule_slots(student_id,branch_id,starts_on)
  values(s,c.branch_id,c.today-8) returning id into slot_id;

  result:=public.schedule_student_withdrawal(s,c.today-14);
  archive_id:=(result->>'finalizationId')::uuid;
  if (result->>'finalized')::boolean is distinct from true or archive_id is null
     or (result->>'deletedLessonCount')::integer<>3 then
    raise exception 'TEST_FAIL terminal result %',result;
  end if;
  if exists(select 1 from public.lessons where student_id=s and starts_at >= (c.today-14)::timestamp at time zone 'Asia/Seoul')
     or not exists(select 1 from public.lessons where id=before_lesson)
     or (select status from public.students where id=s)<>'withdrawn'
     or (select withdrawal_date from public.students where id=s)<>c.today-14
     or (select is_active from public.profiles where id=s)
     or (select ends_on from public.student_enrollment_periods where student_id=s)<>c.today-15 then
    raise exception 'TEST_FAIL terminal boundary/student/enrollment';
  end if;
  if exists(select 1 from public.lesson_rights where student_id=s and status in ('available','reserved'))
     or (select status from public.lesson_rights where id=before_right)<>'consumed'
     or (select status from public.lesson_rights where id=past_right)<>'revoked'
     or (select status from public.lesson_rights where id=future_right)<>'revoked' then
    raise exception 'TEST_FAIL terminal entitlement balance';
  end if;
  if event_before is distinct from (select to_jsonb(e) from public.lesson_cancellation_events e where id=event_id)
     or plan_before is distinct from (select to_jsonb(sp) from public.student_semester_plans sp where student_id=s) then
    raise exception 'TEST_FAIL immutable cancellation/completed-plan history changed';
  end if;
  if not exists(select 1 from private.student_withdrawal_lesson_snapshots
       where finalization_id=archive_id and lesson_id=past_lesson and lesson_snapshot=past_before
         and closed_at is not null and resolution='finalized')
     or (select count(*) from private.student_withdrawal_lesson_snapshots where finalization_id=archive_id)<>3
     or not exists(select 1 from private.student_withdrawal_finalization_archives a
       where a.id=archive_id and jsonb_array_length(a.assignments_snapshot)=1
         and jsonb_array_length(a.slots_snapshot)=1 and jsonb_array_length(a.plans_snapshot)=1
         and jsonb_array_length(a.rights_snapshot)=5)
     or exists(select 1 from public.teacher_student_assignments where id=assignment_id)
     or not exists(select 1 from public.regular_schedule_slots where id=slot_id and ends_on=starts_on) then
    raise exception 'TEST_FAIL removed records were not archived';
  end if;
  select count(*) into archive_count from private.student_withdrawal_finalization_archives where student_id=s;
  result:=public.schedule_student_withdrawal(s,c.today-14);
  if (result->>'changed')::boolean or (select count(*) from private.student_withdrawal_finalization_archives where student_id=s)<>archive_count then
    raise exception 'TEST_FAIL repeated finalization duplicated archive';
  end if;
  begin
    update private.student_withdrawal_finalization_archives set withdrawal_date=c.today where id=archive_id;
    raise exception 'TEST_FAIL mutable finalization archive';
  exception when others then
    if sqlerrm<>'FORESTRING_WITHDRAWAL_ARCHIVE_IMMUTABLE' then raise; end if;
  end;
  begin
    delete from private.student_withdrawal_lesson_snapshots where finalization_id=archive_id;
    raise exception 'TEST_FAIL mutable lesson archive';
  exception when others then
    if sqlerrm<>'FORESTRING_WITHDRAWAL_ARCHIVE_IMMUTABLE' then raise; end if;
  end;
end;
$terminal$;

-- A previously precleared reservation, even elapsed/changed, is retained as
-- archival evidence. A consumed right still used BEFORE withdrawal stays used.
do $pending$
declare
  c pg_temp.qa_backdate_context%rowtype;
  s uuid; held uuid; old_lesson uuid; kept_lesson uuid; result jsonb;
  original jsonb; changed_consumed_at timestamptz; archive_id uuid;
begin
  select * into c from pg_temp.qa_backdate_context;
  s:=pg_temp.qa_profile('student',c.branch_id);
  held:=pg_temp.qa_right(s,'consumed');
  old_lesson:=pg_temp.qa_lesson(s,c.today+3,'scheduled',held,true);
  perform public.schedule_student_withdrawal(s,c.today+2);
  -- Simulate the old reservation having elapsed; do not rewrite its payload.
  update private.student_withdrawal_lesson_snapshots
    set starts_at=(c.today-1)::timestamp at time zone 'Asia/Seoul'
    where student_id=s and closed_at is null;
  select lesson_snapshot into original from private.student_withdrawal_lesson_snapshots
    where student_id=s and closed_at is null;
  update public.lesson_rights set consumed_at=now()-interval '1 day' where id=held;
  result:=public.schedule_student_withdrawal(s,c.today-3);
  archive_id:=(result->>'finalizationId')::uuid;
  if not exists(select 1 from private.student_withdrawal_lesson_snapshots
       where finalization_id=archive_id and lesson_id=old_lesson and lesson_snapshot=original
         and resolution='finalized' and closed_at is not null)
     or exists(select 1 from public.lessons where id=old_lesson)
     or (select status from public.lesson_rights where id=held)<>'revoked'
     or (result->>'restoredLessonCount')::integer<>0 then
    raise exception 'TEST_FAIL old pending reservation lost/restored';
  end if;
  perform public.reactivate_student(s);
  if exists(select 1 from public.lessons where id=old_lesson)
     or exists(select 1 from private.student_withdrawal_lesson_snapshots where student_id=s and closed_at is null)
     or (select status from public.lesson_rights where id=held)<>'revoked' then
    raise exception 'TEST_FAIL reactivation revived retired reservation';
  end if;

  s:=pg_temp.qa_profile('student',c.branch_id);
  held:=pg_temp.qa_right(s,'consumed');
  old_lesson:=pg_temp.qa_lesson(s,c.today+3,'scheduled',held,true);
  perform public.schedule_student_withdrawal(s,c.today+2);
  kept_lesson:=pg_temp.qa_lesson(s,c.today-10,'scheduled',held,true);
  select consumed_at into changed_consumed_at from public.lesson_rights where id=held;
  perform public.schedule_student_withdrawal(s,c.today-3);
  if not exists(select 1 from public.lessons where id=kept_lesson)
     or (select status from public.lesson_rights where id=held)<>'consumed'
     or (select consumed_at from public.lesson_rights where id=held) is distinct from changed_consumed_at then
    raise exception 'TEST_FAIL preserved historical use was revoked';
  end if;
end;
$pending$;

-- Closed-semester carryover identities remain intact; all unused descendants
-- retire without reopening a completed plan or issuing replacement rights.
do $carryover$
declare
  c pg_temp.qa_backdate_context%rowtype;
  s uuid; source_sem uuid:=gen_random_uuid(); parent uuid:=gen_random_uuid();
  child uuid:=gen_random_uuid(); source_start date; plan_before jsonb;
begin
  select * into c from pg_temp.qa_backdate_context;
  s:=pg_temp.qa_profile('student',c.branch_id);
  select max(ends_on)+100 into source_start from public.semesters;
  insert into public.semesters(id,code,starts_on,ends_on)
  values(source_sem,'terminal-closed-'||source_sem::text,source_start,source_start+27);
  insert into public.branch_semester_overrides(branch_id,semester_id,starts_on,ends_on)
  values(c.branch_id,source_sem,c.today-49,c.today-22);
  insert into public.student_semester_plans(student_id,branch_id,semester_id,
    student_type_snapshot,status,flex_base_right_count,flex_duration_minutes)
  values(s,c.branch_id,source_sem,'flex','completed',4,30);
  select to_jsonb(sp) into plan_before from public.student_semester_plans sp where student_id=s;
  insert into public.lesson_rights(id,student_id,branch_id,source_semester_id,usable_semester_id,
    origin,sequence_no,duration_minutes,status)
  values(parent,s,c.branch_id,source_sem,source_sem,'flex_base',1,30,'expired');
  insert into public.lesson_rights(id,student_id,branch_id,source_semester_id,usable_semester_id,
    source_right_id,origin,sequence_no,duration_minutes,status,carryover_count)
  values(child,s,c.branch_id,source_sem,c.semester_id,parent,'carryover',1,30,'available',1);
  perform public.schedule_student_withdrawal(s,c.today-30);
  if (select status from public.lesson_rights where id=parent)<>'expired'
     or (select status from public.lesson_rights where id=child)<>'revoked'
     or (select source_right_id from public.lesson_rights where id=child)<>parent
     or (select count(*) from public.lesson_rights where student_id=s)<>2
     or plan_before is distinct from (select to_jsonb(sp) from public.student_semester_plans sp where student_id=s) then
    raise exception 'TEST_FAIL closed plan/carryover history changed';
  end if;
end;
$carryover$;

-- Actual regular-series versions and legacy credits are archived as well.
-- A pre-boundary canceled lesson survives; a post-boundary version is removed.
do $regular_versions$
declare
  c pg_temp.qa_backdate_context%rowtype;
  s uuid; teacher_id uuid; slot_a uuid; slot_b uuid; series_a uuid; series_b uuid;
  kept uuid; removed uuid; right_id uuid; credit_a uuid; credit_b uuid; result jsonb;
begin
  select * into c from pg_temp.qa_backdate_context;
  s:=pg_temp.qa_profile('student',c.branch_id);
  teacher_id:=pg_temp.qa_profile('teacher',c.branch_id);
  update public.students set student_type='regular' where id=s;
  insert into public.regular_schedule_slots(student_id,branch_id,starts_on)
    values(s,c.branch_id,c.today-20) returning id into slot_a;
  insert into public.regular_schedule_slots(student_id,branch_id,starts_on)
    values(s,c.branch_id,c.today-5) returning id into slot_b;
  insert into public.lesson_series(student_id,teacher_id,weekday,start_time,duration_minutes,
    effective_from,branch_id,schedule_slot_id)
    values(s,teacher_id,1,time '18:00',30,c.today-20,c.branch_id,slot_a) returning id into series_a;
  insert into public.lesson_series(student_id,teacher_id,weekday,start_time,duration_minutes,
    effective_from,branch_id,schedule_slot_id)
    values(s,teacher_id,2,time '19:00',30,c.today-5,c.branch_id,slot_b) returning id into series_b;
  insert into public.lesson_rights(student_id,branch_id,source_semester_id,usable_semester_id,
    schedule_slot_id,origin,sequence_no,duration_minutes,status,consumed_at)
    values(s,c.branch_id,c.semester_id,c.semester_id,slot_b,'regular_base',1,30,'consumed',now())
    returning id into right_id;
  insert into public.lessons(series_id,student_id,teacher_id,occurrence_at,starts_at,
    duration_minutes,lesson_type,status,canceled_at,canceled_by)
    values(series_a,s,teacher_id,(c.today-10+time '18:00') at time zone 'Asia/Seoul',
      (c.today-10+time '18:00') at time zone 'Asia/Seoul',30,'regular','canceled',now(),c.manager_id)
    returning id into kept;
  insert into public.lessons(series_id,student_id,teacher_id,occurrence_at,starts_at,
    duration_minutes,lesson_type,status,canceled_at,canceled_by,lesson_right_id)
    values(series_b,s,teacher_id,(c.today-3+time '19:00') at time zone 'Asia/Seoul',
      (c.today-3+time '19:00') at time zone 'Asia/Seoul',30,'regular','canceled',now(),c.manager_id,right_id)
    returning id into removed;
  insert into public.lesson_rebooking_credits(student_id,source_lesson_id,source_series_id,
    source_semester_id,usable_semester_id,teacher_id,duration_minutes,cancellation_no)
    values(s,kept,series_a,c.semester_id,c.semester_id,teacher_id,30,1) returning id into credit_a;
  insert into public.lesson_rebooking_credits(student_id,source_lesson_id,source_series_id,
    source_semester_id,usable_semester_id,teacher_id,duration_minutes,cancellation_no)
    values(s,removed,series_b,c.semester_id,c.semester_id,teacher_id,30,1) returning id into credit_b;
  result:=public.schedule_student_withdrawal(s,c.today-7);
  if not exists(select 1 from public.lessons where id=kept)
     or exists(select 1 from public.lessons where id=removed)
     or exists(select 1 from public.lesson_series where id=series_b)
     or not exists(select 1 from public.lesson_series where id=series_a and effective_until=c.today-8)
     or (select status from public.lesson_rights where id=right_id)<>'revoked'
     or (select status from public.lesson_rebooking_credits where id=credit_a)<>'expired'
     or exists(select 1 from public.lesson_rebooking_credits where id=credit_b)
     or not exists(select 1 from private.student_withdrawal_finalization_archives
       where id=(result->>'finalizationId')::uuid and jsonb_array_length(series_snapshot)=2
         and jsonb_array_length(legacy_credits_snapshot)=2) then
    raise exception 'TEST_FAIL regular versions/legacy credits were not retired and archived %',result;
  end if;
end;
$regular_versions$;

-- Today is also atomic. Midnight on the chosen KST date is inclusive.
do $today_and_future$
declare
  c pg_temp.qa_backdate_context%rowtype;
  s uuid; l uuid; kept uuid; result jsonb; teacher_id uuid;
begin
  select * into c from pg_temp.qa_backdate_context;
  s:=pg_temp.qa_profile('student',c.branch_id);
  kept:=pg_temp.qa_lesson(s,c.today-1);
  l:=pg_temp.qa_lesson(s,c.today,'canceled');
  update public.lessons set starts_at=c.today::timestamp at time zone 'Asia/Seoul' where id=l;
  result:=public.schedule_student_withdrawal(s,c.today);
  if (result->>'finalized')::boolean is distinct from true
     or exists(select 1 from public.lessons where id=l)
     or not exists(select 1 from public.lessons where id=kept) then
    raise exception 'TEST_FAIL today midnight boundary/atomic finalization';
  end if;

  s:=pg_temp.qa_profile('student',c.branch_id);
  l:=pg_temp.qa_lesson(s,c.today+4);
  select lesson_row.teacher_id into teacher_id from public.lessons lesson_row where lesson_row.id=l;
  insert into public.teacher_work_hours(teacher_id,weekday,start_time,end_time)
  select teacher_id,weekday::smallint,time '00:00',time '23:45' from generate_series(1,7) weekday;
  result:=public.schedule_student_withdrawal(s,c.today+2);
  if (result->>'finalized')::boolean or not (select is_active from public.profiles where id=s)
     or exists(select 1 from public.lessons where id=l) then
    raise exception 'TEST_FAIL future reservation changed';
  end if;
  -- Moving later restores the original lesson; cancelling clears the boundary.
  result:=public.schedule_student_withdrawal(s,c.today+6);
  if not exists(select 1 from public.lessons where id=l) then
    raise exception 'TEST_FAIL future postponement did not restore booking %',result;
  end if;
  perform public.cancel_student_withdrawal(s);
  if (select withdrawal_date from public.students where id=s) is not null
     or not exists(select 1 from public.lessons where id=l)
     or exists(select 1 from private.student_withdrawal_finalization_archives where student_id=s) then
    raise exception 'TEST_FAIL future cancellation created terminal archive';
  end if;
end;
$today_and_future$;

create function pg_temp.qa_terminal_failure() returns trigger language plpgsql as $failure$
begin
  if not new.is_active and new.id::text=current_setting('forestring.qa_fail_student',true) then
    if current_setting('forestring.qa_lock_failure',true)='on' then
      raise exception using errcode='55P03',message='QA_BUSY_FINALIZATION';
    end if;
    raise exception 'QA_FORCED_FINALIZATION_FAILURE';
  end if;
  return new;
end;
$failure$;
create trigger qa_terminal_failure before update of is_active on public.profiles
for each row execute function pg_temp.qa_terminal_failure();
do $rollback$
declare
  c pg_temp.qa_backdate_context%rowtype;
  s uuid; r uuid; l uuid; failure text;
begin
  select * into c from pg_temp.qa_backdate_context;
  foreach failure in array array['QA_FORCED_FINALIZATION_FAILURE','FORESTRING_STUDENT_SETTLEMENT_BUSY'] loop
    s:=pg_temp.qa_profile('student',c.branch_id);
    r:=pg_temp.qa_right(s,'consumed');
    l:=pg_temp.qa_lesson(s,c.today-1,'scheduled',r,true);
    perform set_config('forestring.qa_fail_student',s::text,true);
    perform set_config('forestring.qa_lock_failure',case when failure='FORESTRING_STUDENT_SETTLEMENT_BUSY' then 'on' else 'off' end,true);
    perform pg_temp.qa_expect_error(s,c.today-3,failure);
    if (select withdrawal_date from public.students where id=s) is not null
       or (select ends_on from public.student_enrollment_periods where student_id=s) is not null
       or not exists(select 1 from public.lessons where id=l)
       or (select status from public.lesson_rights where id=r)<>'consumed'
       or exists(select 1 from private.student_withdrawal_finalization_archives where student_id=s)
       or exists(select 1 from private.student_withdrawal_lesson_snapshots where student_id=s)
       or exists(select 1 from public.audit_events where subject_profile_id=s) then
      raise exception 'TEST_FAIL partial terminal commit after %',failure;
    end if;
  end loop;
  perform set_config('forestring.qa_fail_student','',true);
  perform set_config('forestring.qa_lock_failure','off',true);
end;
$rollback$;
drop trigger qa_terminal_failure on public.profiles;

do $cron$
declare c pg_temp.qa_backdate_context%rowtype; s uuid; l uuid; result jsonb;
begin
  select * into c from pg_temp.qa_backdate_context;
  s:=pg_temp.qa_profile('student',c.branch_id);
  l:=pg_temp.qa_lesson(s,c.today-1);
  update public.students set withdrawal_date=c.today-3 where id=s;
  perform pg_temp.qa_actor(null);
  perform set_config('forestring.system_withdrawal','cron',true);
  result:=public.finalize_student_withdrawal(s);
  if (result->>'changed')::boolean is distinct from true
     or exists(select 1 from public.lessons where id=l)
     or not exists(select 1 from private.student_withdrawal_finalization_archives
         where id=(result->>'finalizationId')::uuid and actor_id is null)
     or not exists(select 1 from private.student_withdrawal_lesson_snapshots
         where lesson_id=l and finalization_id=(result->>'finalizationId')::uuid) then
    raise exception 'TEST_FAIL delayed cron terminal finalization';
  end if;
  perform set_config('forestring.system_withdrawal','',true);
  perform pg_temp.qa_actor(c.manager_id);
end;
$cron$;

do $authorization_and_enrollment$
declare c pg_temp.qa_backdate_context%rowtype; s uuid; other uuid; teacher_id uuid;
begin
  select * into c from pg_temp.qa_backdate_context;
  s:=pg_temp.qa_profile('student',c.branch_id);
  other:=pg_temp.qa_profile('student',c.other_branch_id);
  perform pg_temp.qa_expect_error(s,c.today-60,'FORESTRING_STUDENT_WITHDRAWAL_BEFORE_ENROLLMENT');
  perform pg_temp.qa_expect_error(other,c.today-3,'FORESTRING_MANAGER_BRANCH_FORBIDDEN');
  teacher_id:=pg_temp.qa_profile('teacher',c.branch_id);
  perform pg_temp.qa_actor(teacher_id);
  perform pg_temp.qa_expect_error(s,c.today-3,'FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN');
  perform pg_temp.qa_actor(null);
  perform pg_temp.qa_expect_error(s,c.today-3,'FORESTRING_AUTH_REQUIRED');
  perform pg_temp.qa_actor(c.manager_id);
  if has_table_privilege('authenticated','private.student_withdrawal_finalization_archives','SELECT')
     or has_function_privilege('authenticated','private.archive_student_withdrawal_finalization(uuid,date,uuid)','EXECUTE')
     or has_function_privilege('anon','public.finalize_student_withdrawal(uuid)','EXECUTE') then
    raise exception 'TEST_FAIL private archive/RPC exposure';
  end if;
end;
$authorization_and_enrollment$;
select 'PASS: terminal withdrawal / archived past+canceled lessons / zero usable rights / closed plans+carryovers / pending snapshots / atomic rollback / future reservations / authorization' as result;
rollback;
