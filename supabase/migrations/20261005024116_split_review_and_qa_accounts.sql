-- Separate App Store review sandbox accounts from real-backend QA accounts.
--
-- is_review_account:
--   App Store review/demo account. Flutter may route it to review-only fake data.
--
-- is_qa_account:
--   Real Supabase/Auth/business/FCM account used for E2E QA. It keeps normal
--   effective access, but is omitted from operational lists and aggregates.

alter table public.profiles
  add column if not exists is_qa_account boolean not null default false;

alter table public.profiles
  drop constraint if exists profiles_review_qa_mutually_exclusive;

alter table public.profiles
  add constraint profiles_review_qa_mutually_exclusive
  check (not (is_review_account and is_qa_account));

comment on column public.profiles.is_qa_account is
  'Real-backend QA account. Uses normal Supabase/business/Push flows but is excluded from operational lists and aggregate reporting.';


create or replace function private.branch_management_summary(
  p_branch_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with branch_row as (
    select
      b.id,
      b.name,
      b.is_active
    from public.branches b
    where b.id = p_branch_id
  ),
  counts as (
    select
      count(*) filter (
        where p.role = 'manager'::public.user_role
          and coalesce(p.is_review_account, false) = false
          and coalesce(p.is_qa_account, false) = false
          and private.profile_has_effective_access(p.id)
      )::integer as active_manager_count,
      count(*) filter (
        where p.role = 'teacher'::public.user_role
          and coalesce(p.is_review_account, false) = false
          and coalesce(p.is_qa_account, false) = false
          and private.profile_has_effective_access(p.id)
      )::integer as active_teacher_count,
      count(*) filter (
        where p.role = 'student'::public.user_role
          and coalesce(p.is_review_account, false) = false
          and coalesce(p.is_qa_account, false) = false
          and private.profile_has_effective_access(p.id)
      )::integer as active_student_count
    from public.profiles p
    where p.branch_id = p_branch_id
  ),
  operational_counts as (
    select
      (
        select count(*)::integer
        from public.teacher_student_assignments a
        where a.branch_id = p_branch_id
          and (
            a.ends_on is null
            or a.ends_on >= (
              pg_catalog.now() at time zone 'Asia/Seoul'
            )::date
          )
          and not exists (
            select 1
            from public.profiles p
            where p.id in (a.teacher_id, a.student_id)
              and (
                coalesce(p.is_review_account, false) = true
                or coalesce(p.is_qa_account, false) = true
              )
          )
      ) as open_assignment_count,
      (
        select count(*)::integer
        from public.lesson_series s
        where s.branch_id = p_branch_id
          and (
            s.effective_until is null
            or s.effective_until >= (
              pg_catalog.now() at time zone 'Asia/Seoul'
            )::date
          )
          and not exists (
            select 1
            from public.profiles p
            where p.id in (s.teacher_id, s.student_id)
              and (
                coalesce(p.is_review_account, false) = true
                or coalesce(p.is_qa_account, false) = true
              )
          )
      ) as active_series_count,
      (
        select count(*)::integer
        from public.lessons l
        where l.branch_id = p_branch_id
          and l.status = 'scheduled'::public.lesson_status
          and l.ends_at > pg_catalog.now()
          and not exists (
            select 1
            from public.profiles p
            where p.id in (l.teacher_id, l.student_id)
              and (
                coalesce(p.is_review_account, false) = true
                or coalesce(p.is_qa_account, false) = true
              )
          )
      ) as remaining_lesson_count
  )
  select jsonb_build_object(
    'branchId', b.id,
    'name', b.name,
    'isActive', b.is_active,
    'activeManagerCount', c.active_manager_count,
    'activeTeacherCount', c.active_teacher_count,
    'activeStudentCount', c.active_student_count,
    'openAssignmentCount', o.open_assignment_count,
    'activeSeriesCount', o.active_series_count,
    'remainingLessonCount', o.remaining_lesson_count,
    'canDeactivate',
      c.active_manager_count = 0
      and c.active_teacher_count = 0
      and c.active_student_count = 0
      and o.open_assignment_count = 0
      and o.active_series_count = 0
      and o.remaining_lesson_count = 0
  )
  from branch_row b
  cross join counts c
  cross join operational_counts o;
$$;

revoke all on function private.branch_management_summary(uuid)
  from public, anon, authenticated, service_role;


create or replace function public.get_staff_work_report(
  p_semester_id uuid,
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text;
  v_actor_branch_id uuid;
  v_effective_branch_id uuid;
  v_semester_code text;
  v_result jsonb;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  select p.role::text, p.branch_id
  into v_actor_role, v_actor_branch_id
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true
    and coalesce(p.is_review_account, false) = false;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_EFFECTIVE_ACCESS_REQUIRED';
  end if;

  if v_actor_role not in ('master', 'manager') then
    raise exception using errcode='P0001', message='FORESTRING_WORK_REPORT_FORBIDDEN';
  end if;

  if v_actor_role = 'manager' then
    if v_actor_branch_id is null then
      raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_REQUIRED';
    end if;
    if p_branch_id is not null and p_branch_id is distinct from v_actor_branch_id then
      raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
    end if;
    v_effective_branch_id := v_actor_branch_id;
  else
    v_effective_branch_id := p_branch_id;
  end if;

  select s.code
  into v_semester_code
  from public.semesters s
  where s.id = p_semester_id;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  if v_effective_branch_id is not null and not exists (
    select 1
    from public.branches b
    where b.id = v_effective_branch_id
  ) then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_NOT_FOUND';
  end if;

  with branch_bounds as (
    select
      b.id as branch_id,
      b.name as branch_name,
      eb.starts_on,
      eb.ends_on
    from public.branches b
    cross join lateral private.get_effective_semester_bounds(
      b.id,
      p_semester_id
    ) eb
    where v_effective_branch_id is null
       or b.id = v_effective_branch_id
  ),
  completed_lessons as (
    select
      l.id,
      l.teacher_id,
      l.branch_id,
      l.duration_minutes,
      l.lesson_type::text as lesson_type
    from public.lessons l
    join branch_bounds bb
      on bb.branch_id = l.branch_id
    join public.profiles lp
      on lp.id = l.teacher_id
     and coalesce(lp.is_review_account, false) = false
     and coalesce(lp.is_qa_account, false) = false
    where (l.starts_at at time zone 'Asia/Seoul')::date
          between bb.starts_on and bb.ends_on
      and l.status::text = 'scheduled'
      and l.ends_at <= now()
  ),
  duration_counts as (
    select
      cl.teacher_id,
      cl.branch_id,
      cl.duration_minutes,
      count(*)::integer as lesson_count
    from completed_lessons cl
    group by cl.teacher_id, cl.branch_id, cl.duration_minutes
  ),
  type_counts as (
    select
      cl.teacher_id,
      cl.branch_id,
      cl.lesson_type,
      count(*)::integer as lesson_count,
      coalesce(sum(cl.duration_minutes), 0)::integer as total_minutes
    from completed_lessons cl
    group by cl.teacher_id, cl.branch_id, cl.lesson_type
  ),
  staff_rows as (
    select
      cl.teacher_id as staff_id,
      p.display_name as staff_name,
      p.role::text as staff_role,
      cl.branch_id,
      bb.branch_name,
      count(*)::integer as lesson_count,
      coalesce(sum(cl.duration_minutes), 0)::integer as total_minutes
    from completed_lessons cl
    join public.profiles p
      on p.id = cl.teacher_id
     and p.role::text in ('teacher', 'manager')
     and coalesce(p.is_review_account, false) = false
     and coalesce(p.is_qa_account, false) = false
    join branch_bounds bb
      on bb.branch_id = cl.branch_id
    group by
      cl.teacher_id,
      p.display_name,
      p.role,
      cl.branch_id,
      bb.branch_name
  ),
  branch_rows as (
    select
      bb.branch_id,
      bb.branch_name,
      bb.starts_on,
      bb.ends_on,
      count(cl.id)::integer as lesson_count,
      coalesce(sum(cl.duration_minutes), 0)::integer as total_minutes,
      count(distinct cl.teacher_id)::integer as staff_count
    from branch_bounds bb
    left join completed_lessons cl
      on cl.branch_id = bb.branch_id
    group by
      bb.branch_id,
      bb.branch_name,
      bb.starts_on,
      bb.ends_on
  ),
  overall as (
    select
      count(*)::integer as lesson_count,
      coalesce(sum(cl.duration_minutes), 0)::integer as total_minutes,
      count(distinct cl.teacher_id)::integer as staff_count,
      count(distinct cl.branch_id)::integer as worked_branch_count
    from completed_lessons cl
  )
  select jsonb_build_object(
    'semesterId', p_semester_id,
    'semesterCode', v_semester_code,
    'branchId', v_effective_branch_id,
    'calculatedAt', now(),
    'totalLessonCount', o.lesson_count,
    'totalMinutes', o.total_minutes,
    'staffCount', o.staff_count,
    'workedBranchCount', o.worked_branch_count,
    'branches',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'branchId', br.branch_id,
              'branchName', br.branch_name,
              'startsOn', br.starts_on,
              'endsOn', br.ends_on,
              'lessonCount', br.lesson_count,
              'totalMinutes', br.total_minutes,
              'staffCount', br.staff_count
            )
            order by br.total_minutes desc, br.branch_name
          )
          from branch_rows br
        ),
        '[]'::jsonb
      ),
    'staff',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'staffId', sr.staff_id,
              'staffName', sr.staff_name,
              'staffRole', sr.staff_role,
              'branchId', sr.branch_id,
              'branchName', sr.branch_name,
              'lessonCount', sr.lesson_count,
              'totalMinutes', sr.total_minutes,
              'durationGroups',
                coalesce(
                  (
                    select jsonb_agg(
                      jsonb_build_object(
                        'durationMinutes', dc.duration_minutes,
                        'lessonCount', dc.lesson_count
                      )
                      order by dc.duration_minutes
                    )
                    from duration_counts dc
                    where dc.teacher_id = sr.staff_id
                      and dc.branch_id = sr.branch_id
                  ),
                  '[]'::jsonb
                ),
              'typeGroups',
                coalesce(
                  (
                    select jsonb_agg(
                      jsonb_build_object(
                        'lessonType', tc.lesson_type,
                        'lessonCount', tc.lesson_count,
                        'totalMinutes', tc.total_minutes
                      )
                      order by tc.lesson_type
                    )
                    from type_counts tc
                    where tc.teacher_id = sr.staff_id
                      and tc.branch_id = sr.branch_id
                  ),
                  '[]'::jsonb
                )
            )
            order by sr.total_minutes desc, sr.staff_name
          )
          from staff_rows sr
        ),
        '[]'::jsonb
      )
  )
  into v_result
  from overall o;

  return v_result;
end;
$function$;

revoke all on function public.get_staff_work_report(uuid, uuid)
  from public, anon;

grant execute on function public.get_staff_work_report(uuid, uuid)
  to authenticated, service_role;


create or replace function public.get_teacher_semester_lesson_stats(
  p_teacher_id uuid
)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text;
  v_actor_branch_id uuid;
  v_teacher_name text;
  v_teacher_branch_id uuid;
  v_teacher_created_at timestamptz;
  v_withdrawal_date date;
  v_first_lesson_date date;
  v_employment_starts_on date;
  v_semesters jsonb;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  select p.role::text,p.branch_id
  into v_actor_role,v_actor_branch_id
  from public.profiles p
  where p.id=v_actor_id
    and p.is_active=true
    and coalesce(p.is_review_account,false)=false;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_EFFECTIVE_ACCESS_REQUIRED';
  end if;

  if v_actor_role not in ('master','manager') then
    raise exception using errcode='P0001', message='FORESTRING_TEACHER_STATS_FORBIDDEN';
  end if;

  select p.display_name,p.branch_id,t.created_at,t.withdrawal_date
  into v_teacher_name,v_teacher_branch_id,v_teacher_created_at,v_withdrawal_date
  from public.profiles p
  join public.teachers t on t.id=p.id
  where p.id=p_teacher_id
    and p.role::text in ('teacher','manager')
    and coalesce(p.is_review_account,false)=false
    and coalesce(p.is_qa_account,false)=false;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_TEACHER_NOT_FOUND';
  end if;

  if v_actor_role='manager'
     and v_actor_branch_id is distinct from v_teacher_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select min((l.starts_at at time zone 'Asia/Seoul')::date)
  into v_first_lesson_date
  from public.lessons l
  where l.teacher_id=p_teacher_id;

  v_employment_starts_on := least(
    (v_teacher_created_at at time zone 'Asia/Seoul')::date,
    coalesce(
      v_first_lesson_date,
      (v_teacher_created_at at time zone 'Asia/Seoul')::date
    )
  );

  with relevant_semesters as (
    select
      s.id,
      s.code,
      eb.starts_on,
      eb.ends_on,
      eb.is_overridden
    from public.semesters s
    cross join lateral private.get_effective_semester_bounds(
      v_teacher_branch_id,
      s.id
    ) eb
    where eb.starts_on <= (now() at time zone 'Asia/Seoul')::date
      and eb.ends_on >= v_employment_starts_on
      and (
        v_withdrawal_date is null
        or eb.starts_on <= v_withdrawal_date
      )
  ),
  duration_counts as (
    select
      s.id as semester_id,
      l.duration_minutes,
      count(*)::integer as lesson_count
    from relevant_semesters s
    join public.lessons l
      on l.teacher_id=p_teacher_id
     and (l.starts_at at time zone 'Asia/Seoul')::date
         between s.starts_on and s.ends_on
     and l.status::text='scheduled'
     and l.ends_at <= now()
    group by s.id,l.duration_minutes
  ),
  semester_rows as (
    select
      s.id,
      s.code,
      s.starts_on,
      s.ends_on,
      s.is_overridden,
      coalesce(sum(dc.lesson_count),0)::integer as total_lesson_count,
      coalesce(sum(dc.lesson_count*dc.duration_minutes),0)::integer
        as total_minutes,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'durationMinutes',dc.duration_minutes,
            'lessonCount',dc.lesson_count
          ) order by dc.duration_minutes
        ) filter (where dc.duration_minutes is not null),
        '[]'::jsonb
      ) as duration_groups
    from relevant_semesters s
    left join duration_counts dc on dc.semester_id=s.id
    group by s.id,s.code,s.starts_on,s.ends_on,s.is_overridden
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'semesterId',sr.id,
        'code',sr.code,
        'startsOn',sr.starts_on,
        'endsOn',sr.ends_on,
        'isCurrent',
          (now() at time zone 'Asia/Seoul')::date
            between sr.starts_on and sr.ends_on,
        'totalLessonCount',sr.total_lesson_count,
        'totalMinutes',sr.total_minutes,
        'durationGroups',sr.duration_groups
      ) order by sr.starts_on desc
    ),
    '[]'::jsonb
  ) into v_semesters
  from semester_rows sr;

  return jsonb_build_object(
    'teacherId',p_teacher_id,
    'teacherName',v_teacher_name,
    'employmentStartsOn',v_employment_starts_on,
    'withdrawalDate',v_withdrawal_date,
    'calculatedAt',now(),
    'semesters',v_semesters
  );
end;
$function$;
