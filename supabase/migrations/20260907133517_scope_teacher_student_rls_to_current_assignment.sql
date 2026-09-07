create or replace function private.teacher_has_student_relation(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.teacher_student_assignments a
    where a.teacher_id = (select auth.uid())
      and a.student_id = p_student_id
      and a.starts_on <= ((pg_catalog.now() at time zone 'Asia/Seoul')::date)
      and (
        a.ends_on is null
        or a.ends_on >= ((pg_catalog.now() at time zone 'Asia/Seoul')::date)
      )
  );
$function$;

create or replace function private.student_has_teacher_relation(p_teacher_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.teacher_student_assignments a
    where a.student_id = (select auth.uid())
      and a.teacher_id = p_teacher_id
      and a.starts_on <= ((pg_catalog.now() at time zone 'Asia/Seoul')::date)
      and (
        a.ends_on is null
        or a.ends_on >= ((pg_catalog.now() at time zone 'Asia/Seoul')::date)
      )
  );
$function$;

create or replace function private.actor_has_shared_lesson_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.lessons l
    where (
      l.teacher_id = (select auth.uid())
      and l.student_id = p_profile_id
    )
    or (
      l.student_id = (select auth.uid())
      and l.teacher_id = p_profile_id
    )
  );
$function$;

alter policy profiles_select
on public.profiles
using (
  (
    id = (select auth.uid())
    and is_active = true
    and is_review_account = true
  )
  or (
    (select private.is_active_user())
    and (
      id = (select auth.uid())
      or (
        is_review_account = false
        and (
          (select private.is_master())
          or (
            (select private.is_manager())
            and branch_id = (select private.current_branch_id())
            and role = any(array[
              'manager'::public.user_role,
              'teacher'::public.user_role,
              'student'::public.user_role
            ])
          )
          or (
            role = 'student'::public.user_role
            and private.teacher_has_student_relation(id)
          )
          or (
            role = any(array[
              'teacher'::public.user_role,
              'manager'::public.user_role
            ])
            and private.student_has_teacher_relation(id)
          )
          or private.actor_has_shared_lesson_profile(id)
        )
      )
    )
  )
);
