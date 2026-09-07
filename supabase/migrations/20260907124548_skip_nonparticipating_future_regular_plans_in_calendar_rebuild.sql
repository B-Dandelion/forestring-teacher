do $migration$
declare
  v_def text;
  v_old text := $old$if v_effective_end < v_start then
      raise exception using
        errcode='P0001',
        message='FORESTRING_CALENDAR_CHANGE_REMOVES_ACTIVE_PLAN_WINDOW',
        detail='plan_id=' || v_plan.id::text;
    end if;$old$;
  v_new text := $new$if v_effective_end < v_start then
      -- The student does not participate in this semester (for example,
      -- withdrawal is effective before the semester begins). Any stale future
      -- plan is lifecycle history and must not block an unrelated calendar edit.
      continue;
    end if;$new$;
begin
  select pg_get_functiondef(
    'private.rebuild_future_regular_semester(uuid,uuid)'::regprocedure
  ) into v_def;

  if position(v_old in v_def) = 0 then
    raise exception 'FORESTRING_MIGRATION_REBUILD_FRAGMENT_NOT_FOUND';
  end if;

  execute replace(v_def, v_old, v_new);
end;
$migration$;
