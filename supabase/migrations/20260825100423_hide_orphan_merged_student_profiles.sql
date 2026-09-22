drop policy if exists profiles_hide_orphan_merged_students on public.profiles;

create policy profiles_hide_orphan_merged_students
on public.profiles
as restrictive
for select
to authenticated
using (
  role <> 'student'::public.user_role
  or is_review_account = true
  or exists (
    select 1
    from public.students s
    where s.id = profiles.id
  )
);
