create or replace function public.get_teacher_semester_lesson_stats(p_teacher_id uuid)
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
    and coalesce(p.is_review_account,false)=false;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_TEACHER_NOT_FOUND';
  end if;

  if v_actor_role='manager' and v_actor_branch_id is distinct from v_teacher_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select min((l.starts_at at time zone 'Asia/Seoul')::date)
  into v_first_lesson_date
  from public.lessons l
  where l.teacher_id=p_teacher_id;

  v_employment_starts_on := least(
    (v_teacher_created_at at time zone 'Asia/Seoul')::date,
    coalesce(v_first_lesson_date,(v_teacher_created_at at time zone 'Asia/Seoul')::date)
  );

  with relevant_semesters as (
    select
      s.id,
      s.code,
      eb.starts_on,
      eb.ends_on,
      eb.is_overridden
    from public.semesters s
    cross join lateral private.get_effective_semester_bounds(v_teacher_branch_id,s.id) eb
    where eb.starts_on <= (now() at time zone 'Asia/Seoul')::date
      and eb.ends_on >= v_employment_starts_on
      and (v_withdrawal_date is null or eb.starts_on <= v_withdrawal_date)
  ),
  duration_counts as (
    select
      s.id as semester_id,
      l.duration_minutes,
      count(*)::integer as lesson_count
    from relevant_semesters s
    join public.lessons l
      on l.teacher_id=p_teacher_id
     and (l.starts_at at time zone 'Asia/Seoul')::date between s.starts_on and s.ends_on
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
      coalesce(sum(dc.lesson_count*dc.duration_minutes),0)::integer as total_minutes,
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
        'isCurrent',(now() at time zone 'Asia/Seoul')::date between sr.starts_on and sr.ends_on,
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
