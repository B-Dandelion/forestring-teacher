-- Supabase grants EXECUTE on new public functions to anon by default.
-- These SECURITY DEFINER functions already reject calls without
-- auth.uid(), but anon should not be able to call them at all.

revoke all on function public.get_student_lesson_activity(uuid, uuid) from anon;
revoke all on function public.get_student_cancellation_quotas(uuid) from anon;
