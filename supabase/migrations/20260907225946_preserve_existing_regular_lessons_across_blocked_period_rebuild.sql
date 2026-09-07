create or replace function private.regular_right_lesson_matches_target(
  p_right_id uuid,
  p_series_id uuid,
  p_teacher_id uuid,
  p_starts_at timestamptz,
  p_duration_minutes integer
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.lessons l
    where l.lesson_right_id = p_right_id
      and l.lesson_type = 'regular'::public.lesson_type
      and l.status = 'scheduled'::public.lesson_status
      and l.rescheduled_by is null
      and l.canceled_at is null
      and l.series_id is not distinct from p_series_id
      and l.teacher_id = p_teacher_id
      and l.occurrence_at is not distinct from p_starts_at
      and l.starts_at = p_starts_at
      and l.duration_minutes = p_duration_minutes
  );
$function$;

revoke all on function private.regular_right_lesson_matches_target(uuid,uuid,uuid,timestamptz,integer)
from public, anon, authenticated, service_role;

do $mig$
declare
  v_def text;
  v_new text;
  v_old text := $old$if v_default_following then
            if not exists ($old$;
  v_replacement text := $new$if v_default_following then
            if private.regular_right_lesson_matches_target(
              v_right.id,
              v_candidate.series_id,
              v_candidate.teacher_id,
              v_candidate.starts_at,
              v_candidate.duration_minutes
            ) then
              update public.lesson_rights
              set duration_minutes = v_candidate.duration_minutes
              where id = v_right.id;

              v_reconciled := v_reconciled + 1;
              continue;
            end if;

            if not exists ($new$;
begin
  select pg_get_functiondef('private.rebuild_future_regular_semester(uuid,uuid)'::regprocedure)
  into v_def;

  if position('regular_right_lesson_matches_target' in v_def) = 0 then
    if position(v_old in v_def) = 0 then
      raise exception 'FORESTRING_REBUILD_DEFAULT_BRANCH_PATCH_TARGET_NOT_FOUND';
    end if;
    v_new := replace(v_def, v_old, v_replacement);
    execute v_new;
  end if;

  select pg_get_functiondef('private.rebuild_future_regular_semester(uuid,uuid)'::regprocedure)
  into v_def;
  if position('regular_right_lesson_matches_target' in v_def) = 0 then
    raise exception 'FORESTRING_REBUILD_EXISTING_TARGET_BYPASS_NOT_INSTALLED';
  end if;
end;
$mig$;
