create or replace function private.regular_right_rebuild_target(
  p_right_id uuid,
  p_semester_id uuid,
  p_branch_id uuid
)
returns table(
  lesson_date date,
  series_id uuid,
  teacher_id uuid,
  weekday integer,
  start_time time without time zone,
  duration_minutes integer,
  starts_at timestamptz,
  ends_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  with base as (
    select
      r.id as right_id,
      r.student_id,
      r.source_semester_id,
      r.schedule_slot_id,
      l.id as lesson_id,
      l.occurrence_at,
      (l.occurrence_at at time zone 'Asia/Seoul')::date as occurrence_date,
      rs.starts_on as slot_starts_on,
      rs.ends_on as slot_ends_on,
      s.withdrawal_date
    from public.lesson_rights r
    join public.lessons l on l.lesson_right_id = r.id
    join public.regular_schedule_slots rs on rs.id = r.schedule_slot_id
    join public.students s on s.id = r.student_id
    where r.id = p_right_id
      and r.branch_id = p_branch_id
      and r.source_semester_id = p_semester_id
      and r.origin = 'regular_base'::public.lesson_right_origin
      and l.lesson_type = 'regular'::public.lesson_type
      and l.occurrence_at is not null
  ), versioned as (
    select b.*, ls.id as target_series_id, ls.teacher_id as target_teacher_id,
           ls.weekday as target_weekday, ls.start_time as target_start_time,
           ls.duration_minutes as target_duration_minutes,
           ls.effective_from, ls.effective_until
    from base b
    join lateral (
      select ls.*
      from public.lesson_series ls
      where ls.schedule_slot_id = b.schedule_slot_id
        and ls.student_id = b.student_id
        and ls.branch_id = p_branch_id
        and b.occurrence_date >= ls.effective_from
        and (ls.effective_until is null or b.occurrence_date <= ls.effective_until)
      order by ls.effective_from desc, ls.id
      limit 1
    ) ls on true
  ), positioned as (
    select v.*,
      (
        select count(*)::integer
        from public.lesson_rights r2
        join public.lessons l2 on l2.lesson_right_id = r2.id
        where r2.student_id = v.student_id
          and r2.branch_id = p_branch_id
          and r2.source_semester_id = p_semester_id
          and r2.schedule_slot_id = v.schedule_slot_id
          and r2.origin = 'regular_base'::public.lesson_right_origin
          and l2.lesson_type = 'regular'::public.lesson_type
          and l2.occurrence_at is not null
          and (l2.occurrence_at at time zone 'Asia/Seoul')::date >= v.effective_from
          and (
            v.effective_until is null
            or (l2.occurrence_at at time zone 'Asia/Seoul')::date <= v.effective_until
          )
          and (
            l2.occurrence_at < v.occurrence_at
            or (l2.occurrence_at = v.occurrence_at and l2.id <= v.lesson_id)
          )
      ) as version_ordinal
    from versioned v
  ), bounded as (
    select p.*, eb.starts_on as semester_starts_on, eb.ends_on as semester_ends_on,
           least(
             eb.ends_on,
             coalesce(p.slot_ends_on, eb.ends_on),
             coalesce(p.effective_until, eb.ends_on),
             coalesce(p.withdrawal_date - 1, eb.ends_on)
           ) as target_end
    from positioned p
    cross join lateral private.get_effective_semester_bounds(p_branch_id, p_semester_id) eb
  ), candidates as (
    select
      b.*,
      d::date as candidate_date,
      row_number() over(order by d::date)::integer as candidate_ordinal
    from bounded b
    cross join lateral pg_catalog.generate_series(
      greatest(b.semester_starts_on, b.slot_starts_on, b.effective_from)::timestamp,
      b.target_end::timestamp,
      interval '1 day'
    ) d
    where extract(isodow from d::date)::integer = b.target_weekday
      and not exists (
        select 1
        from public.closure_periods cp
        where cp.branch_id = p_branch_id
          and cp.semester_id = p_semester_id
          and cp.closure_kind = 'instructional_break'::public.closure_kind
          and d::date between cp.starts_on and cp.ends_on
      )
  )
  select
    c.candidate_date,
    c.target_series_id,
    c.target_teacher_id,
    c.target_weekday::integer,
    c.target_start_time,
    c.target_duration_minutes,
    (c.candidate_date + c.target_start_time) at time zone 'Asia/Seoul' as starts_at,
    ((c.candidate_date + c.target_start_time) at time zone 'Asia/Seoul')
      + pg_catalog.make_interval(mins => c.target_duration_minutes) as ends_at
  from candidates c
  where c.candidate_ordinal = c.version_ordinal;
$function$;

revoke all on function private.regular_right_rebuild_target(uuid,uuid,uuid)
from public, anon, authenticated, service_role;

create or replace function private.regular_right_lesson_matches_target(
  p_right_id uuid,
  p_series_id uuid,
  p_teacher_id uuid,
  p_starts_at timestamptz,
  p_duration_minutes integer
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.lessons l
    where l.lesson_right_id = p_right_id
      and l.lesson_type = 'regular'::public.lesson_type
      and l.status = 'scheduled'::public.lesson_status
      and l.rescheduled_by is null
      and l.canceled_at is null
      and l.teacher_id = p_teacher_id
      and l.starts_at = p_starts_at
      and l.duration_minutes = p_duration_minutes
  );
$function$;

revoke all on function private.regular_right_lesson_matches_target(uuid,uuid,uuid,timestamptz,integer)
from public, anon, authenticated, service_role;

do $mig$
declare
  v_def text;
  v_new text;
  v_old text := $old$v_default_following :=
            coalesce(v_default_following, false)
            and v_right.status = 'reserved'::public.lesson_right_status
            and v_candidate.starts_at > pg_catalog.now();

          if v_default_following then$old$;
  v_replacement text := $new$v_default_following :=
            coalesce(v_default_following, false)
            and v_right.status = 'reserved'::public.lesson_right_status;

          if v_default_following then
            select * into v_candidate
            from private.regular_right_rebuild_target(
              v_right.id,
              p_semester_id,
              p_branch_id
            );

            if not found then
              raise exception using
                errcode='P0001',
                message='FORESTRING_REGULAR_RECONCILIATION_COUNT_MISMATCH',
                detail='right_id=' || v_right.id::text || ', schedule-version target missing';
            end if;

            v_default_following := v_candidate.starts_at > pg_catalog.now();
          end if;

          if v_default_following then$new$;
begin
  select pg_get_functiondef('private.rebuild_future_regular_semester(uuid,uuid)'::regprocedure)
  into v_def;

  if position('regular_right_rebuild_target' in v_def) = 0 then
    if position(v_old in v_def) = 0 then
      raise exception 'FORESTRING_REBUILD_VERSION_TARGET_PATCH_NOT_FOUND';
    end if;
    v_new := replace(v_def, v_old, v_replacement);
    execute v_new;
  end if;

  select pg_get_functiondef('private.rebuild_future_regular_semester(uuid,uuid)'::regprocedure)
  into v_def;
  if position('regular_right_rebuild_target' in v_def) = 0 then
    raise exception 'FORESTRING_REBUILD_VERSION_TARGET_NOT_INSTALLED';
  end if;
end;
$mig$;
