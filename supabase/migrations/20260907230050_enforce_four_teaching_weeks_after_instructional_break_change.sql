create or replace function private.assert_four_teaching_weeks_after_instructional_break_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_summary record;
  v_check_old boolean := false;
  v_check_new boolean := false;
begin
  if tg_op in ('UPDATE','DELETE') then
    v_check_old := old.semester_id is not null
      and old.closure_kind = 'instructional_break'::public.closure_kind;
  end if;

  if tg_op in ('INSERT','UPDATE') then
    v_check_new := new.semester_id is not null
      and new.closure_kind = 'instructional_break'::public.closure_kind;
  end if;

  if v_check_old then
    select * into v_summary
    from private.get_semester_week_summary(old.branch_id, old.semester_id);

    if found and not coalesce(v_summary.has_four_teaching_weeks, false) then
      raise exception using
        errcode='P0001',
        message='FORESTRING_SEMESTER_NOT_FOUR_TEACHING_WEEKS_AFTER_CLOSURE_CHANGE',
        detail=jsonb_build_object(
          'branchId', old.branch_id,
          'semesterId', old.semester_id,
          'teachingWeeks', v_summary.teaching_weeks,
          'instructionalBreakWeeks', v_summary.instructional_break_weeks
        )::text;
    end if;
  end if;

  if v_check_new
     and (
       not v_check_old
       or old.branch_id is distinct from new.branch_id
       or old.semester_id is distinct from new.semester_id
     ) then
    select * into v_summary
    from private.get_semester_week_summary(new.branch_id, new.semester_id);

    if found and not coalesce(v_summary.has_four_teaching_weeks, false) then
      raise exception using
        errcode='P0001',
        message='FORESTRING_SEMESTER_NOT_FOUR_TEACHING_WEEKS_AFTER_CLOSURE_CHANGE',
        detail=jsonb_build_object(
          'branchId', new.branch_id,
          'semesterId', new.semester_id,
          'teachingWeeks', v_summary.teaching_weeks,
          'instructionalBreakWeeks', v_summary.instructional_break_weeks
        )::text;
    end if;
  elsif v_check_new and v_check_old then
    null;
  end if;

  if tg_op='DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

revoke all on function private.assert_four_teaching_weeks_after_instructional_break_change()
from public, anon, authenticated, service_role;

drop trigger if exists trg_validate_four_teaching_weeks_after_break_change
on public.closure_periods;

create constraint trigger trg_validate_four_teaching_weeks_after_break_change
after insert or update or delete on public.closure_periods
deferrable initially deferred
for each row
execute function private.assert_four_teaching_weeks_after_instructional_break_change();
