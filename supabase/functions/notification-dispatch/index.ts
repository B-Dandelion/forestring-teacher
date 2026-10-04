import { withSupabase } from 'npm:@supabase/server@^1'
import { GoogleAuth } from 'npm:google-auth-library@9.15.1'

type OutboxRow = {
  id: string
  recipient_profile_id: string
  event_key: string
  title: string
  body: string
  data: Record<string, unknown>
  attempt_count: number
  created_at: string
}

type DeviceToken = {
  id: string
  fcm_token: string
  platform: 'android' | 'ios'
}

type FcmResult = {
  ok: boolean
  providerMessageId: string | null
  errorCode: string | null
  errorDetail: string | null
  unregistered: boolean
  retryable: boolean
}

type ServiceAccount = {
  project_id: string
  client_email: string
  private_key: string
}

const FCM_SCOPE =
  'https://www.googleapis.com/auth/firebase.messaging'

const EXPECTED_FIREBASE_PROJECT = 'forestring1-1'

function requireServiceAccount(): ServiceAccount {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')

  if (!raw) {
    throw new Error(
      'FCM_SERVICE_ACCOUNT_JSON is not configured.',
    )
  }

  const parsed = JSON.parse(raw) as Partial<ServiceAccount>

  if (
    parsed.project_id !== EXPECTED_FIREBASE_PROJECT
    || typeof parsed.client_email !== 'string'
    || typeof parsed.private_key !== 'string'
  ) {
    throw new Error(
      'FCM service account does not match forestring1-1.',
    )
  }

  return parsed as ServiceAccount
}

async function getAccessToken(
  credentials: ServiceAccount,
): Promise<string> {
  const auth = new GoogleAuth({
    credentials,
    scopes: [FCM_SCOPE],
  })

  const client = await auth.getClient()
  const token = await client.getAccessToken()

  const value =
    typeof token === 'string'
      ? token
      : token?.token

  if (!value) {
    throw new Error('Unable to obtain FCM OAuth token.')
  }

  return value
}

function stringifyData(
  data: Record<string, unknown>,
  outbox: OutboxRow,
): Record<string, string> {
  const values: Record<string, unknown> = {
    ...data,
    eventKey: outbox.event_key,
    outboxId: outbox.id,
  }

  const result: Record<string, string> = {}

  for (const [key, value] of Object.entries(values)) {
    if (value === null || value === undefined) {
      continue
    }

    result[key] =
      typeof value === 'string'
        ? value
        : JSON.stringify(value)
  }

  return result
}

function parseFcmError(
  status: number,
  payload: any,
): {
  code: string | null
  detail: string
  unregistered: boolean
  retryable: boolean
} {
  const details =
    Array.isArray(payload?.error?.details)
      ? payload.error.details
      : []

  const fcmDetail = details.find(
    (item: any) =>
      item?.['@type'] ===
        'type.googleapis.com/google.firebase.fcm.v1.FcmError',
  )

  const code =
    typeof fcmDetail?.errorCode === 'string'
      ? fcmDetail.errorCode
      : typeof payload?.error?.status === 'string'
        ? payload.error.status
        : null

  const detail =
    typeof payload?.error?.message === 'string'
      ? payload.error.message
      : `FCM HTTP ${status}`

  return {
    code,
    detail,
    unregistered: code === 'UNREGISTERED',
    retryable:
      status === 429
      || status >= 500
      || code === 'INTERNAL'
      || code === 'UNAVAILABLE',
  }
}

async function sendFcm(
  accessToken: string,
  projectId: string,
  token: DeviceToken,
  outbox: OutboxRow,
): Promise<FcmResult> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: token.fcm_token,
          notification: {
            title: outbox.title,
            body: outbox.body,
          },
          data: stringifyData(
            outbox.data ?? {},
            outbox,
          ),
          android: {
            priority: 'HIGH',
            notification: {
              sound: 'default',
            },
          },
          apns: {
            headers: {
              'apns-priority': '10',
            },
            payload: {
              aps: {
                sound: 'default',
              },
            },
          },
        },
      }),
    },
  )

  const payload = await response.json().catch(
    () => ({}),
  )

  if (response.ok) {
    return {
      ok: true,
      providerMessageId:
        typeof payload?.name === 'string'
          ? payload.name
          : null,
      errorCode: null,
      errorDetail: null,
      unregistered: false,
      retryable: false,
    }
  }

  const parsed = parseFcmError(
    response.status,
    payload,
  )

  return {
    ok: false,
    providerMessageId: null,
    errorCode: parsed.code,
    errorDetail: parsed.detail,
    unregistered: parsed.unregistered,
    retryable: parsed.retryable,
  }
}

function retryDelaySeconds(
  attemptCount: number,
): number {
  return Math.min(
    15 * Math.pow(2, Math.max(attemptCount - 1, 0)),
    15 * 60,
  )
}

async function updateOutbox(
  supabaseAdmin: any,
  outboxId: string,
  values: Record<string, unknown>,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from('notification_outbox')
    .update(values)
    .eq('id', outboxId)

  if (error) {
    throw error
  }
}

async function recordDelivery(
  supabaseAdmin: any,
  values: Record<string, unknown>,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from('notification_deliveries')
    .insert(values)

  if (error) {
    throw error
  }
}

async function dispatchOne(
  supabaseAdmin: any,
  accessToken: string,
  projectId: string,
  outbox: OutboxRow,
): Promise<void> {
  const {
    data: tokenRows,
    error: tokenError,
  } = await supabaseAdmin
    .from('device_push_tokens')
    .select('id, fcm_token, platform')
    .eq(
      'profile_id',
      outbox.recipient_profile_id,
    )
    .eq('app_id', 'forestring.teacher.app')
    .is('disabled_at', null)

  if (tokenError) {
    throw tokenError
  }

  const tokens = (tokenRows ?? []) as DeviceToken[]

  if (tokens.length === 0) {
    await recordDelivery(
      supabaseAdmin,
      {
        outbox_id: outbox.id,
        device_push_token_id: null,
        attempt_no: outbox.attempt_count,
        status: 'skipped',
        error_code: 'NO_ACTIVE_DEVICE',
        error_detail:
          'No active Push installation for recipient.',
      },
    )

    await updateOutbox(
      supabaseAdmin,
      outbox.id,
      {
        status: 'skipped',
        locked_at: null,
        last_error: 'NO_ACTIVE_DEVICE',
      },
    )

    return
  }

  let acceptedCount = 0
  let retryableFailureCount = 0
  let permanentFailureCount = 0

  const failures: string[] = []

  for (const token of tokens) {
    const result = await sendFcm(
      accessToken,
      projectId,
      token,
      outbox,
    )

    if (result.ok) {
      acceptedCount += 1

      await recordDelivery(
        supabaseAdmin,
        {
          outbox_id: outbox.id,
          device_push_token_id: token.id,
          attempt_no: outbox.attempt_count,
          status: 'accepted',
          provider_message_id:
            result.providerMessageId,
        },
      )

      continue
    }

    if (result.retryable) {
      retryableFailureCount += 1
    } else {
      permanentFailureCount += 1
    }

    failures.push(
      [
        result.errorCode ?? 'FCM_ERROR',
        result.errorDetail ?? 'Unknown FCM error',
      ].join(': '),
    )

    await recordDelivery(
      supabaseAdmin,
      {
        outbox_id: outbox.id,
        device_push_token_id: token.id,
        attempt_no: outbox.attempt_count,
        status: 'failed',
        error_code:
          result.errorCode ?? 'FCM_ERROR',
        error_detail: result.errorDetail,
      },
    )

    if (result.unregistered) {
      const { error } = await supabaseAdmin
        .from('device_push_tokens')
        .update({
          disabled_at: new Date().toISOString(),
        })
        .eq('id', token.id)

      if (error) {
        throw error
      }
    }
  }

  if (acceptedCount > 0) {
    await updateOutbox(
      supabaseAdmin,
      outbox.id,
      {
        status: 'sent',
        sent_at: new Date().toISOString(),
        locked_at: null,
        last_error:
          failures.length > 0
            ? failures.join(' | ').slice(0, 2000)
            : null,
      },
    )

    return
  }

  if (retryableFailureCount > 0) {
    const delaySeconds =
      retryDelaySeconds(outbox.attempt_count)

    await updateOutbox(
      supabaseAdmin,
      outbox.id,
      {
        status: 'failed',
        locked_at: null,
        available_at:
          new Date(
            Date.now() + delaySeconds * 1000,
          ).toISOString(),
        last_error:
          failures.join(' | ').slice(0, 2000),
      },
    )

    return
  }

  await updateOutbox(
    supabaseAdmin,
    outbox.id,
    {
      status: 'skipped',
      locked_at: null,
      last_error:
        failures.length > 0
          ? failures.join(' | ').slice(0, 2000)
          : `ALL_PERMANENT_FAILURES:${permanentFailureCount}`,
    },
  )
}

function requireDispatcherSecret(req: Request): void {
  const expected =
    Deno.env.get('NOTIFICATION_DISPATCH_SECRET')

  const provided =
    req.headers.get(
      'x-forestring-dispatch-secret',
    )

  if (
    !expected
    || !provided
    || provided !== expected
  ) {
    throw new Error('FORESTRING_DISPATCH_FORBIDDEN')
  }
}

export default {
  fetch: withSupabase(
    { auth: 'none' },
    async (req, ctx) => {
  if (req.method !== 'POST') {
    return Response.json(
      { message: 'Method not allowed.' },
      { status: 405 },
    )
  }

  try {
    requireDispatcherSecret(req)

    const supabaseAdmin = ctx.supabaseAdmin

    const credentials = requireServiceAccount()
    const accessToken =
      await getAccessToken(credentials)

    let limit = 25

    try {
      const body = await req.json()

      if (
        typeof body?.limit === 'number'
        && Number.isFinite(body.limit)
      ) {
        limit = Math.min(
          Math.max(
            Math.trunc(body.limit),
            1,
          ),
          100,
        )
      }
    } catch (_) {
      // Empty request body is valid.
    }

    const {
      data,
      error,
    } = await supabaseAdmin.rpc(
      'claim_notification_outbox',
      {
        p_limit: limit,
      },
    )

    if (error) {
      throw error
    }

    const rows =
      Array.isArray(data)
        ? data as OutboxRow[]
        : []

    let sentOrSkipped = 0
    let failed = 0

    for (const outbox of rows) {
      try {
        await dispatchOne(
          supabaseAdmin,
          accessToken,
          credentials.project_id,
          outbox,
        )

        sentOrSkipped += 1
      } catch (error) {
        failed += 1

        console.error(
          'notification dispatch row failed:',
          outbox.id,
          error,
        )

        const delaySeconds =
          retryDelaySeconds(
            outbox.attempt_count,
          )

        try {
          await updateOutbox(
            supabaseAdmin,
            outbox.id,
            {
              status: 'failed',
              locked_at: null,
              available_at:
                new Date(
                  Date.now()
                    + delaySeconds * 1000,
                ).toISOString(),
              last_error:
                error instanceof Error
                  ? error.message.slice(0, 2000)
                  : 'UNKNOWN_DISPATCH_ERROR',
            },
          )
        } catch (updateError) {
          console.error(
            'notification outbox recovery failed:',
            outbox.id,
            updateError,
          )
        }
      }
    }

    return Response.json({
      claimed: rows.length,
      completed: sentOrSkipped,
      failed,
    })
  } catch (error) {
    const forbidden =
      error instanceof Error
      && error.message ===
        'FORESTRING_DISPATCH_FORBIDDEN'

    if (!forbidden) {
      console.error(
        'notification-dispatch failed:',
        error,
      )
    }

    return Response.json(
      {
        message:
          forbidden
            ? 'Forbidden.'
            : 'Notification dispatch failed.',
      },
      {
        status: forbidden ? 403 : 500,
      },
    )
  }
    },
  ),
}
