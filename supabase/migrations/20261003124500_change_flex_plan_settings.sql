-- ============================================================
-- Forestring v3
-- Active flex semester settings (base-right count + duration)
--
-- Existing booked lessons keep lessons.duration_minutes.
-- Entitlements are retargeted to the new duration so future
-- bookings, including a right restored by cancellation, use the
-- new duration.
-- ============================================================

create or replace function public.change_flex_plan_settings(
  p_student_id uuid,
  p_new_base_right_count integer,
  p_new_duration_minutes integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_actor_branch_id uuid;

  v_student_branch_id uuid;
  v_student_profile_active boolean;
  v_student_status public.student_status;
  v_student_type public.student_type;

  v_plan public.student_semester_plans%rowtype;
  v_old_base_right_count integer;
  v_old_duration_minutes integer;

  v_count_result jsonb;
  v_updated_right_count integer := 0;
  v_existing_scheduled_lesson_count integer := 0;
begin
  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role, p.branch_id
  into v_actor_role, v_actor_branch_id
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STAFF_REQUIRED';
  end if;

  if p_new_base_right_count is null
     or p_new_base_right_count <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_FLEX_RIGHT_COUNT';
  end if;

  if p_new_duration_minutes is null
     or p_new_duration_minutes not in (15, 30, 45, 60) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_FLEX_DURATION';
  end if;

  select
    p.branch_id,
    p.is_active,
    s.status,
    s.student_type
  into
    v_student_branch_id,
    v_student_profile_active,
    v_student_status,
    v_student_type
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = p_student_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_student_profile_active <> true
     or v_student_status <> 'active'::public.student_status then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_student_type <> 'flex'::public.student_type then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_STUDENT_REQUIRED';
  end if;

  select sp.*
  into v_plan
  from public.student_semester_plans sp
  cross join lateral private.get_effective_semester_bounds(
    sp.branch_id,
    sp.semester_id
  ) bounds
  where sp.student_id = p_student_id
    and sp.student_type_snapshot = 'flex'::public.student_type
    and sp.status = 'active'::public.student_semester_plan_status
    and (pg_catalog.now() at time zone 'Asia/Seoul')::date
        between bounds.starts_on and bounds.ends_on
  order by bounds.starts_on desc, sp.created_at desc
  limit 1
  for update of sp;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_FLEX_PLAN_REQUIRED';
  end if;

  if v_plan.flex_base_right_count is null
     or v_plan.flex_duration_minutes is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_PLAN_CONFIGURATION_REQUIRED';
  end if;

  if v_student_branch_id is distinct from v_plan.branch_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_PLAN_BRANCH_MISMATCH';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and v_actor_branch_id is distinct from v_plan.branch_id then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  v_old_base_right_count := v_plan.flex_base_right_count;
  v_old_duration_minutes := v_plan.flex_duration_minutes;

  if p_new_base_right_count = v_old_base_right_count
     and p_new_duration_minutes = v_old_duration_minutes then
    return jsonb_build_object(
      'changed', false,
      'studentId', v_plan.student_id,
      'planId', v_plan.id,
      'semesterId', v_plan.semester_id,
      'oldBaseRightCount', v_old_base_right_count,
      'newBaseRightCount', p_new_base_right_count,
      'oldDurationMinutes', v_old_duration_minutes,
      'newDurationMinutes', p_new_duration_minutes,
      'updatedRightCount', 0,
      'preservedScheduledLessonCount', 0,
      'newCancellationLimit',
        floor(p_new_base_right_count::numeric / 4)::integer * 2,
      'newCarryoverCap',
        floor(p_new_base_right_count::numeric / 4)::integer
    );
  end if;

  -- This existing RPC owns the complex right-count ledger rules.
  -- Calling it inside this function keeps count + duration changes
  -- atomic in a single transaction.
  v_count_result := public.change_flex_base_right_count(
    p_student_id,
    p_new_base_right_count
  );

  select count(*)::integer
  into v_existing_scheduled_lesson_count
  from public.lesson_rights r
  join public.lessons l on l.lesson_right_id = r.id
  where r.student_id = v_plan.student_id
    and r.source_semester_id = v_plan.semester_id
    and r.origin = 'flex_base'::public.lesson_right_origin
    and l.status = 'scheduled'::public.lesson_status;

  -- Keep the plan/right invariant intact for every flex-base right,
  -- including reserved and revoked rows. Existing lessons are not
  -- updated; a future cancellation restores this now-updated right.
  update public.lesson_rights r
  set duration_minutes = p_new_duration_minutes
  where r.student_id = v_plan.student_id
    and r.source_semester_id = v_plan.semester_id
    and r.origin = 'flex_base'::public.lesson_right_origin
    and r.duration_minutes is distinct from p_new_duration_minutes;

  get diagnostics v_updated_right_count = row_count;

  update public.student_semester_plans sp
  set
    flex_duration_minutes = p_new_duration_minutes,
    updated_by = v_actor_id
  where sp.id = v_plan.id;

  if exists (
    select 1
    from public.lesson_rights r
    where r.student_id = v_plan.student_id
      and r.source_semester_id = v_plan.semester_id
      and r.origin = 'flex_base'::public.lesson_right_origin
      and r.duration_minutes is distinct from p_new_duration_minutes
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_FLEX_RIGHTS_PLAN_MISMATCH';
  end if;

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    v_plan.student_id,
    v_plan.branch_id,
    v_plan.semester_id,
    'FLEX_PLAN_SETTINGS_CHANGED',
    (pg_catalog.now() at time zone 'Asia/Seoul')::date,
    v_actor_id,
    jsonb_build_object(
      'planId', v_plan.id,
      'oldBaseRightCount', v_old_base_right_count,
      'newBaseRightCount', p_new_base_right_count,
      'oldDurationMinutes', v_old_duration_minutes,
      'newDurationMinutes', p_new_duration_minutes,
      'updatedRightCount', v_updated_right_count,
      'preservedScheduledLessonCount',
        v_existing_scheduled_lesson_count,
      'countChange', v_count_result
    )
  );

  return jsonb_build_object(
    'changed', true,
    'studentId', v_plan.student_id,
    'planId', v_plan.id,
    'semesterId', v_plan.semester_id,
    'oldBaseRightCount', v_old_base_right_count,
    'newBaseRightCount', p_new_base_right_count,
    'oldDurationMinutes', v_old_duration_minutes,
    'newDurationMinutes', p_new_duration_minutes,
    'updatedRightCount', v_updated_right_count,
    'preservedScheduledLessonCount',
      v_existing_scheduled_lesson_count,
    'insertedCount',
      coalesce((v_count_result->>'insertedCount')::integer, 0),
    'removedCount',
      coalesce((v_count_result->>'removedCount')::integer, 0),
    'newCancellationLimit',
      coalesce(
        (v_count_result->>'newCancellationLimit')::integer,
        floor(p_new_base_right_count::numeric / 4)::integer * 2
      ),
    'newCarryoverCap',
      coalesce(
        (v_count_result->>'newCarryoverCap')::integer,
        floor(p_new_base_right_count::numeric / 4)::integer
      )
  );
end;
$function$;

revoke all
on function public.change_flex_plan_settings(uuid, integer, integer)
from public, anon;

grant execute
on function public.change_flex_plan_settings(uuid, integer, integer)
to authenticated;

comment on function public.change_flex_plan_settings(uuid, integer, integer) is
  'Atomically changes the active flex semester base-right count and entitlement duration. Existing lesson rows keep their booked duration; all flex-base entitlement rows adopt the new duration so future bookings or restored rights use it. Master or same-branch manager only.';
