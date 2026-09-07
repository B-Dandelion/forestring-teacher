do $mig$
declare
  v_def text;
  v_new text;
  v_old text := $old$if v_target_count > 4 then
        raise exception using
          errcode='P0001',
          message='FORESTRING_REGULAR_SLOT_TOO_MANY_OCCURRENCES',
          detail='schedule_slot_id=' || v_slot.id::text || ', candidate_count=' || v_target_count::text;
      end if;$old$;
  v_replacement text := $new$-- A mid-semester weekday change can produce five theoretical dates
      -- across adjacent series versions even though the logical entitlement is
      -- still capped at four lessons for the four teaching weeks. Calendar
      -- rebuild reconciles entitlement positions, not raw series-date count.
      v_target_count := least(v_target_count, 4);$new$;
begin
  select pg_get_functiondef('private.rebuild_future_regular_semester(uuid,uuid)'::regprocedure)
  into v_def;

  if position('v_target_count := least(v_target_count, 4);' in v_def) = 0 then
    if position(v_old in v_def)=0 then
      raise exception 'FORESTRING_REBUILD_FOUR_ENTITLEMENT_CAP_TARGET_NOT_FOUND';
    end if;
    v_new := replace(v_def,v_old,v_replacement);
    execute v_new;
  end if;
end;
$mig$;
