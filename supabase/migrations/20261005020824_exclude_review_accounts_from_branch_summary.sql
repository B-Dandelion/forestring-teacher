-- Keep review/QA accounts out of operational branch management totals.
-- These accounts still retain effective access so they can be used for real
-- device and push-notification E2E tests without appearing as operating staff.

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
          and private.profile_has_effective_access(p.id)
      )::integer as active_manager_count,
      count(*) filter (
        where p.role = 'teacher'::public.user_role
          and coalesce(p.is_review_account, false) = false
          and private.profile_has_effective_access(p.id)
      )::integer as active_teacher_count,
      count(*) filter (
        where p.role = 'student'::public.user_role
          and coalesce(p.is_review_account, false) = false
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
              and coalesce(p.is_review_account, false) = true
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
              and coalesce(p.is_review_account, false) = true
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
              and coalesce(p.is_review_account, false) = true
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
