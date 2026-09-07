create or replace function private.assert_blocked_period_no_lesson_conflict()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  -- Serialize personal-schedule writes with lesson writes for the same teacher.
  -- Existing scheduled lessons are intentionally allowed to remain. The public
  -- RPC reports them as warnings after the blocked period is stored. Once the
  -- blocked period exists, the opposite lesson trigger continues to reject any
  -- new or moved scheduled lesson that would overlap it.
  perform private.lock_teacher_schedule(new.teacher_id);
  return new;
end;
$function$;
