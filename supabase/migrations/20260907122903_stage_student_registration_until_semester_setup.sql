create table if not exists private.pending_student_registrations (
  student_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  login_name_normalized text not null,
  pin_hash text,
  pin_fingerprint text not null,
  branch_id uuid not null references public.branches(id) on delete restrict,
  student_type public.student_type not null,
  registration_kind text not null check (registration_kind in ('new','reactivation')),
  effective_start date not null,
  staged_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint pending_student_registrations_name_not_blank check (length(btrim(display_name)) > 0),
  constraint pending_student_registrations_login_not_blank check (length(btrim(login_name_normalized)) > 0),
  constraint pending_student_registrations_login_trimmed check (login_name_normalized = btrim(login_name_normalized)),
  constraint pending_student_registrations_fingerprint_format check (pin_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint pending_student_registrations_new_hash check (registration_kind <> 'new' or (pin_hash is not null and length(btrim(pin_hash)) > 0)),
  unique (login_name_normalized, pin_fingerprint)
);

revoke all on table private.pending_student_registrations from public, anon, authenticated, service_role;

create or replace function public.admin_prepare_student_registration(
  p_actor_id uuid,
  p_display_name text,
  p_login_name_normalized text,
  p_pin_fingerprint text,
  p_branch_id uuid,
  p_student_type public.student_type
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor_role public.user_role;
  v_actor_branch_id uuid;
  v_student_id uuid;
  v_existing_branch_id uuid;
  v_profile_active boolean;
  v_student_status public.student_status;
  v_withdrawal_date date;
  v_pending private.pending_student_registrations%rowtype;
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
begin
  if p_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_ACTOR_NOT_FOUND';
  end if;

  perform private.require_effective_actor(p_actor_id);

  select p.role,p.branch_id
    into v_actor_role,v_actor_branch_id
  from public.profiles p
  where p.id=p_actor_id and p.is_active=true;

  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_CREATE_FORBIDDEN';
  end if;

  if p_display_name is null or length(btrim(p_display_name))=0 or length(p_display_name)>100 then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_DISPLAY_NAME';
  end if;
  if p_login_name_normalized is null or length(btrim(p_login_name_normalized))=0
     or p_login_name_normalized<>btrim(p_login_name_normalized) then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_LOGIN_NAME';
  end if;
  if p_pin_fingerprint is null or p_pin_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='P0001', message='FORESTRING_PIN_FINGERPRINT_REQUIRED';
  end if;
  if p_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_REQUIRED';
  end if;
  if p_student_type is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_TYPE_REQUIRED';
  end if;

  if v_actor_role='manager'::public.user_role and v_actor_branch_id is distinct from p_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_MISMATCH';
  end if;

  if not exists (
    select 1 from public.branches b where b.id=p_branch_id and b.is_active=true
  ) then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_NOT_FOUND';
  end if;

  select p.id,p.branch_id,p.is_active,s.status,s.withdrawal_date
    into v_student_id,v_existing_branch_id,v_profile_active,v_student_status,v_withdrawal_date
  from private.login_credentials lc
  join public.profiles p on p.id=lc.profile_id
  join public.students s on s.id=p.id
  where lc.login_name_normalized=p_login_name_normalized
    and lc.pin_fingerprint=p_pin_fingerprint
  limit 1
  for update of p,s;

  if found then
    if v_profile_active=true or v_student_status<>'withdrawn'::public.student_status then
      raise exception using errcode='P0001', message='FORESTRING_NAME_PIN_ALREADY_IN_USE';
    end if;
    if v_withdrawal_date is null then
      raise exception using errcode='P0001', message='FORESTRING_WITHDRAWN_STUDENT_DATE_REQUIRED';
    end if;
    if v_existing_branch_id is distinct from p_branch_id then
      raise exception using errcode='P0001', message='FORESTRING_REACTIVATION_BRANCH_MISMATCH';
    end if;

    if exists (
      select 1
      from public.student_semester_plans sp
      cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
      join public.lesson_rights r
        on r.student_id=sp.student_id and r.source_semester_id=sp.semester_id
      where sp.student_id=v_student_id
        and sp.status in ('planned'::public.student_semester_plan_status,'active'::public.student_semester_plan_status)
        and bounds.starts_on>=v_withdrawal_date
        and (
          r.status not in ('available'::public.lesson_right_status,'reserved'::public.lesson_right_status,'revoked'::public.lesson_right_status)
          or exists (select 1 from public.lessons l where l.lesson_right_id=r.id or l.manual_makeup_right_id=r.id)
          or exists (select 1 from public.lesson_cancellation_events e where e.lesson_right_id=r.id)
          or exists (select 1 from public.lesson_rights child where child.source_right_id=r.id)
        )
    ) then
      raise exception using errcode='P0001', message='FORESTRING_REACTIVATION_HISTORY_CONFLICT';
    end if;

    insert into private.pending_student_registrations(
      student_id,display_name,login_name_normalized,pin_hash,pin_fingerprint,
      branch_id,student_type,registration_kind,effective_start,staged_by,updated_at
    ) values (
      v_student_id,btrim(p_display_name),p_login_name_normalized,null,p_pin_fingerprint,
      p_branch_id,p_student_type,'reactivation',v_today,p_actor_id,pg_catalog.now()
    )
    on conflict (student_id) do update set
      display_name=excluded.display_name,
      login_name_normalized=excluded.login_name_normalized,
      pin_hash=null,
      pin_fingerprint=excluded.pin_fingerprint,
      branch_id=excluded.branch_id,
      student_type=excluded.student_type,
      registration_kind='reactivation',
      effective_start=excluded.effective_start,
      staged_by=excluded.staged_by,
      updated_at=pg_catalog.now();

    return jsonb_build_object(
      'studentId',v_student_id,
      'registrationKind','reactivation',
      'needsAuthCreation',false,
      'effectiveStart',v_today
    );
  end if;

  select * into v_pending
  from private.pending_student_registrations pr
  where pr.login_name_normalized=p_login_name_normalized
    and pr.pin_fingerprint=p_pin_fingerprint
  for update;

  if found then
    if v_pending.registration_kind='reactivation' then
      raise exception using errcode='P0001', message='FORESTRING_REACTIVATION_RETRY_STATE_INVALID';
    end if;

    update private.pending_student_registrations
    set display_name=btrim(p_display_name),
        branch_id=p_branch_id,
        student_type=p_student_type,
        effective_start=v_today,
        staged_by=p_actor_id,
        updated_at=pg_catalog.now()
    where student_id=v_pending.student_id;

    return jsonb_build_object(
      'studentId',v_pending.student_id,
      'registrationKind','new',
      'needsAuthCreation',false,
      'effectiveStart',v_today
    );
  end if;

  return jsonb_build_object(
    'studentId',null,
    'registrationKind','new',
    'needsAuthCreation',true,
    'effectiveStart',v_today
  );
end;
$function$;

create or replace function public.admin_stage_new_student_registration(
  p_actor_id uuid,
  p_profile_id uuid,
  p_display_name text,
  p_login_name_normalized text,
  p_pin_hash text,
  p_pin_fingerprint text,
  p_branch_id uuid,
  p_student_type public.student_type
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor_role public.user_role;
  v_actor_branch_id uuid;
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
begin
  if p_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_ACTOR_NOT_FOUND';
  end if;
  perform private.require_effective_actor(p_actor_id);

  select p.role,p.branch_id into v_actor_role,v_actor_branch_id
  from public.profiles p
  where p.id=p_actor_id and p.is_active=true;

  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_CREATE_FORBIDDEN';
  end if;

  if p_profile_id is null then
    raise exception using errcode='P0001', message='FORESTRING_PROFILE_ID_REQUIRED';
  end if;
  if p_display_name is null or length(btrim(p_display_name))=0 or length(p_display_name)>100 then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_DISPLAY_NAME';
  end if;
  if p_login_name_normalized is null or length(btrim(p_login_name_normalized))=0
     or p_login_name_normalized<>btrim(p_login_name_normalized) then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_LOGIN_NAME';
  end if;
  if p_pin_hash is null or length(btrim(p_pin_hash))=0 then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_PIN_HASH';
  end if;
  if p_pin_fingerprint is null or p_pin_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='P0001', message='FORESTRING_PIN_FINGERPRINT_REQUIRED';
  end if;
  if p_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_REQUIRED';
  end if;
  if p_student_type is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_TYPE_REQUIRED';
  end if;

  if v_actor_role='manager'::public.user_role and v_actor_branch_id is distinct from p_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_MISMATCH';
  end if;
  if not exists (select 1 from public.branches b where b.id=p_branch_id and b.is_active=true) then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_NOT_FOUND';
  end if;
  if not exists (select 1 from auth.users u where u.id=p_profile_id) then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_USER_REQUIRED';
  end if;
  if exists (select 1 from public.profiles p where p.id=p_profile_id) then
    raise exception using errcode='P0001', message='FORESTRING_PROFILE_ALREADY_EXISTS';
  end if;
  if exists (
    select 1 from private.login_credentials c
    where c.login_name_normalized=p_login_name_normalized and c.pin_fingerprint=p_pin_fingerprint
  ) then
    raise exception using errcode='P0001', message='FORESTRING_NAME_PIN_ALREADY_IN_USE';
  end if;

  insert into private.pending_student_registrations(
    student_id,display_name,login_name_normalized,pin_hash,pin_fingerprint,
    branch_id,student_type,registration_kind,effective_start,staged_by
  ) values (
    p_profile_id,btrim(p_display_name),p_login_name_normalized,p_pin_hash,p_pin_fingerprint,
    p_branch_id,p_student_type,'new',v_today,p_actor_id
  );

  return p_profile_id;
exception
  when unique_violation then
    raise exception using errcode='P0001', message='FORESTRING_NAME_PIN_ALREADY_IN_USE';
end;
$function$;

create or replace function private.finalize_pending_student_registration(
  p_student_id uuid,
  p_actor_id uuid,
  p_expected_type public.student_type
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_pending private.pending_student_registrations%rowtype;
  v_result_id uuid;
begin
  select * into v_pending
  from private.pending_student_registrations pr
  where pr.student_id=p_student_id
  for update;

  if not found then
    return jsonb_build_object('finalized',false);
  end if;

  if v_pending.student_type is distinct from p_expected_type then
    raise exception using errcode='P0001', message='FORESTRING_PENDING_STUDENT_TYPE_MISMATCH';
  end if;

  if v_pending.registration_kind='new' then
    if v_pending.pin_hash is null then
      raise exception using errcode='P0001', message='FORESTRING_PENDING_PIN_HASH_REQUIRED';
    end if;

    v_result_id := public.admin_create_student_account_data(
      p_actor_id,
      v_pending.student_id,
      v_pending.display_name,
      v_pending.login_name_normalized,
      v_pending.pin_hash,
      v_pending.pin_fingerprint,
      v_pending.branch_id,
      v_pending.student_type
    );
  elsif v_pending.registration_kind='reactivation' then
    v_result_id := public.admin_reactivate_withdrawn_student_account_data(
      p_actor_id,
      v_pending.login_name_normalized,
      v_pending.pin_fingerprint,
      v_pending.branch_id,
      v_pending.student_type
    );
  else
    raise exception using errcode='P0001', message='FORESTRING_PENDING_REGISTRATION_KIND_INVALID';
  end if;

  if v_result_id is distinct from v_pending.student_id then
    raise exception using errcode='P0001', message='FORESTRING_PENDING_FINALIZATION_ID_MISMATCH';
  end if;

  update public.student_enrollment_periods ep
  set starts_on=v_pending.effective_start,
      started_by=p_actor_id
  where ep.id=(
    select ep2.id
    from public.student_enrollment_periods ep2
    where ep2.student_id=v_pending.student_id
      and ep2.ends_on is null
    order by ep2.starts_on desc,ep2.created_at desc
    limit 1
  );

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_ENROLLMENT_PERIOD_REQUIRED';
  end if;

  delete from private.pending_student_registrations
  where student_id=v_pending.student_id;

  return jsonb_build_object(
    'finalized',true,
    'registrationKind',v_pending.registration_kind,
    'effectiveStart',v_pending.effective_start
  );
end;
$function$;

revoke all on function public.admin_prepare_student_registration(uuid,text,text,text,uuid,public.student_type) from public,anon,authenticated;
grant execute on function public.admin_prepare_student_registration(uuid,text,text,text,uuid,public.student_type) to service_role;
revoke all on function public.admin_stage_new_student_registration(uuid,uuid,text,text,text,text,uuid,public.student_type) from public,anon,authenticated;
grant execute on function public.admin_stage_new_student_registration(uuid,uuid,text,text,text,text,uuid,public.student_type) to service_role;
revoke all on function private.finalize_pending_student_registration(uuid,uuid,public.student_type) from public,anon,authenticated,service_role;

create or replace function public.initialize_flex_student_semester(
  p_student_id uuid,
  p_teacher_id uuid,
  p_semester_id uuid,
  p_base_right_count integer,
  p_duration_minutes integer
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_actor_branch_id uuid;
  v_student_branch_id uuid;
  v_student_type public.student_type;
  v_student_status public.student_status;
  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_withdrawal_date date;
  v_semester_start date;
  v_semester_end date;
  v_setup_start date;
  v_plan_id uuid;
  v_activation jsonb;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role,p.branch_id into v_actor_role,v_actor_branch_id
  from public.profiles p
  where p.id=v_actor_id and p.is_active=true;

  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STAFF_REQUIRED';
  end if;

  perform private.finalize_pending_student_registration(p_student_id,v_actor_id,'flex'::public.student_type);

  select p.branch_id,s.student_type,s.status
    into v_student_branch_id,v_student_type,v_student_status
  from public.students s
  join public.profiles p on p.id=s.id
  where s.id=p_student_id and p.is_active=true;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;
  if v_student_status<>'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_INACTIVE';
  end if;
  if v_student_type<>'flex'::public.student_type then
    raise exception using errcode='P0001', message='FORESTRING_FLEX_STUDENT_REQUIRED';
  end if;
  if v_student_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;
  if v_actor_role='manager'::public.user_role and v_actor_branch_id is distinct from v_student_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_MISMATCH';
  end if;

  if p_base_right_count is null or p_base_right_count<=0 then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_FLEX_RIGHT_COUNT';
  end if;
  if p_duration_minutes is null or p_duration_minutes<=0 or p_duration_minutes>720 or mod(p_duration_minutes,15)<>0 then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_FLEX_DURATION';
  end if;

  select p.branch_id,p.is_active,t.withdrawal_date
    into v_teacher_branch_id,v_teacher_active,v_teacher_withdrawal_date
  from public.teachers t
  join public.profiles p on p.id=t.id
  where t.id=p_teacher_id;

  if not found or v_teacher_active<>true then
    raise exception using errcode='P0001', message='FORESTRING_TEACHER_NOT_FOUND';
  end if;
  if v_teacher_branch_id is distinct from v_student_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_MISMATCH';
  end if;

  select e.starts_on,e.ends_on into v_semester_start,v_semester_end
  from private.get_effective_semester_bounds(v_student_branch_id,p_semester_id) e;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  select greatest(v_semester_start,max(ep.starts_on)) into v_setup_start
  from public.student_enrollment_periods ep
  where ep.student_id=p_student_id
    and ep.branch_id=v_student_branch_id
    and ep.starts_on<=v_semester_end
    and (ep.ends_on is null or ep.ends_on>=v_semester_start);

  if v_setup_start is null or v_setup_start>v_semester_end then
    raise exception using errcode='P0001', message='FORESTRING_ENROLLMENT_PERIOD_REQUIRED';
  end if;

  if v_teacher_withdrawal_date is not null and v_setup_start>=v_teacher_withdrawal_date then
    raise exception using errcode='P0001', message='FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL';
  end if;

  if exists (
    select 1 from public.student_semester_plans sp
    where sp.student_id=p_student_id and sp.semester_id=p_semester_id
  ) then
    raise exception using errcode='P0001', message='FORESTRING_FLEX_INITIAL_SETUP_ALREADY_EXISTS';
  end if;

  if exists (
    select 1 from public.teacher_student_assignments a
    where a.student_id=p_student_id
      and a.starts_on<=v_setup_start
      and (a.ends_on is null or a.ends_on>=v_setup_start)
      and a.teacher_id<>p_teacher_id
  ) then
    raise exception using errcode='P0001', message='FORESTRING_ASSIGNMENT_PERIOD_OVERLAP';
  end if;

  if not exists (
    select 1 from public.teacher_student_assignments a
    where a.student_id=p_student_id and a.teacher_id=p_teacher_id
      and a.starts_on<=v_setup_start
      and (a.ends_on is null or a.ends_on>=v_setup_start)
  ) then
    perform public.assign_student_teacher(p_student_id,p_teacher_id,v_setup_start);
  end if;

  insert into public.student_semester_plans(
    student_id,semester_id,branch_id,student_type_snapshot,
    flex_base_right_count,flex_duration_minutes,status,created_by,updated_by
  ) values (
    p_student_id,p_semester_id,v_student_branch_id,'flex'::public.student_type,
    p_base_right_count,p_duration_minutes,'planned'::public.student_semester_plan_status,
    v_actor_id,v_actor_id
  ) returning id into v_plan_id;

  v_activation:=public.activate_student_semester_plan(v_plan_id);

  return jsonb_build_object(
    'studentId',p_student_id,
    'semesterId',p_semester_id,
    'teacherId',p_teacher_id,
    'setupStart',v_setup_start,
    'baseRightCount',p_base_right_count,
    'durationMinutes',p_duration_minutes,
    'activation',v_activation
  );
exception
  when exclusion_violation then
    raise exception using errcode='P0001', message='FORESTRING_FLEX_INITIAL_SETUP_CONFLICT';
end;
$function$;

create or replace function public.initialize_regular_student_semester(
  p_student_id uuid,
  p_teacher_id uuid,
  p_semester_id uuid,
  p_schedules jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_actor_branch_id uuid;
  v_student_branch_id uuid;
  v_student_type public.student_type;
  v_student_status public.student_status;
  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_withdrawal_date date;
  v_semester_start date;
  v_semester_end date;
  v_setup_start date;
  v_item jsonb;
  v_weekday integer;
  v_start_time time;
  v_duration integer;
  v_slot_id uuid;
  v_plan_id uuid;
  v_schedule_count integer := 0;
  v_activation jsonb;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role,p.branch_id into v_actor_role,v_actor_branch_id
  from public.profiles p
  where p.id=v_actor_id and p.is_active=true;

  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STAFF_REQUIRED';
  end if;

  perform private.finalize_pending_student_registration(p_student_id,v_actor_id,'regular'::public.student_type);

  select p.branch_id,s.student_type,s.status
    into v_student_branch_id,v_student_type,v_student_status
  from public.students s
  join public.profiles p on p.id=s.id
  where s.id=p_student_id and p.is_active=true;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;
  if v_student_status<>'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_INACTIVE';
  end if;
  if v_student_type<>'regular'::public.student_type then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_STUDENT_REQUIRED';
  end if;
  if v_student_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;
  if v_actor_role='manager'::public.user_role and v_actor_branch_id is distinct from v_student_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_MISMATCH';
  end if;

  select p.branch_id,p.is_active,t.withdrawal_date
    into v_teacher_branch_id,v_teacher_active,v_teacher_withdrawal_date
  from public.teachers t
  join public.profiles p on p.id=t.id
  where t.id=p_teacher_id;

  if not found or v_teacher_active<>true then
    raise exception using errcode='P0001', message='FORESTRING_TEACHER_NOT_FOUND';
  end if;
  if v_teacher_branch_id is distinct from v_student_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_MISMATCH';
  end if;

  select e.starts_on,e.ends_on into v_semester_start,v_semester_end
  from private.get_effective_semester_bounds(v_student_branch_id,p_semester_id) e;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  select greatest(v_semester_start,max(ep.starts_on)) into v_setup_start
  from public.student_enrollment_periods ep
  where ep.student_id=p_student_id
    and ep.branch_id=v_student_branch_id
    and ep.starts_on<=v_semester_end
    and (ep.ends_on is null or ep.ends_on>=v_semester_start);

  if v_setup_start is null or v_setup_start>v_semester_end then
    raise exception using errcode='P0001', message='FORESTRING_ENROLLMENT_PERIOD_REQUIRED';
  end if;

  if v_teacher_withdrawal_date is not null and v_setup_start>=v_teacher_withdrawal_date then
    raise exception using errcode='P0001', message='FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL';
  end if;

  if jsonb_typeof(p_schedules)<>'array' or jsonb_array_length(p_schedules)=0 then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULES_REQUIRED';
  end if;

  if exists (
    select 1 from public.student_semester_plans sp
    where sp.student_id=p_student_id and sp.semester_id=p_semester_id
  ) or exists (
    select 1 from public.regular_schedule_slots rs
    where rs.student_id=p_student_id
      and rs.starts_on<=v_semester_end
      and (rs.ends_on is null or rs.ends_on>=v_setup_start)
  ) then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_INITIAL_SETUP_ALREADY_EXISTS';
  end if;

  if exists (
    select 1 from public.teacher_student_assignments a
    where a.student_id=p_student_id
      and a.starts_on<=v_setup_start
      and (a.ends_on is null or a.ends_on>=v_setup_start)
      and a.teacher_id<>p_teacher_id
  ) then
    raise exception using errcode='P0001', message='FORESTRING_ASSIGNMENT_PERIOD_OVERLAP';
  end if;

  if not exists (
    select 1 from public.teacher_student_assignments a
    where a.student_id=p_student_id and a.teacher_id=p_teacher_id
      and a.starts_on<=v_setup_start
      and (a.ends_on is null or a.ends_on>=v_setup_start)
  ) then
    perform public.assign_student_teacher(p_student_id,p_teacher_id,v_setup_start);
  end if;

  for v_item in select value from jsonb_array_elements(p_schedules)
  loop
    begin
      v_weekday:=(v_item->>'weekday')::integer;
      v_start_time:=(v_item->>'startTime')::time;
      v_duration:=(v_item->>'durationMinutes')::integer;
    exception when others then
      raise exception using errcode='P0001', message='FORESTRING_INVALID_REGULAR_SCHEDULE';
    end;

    if v_weekday not between 1 and 7 then
      raise exception using errcode='P0001', message='FORESTRING_INVALID_WEEKDAY';
    end if;
    if extract(second from v_start_time)<>0 or mod(extract(minute from v_start_time)::integer,15)<>0 then
      raise exception using errcode='P0001', message='FORESTRING_REGULAR_START_NOT_15_MINUTE_ALIGNED';
    end if;
    if v_duration<=0 or v_duration>720 or mod(v_duration,15)<>0 then
      raise exception using errcode='P0001', message='FORESTRING_INVALID_REGULAR_DURATION';
    end if;

    if not exists (
      select 1 from private.teacher_work_hours_for_date(p_teacher_id,v_setup_start) wh
      where wh.teacher_id=p_teacher_id and wh.weekday=v_weekday
        and wh.start_time<=v_start_time
        and wh.end_time>=(v_start_time+pg_catalog.make_interval(mins=>v_duration))::time
    ) then
      raise exception using errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS';
    end if;

    insert into public.regular_schedule_slots(student_id,branch_id,starts_on,ends_on,created_by)
    values(p_student_id,v_student_branch_id,v_setup_start,null,v_actor_id)
    returning id into v_slot_id;

    insert into public.lesson_series(
      student_id,teacher_id,weekday,start_time,duration_minutes,
      effective_from,effective_until,branch_id,schedule_slot_id
    ) values (
      p_student_id,p_teacher_id,v_weekday,v_start_time,v_duration,
      v_setup_start,null,v_student_branch_id,v_slot_id
    );

    v_schedule_count:=v_schedule_count+1;
  end loop;

  insert into public.student_semester_plans(
    student_id,semester_id,branch_id,student_type_snapshot,
    flex_base_right_count,flex_duration_minutes,status,created_by,updated_by
  ) values (
    p_student_id,p_semester_id,v_student_branch_id,'regular'::public.student_type,
    null,null,'planned'::public.student_semester_plan_status,v_actor_id,v_actor_id
  ) returning id into v_plan_id;

  v_activation:=public.activate_student_semester_plan(v_plan_id);

  return jsonb_build_object(
    'studentId',p_student_id,
    'semesterId',p_semester_id,
    'teacherId',p_teacher_id,
    'setupStart',v_setup_start,
    'scheduleCount',v_schedule_count,
    'activation',v_activation
  );
exception
  when exclusion_violation then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_INITIAL_SETUP_CONFLICT';
end;
$function$;
