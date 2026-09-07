create or replace function private.lesson_series_operational_on_or_after(
  p_series_id uuid,
  p_on_date date
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce((
    select
      case
        when ls.schedule_slot_id is null then
          coalesce(ls.effective_until, 'infinity'::date) >= p_on_date
        else
          greatest(ls.effective_from, rs.starts_on)
            <= least(
                 coalesce(ls.effective_until, 'infinity'::date),
                 coalesce(rs.ends_on, 'infinity'::date)
               )
          and least(
                coalesce(ls.effective_until, 'infinity'::date),
                coalesce(rs.ends_on, 'infinity'::date)
              ) >= p_on_date
      end
    from public.lesson_series ls
    left join public.regular_schedule_slots rs
      on rs.id = ls.schedule_slot_id
    where ls.id = p_series_id
  ), false);
$function$;

revoke all on function private.lesson_series_operational_on_or_after(uuid,date)
from public, anon, authenticated, service_role;

do $mig$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('private.staff_departure_blocker_summary(uuid,date)'::regprocedure)
  into v_def;
  if position('lesson_series_operational_on_or_after' in v_def) = 0 then
    v_new := replace(
      v_def,
      $old$and (ls.effective_until is null or ls.effective_until >= v_cutoff_date)$old$,
      $new$and private.lesson_series_operational_on_or_after(ls.id, v_cutoff_date)$new$
    );
    if v_new = v_def then
      raise exception 'FORESTRING_STAFF_SERIES_OPERATIONAL_PATCH_TARGET_NOT_FOUND';
    end if;
    execute v_new;
  end if;

  select pg_get_functiondef('private.branch_management_summary(uuid)'::regprocedure)
  into v_def;
  if position('lesson_series_operational_on_or_after' in v_def) = 0 then
    v_new := replace(
      v_def,
      $old$and (
            s.effective_until is null
            or s.effective_until >= (
              pg_catalog.now() at time zone 'Asia/Seoul'
            )::date
          )$old$,
      $new$and private.lesson_series_operational_on_or_after(
            s.id,
            (pg_catalog.now() at time zone 'Asia/Seoul')::date
          )$new$
    );
    if v_new = v_def then
      raise exception 'FORESTRING_BRANCH_SERIES_OPERATIONAL_PATCH_TARGET_NOT_FOUND';
    end if;
    execute v_new;
  end if;

  select pg_get_functiondef('public.change_manager_branch(uuid,uuid)'::regprocedure)
  into v_def;
  if position('lesson_series_operational_on_or_after' in v_def) = 0 then
    v_new := replace(
      v_def,
      $old$and (s.effective_until is null or s.effective_until >= v_today)$old$,
      $new$and private.lesson_series_operational_on_or_after(s.id, v_today)$new$
    );
    if v_new = v_def then
      raise exception 'FORESTRING_MANAGER_BRANCH_SERIES_OPERATIONAL_PATCH_TARGET_NOT_FOUND';
    end if;
    execute v_new;
  end if;

  if position('lesson_series_operational_on_or_after' in pg_get_functiondef('private.staff_departure_blocker_summary(uuid,date)'::regprocedure)) = 0
     or position('lesson_series_operational_on_or_after' in pg_get_functiondef('private.branch_management_summary(uuid)'::regprocedure)) = 0
     or position('lesson_series_operational_on_or_after' in pg_get_functiondef('public.change_manager_branch(uuid,uuid)'::regprocedure)) = 0 then
    raise exception 'FORESTRING_SERIES_OPERATIONAL_MODEL_NOT_FULLY_INSTALLED';
  end if;
end;
$mig$;
