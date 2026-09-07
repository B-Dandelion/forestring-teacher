do $migration$
declare
  v_reg regprocedure := 'private.rebuild_future_regular_semester(uuid,uuid)'::regprocedure;
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(v_reg::oid) into v_def;

  v_new := replace(
    v_def,
    $old$if not found
               or v_original_date is distinct from v_candidate.lesson_date then
              raise exception using
                errcode='P0001',
                message='FORESTRING_CALENDAR_CHANGE_TOUCHES_USED_REGULAR_RIGHT',
                detail='right_id=' || v_right.id::text
                  || ', original=' || coalesce(v_original_date::text, 'null')
                  || ', target=' || v_candidate.lesson_date::text;
            end if;

            v_preserved := v_preserved + 1;$old$,
    $new$if v_start > v_today then
              if not found
                 or v_original_date is distinct from v_candidate.lesson_date then
                raise exception using
                  errcode='P0001',
                  message='FORESTRING_CALENDAR_CHANGE_TOUCHES_USED_REGULAR_RIGHT',
                  detail='right_id=' || v_right.id::text
                    || ', original=' || coalesce(v_original_date::text, 'null')
                    || ', target=' || v_candidate.lesson_date::text;
              end if;
            end if;

            v_preserved := v_preserved + 1;$new$
  );

  if v_new = v_def then
    raise exception 'FORESTRING_MIGRATION_CURRENT_HISTORY_PRESERVE_BLOCK_NOT_FOUND';
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
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_bounds record;
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

      select * into v_bounds
      from private.get_effective_semester_bounds(old.branch_id, old.semester_id);

      if found
         and v_bounds.starts_on <= v_today
         and v_today <= v_bounds.ends_on
         and old.starts_on < v_today then
        raise exception using errcode='P0001', message='FORESTRING_STARTED_INSTRUCTIONAL_BREAK_IMMUTABLE';
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

      select * into v_bounds
      from private.get_effective_semester_bounds(new.branch_id, new.semester_id);

      if found
         and v_bounds.starts_on <= v_today
         and v_today <= v_bounds.ends_on
         and new.starts_on < v_today then
        raise exception using errcode='P0001', message='FORESTRING_STARTED_INSTRUCTIONAL_BREAK_IMMUTABLE';
      end if;

      perform private.rebuild_future_regular_semester(new.semester_id, new.branch_id);
    end if;
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;