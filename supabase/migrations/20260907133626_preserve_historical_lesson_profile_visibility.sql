create or replace function private.profile_has_canonical_student_row(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.students s
    where s.id = p_profile_id
  );
$function$;

alter policy profiles_hide_orphan_merged_students
on public.profiles
using (
  role <> 'student'::public.user_role
  or is_review_account = true
  or private.profile_has_canonical_student_row(id)
);
