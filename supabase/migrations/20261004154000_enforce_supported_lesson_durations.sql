-- Forestring 3.3 release hardening
--
-- The mobile UI only supports 15 / 30 / 45 / 60 minute lessons.
-- Production data was checked before this migration and contains no other
-- duration values in lessons, lesson_series, lesson_rights, or flex plans.
-- Keep the existing technical duration checks and add the product-level rule.

alter table public.lessons
  add constraint lessons_supported_duration_check
  check (duration_minutes in (15, 30, 45, 60))
  not valid;

alter table public.lesson_series
  add constraint lesson_series_supported_duration_check
  check (duration_minutes in (15, 30, 45, 60))
  not valid;

alter table public.lesson_rights
  add constraint lesson_rights_supported_duration_check
  check (duration_minutes in (15, 30, 45, 60))
  not valid;

alter table public.student_semester_plans
  add constraint student_semester_plans_supported_flex_duration_check
  check (
    flex_duration_minutes is null
    or flex_duration_minutes in (15, 30, 45, 60)
  )
  not valid;

alter table public.lessons
  validate constraint lessons_supported_duration_check;

alter table public.lesson_series
  validate constraint lesson_series_supported_duration_check;

alter table public.lesson_rights
  validate constraint lesson_rights_supported_duration_check;

alter table public.student_semester_plans
  validate constraint student_semester_plans_supported_flex_duration_check;
