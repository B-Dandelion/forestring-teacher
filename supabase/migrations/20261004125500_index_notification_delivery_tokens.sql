-- Forestring v3.4 notification delivery lookup support.

create index notification_deliveries_device_token_idx
  on public.notification_deliveries(device_push_token_id, attempted_at desc)
  where device_push_token_id is not null;
