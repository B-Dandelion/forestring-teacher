-- Local/staging regression only. Every fixture and mutation is rolled back.
begin;

create function pg_temp.makeup_actor(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_id::text, 'role', 'authenticated'
  )::text, true);
end;
$$;

create function pg_temp.makeup_expect_error(
  p_expected text, p_student uuid, p_teacher uuid, p_at timestamptz,
  p_duration integer default 30, p_deduct boolean default false
)
returns void language plpgsql as $$
begin
  perform public.create_managed_makeup_lesson(
    p_student, p_teacher, p_at, p_duration, true, 'rollback regression', p_deduct
  );
  raise exception 'TEST_FAILED: expected %', p_expected;
exception when others then
  if sqlerrm <> p_expected then
    raise;
  end if;
end;
$$;

do $test$
declare
  v_branch uuid := gen_random_uuid();
  v_other_branch uuid := gen_random_uuid();
  v_master uuid := gen_random_uuid();
  v_manager uuid := gen_random_uuid();
  v_other_manager uuid := gen_random_uuid();
  v_teacher uuid := gen_random_uuid();
  v_other_teacher uuid := gen_random_uuid();
  v_student uuid := gen_random_uuid();
  v_other_student uuid := gen_random_uuid();
  v_source_semester uuid := gen_random_uuid();
  v_semester uuid := gen_random_uuid();
  v_today_semester uuid;
  v_future_semester uuid;
  v_plan uuid := gen_random_uuid();
  v_available_right uuid := gen_random_uuid();
  v_expired_right uuid := gen_random_uuid();
  v_revoked_right uuid := gen_random_uuid();
  v_source_right uuid := gen_random_uuid();
  v_carryover_right uuid := gen_random_uuid();
  v_current_right uuid := gen_random_uuid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_anchor date;
  v_calendar_start date;
  v_calendar_end date;
  v_before_cutoff timestamptz;
  v_after_cutoff timestamptz;
  v_at timestamptz;
  v_lesson uuid;
  v_free_lesson uuid;
  v_existing_lesson jsonb;
  v_rights_before jsonb;
  v_cancel_before jsonb;
  v_result jsonb;
  v_count integer;
  v_audit_count integer;
begin
  -- Disjoint synthetic historical semesters avoid existing calendar ranges.
  select date_trunc('week', least(
    v_today - 120, coalesce(min(starts_on) - 90, v_today - 120)
  )::timestamp)::date
  into v_anchor from public.semesters;
  insert into public.semesters(id, code, starts_on, ends_on) values
    (v_source_semester, 'ROLLBACK-MAKEUP-SOURCE-' || v_source_semester,
     v_anchor - 28, v_anchor - 1),
    (v_semester, 'ROLLBACK-MAKEUP-' || v_semester, v_anchor, v_anchor + 27);

  select id into v_today_semester from public.semesters
  where v_today between starts_on and ends_on limit 1;
  if v_today_semester is null then
    v_today_semester := gen_random_uuid();
    v_calendar_start := date_trunc('week', v_today::timestamp)::date;
    insert into public.semesters(id, code, starts_on, ends_on) values
      (v_today_semester, 'ROLLBACK-MAKEUP-TODAY-' || v_today_semester,
       v_calendar_start, v_calendar_start + 27);
  end if;
  select id into v_future_semester from public.semesters
  where v_today + 1 between starts_on and ends_on limit 1;
  if v_future_semester is null then
    v_future_semester := gen_random_uuid();
    v_calendar_start := date_trunc('week', (v_today + 1)::timestamp)::date;
    insert into public.semesters(id, code, starts_on, ends_on) values
      (v_future_semester, 'ROLLBACK-MAKEUP-FUTURE-' || v_future_semester,
       v_calendar_start, v_calendar_start + 27);
  end if;

  insert into public.branches(id, name) values
    (v_branch, 'ROLLBACK makeup ' || v_branch),
    (v_other_branch, 'ROLLBACK makeup other ' || v_other_branch);
  insert into auth.users(id) select unnest(array[
    v_master, v_manager, v_other_manager, v_teacher, v_other_teacher,
    v_student, v_other_student
  ]);
  insert into public.profiles(id, display_name, role, branch_id) values
    (v_master, 'ROLLBACK Master', 'master', null),
    (v_manager, 'ROLLBACK Manager', 'manager', v_branch),
    (v_other_manager, 'ROLLBACK Other Manager', 'manager', v_other_branch),
    (v_teacher, 'ROLLBACK Teacher', 'teacher', v_branch),
    (v_other_teacher, 'ROLLBACK Other Teacher', 'teacher', v_branch),
    (v_student, 'ROLLBACK Student', 'student', v_branch),
    (v_other_student, 'ROLLBACK Other Student', 'student', v_branch);
  insert into public.teachers(id) values
    (v_manager), (v_other_manager), (v_teacher), (v_other_teacher);
  insert into public.students(id, status, student_type) values
    (v_student, 'active', 'flex'), (v_other_student, 'active', 'flex');

  -- Two real enrollment episodes with a deliberate re-enrollment gap.
  update public.student_enrollment_periods
  set starts_on = v_anchor + 14 where student_id = v_student;
  insert into public.student_enrollment_periods(
    student_id, branch_id, starts_on, ends_on, start_reason, end_reason
  ) values (v_student, v_branch, v_anchor + 2, v_anchor + 11,
            'rollback initial', 'rollback withdrawal');
  update public.student_enrollment_periods
  set starts_on = v_anchor where student_id = v_other_student;
  insert into public.teacher_work_hours(teacher_id, weekday, start_time, end_time)
  select teacher_id, weekday, time '09:00', time '18:00'
  from unnest(array[v_teacher, v_other_teacher]) teacher_id
  cross join generate_series(1, 7) weekday;

  insert into public.student_semester_plans(
    id, student_id, semester_id, branch_id, student_type_snapshot,
    flex_base_right_count, flex_duration_minutes, status
  ) values (v_plan, v_student, v_semester, v_branch, 'flex', 8, 30, 'active');
  insert into public.lesson_rights(
    id, student_id, branch_id, source_semester_id, usable_semester_id,
    origin, sequence_no, duration_minutes, status
  ) values
    (v_available_right, v_student, v_branch, v_semester, v_semester,
     'flex_base', 1, 30, 'available'),
    (v_expired_right, v_student, v_branch, v_semester, v_semester,
     'flex_base', 2, 30, 'expired'),
    (v_revoked_right, v_student, v_branch, v_semester, v_semester,
     'flex_base', 3, 30, 'revoked'),
    (v_source_right, v_student, v_branch, v_source_semester, v_source_semester,
     'flex_base', 1, 30, 'expired');
  insert into public.lesson_rights(
    id, student_id, branch_id, source_semester_id, usable_semester_id,
    origin, source_right_id, sequence_no, duration_minutes, status, carryover_count
  ) values (v_carryover_right, v_student, v_branch, v_source_semester, v_semester,
            'carryover', v_source_right, 1, 30, 'available', 1);

  perform pg_temp.makeup_actor(v_manager);
  v_at := ((v_anchor + 3) + time '10:00') at time zone 'Asia/Seoul';
  perform pg_temp.makeup_expect_error('FORESTRING_MAKEUP_DEDUCTION_PLAN_NOT_OPEN',
    v_other_student, v_other_teacher, v_at + interval '2 hours', 30, true);
  select jsonb_agg(to_jsonb(r) order by r.id) into v_rights_before
  from public.lesson_rights r where student_id = v_student;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.id), '[]'::jsonb)
  into v_cancel_before from public.lesson_cancellation_events e
  where student_id = v_student;

  -- A backdated standalone record leaves the entitlement/cancellation ledger alone.
  v_result := public.create_managed_makeup_lesson(
    v_student, v_teacher, v_at, 45, false, 'historical record', false
  );
  if (v_result->>'changed')::boolean is distinct from true
     or (v_result->>'lessonRightDeducted')::boolean is distinct from false
     or (v_result->>'requiresConfirmation')::boolean is distinct from false then
    raise exception 'TEST_FAILED: backdated 45 minute standalone record: %', v_result;
  end if;
  v_free_lesson := (v_result->>'lessonId')::uuid;
  select to_jsonb(l) into v_existing_lesson from public.lessons l
  where id = v_free_lesson;
  if (select jsonb_agg(to_jsonb(r) order by r.id) from public.lesson_rights r
      where student_id = v_student) is distinct from v_rights_before then
    raise exception 'TEST_FAILED: record-only creation mutated lesson rights';
  end if;
  if (select coalesce(jsonb_agg(to_jsonb(e) order by e.id), '[]'::jsonb)
      from public.lesson_cancellation_events e where student_id = v_student)
      is distinct from v_cancel_before then
    raise exception 'TEST_FAILED: record-only creation mutated cancellations';
  end if;
  if not exists (select 1 from public.audit_events
    where event_type = 'MAKEUP_LESSON_CREATED' and effective_on = v_anchor + 3
      and details->>'lessonId' = v_free_lesson::text) then
    raise exception 'TEST_FAILED: historical effective date missing';
  end if;

  -- Conflict, enrollment, role and branch checks still reject invalid records.
  perform pg_temp.makeup_expect_error('FORESTRING_TEACHER_LESSON_OVERLAP',
    v_other_student, v_teacher, v_at);
  perform pg_temp.makeup_expect_error('FORESTRING_STUDENT_LESSON_OVERLAP',
    v_student, v_other_teacher, v_at);
  perform pg_temp.makeup_expect_error('FORESTRING_MAKEUP_OUTSIDE_ENROLLMENT',
    v_student, v_teacher, ((v_anchor + 1) + time '10:00') at time zone 'Asia/Seoul');
  perform pg_temp.makeup_expect_error('FORESTRING_MAKEUP_OUTSIDE_ENROLLMENT',
    v_student, v_teacher, ((v_anchor + 12) + time '10:00') at time zone 'Asia/Seoul');
  update public.student_enrollment_periods set branch_id = v_other_branch
  where student_id = v_student and starts_on = v_anchor + 2;
  perform pg_temp.makeup_expect_error('FORESTRING_MAKEUP_OUTSIDE_ENROLLMENT',
    v_student, v_teacher, v_at + interval '2 hours');
  update public.student_enrollment_periods set branch_id = v_branch
  where student_id = v_student and starts_on = v_anchor + 2;
  perform pg_temp.makeup_actor(v_other_manager);
  perform pg_temp.makeup_expect_error('FORESTRING_MANAGER_BRANCH_FORBIDDEN',
    v_student, v_teacher, v_at + interval '2 hours');
  perform pg_temp.makeup_actor(v_student);
  perform pg_temp.makeup_expect_error('FORESTRING_LESSON_MANAGEMENT_REQUIRED',
    v_student, v_teacher, v_at + interval '2 hours');
  perform pg_temp.makeup_actor(v_manager);

  -- Existing warning confirmation remains a no-write preview.
  v_result := public.create_managed_makeup_lesson(
    v_student, v_teacher, v_at + interval '10 hours', 30, false, null, false
  );
  if (v_result->>'changed')::boolean is distinct from false
     or (v_result->>'requiresConfirmation')::boolean is distinct from true
     or not (v_result->'warningCodes' ? 'FORESTRING_OUTSIDE_WORK_HOURS') then
    raise exception 'TEST_FAILED: work hours warning changed: %', v_result;
  end if;
  v_result := public.create_managed_makeup_lesson(
    v_student, v_teacher, v_at + interval '10 hours', 30, true, null, false
  );
  if (v_result->>'changed')::boolean is distinct from true then
    raise exception 'TEST_FAILED: work-hours warning confirmation rejected';
  end if;

  -- One matching right is consumed; carryover priority and processing time survive.
  v_result := public.create_managed_makeup_lesson(
    v_student, v_teacher, v_at + interval '2 hours', 30, false, null, true
  );
  v_lesson := (v_result->>'lessonId')::uuid;
  if (v_result->>'lessonRightId')::uuid is distinct from v_carryover_right
     or not exists (select 1 from public.lesson_rights
       where id = v_carryover_right and status = 'consumed' and consumed_at = now())
     or not exists (select 1 from public.lessons
       where id = v_lesson and manual_makeup_right_id = v_carryover_right
         and lesson_right_id is null and series_id is null) then
    raise exception 'TEST_FAILED: historical right deduction/link: %', v_result;
  end if;
  if not exists (select 1 from public.lesson_rights
    where id = v_available_right and status = 'available') then
    raise exception 'TEST_FAILED: deduction consumed more than one right';
  end if;
  if not exists (select 1 from public.audit_events
    where event_type = 'MAKEUP_LESSON_RIGHT_DEDUCTED' and effective_on = v_anchor + 3
      and details->>'lessonId' = v_lesson::text) then
    raise exception 'TEST_FAILED: deduction audit uses wrong effective day';
  end if;
  v_result := public.cancel_standalone_makeup_lesson(v_lesson, 'rollback cancellation');
  if (v_result->>'lessonRightRestored')::boolean is distinct from true
     or not exists (select 1 from public.lessons where id = v_lesson and status = 'canceled')
     or not exists (select 1 from public.lesson_rights
       where id = v_carryover_right and status = 'available') then
    raise exception 'TEST_FAILED: cancellation did not preserve lesson/restore open-plan right';
  end if;

  -- Completed plans can retain an available carryover. It must not be consumed.
  update public.student_semester_plans set status = 'completed' where id = v_plan;
  select count(*) into v_count from public.lessons where student_id = v_student;
  select count(*) into v_audit_count from public.audit_events where subject_profile_id = v_student;
  perform pg_temp.makeup_expect_error('FORESTRING_MAKEUP_DEDUCTION_PLAN_NOT_OPEN',
    v_student, v_teacher, v_at + interval '3 hours', 30, true);
  if (select count(*) from public.lessons where student_id = v_student) <> v_count
     or (select count(*) from public.audit_events where subject_profile_id = v_student) <> v_audit_count
     or not exists (select 1 from public.lesson_rights
       where id = v_carryover_right and status = 'available') then
    raise exception 'TEST_FAILED: rejected closed-plan deduction was not atomic';
  end if;
  -- A record-only addition is still allowed in that completed semester.
  v_result := public.create_managed_makeup_lesson(
    v_student, v_teacher, v_at + interval '3 hours', 30, false, null, false
  );
  if (v_result->>'changed')::boolean is distinct from true then
    raise exception 'TEST_FAILED: completed semester record-only addition rejected';
  end if;

  update public.student_semester_plans set status = 'active' where id = v_plan;
  select count(*) into v_count from public.lessons where student_id = v_student;
  perform pg_temp.makeup_expect_error('FORESTRING_NO_MATCHING_AVAILABLE_LESSON_RIGHT',
    v_student, v_teacher, v_at + interval '4 hours', 45, true);
  if (select count(*) from public.lessons where student_id = v_student) <> v_count
     or not exists (select 1 from public.lesson_rights where id = v_expired_right and status = 'expired')
     or not exists (select 1 from public.lesson_rights where id = v_revoked_right and status = 'revoked') then
    raise exception 'TEST_FAILED: missing-right failure changed a record or unavailable right';
  end if;

  -- Planned ledgers also permit a matching right, without reviving unavailable rights.
  update public.lesson_rights set status = 'expired', expired_at = now()
  where id = v_carryover_right;
  update public.student_semester_plans set status = 'planned' where id = v_plan;
  v_result := public.create_managed_makeup_lesson(
    v_student, v_teacher, v_at + interval '4 hours', 30, false, null, true
  );
  v_lesson := (v_result->>'lessonId')::uuid;
  if (v_result->>'lessonRightId')::uuid is distinct from v_available_right then
    raise exception 'TEST_FAILED: planned ledger did not use its available base right';
  end if;
  update public.student_semester_plans set status = 'completed' where id = v_plan;
  v_result := public.cancel_standalone_makeup_lesson(v_lesson, 'completed-plan rollback');
  if (v_result->>'lessonRightRestored')::boolean is distinct from false
     or not exists (select 1 from public.lesson_rights
       where id = v_available_right and status = 'consumed')
     or not exists (select 1 from public.lessons
       where id = v_lesson and status = 'canceled') then
    raise exception 'TEST_FAILED: cancellation reopened a settled right or erased history';
  end if;

  insert into public.blocked_periods(teacher_id, starts_at, ends_at, reason)
  values (v_teacher, v_at + interval '5 hours', v_at + interval '6 hours', 'rollback');
  perform pg_temp.makeup_expect_error('FORESTRING_LESSON_BLOCKED_PERIOD_CONFLICT',
    v_student, v_teacher, v_at + interval '5 hours');

  insert into public.closure_periods(
    branch_id, semester_id, starts_on, ends_on, closure_kind, reason
  ) values (v_branch, v_semester, v_anchor + 4, v_anchor + 4, 'ordinary', 'rollback');
  v_result := public.create_managed_makeup_lesson(
    v_student, v_teacher, v_at + interval '1 day', 30, false, null, false
  );
  if (v_result->>'changed')::boolean is distinct from true then
    raise exception 'TEST_FAILED: managed creation during branch closure regressed';
  end if;

  -- Today is included even when its selected time has already passed in Korea.
  v_at := (v_today + time '00:00') at time zone 'Asia/Seoul';
  v_result := public.create_managed_makeup_lesson(
    v_student, v_teacher, v_at, 15, true, 'today past time', false
  );
  if (v_result->>'changed')::boolean is distinct from true then
    raise exception 'TEST_FAILED: today past time rejected';
  end if;

  update public.students set withdrawal_date = v_today + 1 where id = v_student;
  perform pg_temp.makeup_expect_error('FORESTRING_LESSON_AFTER_STUDENT_WITHDRAWAL',
    v_student, v_teacher, v_at + interval '1 day 2 hours');
  update public.students set withdrawal_date = null where id = v_student;
  update public.teachers set withdrawal_date = v_today + 1 where id = v_teacher;
  perform pg_temp.makeup_expect_error('FORESTRING_LESSON_AFTER_TEACHER_WITHDRAWAL',
    v_student, v_teacher, v_at + interval '1 day 2 hours');
  update public.teachers set withdrawal_date = null where id = v_teacher;

  update public.profiles set is_active = false where id = v_student;
  perform pg_temp.makeup_expect_error('FORESTRING_ACTIVE_STUDENT_REQUIRED',
    v_student, v_teacher, v_at + interval '2 hours');
  update public.profiles set is_active = true where id = v_student;
  update public.profiles set is_active = false where id = v_teacher;
  perform pg_temp.makeup_expect_error('FORESTRING_ACTIVE_TEACHER_REQUIRED',
    v_student, v_teacher, v_at + interval '2 hours');
  update public.profiles set is_active = true where id = v_teacher;

  -- A future day keeps the existing creation path (without an enrollment draft).
  update public.student_enrollment_periods set ends_on = v_today
  where student_id = v_student and ends_on is null;
  v_at := ((v_today + 1) + time '10:00') at time zone 'Asia/Seoul';
  v_result := public.create_managed_makeup_lesson(
    v_student, v_other_teacher, v_at, 15, false, 'future day', false
  );
  if (v_result->>'changed')::boolean is distinct from true then
    raise exception 'TEST_FAILED: future creation regressed';
  end if;

  if (select to_jsonb(l) from public.lessons l where id = v_free_lesson)
      is distinct from v_existing_lesson then
    raise exception 'TEST_FAILED: original lesson history was changed';
  end if;

  -- Exercise the real student booking path on a separate current-semester right.
  -- Both slots otherwise fit the assignment, work hours, calendar and conflicts.
  v_before_cutoff := (date_trunc('hour', now() at time zone 'Asia/Seoul')
                     + interval '2 hours') at time zone 'Asia/Seoul';
  v_after_cutoff := (date_trunc('hour', now() at time zone 'Asia/Seoul')
                    + interval '6 hours') at time zone 'Asia/Seoul';
  select starts_on, ends_on into v_calendar_start, v_calendar_end
  from private.get_effective_semester_bounds(v_branch, v_today_semester);
  if (v_after_cutoff at time zone 'Asia/Seoul')::date > v_calendar_end then
    -- On the final evening of an existing semester, give this synthetic branch
    -- a longer valid range before materializing its current plan and rights.
    insert into public.branch_semester_overrides(
      branch_id, semester_id, starts_on, ends_on
    ) values (v_branch, v_today_semester, v_calendar_start, v_calendar_end + 28);
  end if;
  update public.teacher_work_hours set start_time = time '00:00', end_time = time '23:45'
  where teacher_id = v_teacher;
  insert into public.teacher_student_assignments(
    teacher_id, student_id, branch_id, starts_on
  ) values (v_teacher, v_other_student, v_branch, v_today - 1);
  insert into public.student_semester_plans(
    student_id, semester_id, branch_id, student_type_snapshot,
    flex_base_right_count, flex_duration_minutes, status
  ) values (v_other_student, v_today_semester, v_branch, 'flex', 4, 15, 'active');
  insert into public.lesson_rights(
    id, student_id, branch_id, source_semester_id, usable_semester_id,
    origin, sequence_no, duration_minutes, status
  ) values (v_current_right, v_other_student, v_branch, v_today_semester,
            v_today_semester, 'flex_base', 1, 15, 'available');
  perform pg_temp.makeup_actor(v_other_student);
  if exists (select 1 from private.lesson_right_slot_candidates(
    v_current_right, (v_before_cutoff at time zone 'Asia/Seoul')::date, v_other_student
  ) where starts_at = v_before_cutoff) then
    raise exception 'TEST_FAILED: self-service availability exposed a slot within five hours';
  end if;
  begin
    perform public.book_lesson_right(v_current_right, v_before_cutoff);
    raise exception 'TEST_FAILED: student booked a slot within five hours';
  exception when others then
    if sqlerrm <> 'FORESTRING_BOOKING_SLOT_NOT_AVAILABLE' then raise; end if;
  end;
  if not exists (select 1 from private.lesson_right_slot_candidates(
    v_current_right, (v_after_cutoff at time zone 'Asia/Seoul')::date, v_other_student
  ) where starts_at = v_after_cutoff) then
    raise exception 'TEST_FAILED: five-hour positive-control slot missing';
  end if;
  v_result := public.book_lesson_right(v_current_right, v_after_cutoff);
  if not exists (select 1 from public.lessons
    where lesson_right_id = v_current_right and starts_at = v_after_cutoff
      and teacher_id = v_teacher and student_id = v_other_student) then
    raise exception 'TEST_FAILED: student could not book a valid later slot: %', v_result;
  end if;

  if has_function_privilege('anon',
      'public.create_managed_makeup_lesson(uuid,uuid,timestamptz,integer,boolean,text,boolean)', 'EXECUTE')
     or has_function_privilege('anon',
      'public.create_makeup_lesson(uuid,uuid,timestamptz,integer,boolean,text)', 'EXECUTE') then
    raise exception 'TEST_FAILED: management RPC leaked to anon';
  end if;
end;
$test$;

rollback;

select 'PASS: backdated makeup lessons, settlement preservation and student booking guards' as result;
