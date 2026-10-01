begin;

do $$
declare
  -- ==========================================================
  -- ACTORS
  -- ==========================================================

  v_manager_id uuid;
  v_other_manager_id uuid;
  v_branch_id uuid;
  v_teacher_id uuid;
  v_student_id uuid;

  -- ==========================================================
  -- SEMESTER / PLAN
  -- ==========================================================

  v_semester_id uuid;
  v_plan_id uuid;

  -- ==========================================================
  -- REGULAR SLOT / SERIES
  -- ==========================================================

  v_slot_id uuid;
  v_old_series_id uuid;
  v_new_series_id uuid;

  -- ==========================================================
  -- RIGHTS
  -- ==========================================================

  v_right_1 uuid;
  v_right_2 uuid;
  v_right_3 uuid;
  v_right_4 uuid;

  -- ==========================================================
  -- LESSONS
  -- ==========================================================

  v_lesson_1 uuid;
  v_lesson_2 uuid;
  v_lesson_3 uuid;
  v_lesson_4 uuid;

  v_conflict_lesson_id uuid;

  -- ==========================================================
  -- DATES
  --
  -- 2101-01-03 = Monday
  -- source semester = exactly 4 weeks
  --
  -- OLD:
  --   Mondays 18:00 / 30m
  --
  -- NEW:
  --   Thursdays 19:00 / 60m
  --
  -- New Thursday occurrences:
  --   #1 01/06
  --   #2 01/13
  --   #3 01/20
  --   #4 01/27
  -- ==========================================================

  v_effective_on date :=
    date '2101-01-03';

  v_new_3_starts_at timestamptz :=
    timestamptz '2101-01-20 19:00:00+09';

  v_new_4_starts_at timestamptz :=
    timestamptz '2101-01-27 19:00:00+09';

  v_moved_2_starts_at timestamptz :=
    timestamptz '2101-01-11 20:00:00+09';

  -- ==========================================================
  -- GENERAL
  -- ==========================================================

  v_result jsonb;
  v_count integer;
  v_denied boolean;

begin

  -- ==========================================================
  -- 1. PRIMARY FIXTURE
  -- ==========================================================

  select
    manager_profile.id,
    manager_profile.branch_id,
    teacher_profile.id,
    student_profile.id

  into
    v_manager_id,
    v_branch_id,
    v_teacher_id,
    v_student_id

  from public.profiles manager_profile

  join public.teachers manager_teacher
    on manager_teacher.id =
       manager_profile.id

  join public.profiles teacher_profile
    on teacher_profile.branch_id =
       manager_profile.branch_id

   and teacher_profile.role =
       'teacher'::public.user_role

   and teacher_profile.is_active = true

  join public.teachers teacher_entity
    on teacher_entity.id =
       teacher_profile.id

  join public.profiles student_profile
    on student_profile.branch_id =
       manager_profile.branch_id

   and student_profile.role =
       'student'::public.user_role

   and student_profile.is_active = true

  join public.students student_entity
    on student_entity.id =
       student_profile.id

   and student_entity.status =
       'active'::public.student_status

  where manager_profile.role =
        'manager'::public.user_role

    and manager_profile.is_active = true

    and manager_profile.branch_id is not null

  order by
    manager_profile.created_at,
    teacher_profile.created_at,
    student_profile.created_at

  limit 1;


  if v_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager + teacher + active student';
  end if;


  update public.students
  set
    student_type =
      'regular'::public.student_type
  where id =
        v_student_id;


  -- ==========================================================
  -- 2. OTHER-BRANCH MANAGER
  -- ==========================================================

  select p.id
  into v_other_manager_id

  from public.profiles p

  where p.role =
        'manager'::public.user_role

    and p.is_active = true

    and p.branch_id is not null

    and p.branch_id <>
        v_branch_id

  order by p.created_at

  limit 1;


  if v_other_manager_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: manager from another branch';
  end if;


  -- ==========================================================
  -- 3. ISOLATE SYNTHETIC FUTURE ASSIGNMENTS
  -- ==========================================================

  delete from public.teacher_student_assignments
  where student_id =
        v_student_id

    and starts_on >=
        date '2100-12-01';


  update public.teacher_student_assignments
  set
    ends_on =
      date '2100-11-30'

  where student_id =
        v_student_id

    and starts_on <=
        date '2100-11-30'

    and (
      ends_on is null
      or ends_on >
         date '2100-11-30'
    );


  insert into public.teacher_student_assignments (
    teacher_id,
    student_id,
    starts_on,
    ends_on
  )
  values (
    v_teacher_id,
    v_student_id,
    date '2100-12-01',
    null
  );


  -- ==========================================================
  -- 4. ISOLATE FUTURE SERIES
  --
  -- Existing real series must not collide with synthetic
  -- 2101 recurring rules.
  -- Everything rolls back at the end.
  -- ==========================================================

  update public.lesson_series
  set
    effective_until =
      date '2100-11-30'

  where (
      student_id =
        v_student_id

      or teacher_id =
         v_teacher_id
    )

    and effective_from <=
        date '2100-11-30'

    and (
      effective_until is null
      or effective_until >
         date '2100-11-30'
    );


  -- ==========================================================
  -- 5. CONTROL WORK HOURS / BLOCKS
  -- ==========================================================

  delete from public.teacher_work_hours
  where teacher_id =
        v_teacher_id;


  delete from public.blocked_periods
  where teacher_id =
        v_teacher_id;


  insert into public.teacher_work_hours (
    teacher_id,
    weekday,
    start_time,
    end_time
  )
  values
    (
      v_teacher_id,
      1,
      time '17:00',
      time '21:00'
    ),
    (
      v_teacher_id,
      4,
      time '17:00',
      time '21:00'
    );


  -- ==========================================================
  -- 6. TEST SEMESTER
  -- ==========================================================

  insert into public.semesters (
    code,
    starts_on,
    ends_on
  )
  values (
    'TEST-REGULAR-CHANGE-2101',
    date '2101-01-03',
    date '2101-01-30'
  )
  returning id
  into v_semester_id;


  -- ==========================================================
  -- 7. ACTIVE REGULAR PLAN
  -- ==========================================================

  insert into public.student_semester_plans (
    student_id,
    semester_id,
    branch_id,
    student_type_snapshot,
    status,
    created_by,
    updated_by
  )
  values (
    v_student_id,
    v_semester_id,
    v_branch_id,
    'regular'::public.student_type,
    'active'::public.student_semester_plan_status,
    v_manager_id,
    v_manager_id
  )
  returning id
  into v_plan_id;


  -- ==========================================================
  -- 8. LOGICAL SLOT
  -- ==========================================================

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    created_by
  )
  values (
    v_student_id,
    v_branch_id,
    date '2100-12-01',
    v_manager_id
  )
  returning id
  into v_slot_id;


  -- ==========================================================
  -- 9. OLD DEFAULT SERIES
  --
  -- Monday 18:00 / 30m
  -- Starts BEFORE the requested effective date so the function
  -- must create a NEW series version rather than edit in-place.
  -- ==========================================================

  insert into public.lesson_series (
    student_id,
    teacher_id,
    weekday,
    start_time,
    duration_minutes,
    effective_from,
    branch_id,
    schedule_slot_id
  )
  values (
    v_student_id,
    v_teacher_id,
    1,
    time '18:00',
    30,
    date '2100-12-01',
    v_branch_id,
    v_slot_id
  )
  returning id
  into v_old_series_id;


  -- ==========================================================
  -- 10. FOUR REGULAR RIGHTS
  --
  -- #1 canceled -> available
  -- #2 individually moved -> reserved
  -- #3 untouched -> reserved
  -- #4 untouched -> reserved
  -- ==========================================================

  insert into public.lesson_rights (
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
      v_student_id,
      v_branch_id,
      v_semester_id,
      v_semester_id,
      v_slot_id,
      'regular_base'::public.lesson_right_origin,
      1,
      30,
      'available'::public.lesson_right_status,
      v_manager_id,
      null
    ),
    (
      v_student_id,
      v_branch_id,
      v_semester_id,
      v_semester_id,
      v_slot_id,
      'regular_base'::public.lesson_right_origin,
      2,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    ),
    (
      v_student_id,
      v_branch_id,
      v_semester_id,
      v_semester_id,
      v_slot_id,
      'regular_base'::public.lesson_right_origin,
      3,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    ),
    (
      v_student_id,
      v_branch_id,
      v_semester_id,
      v_semester_id,
      v_slot_id,
      'regular_base'::public.lesson_right_origin,
      4,
      30,
      'reserved'::public.lesson_right_status,
      v_manager_id,
      now()
    );


  select id into v_right_1
  from public.lesson_rights
  where schedule_slot_id = v_slot_id
    and source_semester_id = v_semester_id
    and sequence_no = 1;


  select id into v_right_2
  from public.lesson_rights
  where schedule_slot_id = v_slot_id
    and source_semester_id = v_semester_id
    and sequence_no = 2;


  select id into v_right_3
  from public.lesson_rights
  where schedule_slot_id = v_slot_id
    and source_semester_id = v_semester_id
    and sequence_no = 3;


  select id into v_right_4
  from public.lesson_rights
  where schedule_slot_id = v_slot_id
    and source_semester_id = v_semester_id
    and sequence_no = 4;


  -- ==========================================================
  -- 11. FOUR CANONICAL LESSONS
  -- ==========================================================

  insert into public.lessons (
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
      v_old_series_id,
      v_student_id,
      v_teacher_id,
      v_branch_id,
      timestamptz '2101-01-03 18:00:00+09',
      timestamptz '2101-01-03 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'canceled'::public.lesson_status,
      v_right_1,
      null,
      v_student_id,
      timestamptz '2101-01-02 12:00:00+09',
      'test canceled'
    ),

    (
      v_old_series_id,
      v_student_id,
      v_teacher_id,
      v_branch_id,
      timestamptz '2101-01-10 18:00:00+09',
      v_moved_2_starts_at,
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_right_2,
      v_manager_id,
      null,
      null,
      null
    ),

    (
      v_old_series_id,
      v_student_id,
      v_teacher_id,
      v_branch_id,
      timestamptz '2101-01-17 18:00:00+09',
      timestamptz '2101-01-17 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_right_3,
      null,
      null,
      null,
      null
    ),

    (
      v_old_series_id,
      v_student_id,
      v_teacher_id,
      v_branch_id,
      timestamptz '2101-01-24 18:00:00+09',
      timestamptz '2101-01-24 18:00:00+09',
      30,
      'regular'::public.lesson_type,
      'scheduled'::public.lesson_status,
      v_right_4,
      null,
      null,
      null,
      null
    );


  select id into v_lesson_1
  from public.lessons
  where lesson_right_id = v_right_1;

  select id into v_lesson_2
  from public.lessons
  where lesson_right_id = v_right_2;

  select id into v_lesson_3
  from public.lessons
  where lesson_right_id = v_right_3;

  select id into v_lesson_4
  from public.lessons
  where lesson_right_id = v_right_4;


  -- ==========================================================
  -- 12. CANCELLATION LEDGER FOR #1
  -- ==========================================================

  insert into public.lesson_cancellation_events (
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
  values (
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
  -- 13. STUDENT MAY NOT CHANGE DEFAULT SCHEDULE
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_student_id::text,
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
      'sub', v_student_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;


  begin

    perform public.change_regular_schedule(
      v_slot_id,
      v_teacher_id,
      4,
      time '19:00',
      60,
      v_effective_on
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: student changed regular default schedule';
  end if;


  -- ==========================================================
  -- 14. CROSS-BRANCH MANAGER DENIED
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_other_manager_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_other_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  v_denied := false;


  begin

    perform public.change_regular_schedule(
      v_slot_id,
      v_teacher_id,
      4,
      time '19:00',
      60,
      v_effective_on
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_MANAGER_BRANCH_FORBIDDEN' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: cross-branch manager changed schedule';
  end if;


  -- ==========================================================
  -- 15. LOGIN AS VALID MANAGER
  -- ==========================================================

  perform set_config(
    'request.jwt.claim.sub',
    v_manager_id::text,
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_manager_id::text,
      'role', 'authenticated'
    )::text,
    true
  );


  -- ==========================================================
  -- 16. ASSIGNMENT MISMATCH
  --
  -- Every manager also has a teachers row.
  -- But this student is NOT assigned to the manager.
  -- ==========================================================

  v_denied := false;


  begin

    perform public.change_regular_schedule(
      v_slot_id,
      v_manager_id,
      4,
      time '19:00',
      60,
      v_effective_on
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_REGULAR_TEACHER_ASSIGNMENT_MISMATCH' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: unassigned teacher accepted as default teacher';
  end if;


  -- ==========================================================
  -- 17. OUTSIDE WORK HOURS
  -- ==========================================================

  v_denied := false;


  begin

    perform public.change_regular_schedule(
      v_slot_id,
      v_teacher_id,
      7,
      time '19:00',
      60,
      v_effective_on
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: schedule outside work hours accepted';
  end if;


  -- ==========================================================
  -- 18. BLOCKED PERIOD MUST ABORT WHOLE CHANGE
  --
  -- #3 should map to 2101-01-20 19:00.
  -- Block exactly that candidate.
  -- ==========================================================

  insert into public.blocked_periods (
    teacher_id,
    starts_at,
    ends_at,
    reason,
    created_by
  )
  values (
    v_teacher_id,
    timestamptz '2101-01-20 19:00:00+09',
    timestamptz '2101-01-20 20:00:00+09',
    'schedule reconciliation test',
    v_manager_id
  );


  v_denied := false;


  begin

    perform public.change_regular_schedule(
      v_slot_id,
      v_teacher_id,
      4,
      time '19:00',
      60,
      v_effective_on
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_REGULAR_RECONCILIATION_BLOCKED' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: blocked candidate accepted';
  end if;


  -- Failed transaction must not partially version the series.
  if not exists (
    select 1
    from public.lesson_series ls

    where ls.id =
          v_old_series_id

      and ls.effective_until is null
  ) then

    raise exception
      'TEST_FAILED: blocked rejection partially changed old series';
  end if;


  delete from public.blocked_periods
  where teacher_id =
        v_teacher_id

    and starts_at =
        timestamptz '2101-01-20 19:00:00+09';


  -- ==========================================================
  -- 19. ACTUAL LESSON COLLISION MUST ALSO ABORT
  --
  -- Create standalone makeup lesson for same student/teacher
  -- at #3's new candidate.
  -- ==========================================================

  insert into public.lessons (
    student_id,
    teacher_id,
    branch_id,
    starts_at,
    duration_minutes,
    lesson_type,
    status
  )
  values (
    v_student_id,
    v_teacher_id,
    v_branch_id,
    timestamptz '2101-01-20 19:00:00+09',
    60,
    'makeup'::public.lesson_type,
    'scheduled'::public.lesson_status
  )
  returning id
  into v_conflict_lesson_id;


  v_denied := false;


  begin

    perform public.change_regular_schedule(
      v_slot_id,
      v_teacher_id,
      4,
      time '19:00',
      60,
      v_effective_on
    );

  exception
    when others then

      if sqlerrm =
         'FORESTRING_REGULAR_RECONCILIATION_TIME_CONFLICT' then

        v_denied := true;

      else
        raise;
      end if;

  end;


  if not v_denied then
    raise exception
      'TEST_FAILED: colliding actual lesson accepted';
  end if;


  -- Right duration must also have rolled back.
  if not exists (
    select 1
    from public.lesson_rights r

    where r.id =
          v_right_3

      and r.duration_minutes = 30
  ) then

    raise exception
      'TEST_FAILED: collision rejection partially changed right';
  end if;


  delete from public.lessons
  where id =
        v_conflict_lesson_id;


  -- ==========================================================
  -- 20. SUCCESSFUL DEFAULT SCHEDULE CHANGE
  --
  -- Monday 18:00 / 30
  -- ->
  -- Thursday 19:00 / 60
  -- ==========================================================

  v_result :=
    public.change_regular_schedule(
      v_slot_id,
      v_teacher_id,
      4,
      time '19:00',
      60,
      v_effective_on
    );


  if (v_result ->> 'changed')::boolean <> true then
    raise exception
      'TEST_FAILED: successful change returned changed=false';
  end if;


  if (v_result ->> 'reconciledLessonCount')::integer <> 2 then
    raise exception
      'TEST_FAILED: expected exactly 2 auto-reconciled lessons: %',
      v_result;
  end if;


  if (v_result ->> 'seriesUpdatedInPlace')::boolean <> false then
    raise exception
      'TEST_FAILED: expected versioned series, not in-place change';
  end if;


  v_new_series_id :=
    (
      v_result
      ->> 'newSeriesId'
    )::uuid;


  if v_new_series_id is null
     or v_new_series_id =
        v_old_series_id then

    raise exception
      'TEST_FAILED: new series version not created';
  end if;


  -- ==========================================================
  -- 21. OLD/NEW SERIES VERSIONING
  -- ==========================================================

  if not exists (
    select 1

    from public.lesson_series ls

    where ls.id =
          v_old_series_id

      and ls.teacher_id =
          v_teacher_id

      and ls.weekday = 1

      and ls.start_time =
          time '18:00'

      and ls.duration_minutes = 30

      and ls.effective_until =
          date '2101-01-02'
  ) then

    raise exception
      'TEST_FAILED: old series was not closed correctly';
  end if;


  if not exists (
    select 1

    from public.lesson_series ls

    where ls.id =
          v_new_series_id

      and ls.schedule_slot_id =
          v_slot_id

      and ls.student_id =
          v_student_id

      and ls.branch_id =
          v_branch_id

      and ls.teacher_id =
          v_teacher_id

      and ls.weekday = 4

      and ls.start_time =
          time '19:00'

      and ls.duration_minutes = 60

      and ls.effective_from =
          v_effective_on
  ) then

    raise exception
      'TEST_FAILED: new series version incorrect';
  end if;


  -- ==========================================================
  -- 22. #1 CANCELED LESSON MUST REMAIN UNCHANGED
  -- ==========================================================

  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_lesson_1

      and l.lesson_right_id =
          v_right_1

      and l.series_id =
          v_old_series_id

      and l.occurrence_at =
          timestamptz '2101-01-03 18:00:00+09'

      and l.starts_at =
          timestamptz '2101-01-03 18:00:00+09'

      and l.duration_minutes = 30

      and l.status =
          'canceled'::public.lesson_status
  ) then

    raise exception
      'TEST_FAILED: canceled lesson was auto-reconciled';
  end if;


  if not exists (
    select 1
    from public.lesson_rights r

    where r.id =
          v_right_1

      and r.status =
          'available'::public.lesson_right_status

      and r.duration_minutes = 30
  ) then

    raise exception
      'TEST_FAILED: canceled lesson right was altered';
  end if;


  -- ==========================================================
  -- 23. #2 INDIVIDUALLY MOVED LESSON MUST REMAIN UNCHANGED
  -- ==========================================================

  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_lesson_2

      and l.lesson_right_id =
          v_right_2

      and l.series_id =
          v_old_series_id

      and l.occurrence_at =
          timestamptz '2101-01-10 18:00:00+09'

      and l.starts_at =
          v_moved_2_starts_at

      and l.duration_minutes = 30

      and l.rescheduled_by =
          v_manager_id

      and l.status =
          'scheduled'::public.lesson_status
  ) then

    raise exception
      'TEST_FAILED: individually moved lesson was overwritten';
  end if;


  if not exists (
    select 1
    from public.lesson_rights r
    where r.id =
          v_right_2
      and r.duration_minutes = 30
  ) then

    raise exception
      'TEST_FAILED: individually moved right duration was overwritten';
  end if;


  -- ==========================================================
  -- 24. #3 UNTOUCHED -> NEW SCHEDULE'S THIRD OCCURRENCE
  --
  -- Critical ordinal assertion:
  --
  -- #1 and #2 were preserved,
  -- but #3 must NOT slide forward to new occurrence #1.
  -- ==========================================================

  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_lesson_3

      and l.lesson_right_id =
          v_right_3

      -- Historical generation provenance stays old.
      and l.series_id =
          v_old_series_id

      -- Stable occurrence identity stays old Monday.
      and l.occurrence_at =
          timestamptz '2101-01-17 18:00:00+09'

      -- Actual appointment follows NEW default #3.
      and l.starts_at =
          v_new_3_starts_at

      and l.ends_at =
          v_new_3_starts_at
          + interval '60 minutes'

      and l.duration_minutes = 60

      and l.teacher_id =
          v_teacher_id

      and l.rescheduled_by is null

      and l.status =
          'scheduled'::public.lesson_status
  ) then

    raise exception
      'TEST_FAILED: untouched lesson #3 ordinal/state incorrect';
  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_3

      and r.duration_minutes = 60

      and r.status =
          'reserved'::public.lesson_right_status
  ) then

    raise exception
      'TEST_FAILED: untouched right #3 did not receive new default duration';
  end if;


  -- ==========================================================
  -- 25. #4 UNTOUCHED -> NEW SCHEDULE'S FOURTH OCCURRENCE
  -- ==========================================================

  if not exists (
    select 1

    from public.lessons l

    where l.id =
          v_lesson_4

      and l.lesson_right_id =
          v_right_4

      and l.series_id =
          v_old_series_id

      and l.occurrence_at =
          timestamptz '2101-01-24 18:00:00+09'

      and l.starts_at =
          v_new_4_starts_at

      and l.ends_at =
          v_new_4_starts_at
          + interval '60 minutes'

      and l.duration_minutes = 60

      and l.teacher_id =
          v_teacher_id

      and l.rescheduled_by is null

      and l.status =
          'scheduled'::public.lesson_status
  ) then

    raise exception
      'TEST_FAILED: untouched lesson #4 ordinal/state incorrect';
  end if;


  if not exists (
    select 1

    from public.lesson_rights r

    where r.id =
          v_right_4

      and r.duration_minutes = 60

      and r.status =
          'reserved'::public.lesson_right_status
  ) then

    raise exception
      'TEST_FAILED: untouched right #4 did not receive new default duration';
  end if;


  -- ==========================================================
  -- 26. NO LESSON / RIGHT DUPLICATION
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.lesson_rights r

  where r.schedule_slot_id =
        v_slot_id

    and r.source_semester_id =
        v_semester_id

    and r.origin =
        'regular_base'::public.lesson_right_origin;


  if v_count <> 4 then
    raise exception
      'TEST_FAILED: schedule change changed right count: %',
      v_count;
  end if;


  select count(*)::integer
  into v_count

  from public.lessons l

  where l.lesson_right_id in (
    v_right_1,
    v_right_2,
    v_right_3,
    v_right_4
  );


  if v_count <> 4 then
    raise exception
      'TEST_FAILED: schedule change changed canonical lesson count: %',
      v_count;
  end if;


  -- ==========================================================
  -- 27. AUDIT
  -- ==========================================================

  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.event_type =
        'REGULAR_SCHEDULE_CHANGED'

    and a.subject_profile_id =
        v_student_id

    and a.details ->> 'scheduleSlotId' =
        v_slot_id::text;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: expected exactly 1 schedule-change audit, got %',
      v_count;
  end if;


  if not exists (
    select 1

    from public.audit_events a

    where a.event_type =
          'REGULAR_SCHEDULE_CHANGED'

      and a.subject_profile_id =
          v_student_id

      and a.details ->> 'scheduleSlotId' =
          v_slot_id::text

      and (
        a.details
        ->> 'reconciledLessonCount'
      )::integer = 2

      and (
        a.details
        -> 'before'
        ->> 'weekday'
      )::integer = 1

      and (
        a.details
        -> 'after'
        ->> 'weekday'
      )::integer = 4

      and (
        a.details
        -> 'after'
        ->> 'durationMinutes'
      )::integer = 60
  ) then

    raise exception
      'TEST_FAILED: schedule-change audit details incorrect';
  end if;


  -- ==========================================================
  -- 28. SAME CONFIG AGAIN = NO-OP
  --
  -- Must not create another series or audit.
  -- ==========================================================

  v_result :=
    public.change_regular_schedule(
      v_slot_id,
      v_teacher_id,
      4,
      time '19:00',
      60,
      v_effective_on
    );


  if (v_result ->> 'changed')::boolean <> false
     or
     (v_result ->> 'reconciledLessonCount')::integer <> 0 then

    raise exception
      'TEST_FAILED: repeated same schedule was not a no-op: %',
      v_result;
  end if;


  select count(*)::integer
  into v_count

  from public.lesson_series ls

  where ls.schedule_slot_id =
        v_slot_id;


  if v_count <> 2 then
    raise exception
      'TEST_FAILED: no-op created extra series version: %',
      v_count;
  end if;


  select count(*)::integer
  into v_count

  from public.audit_events a

  where a.event_type =
        'REGULAR_SCHEDULE_CHANGED'

    and a.subject_profile_id =
        v_student_id

    and a.details ->> 'scheduleSlotId' =
        v_slot_id::text;


  if v_count <> 1 then
    raise exception
      'TEST_FAILED: no-op created duplicate audit';
  end if;

end;
$$;


select
  'PASS: regular schedule change / versioned series / untouched future reconcile / canceled preserved / individual move preserved / ordinal preservation / right duration / work hours / blocked / collision / assignment / branch auth / atomic rollback / no-op'
  as test_result;

rollback;
