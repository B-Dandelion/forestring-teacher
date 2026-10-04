do $$
declare
  v_signature regprocedure;
  v_definition text;
begin
  foreach v_signature in array array[
    'public.create_makeup_lesson(uuid,uuid,timestamptz,integer,boolean,text)'::regprocedure,
    'public.update_lesson_once(uuid,timestamptz,integer,boolean,text)'::regprocedure
  ]
  loop
    select pg_get_functiondef(v_signature)
    into v_definition;

    v_definition := regexp_replace(
      v_definition,
      'if p_duration_minutes not in \(\s*15,\s*30,\s*60\s*\) then',
      'if p_duration_minutes not in (15, 30, 45, 60) then',
      'i'
    );

    execute v_definition;
  end loop;
end;
$$;
