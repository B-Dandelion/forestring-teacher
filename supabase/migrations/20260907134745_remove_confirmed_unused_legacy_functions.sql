-- Forestring production cleanup after full DB function audit.
-- Keep auth_record_login_failure() because auth_record_login_failure_scoped() delegates to it.
-- Keep auth_clear_login_rate_limit() because the deployed login-with-pin Edge Function calls it directly
-- and auth_clear_login_rate_limits_for_subject() also delegates to it.

-- Dead trigger/helper functions.
drop function if exists public.assert_teacher_capable_role() restrict;
drop function if exists private.teacher_is_within_work_hours(uuid, date, integer, time without time zone, time without time zone) restrict;
drop function if exists private.student_branch_on_date(uuid, date) restrict;

-- Legacy rate-limit state setter. Current login flow uses get + scoped record + clear helpers.
drop function if exists public.auth_set_login_rate_limit(text, integer, timestamp with time zone, timestamp with time zone) restrict;

-- One-time Firebase/archive import helpers. Keep the historical migration SQL files in git;
-- remove executable importer functions from the production runtime schema.
drop function if exists private.import_firebase_archive_lessons_text_atomic(text) restrict;
drop function if exists private.import_firebase_archive_lessons_text(text) restrict;
drop function if exists private.import_firebase_archive_lessons(jsonb) restrict;

drop function if exists private.import_firebase_archive_people_text(text) restrict;
drop function if exists private.import_firebase_archive_people(jsonb) restrict;

drop function if exists private.import_merged_firebase_history_text_atomic(text) restrict;
drop function if exists private.import_merged_firebase_history_text(text) restrict;

drop function if exists private.import_raw_merged_firebase_history_text_atomic(text) restrict;
drop function if exists private.import_raw_merged_firebase_history_text(text) restrict;
