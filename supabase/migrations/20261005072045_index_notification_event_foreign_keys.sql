create index if not exists notification_event_preferences_event_key_idx
  on private.notification_event_preferences(event_key);

create index if not exists notification_outbox_event_key_idx
  on public.notification_outbox(event_key);
