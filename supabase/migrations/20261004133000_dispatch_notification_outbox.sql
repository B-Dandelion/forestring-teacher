-- ============================================================
-- Forestring v3.4
-- Invoke the notification dispatcher asynchronously from Postgres.
--
-- Immediate path:
--   notification_outbox INSERT -> pg_net -> Edge Function
--
-- Recovery path:
--   pg_cron checks once per minute for due/retryable rows.
--
-- The dispatch secret is read from Supabase Vault. If the secret
-- has not been configured yet, this layer is deliberately a no-op
-- so lesson mutations can never fail because Push is unavailable.
-- ============================================================

create extension if not exists pg_net
with schema extensions;


create or replace function private.invoke_notification_dispatch(
  p_limit integer default 25
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer :=
    least(greatest(coalesce(p_limit, 25), 1), 100);

  v_dispatch_secret text;
  v_request_id bigint;
begin
  -- Do not wake the Edge Function when no row is currently due.
  if not exists (
    select 1
    from public.notification_outbox o
    where (
      (
        o.status in ('pending', 'failed')
        and o.available_at <= pg_catalog.now()
      )
      or (
        o.status = 'processing'
        and o.locked_at <
          pg_catalog.now() - interval '5 minutes'
      )
    )
      and o.attempt_count < 5
  ) then
    return null;
  end if;

  select s.decrypted_secret
  into v_dispatch_secret
  from vault.decrypted_secrets s
  where s.name = 'notification_dispatch_secret'
  order by s.updated_at desc
  limit 1;

  -- Secrets are provisioned out-of-band. Missing Push credentials
  -- must never abort the business transaction that created outbox.
  if v_dispatch_secret is null
     or length(v_dispatch_secret) < 32 then
    return null;
  end if;

  begin
    select net.http_post(
      url =>
        'https://lgfvpgrcvhfxqkdrdndy.supabase.co/functions/v1/notification-dispatch',
      headers =>
        jsonb_build_object(
          'Content-Type', 'application/json',
          'x-forestring-dispatch-secret',
          v_dispatch_secret
        ),
      body =>
        jsonb_build_object(
          'limit',
          v_limit
        ),
      timeout_milliseconds => 5000
    )
    into v_request_id;
  exception
    when others then
      -- Push dispatch must be best effort at this boundary. The
      -- outbox row stays retryable and pg_cron will try again.
      raise warning
        'FORESTRING_NOTIFICATION_DISPATCH_KICK_FAILED: %',
        sqlerrm;

      return null;
  end;

  return v_request_id;
end;
$$;

revoke all
on function private.invoke_notification_dispatch(integer)
from public, anon, authenticated;


create or replace function private.kick_notification_dispatch_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.invoke_notification_dispatch(25);
  return new;
exception
  when others then
    -- Never let Push infrastructure roll back a successful domain
    -- event or lesson mutation.
    raise warning
      'FORESTRING_NOTIFICATION_OUTBOX_TRIGGER_FAILED: %',
      sqlerrm;

    return new;
end;
$$;

revoke all
on function private.kick_notification_dispatch_after_insert()
from public, anon, authenticated;


drop trigger if exists notification_outbox_dispatch_after_insert
on public.notification_outbox;

create trigger notification_outbox_dispatch_after_insert
after insert
on public.notification_outbox
for each row
when (new.status = 'pending')
execute function private.kick_notification_dispatch_after_insert();


-- Retry / recovery heartbeat.
-- This also recovers a row whose immediate pg_net request was lost,
-- or a transient FCM failure whose available_at becomes due later.
select cron.unschedule(j.jobid)
from cron.job j
where j.jobname = 'forestring-notification-dispatch-retry';

select cron.schedule(
  'forestring-notification-dispatch-retry',
  '* * * * *',
  $cron$
    select private.invoke_notification_dispatch(25);
  $cron$
);


comment on function private.invoke_notification_dispatch(integer) is
  'Invokes the notification-dispatch Edge Function through pg_net only when retryable outbox work is due. Auth secret is loaded from Vault; missing secret results in a safe no-op.';
