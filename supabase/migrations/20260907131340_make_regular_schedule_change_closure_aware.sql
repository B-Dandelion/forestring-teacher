create or replace function private.regular_right_is_default_following(
  p_right_id uuid,
  p_allow_auto_closure_canceled boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select
      r.origin = 'regular_base'::public.lesson_right_origin
      and (select count(*) from public.lessons l2 where l2.lesson_right_id = r.id) = 1
      and exists (
        select 1
        from public.lessons l
        where l.lesson_right_id = r.id
          and l.lesson_type = 'regular'::public.lesson_type
          and l.rescheduled_by is null
          and (
            (
              r.status = 'reserved'::public.lesson_right_status
              and l.status = 'scheduled'::public.lesson_status
              and l.canceled_at is null
            )
            or (
              p_allow_auto_closure_canceled
              and r.status = 'available'::public.lesson_right_status
              and l.status = 'canceled'::public.lesson_status
              and l.cancellation_reason like 'AUTO_CLOSURE:%'
            )
          )
      )
      and not exists (
        select 1
        from public.lesson_cancellation_events ce
        where ce.lesson_right_id = r.id
          and (ce.reason is null or ce.reason not like 'AUTO_CLOSURE:%')
      )
      and not exists (select 1 from public.lesson_rights child where child.source_right_id = r.id)
      and not exists (select 1 from public.lessons ml where ml.manual_makeup_right_id = r.id)
      and not exists (
        select 1
        from public.lesson_rebooking_credits c
        join public.lessons sl on sl.id = c.source_lesson_id
        where sl.lesson_right_id = r.id
      )
    from public.lesson_rights r
    where r.id = p_right_id
  ), false);
$$;

revoke all on function private.regular_right_is_default_following(uuid, boolean) from public;
revoke all on function private.regular_right_is_default_following(uuid, boolean) from anon;
revoke all on function private.regular_right_is_default_following(uuid, boolean) from authenticated;

do $mig$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef('public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)'::regprocedure) into v_def;

  v_old := $old$
      and not exists (
        select 1

        from public.lesson_cancellation_events ce

        where ce.lesson_right_id =
              r.id
      )
$old$;
  v_new := $new$
      and private.regular_right_is_default_following(r.id, false)
$new$;
  if position(v_old in v_def)=0 then raise exception 'FORESTRING_MIGRATION_CHANGE_REGULAR_DEFAULT_PREDICATE_NOT_FOUND'; end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := $old$
    -- --------------------------------------------------------
    -- Ordinary branch closure is a hard conflict.
    -- --------------------------------------------------------

    if exists (
      select 1

      from public.closure_periods cp

      where cp.branch_id =
            v_slot.branch_id

        and cp.closure_kind =
            'ordinary'::public.closure_kind

        and v_new_date between
            cp.starts_on
            and cp.ends_on
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_RECONCILIATION_ON_CLOSURE',
        detail =
          'date=' ||
          v_new_date::text;

    end if;
$old$;
  v_new := $new$
    -- Ordinary closures do not invalidate the recurring rule. The deferred
    -- lesson trigger auto-cancels an untouched default occurrence if needed.
$new$;
  if position(v_old in v_def)=0 then raise exception 'FORESTRING_MIGRATION_CHANGE_REGULAR_CLOSURE_BLOCK_NOT_FOUND'; end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end
$mig$;

do $mig$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef('private.rematerialize_academy_canceled_regular_rights(uuid)'::regprocedure) into v_def;

  v_old := 'select e.id, e.origin, e.counts_toward_limit';
  v_new := 'select e.id, e.origin, e.counts_toward_limit, e.reason';
  if position(v_old in v_def)=0 then raise exception 'FORESTRING_MIGRATION_REMATERIALIZE_LATEST_EVENT_NOT_FOUND'; end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := $old$
      and ce.origin = 'academy'::public.lesson_cancellation_origin
      and ce.counts_toward_limit = false
      and l.lesson_type = 'regular'::public.lesson_type
      and l.occurrence_at is not null
      and (
        (r.status='available'::public.lesson_right_status and l.status='canceled'::public.lesson_status)
        or
        (r.status='reserved'::public.lesson_right_status and l.status='scheduled'::public.lesson_status and l.rescheduled_by is null)
      )
$old$;
  v_new := $new$
      and ce.origin = 'academy'::public.lesson_cancellation_origin
      and ce.counts_toward_limit = false
      and ce.reason like 'AUTO_CLOSURE:%'
      and l.lesson_type = 'regular'::public.lesson_type
      and l.occurrence_at is not null
      and r.status='available'::public.lesson_right_status
      and l.status='canceled'::public.lesson_status
      and l.cancellation_reason like 'AUTO_CLOSURE:%'
      and private.regular_right_is_default_following(r.id, true)
$new$;
  if position(v_old in v_def)=0 then raise exception 'FORESTRING_MIGRATION_REMATERIALIZE_SCOPE_NOT_FOUND'; end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := 'select e.origin, e.counts_toward_limit';
  v_new := 'select e.origin, e.counts_toward_limit, e.reason';
  if position(v_old in v_def)=0 then raise exception 'FORESTRING_MIGRATION_REMATERIALIZE_RANK_EVENT_NOT_FOUND'; end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := $old$
        and latest.origin='academy'::public.lesson_cancellation_origin
        and latest.counts_toward_limit=false
$old$;
  v_new := $new$
        and latest.origin='academy'::public.lesson_cancellation_origin
        and latest.counts_toward_limit=false
        and latest.reason like 'AUTO_CLOSURE:%'
$new$;
  if position(v_old in v_def)=0 then raise exception 'FORESTRING_MIGRATION_REMATERIALIZE_RANK_SCOPE_NOT_FOUND'; end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := $old$
    if exists (select 1 from public.closure_periods cp where cp.branch_id=v_slot.branch_id and cp.closure_kind='ordinary'::public.closure_kind and v_new_date between cp.starts_on and cp.ends_on) then
      raise exception using errcode='P0001', message='FORESTRING_ACADEMY_CANCELED_RIGHT_REMATERIALIZATION_ON_CLOSURE';
    end if;
$old$;
  v_new := $new$
    -- An ordinary closure is valid here. The deferred lesson trigger will
    -- auto-cancel the rematerialized default occurrence again if necessary.
$new$;
  if position(v_old in v_def)=0 then raise exception 'FORESTRING_MIGRATION_REMATERIALIZE_CLOSURE_BLOCK_NOT_FOUND'; end if;
  v_def := replace(v_def,v_old,v_new);

  execute v_def;
end
$mig$;