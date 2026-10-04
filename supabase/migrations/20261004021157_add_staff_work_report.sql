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
