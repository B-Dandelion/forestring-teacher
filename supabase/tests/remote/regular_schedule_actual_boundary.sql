begin;

do $$
declare
  v_master_id uuid;
  v_branch_id uuid;
  v_teacher_id uuid;
  v_student_id uuid;

  v_work_version_id uuid;
  v_semester_id uuid;
  v_plan_id uuid;
  v_slot_id uuid;

  v_series_1 uuid;
  v_series_2 uuid;
  v_series_3 uuid;

  v_right_1 uuid;
  v_right_2 uuid;
  v_right_3 uuid;
  v_right_4 uuid;

  v_lesson_1 uuid;
  v_lesson_2 uuid;
  v_lesson_3 uuid;
  v_lesson_4 uuid;

  v_result jsonb;
  v_target record;
  v_count integer;
begin
  -- ==========================================================
  -- 1. CURRENT-PRODUCTION ACTOR / ENTITY FIXTURE
  -- ==========================================================

  select p.id
  into v_master_id
  from public.profiles p
  where p.role = 'master'::public.user_role
    and p.is_active = true
  order by p.created_at
  limit 1;

  select
    tp.branch_id,
    tp.id,
    sp.id
  into
    v_branch_id,
    v_teacher_id,
    v_student_id
  from public.profiles tp
  join public.teachers t
    on t.id = tp.id
   and t.withdrawal_date is null
  join public.profiles sp
    on sp.branch_id = tp.branch_id
   and sp.role = 'student'::public.user_role
   and sp.is_active = true
  join public.students s
    on s.id = sp.id
   and s.status = 'active'::public.student_status
   and s.withdrawal_date is null
  where tp.role = 'teacher'::public.user_role
    and tp.is_active = true
    and tp.branch_id is not null
  order by tp.created_at, sp.created_at
  limit 1;

  if v_master_id is null
     or v_teacher_id is null
     or v_student_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active master + teacher + regular-capable student';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    v_master_id::text,
    true
  );
  perform set_config(
    'request.jwt.claim.role',
    'authenticated',
    true
  );
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_master_id::text,
      'role', 'authenticated'
    )::text,
    true
  );

  update public.students
  set student_type = 'regular'::public.student_type
  where id = v_student_id;


  -- ==========================================================
  -- 2. ISOLATE SYNTHETIC 2101 ASSIGNMENT / SERIES / WORK HOURS
  -- Everything in this file is rolled back.
  -- ==========================================================

  delete from public.teacher_student_assignments
  where student_id = v_student_id
    and starts_on >= date '2100-12-01';

  update public.teacher_student_assignments
  set ends_on = date '2100-11-30'
  where student_id = v_student_id
    and starts_on <= date '2100-11-30'
    and (
      ends_on is null
      or ends_on > date '2100-11-30'
    );

  insert into public.teacher_student_assignments(
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values(
    v_teacher_id,
    v_student_id,
    date '2100-12-01',
    null
  );

  update public.lesson_series
  set effective_until = date '2100-11-30'
  where (
      student_id = v_student_id
      or teacher_id = v_teacher_id
    )
    and effective_from <= date '2100-11-30'
    and (
      effective_until is null
      or effective_until > date '2100-11-30'
    );

  delete from private.teacher_work_hour_versions
  where teacher_id = v_teacher_id
    and effective_from >= date '2100-12-01';

  update private.teacher_work_hour_versions
  set effective_until = date '2100-11-30'
  where teacher_id = v_teacher_id
    and effective_from <= date '2100-11-30'
    and (
      effective_until is null
      or effective_until > date '2100-11-30'
    );

  insert into private.teacher_work_hour_versions(
    teacher_id,
    effective_from,
    effective_until,
    created_by
  )
  values(
    v_teacher_id,
    date '2100-12-01',
    null,
    v_master_id
  )
  returning id into v_work_version_id;

  insert into private.teacher_work_hour_entries(
    version_id,
    weekday,
    start_time,
    end_time
  )
  values
    (v_work_version_id, 1, time '17:00', time '21:00'),
    (v_work_version_id, 4, time '17:00', time '21:00');


  -- ==========================================================
  -- 3. FOUR-WEEK SEMESTER / PLAN / SLOT / ORIGINAL SERIES
  -- 2101-01-03 is Monday.
  -- ==========================================================

  insert into public.semesters(
    code,
    starts_on,
    ends_on
  )
  values(
    'TEST-ACTUAL-BOUNDARY-2101',
    date '2101-01-03',
    date '2101-01-30'
  )
  returning id into v_semester_id;

  insert into public.student_semester_plans(
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    status,
    created_by,
    updated_by
  )
  values(
    v_student_id,
    v_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'active'::public.student_semester_plan_status,
    v_master_id,
    v_master_id
  )
  returning id into v_plan_id;

  insert into public.regular_schedule_slots(
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values(
    v_student_id,
    v_branch_id,
    date '2100-12-01',
    v_master_id
  )
  returning id into v_slot_id;

  insert into public.lesson_series(
    student_id,
    teacher_id,
    weekday,
    start_time,
    duration_minutes,
    effective_from,
    branch_id,
    schedule_slot_id
  )
  values(
    v_student_id,
    v_teacher_id,
    1,
    time '18:00',
    30,
    date '2100-12-01',
    v_branch_id,
    v_slot_id
  )
  returning id into v_series_1;


  -- ==========================================================
  -- 4. FOUR ENTITLEMENT POSITIONS
  --
  -- #1 canceled: must continue occupying position #1.
  -- #2 one-off moved: actual move must not redefine baseline.
  -- #3/#4 untouched: must follow recurring changes.
  -- ==========================================================

  insert into public.lesson_rights(
    student_id,
    branch_id,
    source_semester_id,
    usable_semester_id,
    schedule_slot_id,
    origin,
    sequence_no,
    duration_minutes,
    status,
    created_by,
    reserved_at
  )
  values
    (
      v_student_id,v_branch_id,v_semester_id,v_semester_id,v_slot_id,
      'regular_base'::public.lesson_right_origin,1,30,
      'available'::public.lesson_right_status,v_master_id,null
    ),
    (
      v_student_id,v_branch_id,v_semester_id,v_semester_id,v_slot_id,
      'regular_base'::public.lesson_right_origin,2,30,
      'reserved'::public.lesson_right_status,v_master_id,pg_catalog.now()
    ),
    (
      v_student_id,v_branch_id,v_semester_id,v_semester_id,v_slot_id,
      'regular_base'::public.lesson_right_origin,3,30,
      'reserved'::public.lesson_right_status,v_master_id,pg_catalog.now()
    ),
    (
      v_student_id,v_branch_id,v_semester_id,v_semester_id,v_slot_id,
      'regular_base'::public.lesson_right_origin,4,30,
      'reserved'::public.lesson_right_status,v_master_id,pg_catalog.now()
    );

  select id into v_right_1
  from public.lesson_rights
  where schedule_slot_id=v_slot_id
    and source_semester_id=v_semester_id
    and sequence_no=1;

  select id into v_right_2
  from public.lesson_rights
  where schedule_slot_id=v_slot_id
    and source_semester_id=v_semester_id
    and sequence_no=2;

  select id into v_right_3
  from public.lesson_rights
  where schedule_slot_id=v_slot_id
    and source_semester_id=v_semester_id
    and sequence_no=3;

  select id into v_right_4
  from public.lesson_rights
  where schedule_slot_id=v_slot_id
    and source_semester_id=v_semester_id
    and sequence_no=4;

  insert into public.lessons(
    series_id,
    student_id,
    teacher_id,
    branch_id,
    occurrence_at,
    starts_at,
    duration_minutes,
    lesson_type,
    status,
    lesson_right_id,
    rescheduled_by,
    canceled_by,
    canceled_at,
    cancellation_reason
  )
  values
    (
      v_series_1,v_student_id,v_teacher_id,v_branch_id,
      timestamptz '2101-01-03 18:00:00+09',
      timestamptz '2101-01-03 18:00:00+09',
      30,'regular'::public.lesson_type,'canceled'::public.lesson_status,
      v_right_1,null,v_student_id,
      timestamptz '2101-01-02 12:00:00+09','test canceled'
    ),
    (
      v_series_1,v_student_id,v_teacher_id,v_branch_id,
      timestamptz '2101-01-10 18:00:00+09',
      timestamptz '2101-01-11 20:00:00+09',
      30,'regular'::public.lesson_type,'scheduled'::public.lesson_status,
      v_right_2,v_master_id,null,null,null
    ),
    (
      v_series_1,v_student_id,v_teacher_id,v_branch_id,
      timestamptz '2101-01-17 18:00:00+09',
      timestamptz '2101-01-17 18:00:00+09',
      30,'regular'::public.lesson_type,'scheduled'::public.lesson_status,
      v_right_3,null,null,null,null
    ),
    (
      v_series_1,v_student_id,v_teacher_id,v_branch_id,
      timestamptz '2101-01-24 18:00:00+09',
      timestamptz '2101-01-24 18:00:00+09',
      30,'regular'::public.lesson_type,'scheduled'::public.lesson_status,
      v_right_4,null,null,null,null
    );

  select id into v_lesson_1 from public.lessons where lesson_right_id=v_right_1;
  select id into v_lesson_2 from public.lessons where lesson_right_id=v_right_2;
  select id into v_lesson_3 from public.lessons where lesson_right_id=v_right_3;
  select id into v_lesson_4 from public.lessons where lesson_right_id=v_right_4;

  insert into public.lesson_cancellation_events(
    lesson_id,
    lesson_right_id,
    student_id,
    branch_id,
    origin,
    actor_id,
    counts_toward_limit,
    canceled_at,
    reason
  )
  values(
    v_lesson_1,
    v_right_1,
    v_student_id,
    v_branch_id,
    'student'::public.lesson_cancellation_origin,
    v_student_id,
    true,
    timestamptz '2101-01-02 12:00:00+09',
    'test canceled'
  );


  -- ==========================================================
  -- 5. FIRST RECURRING CHANGE
  -- Monday 18:00 -> Thursday 19:00 from 01/03.
  --
  -- #1/#2 stay preserved but occupy ordinal positions.
  -- #3 -> Thu 01/20 19:00
  -- #4 -> Thu 01/27 19:00
  -- ==========================================================

  v_result := public.change_regular_schedule(
    v_slot_id,
    v_teacher_id,
    4,
    time '19:00',
    60,
    date '2101-01-03'
  );

  if (v_result->>'reconciledLessonCount')::integer <> 2 then
    raise exception
      'TEST_FAILED: first change expected 2 reconciled lessons: %',
      v_result;
  end if;

  v_series_2 := (v_result->>'newSeriesId')::uuid;

  if not exists(
    select 1 from public.lessons l
    where l.id=v_lesson_3
      and l.series_id=v_series_2
      and l.occurrence_at=timestamptz '2101-01-20 19:00:00+09'
      and l.starts_at=timestamptz '2101-01-20 19:00:00+09'
      and l.duration_minutes=60
      and l.rescheduled_by is null
  ) then
    raise exception
      'TEST_FAILED: first change did not advance #3 recurring identity';
  end if;

  if not exists(
    select 1 from public.lessons l
    where l.id=v_lesson_4
      and l.series_id=v_series_2
      and l.occurrence_at=timestamptz '2101-01-27 19:00:00+09'
      and l.starts_at=timestamptz '2101-01-27 19:00:00+09'
      and l.duration_minutes=60
      and l.rescheduled_by is null
  ) then
    raise exception
      'TEST_FAILED: first change did not advance #4 recurring identity';
  end if;

  if not exists(
    select 1 from public.lessons l
    where l.id=v_lesson_1
      and l.status='canceled'::public.lesson_status
      and l.occurrence_at=timestamptz '2101-01-03 18:00:00+09'
      and l.starts_at=timestamptz '2101-01-03 18:00:00+09'
  ) then
    raise exception
      'TEST_FAILED: canceled position was changed';
  end if;

  if not exists(
    select 1 from public.lessons l
    where l.id=v_lesson_2
      and l.rescheduled_by=v_master_id
      and l.occurrence_at=timestamptz '2101-01-10 18:00:00+09'
      and l.starts_at=timestamptz '2101-01-11 20:00:00+09'
  ) then
    raise exception
      'TEST_FAILED: one-off moved position was changed';
  end if;


  -- ==========================================================
  -- 6. LEGACY DIVERGENCE REGRESSION
  --
  -- Recreate the old bug shape: actual starts already follow the
  -- Thursday rule, while occurrence_at / series_id still point to
  -- the earlier Monday generation.
  --
  -- The second change selects Sunday 01/23, but that date belongs
  -- to the 01/17~01/23 teaching week. The change must therefore
  -- include the untouched 01/20 lesson in the same week, plus #4.
  -- ==========================================================

  update public.lessons
  set
    series_id=v_series_1,
    occurrence_at=timestamptz '2101-01-17 18:00:00+09'
  where id=v_lesson_3;

  update public.lessons
  set
    series_id=v_series_1,
    occurrence_at=timestamptz '2101-01-24 18:00:00+09'
  where id=v_lesson_4;

  v_result := public.change_regular_schedule(
    v_slot_id,
    v_teacher_id,
    4,
    time '18:00',
    60,
    date '2101-01-23'
  );

  if (v_result->>'reconciledLessonCount')::integer <> 2 then
    raise exception
      'TEST_FAILED: effective-week boundary expected #3/#4: %',
      v_result;
  end if;

  if (v_result->>'effectiveWeekStart')::date <> date '2101-01-17' then
    raise exception
      'TEST_FAILED: selected 01/23 did not normalize to week start: %',
      v_result;
  end if;

  v_series_3 := (v_result->>'newSeriesId')::uuid;

  if not exists(
    select 1 from public.lessons l
    where l.id=v_lesson_3
      and l.series_id=v_series_3
      and l.occurrence_at=timestamptz '2101-01-20 18:00:00+09'
      and l.starts_at=timestamptz '2101-01-20 18:00:00+09'
      and l.duration_minutes=60
  ) then
    raise exception
      'TEST_FAILED: #3 was skipped by stale occurrence_at';
  end if;

  if not exists(
    select 1 from public.lessons l
    where l.id=v_lesson_4
      and l.series_id=v_series_3
      and l.occurrence_at=timestamptz '2101-01-27 18:00:00+09'
      and l.starts_at=timestamptz '2101-01-27 18:00:00+09'
      and l.duration_minutes=60
  ) then
    raise exception
      'TEST_FAILED: #4 did not retain second position';
  end if;


  -- ==========================================================
  -- 7. CALENDAR REBUILD HELPER MUST AGREE
  -- ==========================================================

  select * into v_target
  from private.regular_right_rebuild_target(
    v_right_3,
    v_semester_id,
    v_branch_id
  );

  if not found
     or v_target.series_id <> v_series_3
     or v_target.starts_at <>
        timestamptz '2101-01-20 18:00:00+09' then
    raise exception
      'TEST_FAILED: rebuild helper disagrees for #3';
  end if;

  select * into v_target
  from private.regular_right_rebuild_target(
    v_right_4,
    v_semester_id,
    v_branch_id
  );

  if not found
     or v_target.series_id <> v_series_3
     or v_target.starts_at <>
        timestamptz '2101-01-27 18:00:00+09' then
    raise exception
      'TEST_FAILED: rebuild helper disagrees for #4';
  end if;


  -- ==========================================================
  -- 8. END-SCHEDULE BOUNDARY MUST ALSO FOLLOW starts_at
  --
  -- Recreate stale occurrence on #4 once more. Ending from its
  -- actual 01/27 date must remove that untouched default position.
  -- ==========================================================

  update public.lessons
  set occurrence_at=timestamptz '2101-01-24 18:00:00+09'
  where id=v_lesson_4;

  v_result := public.end_regular_schedule(
    v_slot_id,
    date '2101-01-27'
  );

  if (v_result->>'deletedRightCount')::integer <> 1
     or exists(
       select 1 from public.lesson_rights r where r.id=v_right_4
     ) then
    raise exception
      'TEST_FAILED: end schedule did not use actual starts_at boundary: %',
      v_result;
  end if;

  if not exists(
    select 1 from public.lesson_rights r where r.id=v_right_3
  ) then
    raise exception
      'TEST_FAILED: end schedule removed pre-boundary #3';
  end if;

  if not exists(
    select 1 from public.lessons l
    where l.id=v_lesson_2
      and l.rescheduled_by=v_master_id
  ) then
    raise exception
      'TEST_FAILED: end schedule erased one-off move';
  end if;

  if not exists(
    select 1 from public.lessons l
    where l.id=v_lesson_1
      and l.status='canceled'::public.lesson_status
  ) then
    raise exception
      'TEST_FAILED: end schedule erased canceled history';
  end if;

  select count(*)::integer
  into v_count
  from public.lesson_rights r
  where r.schedule_slot_id=v_slot_id
    and r.source_semester_id=v_semester_id
    and r.origin='regular_base'::public.lesson_right_origin;

  if v_count <> 3 then
    raise exception
      'TEST_FAILED: end schedule unexpected remaining right count: %',
      v_count;
  end if;
end;
$$;

select
  'PASS: actual starts_at boundary / effective-week boundary / sequence ordinal / recurring identity / rebuild consistency / end schedule consistency'
  as test_result;

rollback;
