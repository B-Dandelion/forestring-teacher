create or replace function public.admin_reactivate_withdrawn_student_account_data(
  p_actor_id uuid,
  p_login_name_normalized text,
  p_pin_fingerprint text,
  p_branch_id uuid,
  p_student_type public.student_type
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_role public.user_role;
  v_actor_branch_id uuid;
  v_student_id uuid;
  v_existing_branch_id uuid;
  v_profile_active boolean;
  v_student_status public.student_status;
  v_previous_student_type public.student_type;
  v_withdrawal_date date;
  v_today date;
  v_stale_semester_ids uuid[] := '{}'::uuid[];
  v_revoked_active_right_count integer := 0;
  v_deleted_stale_right_count integer := 0;
  v_deleted_stale_plan_count integer := 0;
begin
  if p_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_ACTOR_NOT_FOUND';
  end if;

  perform private.require_effective_actor(p_actor_id);

  select p.role, p.branch_id
  into v_actor_role, v_actor_branch_id
  from public.profiles p
  where p.id = p_actor_id
    and p.is_active = true;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_ACTOR_NOT_FOUND';
  end if;

  if v_actor_role not in ('master'::public.user_role, 'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_CREATE_FORBIDDEN';
  end if;

  if p_login_name_normalized is null
     or length(btrim(p_login_name_normalized)) = 0
     or p_login_name_normalized <> btrim(p_login_name_normalized) then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_LOGIN_NAME';
  end if;

  if p_pin_fingerprint is null or length(p_pin_fingerprint) = 0 then
    raise exception using errcode='P0001', message='FORESTRING_PIN_FINGERPRINT_REQUIRED';
  end if;

  if p_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_REQUIRED';
  end if;

  if p_student_type is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_TYPE_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and v_actor_branch_id is distinct from p_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_MISMATCH';
  end if;

  select
    p.id,
    p.branch_id,
    p.is_active,
    s.status,
    s.student_type,
    s.withdrawal_date
  into
    v_student_id,
    v_existing_branch_id,
    v_profile_active,
    v_student_status,
    v_previous_student_type,
    v_withdrawal_date
  from private.login_credentials lc
  join public.profiles p on p.id = lc.profile_id
  join public.students s on s.id = p.id
  where lc.login_name_normalized = p_login_name_normalized
    and lc.pin_fingerprint = p_pin_fingerprint
  limit 1
  for update of p, s;

  if not found then
    return null;
  end if;

  if v_profile_active = true
     or v_student_status <> 'withdrawn'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_NAME_PIN_ALREADY_IN_USE';
  end if;

  if v_withdrawal_date is null then
    raise exception using errcode='P0001', message='FORESTRING_WITHDRAWN_STUDENT_DATE_REQUIRED';
  end if;

  if v_existing_branch_id is distinct from p_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_REACTIVATION_BRANCH_MISMATCH';
  end if;

  if not exists (
    select 1
    from public.branches b
    where b.id = v_existing_branch_id
      and b.is_active = true
  ) then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_NOT_ACTIVE';
  end if;

  update public.lesson_rights r
  set
    status = 'revoked'::public.lesson_right_status,
    revoked_at = coalesce(r.revoked_at, pg_catalog.now())
  where r.student_id = v_student_id
    and r.status in (
      'available'::public.lesson_right_status,
      'reserved'::public.lesson_right_status
    );

  get diagnostics v_revoked_active_right_count = row_count;

  select coalesce(array_agg(x.semester_id), '{}'::uuid[])
  into v_stale_semester_ids
  from (
    select distinct sp.semester_id
    from public.student_semester_plans sp
    cross join lateral private.get_effective_semester_bounds(
      sp.branch_id,
      sp.semester_id
    ) bounds
    where sp.student_id = v_student_id
      and sp.status in (
        'planned'::public.student_semester_plan_status,
        'active'::public.student_semester_plan_status
      )
      and bounds.starts_on >= v_withdrawal_date
  ) x;

  if cardinality(v_stale_semester_ids) > 0 then
    if exists (
      select 1
      from public.lesson_rights r
      where r.student_id = v_student_id
        and r.source_semester_id = any(v_stale_semester_ids)
        and r.status <> 'revoked'::public.lesson_right_status
    ) then
      raise exception using errcode='P0001', message='FORESTRING_REACTIVATION_HISTORY_CONFLICT';
    end if;

    if exists (
      select 1
      from public.lesson_rights r
      where r.student_id = v_student_id
        and r.source_semester_id = any(v_stale_semester_ids)
        and (
          exists (
            select 1 from public.lessons l
            where l.lesson_right_id = r.id
               or l.manual_makeup_right_id = r.id
          )
          or exists (
            select 1 from public.lesson_cancellation_events e
            where e.lesson_right_id = r.id
          )
          or exists (
            select 1 from public.lesson_rights child
            where child.source_right_id = r.id
          )
        )
    ) then
      raise exception using errcode='P0001', message='FORESTRING_REACTIVATION_HISTORY_CONFLICT';
    end if;

    delete from public.lesson_rights r
    where r.student_id = v_student_id
      and r.source_semester_id = any(v_stale_semester_ids)
      and r.status = 'revoked'::public.lesson_right_status;

    get diagnostics v_deleted_stale_right_count = row_count;

    delete from public.student_semester_plans sp
    where sp.student_id = v_student_id
      and sp.semester_id = any(v_stale_semester_ids)
      and sp.status in (
        'planned'::public.student_semester_plan_status,
        'active'::public.student_semester_plan_status
      );

    get diagnostics v_deleted_stale_plan_count = row_count;
  end if;

  update public.students
  set
    status = 'active'::public.student_status,
    withdrawal_date = null,
    student_type = p_student_type
  where id = v_student_id;

  update public.profiles
  set is_active = true
  where id = v_student_id;

  v_today := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  ) values (
    v_student_id,
    v_existing_branch_id,
    null,
    'STUDENT_REACTIVATED',
    v_today,
    p_actor_id,
    jsonb_build_object(
      'previousWithdrawalDate', v_withdrawal_date,
      'previousStudentType', v_previous_student_type,
      'studentType', p_student_type,
      'residualActiveRightsRevoked', v_revoked_active_right_count,
      'staleFutureRightsDeleted', v_deleted_stale_right_count,
      'staleFuturePlansDeleted', v_deleted_stale_plan_count,
      'teacherAssignmentRestored', false,
      'regularScheduleRestored', false,
      'lessonRightsRestored', false,
      'registrationFlow', 'staff_create_student'
    )
  );

  return v_student_id;
end;
$function$;

revoke all on function public.admin_reactivate_withdrawn_student_account_data(
  uuid, text, text, uuid, public.student_type
) from public;
revoke all on function public.admin_reactivate_withdrawn_student_account_data(
  uuid, text, text, uuid, public.student_type
) from anon;
revoke all on function public.admin_reactivate_withdrawn_student_account_data(
  uuid, text, text, uuid, public.student_type
) from authenticated;
grant execute on function public.admin_reactivate_withdrawn_student_account_data(
  uuid, text, text, uuid, public.student_type
) to service_role;
