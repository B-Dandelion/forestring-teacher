-- Materialize the next semester immediately after a CURRENT-semester regular student registration.
--
-- Existing behavior is preserved:
--   * selected/start semester is still materialized by initialize_regular_student_semester()
--   * nightly semester automation remains the recovery/idempotency safety net
--   * future-semester initial registration does NOT pre-create one additional semester
--   * failure to pre-materialize the next semester must not roll back the completed registration
--
-- This migration deliberately patches the final runtime function definitions instead of
-- replacing them with an older full body. Both functions have received semantic patches in
-- later migrations, so this preserves the current production/staging behavior.

do $migration$
declare
  v_oid regprocedure;
  v_def text;
  v_new text;
  v_old_fragment text;
begin
  -- ----------------------------------------------------------
  -- 1. Reuse ensure_semester_plan_materialized from staff flow.
  --
  -- require_semester_automation_actor() already accepts:
  --   * system cron, or
  --   * active master/manager JWT actors.
  --
  -- The extra is_system-only guard prevented the registration RPC from reusing it.
  -- The function itself remains private and EXECUTE stays revoked from client roles.
  -- ----------------------------------------------------------
  v_oid := to_regprocedure(
    'private.ensure_semester_plan_materialized(uuid,uuid)'
  );

  if v_oid is null then
    raise exception
      'FORESTRING_MIGRATION_TARGET_NOT_FOUND: private.ensure_semester_plan_materialized(uuid,uuid)';
  end if;

  select pg_get_functiondef(v_oid) into v_def;

  v_old_fragment :=
$fragment$  if not v_actor.is_system then
    raise exception using errcode='42501', message='FORESTRING_SYSTEM_SEMESTER_AUTOMATION_REQUIRED';
  end if;

$fragment$;

  v_new := replace(v_def, v_old_fragment, '');

  if v_new = v_def then
    raise exception
      'FORESTRING_MIGRATION_MARKER_NOT_FOUND: ensure_semester_plan_materialized system-only guard';
  end if;

  execute v_new;

  -- ----------------------------------------------------------
  -- 2. After CURRENT-semester initial regular activation,
  --    immediately materialize the consecutive next semester.
  -- ----------------------------------------------------------
  v_oid := to_regprocedure(
    'public.initialize_regular_student_semester(uuid,uuid,uuid,jsonb)'
  );

  if v_oid is null then
    raise exception
      'FORESTRING_MIGRATION_TARGET_NOT_FOUND: public.initialize_regular_student_semester(uuid,uuid,uuid,jsonb)';
  end if;

  select pg_get_functiondef(v_oid) into v_def;

  v_new := replace(
    v_def,
$fragment$  v_activation jsonb;
$fragment$,
$fragment$  v_activation jsonb;
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_next_semester_id uuid;
  v_next_error_state text;
  v_next_error_message text;
$fragment$
  );

  if v_new = v_def then
    raise exception
      'FORESTRING_MIGRATION_MARKER_NOT_FOUND: initialize_regular_student_semester declarations';
  end if;

  v_def := v_new;

  v_new := replace(
    v_def,
$fragment$  v_activation:=public.activate_student_semester_plan(v_plan_id);

$fragment$,
$fragment$  v_activation:=public.activate_student_semester_plan(v_plan_id);

  -- When registration starts in the semester that is active today, create the
  -- immediately-consecutive next semester now instead of waiting for midnight cron.
  --
  -- If the selected start semester is already in the future, it has just been
  -- materialized above and we intentionally stop there.
  if v_today between v_semester_start and v_semester_end then
    select sem.id
      into v_next_semester_id
    from public.semesters sem
    cross join lateral
      private.get_effective_semester_bounds(v_student_branch_id,sem.id) e
    where e.starts_on=v_semester_end+1
    order by e.starts_on
    limit 1;

    if v_next_semester_id is not null then
      begin
        perform private.ensure_semester_plan_materialized(
          p_student_id,
          v_next_semester_id
        );
      exception when others then
        get stacked diagnostics
          v_next_error_state=returned_sqlstate,
          v_next_error_message=message_text;

        -- Initial registration has already succeeded. Do not undo it only because
        -- the optional next-semester warm-up failed; nightly cron remains a retry path.
        insert into public.audit_events (
          subject_profile_id,
          branch_id,
          semester_id,
          event_type,
          effective_on,
          actor_id,
          details
        ) values (
          p_student_id,
          v_student_branch_id,
          v_next_semester_id,
          'STUDENT_NEXT_SEMESTER_AUTO_FAILED',
          v_today,
          v_actor_id,
          jsonb_build_object(
            'executionSource','staff_registration',
            'sqlState',v_next_error_state,
            'message',v_next_error_message
          )
        );

        raise warning
          'Immediate next-semester materialization failed for student %: [%] %',
          p_student_id,
          v_next_error_state,
          v_next_error_message;
      end;
    end if;
  end if;

$fragment$
  );

  if v_new = v_def then
    raise exception
      'FORESTRING_MIGRATION_MARKER_NOT_FOUND: initialize_regular_student_semester activation hook';
  end if;

  execute v_new;
end;
$migration$;

-- Re-assert the intended API boundary after CREATE OR REPLACE.
revoke all
on function private.ensure_semester_plan_materialized(uuid,uuid)
from public, anon, authenticated, service_role;

revoke all
on function public.initialize_regular_student_semester(uuid,uuid,uuid,jsonb)
from public, anon;

grant execute
on function public.initialize_regular_student_semester(uuid,uuid,uuid,jsonb)
to authenticated, service_role;
