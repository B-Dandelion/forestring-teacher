create or replace function private.instructional_break_semester_is_locked(
  p_semester_id uuid,
  p_branch_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce((
    select e.ends_on < (pg_catalog.now() at time zone 'Asia/Seoul')::date
    from private.get_effective_semester_bounds(p_branch_id, p_semester_id) e
  ), true);
$function$;

revoke all on function private.instructional_break_semester_is_locked(uuid,uuid) from public;
revoke all on function private.instructional_break_semester_is_locked(uuid,uuid) from anon;
revoke all on function private.instructional_break_semester_is_locked(uuid,uuid) from authenticated;
revoke all on function private.instructional_break_semester_is_locked(uuid,uuid) from service_role;

do $migration$
declare
  v_reg regprocedure;
  v_def text;
  v_new text;
begin
  foreach v_reg in array array[
    'public.upsert_closure_period(uuid,uuid,uuid,date,date,public.closure_kind,text)'::regprocedure,
    'public.delete_closure_period(uuid)'::regprocedure,
    'public.reset_branch_closure_override(uuid)'::regprocedure,
    'public.upsert_default_closure_period(uuid,uuid,date,date,public.closure_kind,text)'::regprocedure,
    'public.delete_default_closure_period(uuid)'::regprocedure
  ]
  loop
    select pg_get_functiondef(v_reg::oid) into v_def;
    v_new := replace(v_def,'private.calendar_semester_is_materialized','private.instructional_break_semester_is_locked');
    if v_new = v_def then
      raise exception 'FORESTRING_MIGRATION_EXPECTED_CLOSURE_LOCK_REFERENCE_MISSING: %', v_reg::text;
    end if;
    execute v_new;
  end loop;
end;
$migration$;

do $migration$
declare
  v_reg regprocedure := 'private.rebuild_future_regular_semester(uuid,uuid)'::regprocedure;
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(v_reg::oid) into v_def;
  v_new := v_def;

  v_new := replace(
    v_new,
    $old$if v_start <= v_today then
    raise exception using
      errcode='P0001',
      message='FORESTRING_CALENDAR_REBUILD_REQUIRES_FUTURE_SEMESTER';
  end if;$old$,
    $new$if v_end < v_today then
    raise exception using
      errcode='P0001',
      message='FORESTRING_CALENDAR_REBUILD_REQUIRES_CURRENT_OR_FUTURE_SEMESTER';
  end if;$new$
  );
  if v_new = v_def then
    raise exception 'FORESTRING_MIGRATION_REBUILD_DATE_GATE_NOT_FOUND';
  end if;

  v_def := v_new;
  v_new := replace(
    v_new,
    $old$and bool_and(l.canceled_at is null)
          and not exists ($old$,
    $new$and bool_and(l.canceled_at is null)
          and bool_and(l.starts_at > pg_catalog.now())
          and not exists ($new$
  );
  if v_new = v_def then
    raise exception 'FORESTRING_MIGRATION_REBUILD_DEFAULT_FUTURE_GUARD_NOT_FOUND';
  end if;

  v_def := v_new;
  v_new := replace(
    v_new,
    $old$v_default_following :=
            coalesce(v_default_following, false)
            and v_right.status = 'reserved'::public.lesson_right_status;$old$,
    $new$v_default_following :=
            coalesce(v_default_following, false)
            and v_right.status = 'reserved'::public.lesson_right_status
            and v_candidate.starts_at > pg_catalog.now();$new$
  );
  if v_new = v_def then
    raise exception 'FORESTRING_MIGRATION_REBUILD_CANDIDATE_TIME_GUARD_NOT_FOUND';
  end if;

  v_def := v_new;
  v_new := replace(
    v_new,
    $old$else
          if not exists (
            select 1
            from private.teacher_work_hours_for_date($old$,
    $new$else
          if v_candidate.starts_at <= pg_catalog.now() then
            raise exception using
              errcode='P0001',
              message='FORESTRING_CALENDAR_CHANGE_REQUIRES_PAST_MATERIALIZATION',
              detail='schedule_slot_id=' || v_slot.id::text || ', starts_at=' || v_candidate.starts_at::text;
          end if;

          if not exists (
            select 1
            from private.teacher_work_hours_for_date($new$
  );
  if v_new = v_def then
    raise exception 'FORESTRING_MIGRATION_REBUILD_PAST_CREATE_GUARD_NOT_FOUND';
  end if;

  execute v_new;
end;
$migration$;

create or replace function private.reconcile_instructional_break_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_old_relevant boolean := false;
  v_new_relevant boolean := false;
begin
  if tg_op in ('UPDATE','DELETE') then
    v_old_relevant := old.semester_id is not null
      and old.closure_kind = 'instructional_break'::public.closure_kind;
  end if;

  if tg_op in ('UPDATE','INSERT') then
    v_new_relevant := new.semester_id is not null
      and new.closure_kind = 'instructional_break'::public.closure_kind;
  end if;

  if v_old_relevant then
    if not v_new_relevant
       or old.branch_id is distinct from new.branch_id
       or old.semester_id is distinct from new.semester_id
       or old.starts_on is distinct from new.starts_on
       or old.ends_on is distinct from new.ends_on then
      if private.instructional_break_semester_is_locked(old.semester_id, old.branch_id) then
        raise exception using errcode='P0001', message='FORESTRING_HISTORICAL_INSTRUCTIONAL_BREAK_IMMUTABLE';
      end if;
      perform private.rebuild_future_regular_semester(old.semester_id, old.branch_id);
    end if;
  end if;

  if v_new_relevant then
    if not v_old_relevant
       or old.branch_id is distinct from new.branch_id
       or old.semester_id is distinct from new.semester_id
       or old.starts_on is distinct from new.starts_on
       or old.ends_on is distinct from new.ends_on then
      if private.instructional_break_semester_is_locked(new.semester_id, new.branch_id) then
        raise exception using errcode='P0001', message='FORESTRING_HISTORICAL_INSTRUCTIONAL_BREAK_IMMUTABLE';
      end if;
      perform private.rebuild_future_regular_semester(new.semester_id, new.branch_id);
    end if;
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;