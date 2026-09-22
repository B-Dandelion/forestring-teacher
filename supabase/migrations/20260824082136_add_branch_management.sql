-- Branch management: detail counts, rename, activation state, and inactive-branch guards.

create or replace function private.branch_management_summary(
  p_branch_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with branch_row as (
    select
      b.id,
      b.name,
      b.is_active
    from public.branches b
    where b.id = p_branch_id
  ),
  counts as (
    select
      count(*) filter (
        where p.role = 'manager'::public.user_role
          and private.profile_has_effective_access(p.id)
      )::integer as active_manager_count,
      count(*) filter (
        where p.role = 'teacher'::public.user_role
          and private.profile_has_effective_access(p.id)
      )::integer as active_teacher_count,
      count(*) filter (
        where p.role = 'student'::public.user_role
          and private.profile_has_effective_access(p.id)
      )::integer as active_student_count
    from public.profiles p
    where p.branch_id = p_branch_id
  ),
  operational_counts as (
    select
      (
        select count(*)::integer
        from public.teacher_student_assignments a
        where a.branch_id = p_branch_id
          and (
            a.ends_on is null
            or a.ends_on >= (
              pg_catalog.now() at time zone 'Asia/Seoul'
            )::date
          )
      ) as open_assignment_count,
      (
        select count(*)::integer
        from public.lesson_series s
        where s.branch_id = p_branch_id
          and (
            s.effective_until is null
            or s.effective_until >= (
              pg_catalog.now() at time zone 'Asia/Seoul'
            )::date
          )
      ) as active_series_count,
      (
        select count(*)::integer
        from public.lessons l
        where l.branch_id = p_branch_id
          and l.status = 'scheduled'::public.lesson_status
          and l.ends_at > pg_catalog.now()
      ) as remaining_lesson_count
  )
  select jsonb_build_object(
    'branchId', b.id,
    'name', b.name,
    'isActive', b.is_active,
    'activeManagerCount', c.active_manager_count,
    'activeTeacherCount', c.active_teacher_count,
    'activeStudentCount', c.active_student_count,
    'openAssignmentCount', o.open_assignment_count,
    'activeSeriesCount', o.active_series_count,
    'remainingLessonCount', o.remaining_lesson_count,
    'canDeactivate',
      c.active_manager_count = 0
      and c.active_teacher_count = 0
      and c.active_student_count = 0
      and o.open_assignment_count = 0
      and o.active_series_count = 0
      and o.remaining_lesson_count = 0
  )
  from branch_row b
  cross join counts c
  cross join operational_counts o;
$$;

revoke all on function private.branch_management_summary(uuid)
  from public, anon, authenticated, service_role;


create or replace function public.get_branch_management_details(
  p_branch_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform private.require_effective_actor((select auth.uid()));

  if not private.is_master() then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MASTER_REQUIRED';
  end if;

  v_result := private.branch_management_summary(p_branch_id);

  if v_result is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NOT_FOUND';
  end if;

  return v_result;
end;
$$;

revoke all on function public.get_branch_management_details(uuid)
  from public, anon;
grant execute on function public.get_branch_management_details(uuid)
  to authenticated;


create or replace function public.rename_branch(
  p_branch_id uuid,
  p_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_old_name text;
  v_name text;
  v_result jsonb;
begin
  perform private.require_effective_actor(v_actor_id);

  if not private.is_master() then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MASTER_REQUIRED';
  end if;

  v_name := regexp_replace(
    btrim(coalesce(p_name, '')),
    '[[:space:]]+',
    ' ',
    'g'
  );

  if v_name = '' or length(v_name) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_BRANCH_NAME';
  end if;

  select b.name
  into v_old_name
  from public.branches b
  where b.id = p_branch_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NOT_FOUND';
  end if;

  if v_old_name is distinct from v_name then
    update public.branches b
    set name = v_name
    where b.id = p_branch_id;

    insert into public.audit_events (
      branch_id,
      event_type,
      actor_id,
      details
    ) values (
      p_branch_id,
      'BRANCH_RENAMED',
      v_actor_id,
      jsonb_build_object(
        'oldName', v_old_name,
        'newName', v_name
      )
    );
  end if;

  v_result := private.branch_management_summary(p_branch_id);

  return v_result || jsonb_build_object(
    'changed', v_old_name is distinct from v_name
  );
exception
  when unique_violation then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NAME_ALREADY_EXISTS';
end;
$$;

revoke all on function public.rename_branch(uuid, text)
  from public, anon;
grant execute on function public.rename_branch(uuid, text)
  to authenticated;


create or replace function public.set_branch_active(
  p_branch_id uuid,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_old_is_active boolean;
  v_summary jsonb;
begin
  perform private.require_effective_actor(v_actor_id);

  if not private.is_master() then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MASTER_REQUIRED';
  end if;

  if p_is_active is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_BRANCH_STATUS';
  end if;

  select b.is_active
  into v_old_is_active
  from public.branches b
  where b.id = p_branch_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NOT_FOUND';
  end if;

  if v_old_is_active = p_is_active then
    return private.branch_management_summary(p_branch_id)
      || jsonb_build_object('changed', false);
  end if;

  if not p_is_active then
    v_summary := private.branch_management_summary(p_branch_id);

    if not coalesce((v_summary ->> 'canDeactivate')::boolean, false) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_BRANCH_DEACTIVATION_BLOCKED';
    end if;
  end if;

  update public.branches b
  set is_active = p_is_active
  where b.id = p_branch_id;

  insert into public.audit_events (
    branch_id,
    event_type,
    actor_id,
    details
  ) values (
    p_branch_id,
    'BRANCH_STATUS_CHANGED',
    v_actor_id,
    jsonb_build_object(
      'oldIsActive', v_old_is_active,
      'newIsActive', p_is_active
    )
  );

  return private.branch_management_summary(p_branch_id)
    || jsonb_build_object('changed', true);
end;
$$;

revoke all on function public.set_branch_active(uuid, boolean)
  from public, anon;
grant execute on function public.set_branch_active(uuid, boolean)
  to authenticated;


create or replace function public.create_branch(
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_name text;
  v_branch_id uuid;
begin
  perform private.require_effective_actor(v_actor_id);

  if not private.is_master() then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MASTER_REQUIRED';
  end if;

  v_name := regexp_replace(
    btrim(coalesce(p_name, '')),
    '[[:space:]]+',
    ' ',
    'g'
  );

  if v_name = '' or length(v_name) > 100 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_BRANCH_NAME';
  end if;

  insert into public.branches (
    name,
    is_active
  ) values (
    v_name,
    true
  )
  returning id into v_branch_id;

  insert into public.audit_events (
    branch_id,
    event_type,
    actor_id,
    details
  ) values (
    v_branch_id,
    'BRANCH_CREATED',
    v_actor_id,
    jsonb_build_object('name', v_name)
  );

  return v_branch_id;
exception
  when unique_violation then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BRANCH_NAME_ALREADY_EXISTS';
end;
$$;

revoke all on function public.create_branch(text)
  from public, anon;
grant execute on function public.create_branch(text)
  to authenticated;


create or replace function private.assert_profile_active_branch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_active boolean;
begin
  if new.role = 'master'::public.user_role
     or not new.is_active
     or new.branch_id is null then
    return new;
  end if;

  select b.is_active
  into v_is_active
  from public.branches b
  where b.id = new.branch_id
  for key share;

  if v_is_active is distinct from true then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_BRANCH_REQUIRED';
  end if;

  return new;
end;
$$;

revoke all on function private.assert_profile_active_branch()
  from public, anon, authenticated, service_role;

drop trigger if exists zz_profiles_assert_active_branch
  on public.profiles;
create trigger zz_profiles_assert_active_branch
before insert or update
on public.profiles
for each row
execute function private.assert_profile_active_branch();


create or replace function private.assert_lesson_active_branch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_active boolean;
begin
  if new.status <> 'scheduled'::public.lesson_status
     or new.branch_id is null then
    return new;
  end if;

  select b.is_active
  into v_is_active
  from public.branches b
  where b.id = new.branch_id
  for key share;

  if v_is_active is distinct from true then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_BRANCH_REQUIRED';
  end if;

  return new;
end;
$$;

revoke all on function private.assert_lesson_active_branch()
  from public, anon, authenticated, service_role;

drop trigger if exists zz_lessons_assert_active_branch
  on public.lessons;
create trigger zz_lessons_assert_active_branch
before insert or update
on public.lessons
for each row
execute function private.assert_lesson_active_branch();


create or replace function private.assert_lesson_series_active_branch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_active boolean;
begin
  if new.branch_id is null then
    return new;
  end if;

  select b.is_active
  into v_is_active
  from public.branches b
  where b.id = new.branch_id
  for key share;

  if v_is_active is distinct from true then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_BRANCH_REQUIRED';
  end if;

  return new;
end;
$$;

revoke all on function private.assert_lesson_series_active_branch()
  from public, anon, authenticated, service_role;

drop trigger if exists zz_lesson_series_assert_active_branch
  on public.lesson_series;
create trigger zz_lesson_series_assert_active_branch
before insert or update
on public.lesson_series
for each row
execute function private.assert_lesson_series_active_branch();
