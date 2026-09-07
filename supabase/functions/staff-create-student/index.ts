import { withSupabase } from 'npm:@supabase/server@^1'
import { hash } from 'npm:bcryptjs@3.0.2'

const encoder = new TextEncoder()
const PIN_PATTERN = /^\d{4}$/
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

type StudentType = 'regular' | 'flex'

function normalizeName(value: string): string {
  return value.normalize('NFC').trim().replace(/\s+/g, ' ')
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(message))
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

function isStudentType(value: unknown): value is StudentType {
  return value === 'regular' || value === 'flex'
}

function dbMessage(error: unknown): string {
  if (typeof error === 'object' && error !== null && 'message' in error) {
    return String((error as { message: unknown }).message)
  }
  return ''
}

function mappedDatabaseResponse(message: string): Response | null {
  if (message.includes('FORESTRING_NAME_PIN_ALREADY_IN_USE')) {
    return Response.json(
      { message: '같은 이름과 PIN을 사용하는 재원 계정이 이미 존재합니다.' },
      { status: 409 },
    )
  }
  if (message.includes('FORESTRING_REACTIVATION_BRANCH_MISMATCH')) {
    return Response.json(
      { message: '퇴원 이력이 있는 학생의 기존 지점과 선택한 지점이 다릅니다. 기존 지점에서 재등록해주세요.' },
      { status: 409 },
    )
  }
  if (message.includes('FORESTRING_REACTIVATION_HISTORY_CONFLICT')) {
    return Response.json(
      { message: '이전 퇴원 이력에 연결된 수업 기록이 있어 자동 재등록할 수 없습니다. 관리자 확인이 필요합니다.' },
      { status: 409 },
    )
  }
  if (message.includes('FORESTRING_MANAGER_BRANCH_MISMATCH')) {
    return Response.json(
      { message: '본인 지점에만 학생을 등록할 수 있습니다.' },
      { status: 403 },
    )
  }
  if (message.includes('FORESTRING_BRANCH')) {
    return Response.json({ message: '학생 지점을 확인해주세요.' }, { status: 400 })
  }
  if (message.includes('FORESTRING_STUDENT_TYPE')) {
    return Response.json({ message: '학생 유형을 확인해주세요.' }, { status: 400 })
  }
  return null
}

export default {
  fetch: withSupabase(
    { auth: 'none' },
    async (req, ctx) => {
      if (req.method !== 'POST') {
        return Response.json({ message: 'Method not allowed.' }, { status: 405 })
      }

      try {
        const authHeader = req.headers.get('Authorization')
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
          return Response.json({ message: '로그인이 필요합니다.' }, { status: 401 })
        }

        const accessToken = authHeader.slice('Bearer '.length)
        const { data: authUserData, error: authUserError } =
          await ctx.supabaseAdmin.auth.getUser(accessToken)

        if (authUserError || !authUserData.user) {
          return Response.json(
            { message: '로그인 정보가 만료되었거나 올바르지 않습니다.' },
            { status: 401 },
          )
        }

        const actorId = authUserData.user.id

        const { error: effectiveActorError } = await (ctx.supabaseAdmin as any).rpc(
          'admin_get_effective_actor_context',
          { p_actor_id: actorId },
        )

        if (effectiveActorError) {
          const message = dbMessage(effectiveActorError)
          if (message.includes('FORESTRING_EFFECTIVE_ACCESS_REQUIRED')) {
            return Response.json(
              { message: '현재 계정은 더 이상 사용할 수 없습니다.' },
              { status: 403 },
            )
          }
          console.error('Effective actor preflight failed:', effectiveActorError)
          return Response.json({ message: '계정 권한을 확인할 수 없습니다.' }, { status: 500 })
        }

        const { data: actorProfile, error: actorError } = await ctx.supabaseAdmin
          .from('profiles')
          .select('role, branch_id, is_active')
          .eq('id', actorId)
          .single()

        if (actorError || !actorProfile || actorProfile.is_active !== true) {
          return Response.json({ message: '계정 권한을 확인할 수 없습니다.' }, { status: 403 })
        }

        if (actorProfile.role !== 'master' && actorProfile.role !== 'manager') {
          return Response.json({ message: '학생을 생성할 권한이 없습니다.' }, { status: 403 })
        }

        const body = await req.json()
        const name = normalizeName(typeof body.name === 'string' ? body.name : '')
        const pin = typeof body.pin === 'string' ? body.pin : ''
        const branchId = typeof body.branchId === 'string' ? body.branchId.trim() : ''
        const studentType = body.studentType

        if (name.length === 0 || name.length > 100) {
          return Response.json({ message: '학생 이름을 확인해주세요.' }, { status: 400 })
        }
        if (!PIN_PATTERN.test(pin)) {
          return Response.json({ message: 'PIN은 4자리 숫자여야 합니다.' }, { status: 400 })
        }
        if (!UUID_PATTERN.test(branchId)) {
          return Response.json({ message: '지점을 다시 선택해주세요.' }, { status: 400 })
        }
        if (!isStudentType(studentType)) {
          return Response.json({ message: '학생 유형을 다시 선택해주세요.' }, { status: 400 })
        }
        if (actorProfile.role === 'manager' && actorProfile.branch_id !== branchId) {
          return Response.json(
            { message: '본인 지점에만 학생을 등록할 수 있습니다.' },
            { status: 403 },
          )
        }

        const pinPepper = Deno.env.get('PIN_PEPPER')
        if (!pinPepper) {
          console.error('PIN_PEPPER is missing.')
          return Response.json({ message: '계정 서버 설정 오류입니다.' }, { status: 500 })
        }

        const pinFingerprint = await hmacHex(pinPepper, pin)

        const { data: prepared, error: prepareError } = await (ctx.supabaseAdmin as any).rpc(
          'admin_prepare_student_registration',
          {
            p_actor_id: actorId,
            p_display_name: name,
            p_login_name_normalized: name,
            p_pin_fingerprint: pinFingerprint,
            p_branch_id: branchId,
            p_student_type: studentType,
          },
        )

        if (prepareError) {
          console.error('Student registration preflight failed:', prepareError)
          const mapped = mappedDatabaseResponse(dbMessage(prepareError))
          if (mapped) return mapped
          return Response.json(
            { message: '학생 등록 정보를 확인하지 못했습니다.' },
            { status: 500 },
          )
        }

        const preparedMap =
          prepared && typeof prepared === 'object' ? prepared as Record<string, unknown> : null
        const preparedStudentId = typeof preparedMap?.studentId === 'string'
          ? preparedMap.studentId
          : null
        const needsAuthCreation = preparedMap?.needsAuthCreation === true
        const registrationKind = preparedMap?.registrationKind

        if (!needsAuthCreation && preparedStudentId) {
          return Response.json(
            {
              studentId: preparedStudentId,
              displayName: name,
              branchId,
              studentType,
              reactivated: registrationKind === 'reactivation',
            },
            { status: 201 },
          )
        }

        if (!needsAuthCreation) {
          console.error('Invalid student registration preflight result:', prepared)
          return Response.json(
            { message: '학생 등록 준비 상태를 확인하지 못했습니다.' },
            { status: 500 },
          )
        }

        const pinHash = await hash(`${pin}:${pinPepper}`, 12)
        const hiddenIdentity = crypto.randomUUID()
        const hiddenEmail = `${hiddenIdentity}@auth.forestring.invalid`

        const { data: authData, error: authError } =
          await ctx.supabaseAdmin.auth.admin.createUser({
            email: hiddenEmail,
            email_confirm: true,
          })

        if (authError || !authData.user) {
          console.error('Student Auth creation failed:', authError)
          return Response.json({ message: '학생 계정 생성에 실패했습니다.' }, { status: 500 })
        }

        const studentId = authData.user.id
        const { error: stageError } = await (ctx.supabaseAdmin as any).rpc(
          'admin_stage_new_student_registration',
          {
            p_actor_id: actorId,
            p_profile_id: studentId,
            p_display_name: name,
            p_login_name_normalized: name,
            p_pin_hash: pinHash,
            p_pin_fingerprint: pinFingerprint,
            p_branch_id: branchId,
            p_student_type: studentType,
          },
        )

        if (stageError) {
          console.error('Student registration staging failed:', stageError)
          const { error: cleanupError } = await ctx.supabaseAdmin.auth.admin.deleteUser(studentId)
          if (cleanupError) {
            console.error('CRITICAL: orphan student Auth cleanup failed:', studentId, cleanupError)
          }
          const mapped = mappedDatabaseResponse(dbMessage(stageError))
          if (mapped) return mapped
          return Response.json({ message: '학생 정보 저장에 실패했습니다.' }, { status: 500 })
        }

        return Response.json(
          { studentId, displayName: name, branchId, studentType },
          { status: 201 },
        )
      } catch (error) {
        console.error('staff-create-student failed:', error)
        return Response.json(
          { message: '학생 계정 생성 중 오류가 발생했습니다.' },
          { status: 500 },
        )
      }
    },
  ),
}
