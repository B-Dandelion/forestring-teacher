-- Teacher semester statistics use a private branch-aware semester helper.
-- Keep the helper private and execute the public RPC with the function owner's
-- privileges. The RPC itself still validates auth.uid(), role, and manager
-- branch scope before reading any teacher statistics.

alter function public.get_teacher_semester_lesson_stats(uuid)
  security definer;

revoke all on function public.get_teacher_semester_lesson_stats(uuid)
  from public, anon;

grant execute on function public.get_teacher_semester_lesson_stats(uuid)
  to authenticated, service_role;
