begin;

do $$
declare
  v_teacher_id uuid;
  v_token_id uuid;
  v_preferences jsonb;
  v_disabled boolean;
  v_dedupe_key text :=
    'TEST:notification-foundation:' || gen_random_uuid()::text;
begin
  select p.id
  into v_teacher_id
  from public.profiles p
  where p.role = 'teacher'::public.user_role
    and p.is_active = true
    and p.is_review_account = false
  order by p.created_at, p.id
  limit 1;

  if v_teacher_id is null then
    raise exception
      'TEST_FIXTURE_REQUIRED: active non-review teacher';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    v_teacher_id::text,
    true
  );

  perform set_config(
    'request.jwt.claim.role',
    'authenticated',
    true
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_teacher_id,
      'role', 'authenticated'
    )::text,
    true
  );

  v_token_id := public.register_push_device(
    'notification-foundation-test-installation',
    'TEST_FCM_TOKEN_NOTIFICATION_FOUNDATION_1234567890',
    'ios',
    'forestring.teacher.app'
  );

  if v_token_id is null then
    raise exception
      'TEST_FAILED: register_push_device returned null';
  end if;

  if not exists (
    select 1
    from public.device_push_tokens t
    where t.id = v_token_id
      and t.profile_id = v_teacher_id
      and t.platform = 'ios'
      and t.disabled_at is null
  ) then
    raise exception
      'TEST_FAILED: device token row was not registered';
  end if;

  v_preferences :=
    public.get_notification_preferences();

  if coalesce(
    (v_preferences ->> 'pushEnabled')::boolean,
    false
  ) <> true then
    raise exception
      'TEST_FAILED: default push preference is not true';
  end if;

  v_preferences :=
    public.update_notification_preferences(
      p_push_enabled => false
    );

  if (
    v_preferences ->> 'pushEnabled'
  )::boolean <> false then
    raise exception
      'TEST_FAILED: preference update failed';
  end if;

  perform private.enqueue_teacher_notification(
    v_teacher_id,
    'lesson_canceled',
    'test',
    gen_random_uuid(),
    v_dedupe_key,
    'TEST',
    'TEST',
    '{}'::jsonb
  );

  if exists (
    select 1
    from public.notification_outbox o
    where o.dedupe_key = v_dedupe_key
  ) then
    raise exception
      'TEST_FAILED: disabled Push preference still enqueued';
  end if;

  perform public.update_notification_preferences(
    p_push_enabled => true
  );

  perform private.enqueue_teacher_notification(
    v_teacher_id,
    'lesson_canceled',
    'test',
    gen_random_uuid(),
    v_dedupe_key,
    'TEST',
    'TEST',
    '{}'::jsonb
  );

  perform private.enqueue_teacher_notification(
    v_teacher_id,
    'lesson_canceled',
    'test',
    gen_random_uuid(),
    v_dedupe_key,
    'TEST duplicate',
    'TEST duplicate',
    '{}'::jsonb
  );

  if (
    select count(*)
    from public.notification_outbox o
    where o.dedupe_key = v_dedupe_key
  ) <> 1 then
    raise exception
      'TEST_FAILED: outbox dedupe key is not idempotent';
  end if;

  v_disabled :=
    public.unregister_push_device(
      'notification-foundation-test-installation',
      'forestring.teacher.app'
    );

  if v_disabled <> true then
    raise exception
      'TEST_FAILED: unregister did not disable row';
  end if;

  if not exists (
    select 1
    from public.device_push_tokens t
    where t.id = v_token_id
      and t.disabled_at is not null
  ) then
    raise exception
      'TEST_FAILED: disabled_at was not set';
  end if;
end;
$$;

rollback;

select
  not exists (
    select 1
    from public.device_push_tokens
    where installation_id =
      'notification-foundation-test-installation'
  )
  and not exists (
    select 1
    from public.notification_outbox
    where source_kind = 'test'
  )
  as notification_foundation_rollback_clean;
