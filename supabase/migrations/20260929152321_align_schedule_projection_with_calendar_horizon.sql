
-- Keep generated lesson projections aligned with the schedule window that
-- teacher, manager, and master calendars can actually browse.
--
-- Flutter calendar window:
--   firstDay/minDate = first day of current month - 2 months
--   lastDay/maxDate  = last day of current month + 3 months
--
-- For future lesson generation we only need the forward half of that window.
-- A semester that starts on/before the visible horizon is materialized in full,
-- because lesson rights/plans are semester-scoped.

create or replace function private.ensure_semester_plan_materialized(
  p_student_id uuid,
  p_semester_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor record;
  v_student_type public.student_type;
  v_inherited_type public.student_type;
  v_student_status public.student_status;
  v_branch_id uuid;
  v_active boolean;
  v_withdrawal_date date;
  v_semester_start date;
  v_semester_end date;
  v_plan public.student_semester_plans%rowtype;
  v_plan_id uuid;
  v_plan_created boolean := false;
  v_flex_count integer;
  v_flex_duration integer;
  v_activation jsonb;
begin
  select * into v_actor from private.require_semester_automation_actor();

  select s.student_type,s.status,p.branch_id,p.is_active,s.withdrawal_date
  into v_student_type,v_student_status,v_branch_id,v_active,v_withdrawal_date
  from public.students s
  join public.profiles p on p.id=s.id
  where s.id=p_student_id;

  if not found or not v_active or v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  select e.starts_on,e.ends_on into v_semester_start,v_semester_end
  from private.get_effective_semester_bounds(v_branch_id,p_semester_id) e;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  if v_withdrawal_date is not null and v_withdrawal_date <= v_semester_start then
    return jsonb_build_object(
      'studentId',p_student_id,'semesterId',p_semester_id,
      'changed',false,'skipped',true,'reason','withdrawal_before_semester'
    );
  end if;

  select * into v_plan
  from public.student_semester_plans sp
  where sp.student_id=p_student_id and sp.semester_id=p_semester_id
  for update;

  if found then
    v_plan_id := v_plan.id;
  else
    -- A future planned type change must carry forward to later projected
    -- semesters. students.student_type intentionally remains the CURRENT type
    -- until the boundary transition, so inherit the nearest earlier plan when
    -- one exists in the same branch.
    select sp.student_type_snapshot
      into v_inherited_type
    from public.student_semester_plans sp
    cross join lateral private.get_effective_semester_bounds(
      sp.branch_id,
      sp.semester_id
    ) b
    where sp.student_id=p_student_id
      and sp.branch_id=v_branch_id
      and b.starts_on < v_semester_start
    order by b.starts_on desc
    limit 1;

    v_student_type := coalesce(v_inherited_type,v_student_type);

    if v_student_type='regular'::public.student_type then
      insert into public.student_semester_plans (
        student_id,semester_id,branch_id,student_type_snapshot,
        flex_base_right_count,flex_duration_minutes,status,created_by,updated_by
      ) values (
        p_student_id,p_semester_id,v_branch_id,'regular'::public.student_type,
        null,null,'planned'::public.student_semester_plan_status,
        v_actor.actor_id,v_actor.actor_id
      ) returning id into v_plan_id;
    elsif v_student_type='flex'::public.student_type then
      select sp.flex_base_right_count,sp.flex_duration_minutes
      into v_flex_count,v_flex_duration
      from public.student_semester_plans sp
      join public.semesters sem on sem.id=sp.semester_id
      where sp.student_id=p_student_id
        and sp.student_type_snapshot='flex'::public.student_type
        and sp.flex_base_right_count is not null
        and sp.flex_duration_minutes is not null
        and sem.starts_on < (select starts_on from public.semesters where id=p_semester_id)
      order by sem.starts_on desc
      limit 1;

      if v_flex_count is null or v_flex_duration is null then
        raise exception using errcode='P0001', message='FORESTRING_FLEX_SEMESTER_PLAN_CONFIGURATION_REQUIRED';
      end if;

      insert into public.student_semester_plans (
        student_id,semester_id,branch_id,student_type_snapshot,
        flex_base_right_count,flex_duration_minutes,status,created_by,updated_by
      ) values (
        p_student_id,p_semester_id,v_branch_id,'flex'::public.student_type,
        v_flex_count,v_flex_duration,'planned'::public.student_semester_plan_status,
        v_actor.actor_id,v_actor.actor_id
      ) returning id into v_plan_id;
    else
      raise exception using errcode='P0001', message='FORESTRING_UNSUPPORTED_STUDENT_TYPE';
    end if;
    v_plan_created := true;
  end if;

  v_activation := public.activate_student_semester_plan(v_plan_id);

  return jsonb_build_object(
    'studentId',p_student_id,'semesterId',p_semester_id,'planId',v_plan_id,
    'planCreated',v_plan_created,
    'changed',v_plan_created or coalesce((v_activation->>'changed')::boolean,false),
    'skipped',false,'activation',v_activation
  );
end;
$function$;

revoke all
on function private.ensure_semester_plan_materialized(uuid,uuid)
from public, anon, authenticated, service_role;


create or replace function private.ensure_student_schedule_projection(
  p_student_id uuid,
  p_reference_date date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor record;
  v_branch_id uuid;
  v_student_status public.student_status;
  v_profile_active boolean;
  v_withdrawal_date date;
  v_reference_date date;
  v_horizon_end date;
  v_current_end date;
  v_cursor_end date;
  v_next_semester_id uuid;
  v_next_start date;
  v_next_end date;
  v_result jsonb;
  v_attempted integer := 0;
  v_materialized integer := 0;
  v_ready integer := 0;
  v_skipped_withdrawal integer := 0;
  v_missing_semester integer := 0;
begin
  select * into v_actor from private.require_semester_automation_actor();

  v_reference_date := coalesce(
    p_reference_date,
    (pg_catalog.now() at time zone 'Asia/Seoul')::date
  );

  -- Matches DateTime(now.year, now.month + 4, 0) in Flutter:
  -- the final day of the third calendar month after the current month.
  v_horizon_end :=
    (
      date_trunc('month',v_reference_date::timestamp)
      + interval '4 months'
      - interval '1 day'
    )::date;

  select p.branch_id,s.status,p.is_active,s.withdrawal_date
    into v_branch_id,v_student_status,v_profile_active,v_withdrawal_date
  from public.students s
  join public.profiles p on p.id=s.id
  where s.id=p_student_id;

  if not found or not v_profile_active or
     v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  select e.ends_on
    into v_current_end
  from public.semesters sem
  cross join lateral private.get_effective_semester_bounds(v_branch_id,sem.id) e
  where v_reference_date between e.starts_on and e.ends_on
  order by e.starts_on desc
  limit 1;

  if v_current_end is null then
    return jsonb_build_object(
      'studentId',p_student_id,
      'referenceDate',v_reference_date,
      'horizonEnd',v_horizon_end,
      'attemptedCount',0,
      'materializedCount',0,
      'alreadyReadyCount',0,
      'skippedWithdrawalCount',0,
      'missingSemesterCount',1,
      'skipped',true,
      'reason','current_semester_not_found'
    );
  end if;

  v_cursor_end := v_current_end;

  while v_cursor_end < v_horizon_end loop
    v_next_semester_id := null;
    v_next_start := null;
    v_next_end := null;

    select sem.id,e.starts_on,e.ends_on
      into v_next_semester_id,v_next_start,v_next_end
    from public.semesters sem
    cross join lateral private.get_effective_semester_bounds(v_branch_id,sem.id) e
    where e.starts_on=v_cursor_end+1
    order by e.starts_on
    limit 1;

    if v_next_semester_id is null then
      v_missing_semester := v_missing_semester + 1;
      exit;
    end if;

    if v_next_start > v_horizon_end then
      exit;
    end if;

    if v_withdrawal_date is not null and v_withdrawal_date <= v_next_start then
      v_skipped_withdrawal := v_skipped_withdrawal + 1;
      exit;
    end if;

    v_attempted := v_attempted + 1;
    v_result := private.ensure_semester_plan_materialized(
      p_student_id,
      v_next_semester_id
    );

    if coalesce((v_result->>'skipped')::boolean,false) then
      v_skipped_withdrawal := v_skipped_withdrawal + 1;
      exit;
    elsif coalesce((v_result->>'changed')::boolean,false) then
      v_materialized := v_materialized + 1;
    else
      v_ready := v_ready + 1;
    end if;

    v_cursor_end := v_next_end;
  end loop;

  return jsonb_build_object(
    'studentId',p_student_id,
    'referenceDate',v_reference_date,
    'horizonEnd',v_horizon_end,
    'attemptedCount',v_attempted,
    'materializedCount',v_materialized,
    'alreadyReadyCount',v_ready,
    'skippedWithdrawalCount',v_skipped_withdrawal,
    'missingSemesterCount',v_missing_semester,
    'skipped',false
  );
end;
$function$;

revoke all
on function private.ensure_student_schedule_projection(uuid,date)
from public, anon, authenticated, service_role;


create or replace function private.run_due_semester_automation(
  p_run_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_run_date date;
  v_source record;
  v_student record;
  v_target_semester_id uuid;
  v_target_plan_id uuid;
  v_result jsonb;
  v_ensure jsonb;
  v_attempted_transition integer := 0;
  v_transitioned integer := 0;
  v_transition_failed integer := 0;
  v_carryover_created integer := 0;
  v_future_attempted integer := 0;
  v_future_materialized integer := 0;
  v_future_ready integer := 0;
  v_future_skipped_withdrawal integer := 0;
  v_future_missing_semester integer := 0;
  v_future_failed integer := 0;
  v_error_state text;
  v_error_message text;
begin
  if session_user <> 'postgres' then
    raise exception using errcode='42501', message='FORESTRING_SYSTEM_SEMESTER_AUTOMATION_FORBIDDEN';
  end if;

  v_run_date := coalesce(
    p_run_date,
    (pg_catalog.now() at time zone 'Asia/Seoul')::date
  );

  perform pg_catalog.set_config('forestring.system_semester_transition','cron',true);
  perform pg_catalog.set_config('forestring.system_semester_run_date',v_run_date::text,true);

  -- Boundary transition/finalization remains day-driven.
  for v_source in
    select sp.id as source_plan_id,sp.student_id,sp.branch_id,s.withdrawal_date
    from public.student_semester_plans sp
    join public.students s on s.id=sp.student_id
    join public.profiles p on p.id=sp.student_id
    cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) e
    where sp.status='active'::public.student_semester_plan_status
      and e.ends_on=v_run_date-1
      and s.status='active'::public.student_status
      and p.is_active=true
      and (s.withdrawal_date is null or s.withdrawal_date > v_run_date)
    order by sp.student_id
  loop
    v_attempted_transition := v_attempted_transition + 1;
    begin
      select sem.id into v_target_semester_id
      from public.semesters sem
      cross join lateral private.get_effective_semester_bounds(v_source.branch_id,sem.id) e
      where e.starts_on=v_run_date
      order by e.starts_on
      limit 1;

      if v_target_semester_id is null then
        raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_NOT_FOUND';
      end if;

      v_ensure := private.ensure_semester_plan_materialized(
        v_source.student_id,
        v_target_semester_id
      );

      select sp.id into v_target_plan_id
      from public.student_semester_plans sp
      where sp.student_id=v_source.student_id
        and sp.semester_id=v_target_semester_id;

      if v_target_plan_id is null then
        raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_PLAN_NOT_FOUND';
      end if;

      v_result := public.transition_student_semester(
        v_source.source_plan_id,
        v_target_plan_id
      );
      v_transitioned := v_transitioned + 1;
      v_carryover_created := v_carryover_created
        + coalesce((v_result->'finalization'->>'carryoverCreated')::integer,0);
    exception when others then
      get stacked diagnostics
        v_error_state=returned_sqlstate,
        v_error_message=message_text;
      v_transition_failed := v_transition_failed + 1;

      insert into public.audit_events (
        subject_profile_id,branch_id,semester_id,event_type,
        effective_on,actor_id,details
      ) values (
        v_source.student_id,v_source.branch_id,null,
        'STUDENT_SEMESTER_AUTO_FAILED',v_run_date,null,
        jsonb_build_object(
          'executionSource','system_cron',
          'runDateKst',v_run_date,
          'sqlState',v_error_state,
          'message',v_error_message
        )
      );

      raise warning
        'Automatic semester transition failed for student %: [%] %',
        v_source.student_id,v_error_state,v_error_message;
    end;
  end loop;

  -- Keep every active student's generated schedule filled through the same
  -- forward date that the staff calendars can browse.
  for v_student in
    select s.id as student_id,p.branch_id
    from public.students s
    join public.profiles p on p.id=s.id
    where s.status='active'::public.student_status
      and p.is_active=true
      and (s.withdrawal_date is null or s.withdrawal_date > v_run_date)
    order by s.id
  loop
    begin
      v_ensure := private.ensure_student_schedule_projection(
        v_student.student_id,
        v_run_date
      );

      v_future_attempted := v_future_attempted
        + coalesce((v_ensure->>'attemptedCount')::integer,0);
      v_future_materialized := v_future_materialized
        + coalesce((v_ensure->>'materializedCount')::integer,0);
      v_future_ready := v_future_ready
        + coalesce((v_ensure->>'alreadyReadyCount')::integer,0);
      v_future_skipped_withdrawal := v_future_skipped_withdrawal
        + coalesce((v_ensure->>'skippedWithdrawalCount')::integer,0);
      v_future_missing_semester := v_future_missing_semester
        + coalesce((v_ensure->>'missingSemesterCount')::integer,0);
    exception when others then
      get stacked diagnostics
        v_error_state=returned_sqlstate,
        v_error_message=message_text;
      v_future_failed := v_future_failed + 1;

      insert into public.audit_events (
        subject_profile_id,branch_id,semester_id,event_type,
        effective_on,actor_id,details
      ) values (
        v_student.student_id,v_student.branch_id,null,
        'STUDENT_NEXT_SEMESTER_AUTO_FAILED',v_run_date,null,
        jsonb_build_object(
          'executionSource','system_cron',
          'projectionMode','calendar_visible_horizon',
          'runDateKst',v_run_date,
          'sqlState',v_error_state,
          'message',v_error_message
        )
      );

      raise warning
        'Automatic schedule projection failed for student %: [%] %',
        v_student.student_id,v_error_state,v_error_message;
    end;
  end loop;

  return jsonb_build_object(
    'runDateKst',v_run_date,
    'projectionHorizonEnd',
      (
        date_trunc('month',v_run_date::timestamp)
        + interval '4 months'
        - interval '1 day'
      )::date,
    'transitionAttemptedCount',v_attempted_transition,
    'transitionedCount',v_transitioned,
    'transitionFailedCount',v_transition_failed,
    'carryoverCreatedCount',v_carryover_created,
    'futureAttemptedCount',v_future_attempted,
    'futureMaterializedCount',v_future_materialized,
    'futureAlreadyReadyCount',v_future_ready,
    'futureSkippedWithdrawalCount',v_future_skipped_withdrawal,
    'futureMissingSemesterCount',v_future_missing_semester,
    'futureFailedCount',v_future_failed
  );
end;
$function$;

revoke all
on function private.run_due_semester_automation(date)
from public, anon, authenticated, service_role;


-- Current-semester regular registration should not wait for the nightly cron.
-- Replace the previous "next semester only" warm-up with the same visible
-- calendar projection used by the nightly worker.
do $migration$
declare
  v_oid regprocedure;
  v_def text;
  v_new text;
begin
  v_oid := to_regprocedure(
    'public.initialize_regular_student_semester(uuid,uuid,uuid,jsonb)'
  );

  if v_oid is null then
    raise exception
      'FORESTRING_MIGRATION_TARGET_NOT_FOUND: initialize_regular_student_semester';
  end if;

  select pg_get_functiondef(v_oid) into v_def;

  v_new := replace(
    v_def,
$old$  if v_today between v_semester_start and v_semester_end then
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

$old$,
$new$  if v_today between v_semester_start and v_semester_end then
    begin
      perform private.ensure_student_schedule_projection(
        p_student_id,
        v_today
      );
    exception when others then
      get stacked diagnostics
        v_next_error_state=returned_sqlstate,
        v_next_error_message=message_text;

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
        null,
        'STUDENT_NEXT_SEMESTER_AUTO_FAILED',
        v_today,
        v_actor_id,
        jsonb_build_object(
          'executionSource','staff_registration',
          'projectionMode','calendar_visible_horizon',
          'sqlState',v_next_error_state,
          'message',v_next_error_message
        )
      );

      raise warning
        'Immediate schedule projection failed for student %: [%] %',
        p_student_id,
        v_next_error_state,
        v_next_error_message;
    end;
  end if;

$new$
  );

  if v_new = v_def then
    raise exception
      'FORESTRING_MIGRATION_MARKER_NOT_FOUND: registration projection warm-up';
  end if;

  execute v_new;
end;
$migration$;

-- Re-assert public/private API boundaries after CREATE OR REPLACE.
revoke all
on function public.initialize_regular_student_semester(uuid,uuid,uuid,jsonb)
from public, anon;

grant execute
on function public.initialize_regular_student_semester(uuid,uuid,uuid,jsonb)
to authenticated, service_role;
