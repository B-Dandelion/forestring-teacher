-- ============================================================
-- Forestring v3.4
-- Atomic notification outbox claiming for backend dispatchers.
-- ============================================================

create or replace function public.claim_notification_outbox(
  p_limit integer default 25
)
returns table (
  id uuid,
  recipient_profile_id uuid,
  event_key text,
  title text,
  body text,
  data jsonb,
  attempt_count integer,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SERVICE_ROLE_REQUIRED';
  end if;

  return query
  with candidates as (
    select o.id
    from public.notification_outbox o
    where (
      (
        o.status in ('pending', 'failed')
        and o.available_at <= pg_catalog.now()
      )
      or (
        o.status = 'processing'
        and o.locked_at < pg_catalog.now() - interval '5 minutes'
      )
    )
      and o.attempt_count < 5
    order by
      o.available_at,
      o.created_at,
      o.id
    for update skip locked
    limit v_limit
  ),
  claimed as (
    update public.notification_outbox o
    set
      status = 'processing',
      attempt_count = o.attempt_count + 1,
      locked_at = pg_catalog.now(),
      last_error = null
    from candidates c
    where o.id = c.id
    returning
      o.id,
      o.recipient_profile_id,
      o.event_key,
      o.title,
      o.body,
      o.data,
      o.attempt_count,
      o.created_at
  )
  select
    c.id,
    c.recipient_profile_id,
    c.event_key,
    c.title,
    c.body,
    c.data,
    c.attempt_count,
    c.created_at
  from claimed c
  order by c.created_at, c.id;
end;
$$;

revoke all
on function public.claim_notification_outbox(integer)
from public, anon, authenticated;

grant execute
on function public.claim_notification_outbox(integer)
to service_role;

comment on function public.claim_notification_outbox(integer) is
  'Atomically claims retryable Push outbox rows using SKIP LOCKED. Backend-only; at most five attempts per notification.';
