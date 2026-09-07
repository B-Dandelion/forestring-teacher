do $mig$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef('private.rebuild_future_regular_semester(uuid,uuid)'::regprocedure) into v_def;

  v_old := $old$
          and not exists (
            select 1
            from public.lesson_cancellation_events ce
            where ce.lesson_right_id = v_right.id
          )
$old$;
  v_new := $new$
          and private.regular_right_is_default_following(v_right.id, false)
$new$;
  if position(v_old in v_def)=0 then raise exception 'FORESTRING_MIGRATION_REBUILD_PREDICATE_A_NOT_FOUND'; end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := $old$
            and not exists (
              select 1
              from public.lesson_cancellation_events ce
              where ce.lesson_right_id = v_right.id
            )
$old$;
  v_new := $new$
            and private.regular_right_is_default_following(v_right.id, false)
$new$;
  if position(v_old in v_def)=0 then raise exception 'FORESTRING_MIGRATION_REBUILD_PREDICATE_B_NOT_FOUND'; end if;
  v_def := replace(v_def,v_old,v_new);

  execute v_def;
end
$mig$;