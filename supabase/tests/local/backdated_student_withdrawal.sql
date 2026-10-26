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

-- A safe backdate retains past reserved/consumed rights and lessons exactly,
-- while future scheduled manual rights are released then revoked atomically.
do $safe_backdate$
declare
  c pg_temp.qa_backdate_context%rowtype;
  v_student uuid; v_past uuid; v_past_manual uuid; v_future uuid;
  v_past_right uuid; v_consumed_right uuid; v_future_right uuid;
  v_before jsonb; v_after jsonb; v_result jsonb;
begin
  select * into c from pg_temp.qa_backdate_context;
  v_student := pg_temp.qa_profile('student', c.branch_id);
  v_past_right := pg_temp.qa_right(v_student, 'reserved');
  v_consumed_right := pg_temp.qa_right(v_student, 'consumed');
  v_future_right := pg_temp.qa_right(v_student, 'consumed');
  v_past := pg_temp.qa_lesson(v_student, c.today - 10, 'scheduled', v_past_right, false);
  v_past_manual := pg_temp.qa_lesson(v_student, c.today - 9, 'scheduled', v_consumed_right, true);
  v_future := pg_temp.qa_lesson(v_student, c.today + 1, 'scheduled', v_future_right, true);
  select jsonb_agg(to_jsonb(l) order by l.id) into v_before from public.lessons l where l.id in (v_past, v_past_manual);
  v_result := public.schedule_student_withdrawal(v_student, c.today - 3);
  if not (v_result ->> 'finalized')::boolean or (v_result ->> 'deletedLessonCount')::integer <> 1
     or (v_result ->> 'revokedRightCount')::integer <> 1 then
    raise exception 'TEST_FAIL backdate response %', v_result;
  end if;
  select jsonb_agg(to_jsonb(l) order by l.id) into v_after from public.lessons l where l.id in (v_past, v_past_manual);
  if v_before is distinct from v_after then raise exception 'TEST_FAIL historical lessons changed'; end if;
  if exists (select 1 from public.lessons where id = v_future) then raise exception 'TEST_FAIL future lesson retained'; end if;
  if (select status from public.lesson_rights where id = v_past_right) <> 'consumed'
     or (select status from public.lesson_rights where id = v_consumed_right) <> 'consumed'
     or (select status from public.lesson_rights where id = v_future_right) <> 'revoked' then
    raise exception 'TEST_FAIL historical/future right settlement';
  end if;
  if not exists (select 1 from public.student_enrollment_periods where student_id = v_student and ends_on = c.today - 4 and end_reason = 'withdrawal')
     or not exists (select 1 from public.students where id = v_student and status = 'withdrawn')
     or (select is_active from public.profiles where id = v_student) then
    raise exception 'TEST_FAIL withdrawal/enrollment/profile state';
  end if;
  v_result := public.schedule_student_withdrawal(v_student, c.today - 3);
  if (v_result ->> 'changed')::boolean or not (v_result ->> 'finalized')::boolean then
    raise exception 'TEST_FAIL replay not idempotent %', v_result;
  end if;
end;
$safe_backdate$;

-- Both scheduled and canceled past rows at/after the exact KST cutoff block
-- the whole request. Every row, right, enrollment date, and audit stays intact.
do $history_conflicts$
declare
  c pg_temp.qa_backdate_context%rowtype;
  v_student uuid; v_lesson uuid; v_right uuid; v_status public.lesson_status;
  v_before jsonb; v_after jsonb; v_audits integer;
begin
  select * into c from pg_temp.qa_backdate_context;
  foreach v_status in array array['scheduled'::public.lesson_status, 'canceled'::public.lesson_status] loop
    v_student := pg_temp.qa_profile('student', c.branch_id);
    v_right := pg_temp.qa_right(v_student, 'consumed');
    v_lesson := pg_temp.qa_lesson(v_student, c.today - 3, v_status, v_right, true);
    update public.lessons set starts_at = (c.today - 3)::timestamp at time zone 'Asia/Seoul' where id = v_lesson;
    select to_jsonb(l) into v_before from public.lessons l where id = v_lesson;
    select count(*) into v_audits from public.audit_events where subject_profile_id = v_student;
    perform pg_temp.qa_expect_error(v_student, c.today - 3, 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT');
    select to_jsonb(l) into v_after from public.lessons l where id = v_lesson;
    if v_before is distinct from v_after
       or (select withdrawal_date from public.students where id = v_student) is not null
       or (select ends_on from public.student_enrollment_periods where student_id = v_student) is not null
       or (select status from public.lesson_rights where id = v_right) <> 'consumed'
       or (select count(*) from public.audit_events where subject_profile_id = v_student) <> v_audits then
      raise exception 'TEST_FAIL conflicting history changed';
    end if;
  end loop;
end;
$history_conflicts$;

do $cancellation_ledger$
declare
  c pg_temp.qa_backdate_context%rowtype;
  v_student uuid; v_right uuid; v_lesson uuid; v_event uuid; v_before jsonb; v_after jsonb;
begin
  select * into c from pg_temp.qa_backdate_context;
  v_student := pg_temp.qa_profile('student', c.branch_id);
  v_right := pg_temp.qa_right(v_student, 'available');
  v_lesson := pg_temp.qa_lesson(v_student, c.today - 2, 'canceled', v_right, false);
  insert into public.lesson_cancellation_events (
    lesson_id, lesson_right_id, student_id, branch_id, origin, actor_id, counts_toward_limit, reason
  ) values (v_lesson, v_right, v_student, c.branch_id, 'academy', c.manager_id, false, 'synthetic cancellation')
  returning id into v_event;
  select to_jsonb(e) into v_before from public.lesson_cancellation_events e where id = v_event;
  perform pg_temp.qa_expect_error(v_student, c.today - 3, 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT');
  select to_jsonb(e) into v_after from public.lesson_cancellation_events e where id = v_event;
  if v_before is distinct from v_after or not exists (select 1 from public.lessons where id = v_lesson)
     or (select status from public.lesson_rights where id = v_right) <> 'available' then
    raise exception 'TEST_FAIL cancellation ledger/right changed';
  end if;
end;
$cancellation_ledger$;

do $enrollment_and_settlement$
declare
  c pg_temp.qa_backdate_context%rowtype;
  v_student uuid; v_teacher uuid; v_row uuid;
begin
  select * into c from pg_temp.qa_backdate_context;
  v_student := pg_temp.qa_profile('student', c.branch_id);
  -- Simulated re-enrollment starts yesterday; an older enrollment must not
  -- allow withdrawing before the latest registration.
  update public.student_enrollment_periods set ends_on = c.today - 10 where student_id = v_student;
  insert into public.student_enrollment_periods (student_id, branch_id, starts_on, start_reason)
  values (v_student, c.branch_id, c.today - 1, 'reactivation');
  perform pg_temp.qa_expect_error(v_student, c.today - 2, 'FORESTRING_STUDENT_WITHDRAWAL_BEFORE_ENROLLMENT');
  perform pg_temp.qa_expect_error(v_student, c.today - 1, 'FORESTRING_STUDENT_WITHDRAWAL_BEFORE_ENROLLMENT');

  v_student := pg_temp.qa_profile('student', c.branch_id);
  insert into public.student_semester_plans (
    student_id, semester_id, branch_id, student_type_snapshot,
    flex_base_right_count, flex_duration_minutes, status
  ) values (v_student, c.semester_id, c.branch_id, 'flex', 4, 30, 'completed');
  perform pg_temp.qa_expect_error(v_student, c.today - 3, 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT');
  if not exists (select 1 from public.student_semester_plans where student_id = v_student and status = 'completed') then
    raise exception 'TEST_FAIL completed settlement changed';
  end if;

  v_student := pg_temp.qa_profile('student', c.branch_id);
  v_teacher := pg_temp.qa_profile('teacher', c.branch_id);
  insert into public.teacher_student_assignments (student_id, teacher_id, starts_on, ends_on)
  values (v_student, v_teacher, c.today - 2, c.today - 1) returning id into v_row;
  perform pg_temp.qa_expect_error(v_student, c.today - 3, 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT');
  if not exists (select 1 from public.teacher_student_assignments where id = v_row and ends_on = c.today - 1) then
    raise exception 'TEST_FAIL historical assignment changed';
  end if;

  v_student := pg_temp.qa_profile('student', c.branch_id);
  update public.students set student_type = 'regular' where id = v_student;
  insert into public.regular_schedule_slots (student_id, branch_id, starts_on)
  values (v_student, c.branch_id, c.today - 2) returning id into v_row;
  perform pg_temp.qa_expect_error(v_student, c.today - 3, 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT');
  if not exists (select 1 from public.regular_schedule_slots where id = v_row and ends_on is null) then
    raise exception 'TEST_FAIL historical schedule identity changed';
  end if;
end;
$enrollment_and_settlement$;

-- Future reservation/cancellation behavior is unchanged. A precleared manual
-- right must also settle correctly if that future date moves into the past.
do $future_snapshots$
declare
  c pg_temp.qa_backdate_context%rowtype;
  v_student uuid; v_right uuid; v_lesson uuid; v_result jsonb;
begin
  select * into c from pg_temp.qa_backdate_context;
  v_student := pg_temp.qa_profile('student', c.branch_id);
  v_right := pg_temp.qa_right(v_student, 'consumed');
  v_lesson := pg_temp.qa_lesson(v_student, c.today + 3, 'scheduled', v_right, true);
  v_result := public.schedule_student_withdrawal(v_student, c.today + 2);
  if (v_result ->> 'finalized')::boolean or (v_result ->> 'deletedLessonCount')::integer <> 1 then
    raise exception 'TEST_FAIL future reservation changed %', v_result;
  end if;
  if not exists (select 1 from private.student_withdrawal_lesson_snapshots where student_id = v_student and closed_at is null)
     or (select status from public.lesson_rights where id = v_right) <> 'consumed' then
    raise exception 'TEST_FAIL future snapshot behavior changed';
  end if;
  v_result := public.schedule_student_withdrawal(v_student, c.today - 3);
  if not (v_result ->> 'finalized')::boolean
     or (select status from public.lesson_rights where id = v_right) <> 'revoked'
     or exists (select 1 from private.student_withdrawal_lesson_snapshots where student_id = v_student and closed_at is null) then
    raise exception 'TEST_FAIL precleared manual right not settled %', v_result;
  end if;

  v_student := pg_temp.qa_profile('student', c.branch_id);
  perform public.schedule_student_withdrawal(v_student, c.today + 2);
  perform public.cancel_student_withdrawal(v_student);
  if (select withdrawal_date from public.students where id = v_student) is not null then
    raise exception 'TEST_FAIL future cancellation changed';
  end if;
end;
$future_snapshots$;

do $snapshot_guards$
declare
  c pg_temp.qa_backdate_context%rowtype;
  v_student uuid; v_right uuid; v_lesson uuid;
begin
  select * into c from pg_temp.qa_backdate_context;
  v_student := pg_temp.qa_profile('student', c.branch_id);
  v_right := pg_temp.qa_right(v_student, 'consumed');
  v_lesson := pg_temp.qa_lesson(v_student, c.today + 3, 'scheduled', v_right, true);
  perform public.schedule_student_withdrawal(v_student, c.today + 2);
  -- A changed right may no longer be released merely because the snapshot
  -- originally recorded a future consumed reservation.
  update public.lesson_rights set status = 'expired', expired_at = now() where id = v_right;
  perform pg_temp.qa_expect_error(v_student, c.today - 3, 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT');
  if (select withdrawal_date from public.students where id = v_student) <> c.today + 2
     or (select status from public.lesson_rights where id = v_right) <> 'expired'
     or not exists (select 1 from private.student_withdrawal_lesson_snapshots where student_id = v_student and closed_at is null) then
    raise exception 'TEST_FAIL changed snapshot right was overwritten';
  end if;

  v_student := pg_temp.qa_profile('student', c.branch_id);
  v_lesson := pg_temp.qa_lesson(v_student, c.today - 2);
  insert into private.student_withdrawal_lesson_snapshots (
    student_id, lesson_id, withdrawal_date, starts_at, lesson_snapshot
  ) select student_id, id, c.today - 3, starts_at, to_jsonb(l)
    from public.lessons l where id = v_lesson;
  delete from public.lessons where id = v_lesson;
  perform pg_temp.qa_expect_error(v_student, c.today - 4, 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT');
  if not exists (select 1 from private.student_withdrawal_lesson_snapshots where student_id = v_student and closed_at is null) then
    raise exception 'TEST_FAIL historical snapshot closed';
  end if;
end;
$snapshot_guards$;

-- Inject a late finalizer failure. The new date, enrollment closure, lesson
-- deletion, right restoration/revocation, and audit must all roll back.
create function pg_temp.qa_fail_deactivation()
returns trigger language plpgsql as $$
begin
  if not new.is_active and new.id::text = current_setting('forestring.qa_fail_student', true) then
    if current_setting('forestring.qa_failure_kind', true) = 'busy' then
      raise exception using errcode = '55P03', message = 'QA_FORCED_LOCK_NOT_AVAILABLE';
    end if;
    raise exception 'QA_FORCED_FINALIZATION_FAILURE';
  end if;
  return new;
end;
$$;
create trigger qa_backdate_fail_deactivation before update of is_active on public.profiles
for each row execute function pg_temp.qa_fail_deactivation();

do $atomic_failure$
declare
  c pg_temp.qa_backdate_context%rowtype;
  v_student uuid; v_right uuid; v_lesson uuid;
begin
  select * into c from pg_temp.qa_backdate_context;
  v_student := pg_temp.qa_profile('student', c.branch_id);
  v_right := pg_temp.qa_right(v_student, 'consumed');
  v_lesson := pg_temp.qa_lesson(v_student, c.today + 1, 'scheduled', v_right, true);
  perform set_config('forestring.qa_fail_student', v_student::text, true);
  perform pg_temp.qa_expect_error(v_student, c.today - 3, 'QA_FORCED_FINALIZATION_FAILURE');
  if (select withdrawal_date from public.students where id = v_student) is not null
     or (select ends_on from public.student_enrollment_periods where student_id = v_student) is not null
     or not exists (select 1 from public.lessons where id = v_lesson)
     or (select status from public.lesson_rights where id = v_right) <> 'consumed'
     or exists (select 1 from public.audit_events where subject_profile_id = v_student) then
    raise exception 'TEST_FAIL finalizer failure partially committed';
  end if;
  -- Also verify SQLSTATE 55P03 is translated by the new backdate-only block
  -- and rolls back even if raised after lessons/rights were already changed.
  perform set_config('forestring.qa_failure_kind', 'busy', true);
  perform pg_temp.qa_expect_error(v_student, c.today - 3, 'FORESTRING_STUDENT_SETTLEMENT_BUSY');
  if (select withdrawal_date from public.students where id = v_student) is not null
     or (select ends_on from public.student_enrollment_periods where student_id = v_student) is not null
     or not exists (select 1 from public.lessons where id = v_lesson)
     or (select status from public.lesson_rights where id = v_right) <> 'consumed'
     or exists (select 1 from public.audit_events where subject_profile_id = v_student) then
    raise exception 'TEST_FAIL busy failure partially committed';
  end if;
  perform set_config('forestring.qa_failure_kind', '', true);
  perform set_config('forestring.qa_fail_student', '', true);
end;
$atomic_failure$;
drop trigger qa_backdate_fail_deactivation on public.profiles;

-- A pre-existing overdue reservation is deliberately different from a NEW
-- backdate. Both unchanged-date app fallback and postgres cron still clean up
-- according to the original effective boundary, without a global now guard.
do $overdue_cleanup$
declare
  c pg_temp.qa_backdate_context%rowtype;
  v_student uuid; v_lesson uuid; v_result jsonb;
begin
  select * into c from pg_temp.qa_backdate_context;
  v_student := pg_temp.qa_profile('student', c.branch_id);
  v_lesson := pg_temp.qa_lesson(v_student, c.today - 1);
  update public.students set withdrawal_date = c.today - 3 where id = v_student;
  perform pg_temp.qa_expect_error(v_student, c.today - 4, 'FORESTRING_STUDENT_WITHDRAWAL_ALREADY_EFFECTIVE');
  v_result := public.schedule_student_withdrawal(v_student, c.today - 3);
  if not (v_result ->> 'finalized')::boolean or exists (select 1 from public.lessons where id = v_lesson) then
    raise exception 'TEST_FAIL overdue app fallback changed %', v_result;
  end if;

  v_student := pg_temp.qa_profile('student', c.branch_id);
  v_lesson := pg_temp.qa_lesson(v_student, c.today - 1);
  update public.students set withdrawal_date = c.today - 3 where id = v_student;
  perform pg_temp.qa_actor(null);
  perform set_config('forestring.system_withdrawal', 'cron', true);
  v_result := public.finalize_student_withdrawal(v_student);
  if not (v_result ->> 'changed')::boolean or exists (select 1 from public.lessons where id = v_lesson) then
    raise exception 'TEST_FAIL delayed cron finalizer changed %', v_result;
  end if;
  perform set_config('forestring.system_withdrawal', '', true);
  perform pg_temp.qa_actor(c.manager_id);
end;
$overdue_cleanup$;

do $authorization$
declare
  c pg_temp.qa_backdate_context%rowtype;
  v_student uuid; v_other uuid; v_teacher uuid;
begin
  select * into c from pg_temp.qa_backdate_context;
  v_student := pg_temp.qa_profile('student', c.branch_id);
  v_other := pg_temp.qa_profile('student', c.other_branch_id);
  v_teacher := pg_temp.qa_profile('teacher', c.branch_id);
  perform pg_temp.qa_expect_error(v_other, c.today - 3, 'FORESTRING_MANAGER_BRANCH_FORBIDDEN');
  perform pg_temp.qa_actor(v_teacher);
  perform pg_temp.qa_expect_error(v_student, c.today - 3, 'FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN');
  perform pg_temp.qa_actor(null);
  perform pg_temp.qa_expect_error(v_student, c.today - 3, 'FORESTRING_AUTH_REQUIRED');
  perform pg_temp.qa_actor(c.manager_id);
  if has_function_privilege('anon', 'public.schedule_student_withdrawal(uuid,date)', 'EXECUTE') then
    raise exception 'TEST_FAIL anonymous RPC privilege';
  end if;
  if (select withdrawal_date from public.students where id = v_student) is not null
     or (select withdrawal_date from public.students where id = v_other) is not null then
    raise exception 'TEST_FAIL forbidden mutation';
  end if;
end;
$authorization$;

select 'PASS: safe backdate / KST history boundaries / rights / enrollment / completed settlement / assignment / future snapshots / atomic rollback / idempotency / overdue cron / authorization' as result;
rollback;
