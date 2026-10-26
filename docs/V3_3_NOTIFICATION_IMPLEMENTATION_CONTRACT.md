# 포레스트링 v3.3 알림·인증·운영관측성 구현 계약서

- 작업 브랜치: `feature/notification-observability-v3.3`
- Release tracking: #10
- 관련 이슈: #5, #6, #7, #8, #9
- 상태: 구현 전 기준선 확정
- 원칙: 운영 Supabase는 검토/QA 전까지 변경하지 않는다.

## 1. 아키텍처 원칙

포레스트링의 데이터베이스, 인증, 도메인 규칙, 알림 설정, 기기 토큰, 발송 대기/결과, 분석 로그는 Supabase를 단일 기준 데이터 소스로 유지한다.

FCM/APNs는 데이터 저장소가 아니라 최종 Push 전달망으로만 사용한다.

예정 흐름:

```text
Flutter
  -> Supabase RPC
  -> PostgreSQL transaction
       -> lesson/domain 변경
       -> audit_events
       -> notification_outbox
  -> Supabase Edge Function
  -> FCM
  -> Android
     또는
     APNs -> iOS
```

Flutter 클라이언트의 버튼 클릭 자체를 알림 발생 근거로 사용하지 않는다.

## 2. 확정된 도메인 알림 규칙

### 정규 학생

정규 학생의 수업 시간 변경은 기존 수업을 직접 이동하는 동작으로 취급하지 않는다.

1. 기존 수업 취소
2. 원하는 시간에 재예약

두 단계는 독립된 도메인 사건이며 각각 알림을 생성한다.

- `LESSON_CANCELED` -> 취소 알림 1회
- `LESSON_RIGHT_BOOKED` + 정규 재예약 -> 예약 알림 1회

따라서 시간 변경 과정 전체에서는 총 2회의 알림이 발생한다.

두 이벤트를 하나의 "수업 시간이 변경되었습니다" 알림으로 합치지 않는다.

### 비정규 학생

보유 수업권으로 신규 예약할 수 있다.

- `LESSON_RIGHT_BOOKED` -> 예약 알림 1회

### 보강

- `MAKEUP_LESSON_CREATED` -> 보강 등록 알림
- `MAKEUP_LESSON_CANCELED` -> 보강 취소 알림

### 기타 단일 수업 수정

- `LESSON_MANUALLY_UPDATED` -> 실제 단일 수업 정보가 직접 변경되는 경우의 수정 알림

`REGULAR_SCHEDULE_CHANGED`는 다수 미래 수업 재구성과 연결될 수 있으므로 개별 Push 발생 여부를 구현 전에 별도 검증한다. 정규 학생의 취소+재예약 규칙을 대체해서는 안 된다.

## 3. 현재 코드/운영 환경 기준선

### Flutter / Auth

- Supabase Flutter를 사용한다.
- 별도 자동로그인 체크박스는 없다.
- Supabase persisted session이 존재하면 `AuthController.initialize()`가 `currentSession`을 확인하고 `profiles`를 조회한다.
- 현재 프로필 검증 timeout은 8초다.
- 명시적 로그아웃은 `Supabase.auth.signOut()`을 호출한다.
- 로그인 화면의 PIN 입력 필드 표시 문구는 현재 "비밀번호"이다.
- `onAuthStateChange` 중심의 세션 수명주기 처리는 아직 없다.

### Supabase

운영 프로젝트에는 기존 인증/계정 관리 Edge Functions가 배포되어 있다.

Push 전용 Edge Function은 아직 없다.

현재 저장소에는 DB Webhook, `pg_net`, `supabase_functions.http_request` 기반 Push 파이프라인이 없다.

`audit_events`에는 다음 알림 후보 이벤트가 이미 기록된다.

- `LESSON_CANCELED`
- `LESSON_RIGHT_BOOKED`
- `MAKEUP_LESSON_CREATED`
- `MAKEUP_LESSON_CANCELED`
- `LESSON_MANUALLY_UPDATED`
- `REGULAR_SCHEDULE_CHANGED`

이벤트의 `details`에는 lessonId, teacherId, startsAt/endsAt, rightId, regularRebooking 등 알림 판별에 사용할 수 있는 데이터가 이미 포함되어 있다.

## 4. 예정 데이터 모델

실제 migration 작성 전 검토할 논리 모델이다. 운영 DB에는 아직 적용하지 않았다.

### notification_preferences

사용자별 앱 수준 알림 수신 설정.

초기에는 전체 ON/OFF를 제공하되 향후 종류별 설정을 확장할 수 있는 구조를 고려한다.

### device_push_tokens

사용자와 기기의 Push 주소를 연결한다.

예상 주요 속성:
- profile_id
- platform
- push_provider
- push_token
- enabled
- last_seen_at
- created_at / updated_at

로그아웃 시 기존 사용자와 해당 기기의 활성 연결을 해제해야 한다.

FCM token refresh를 반영해야 한다.

### notification_outbox

DB에서 확정된 도메인 사건 중 외부 Push가 필요한 건을 기록한다.

원본 `audit_events.id` 또는 동등한 idempotency key와 연결하여 동일 사건의 중복 큐 생성을 방지한다.

정상적인 서로 다른 도메인 이벤트는 중복으로 간주하지 않는다.

### notification_deliveries

실제 외부 전달 시도와 결과를 기록한다.

예상 상태:
- pending
- sent
- failed
- skipped

실패 원인과 provider 응답을 개인정보/credential을 노출하지 않는 범위에서 기록한다.

### app_events

도메인 감사 로그와 분리된 제품 사용/기술 telemetry.

초기 이벤트:
- app_open
- session_restored
- login_success
- login_failure
- token_refreshed
- logout
- screen_view
- lesson_update_attempt
- lesson_update_success
- lesson_update_failure
- notification_permission_result
- notification_received
- notification_opened

PIN, access token, refresh token, Push token 원문 등 인증 비밀은 기록하지 않는다.

## 5. Push 발송 안전 규칙

1. DB transaction이 성공하기 전에 Push를 보내지 않는다.
2. 동일 원본 이벤트에 대한 중복 queue 생성을 막는다.
3. queue 재처리로 동일 기기에 동일 업무 이벤트가 중복 전송되지 않게 한다.
4. 서로 다른 정상 업무 이벤트는 임의로 합치거나 삭제하지 않는다.
5. 정규 학생의 취소 후 재예약은 반드시 2개 이벤트를 보존한다.
6. 로그아웃한 사용자의 기존 device token 연결은 비활성화한다.
7. 타 계정 로그인 후 이전 계정 Push가 도착하는 경우 Release Blocker로 처리한다.
8. Push 전송 실패가 원래 수업 transaction을 rollback시키지 않도록 전송은 비동기로 분리한다.

## 6. Firebase/FCM 범위

Firebase는 다음 용도로만 사용한다.

- Firebase Cloud Messaging
- Android Push transport
- iOS에서는 FCM과 APNs 연결

사용하지 않는 기능:
- Firebase Auth
- Firestore
- Realtime Database
- Firebase Storage
- Firebase Functions

현재 `tool/prepare_teacher_release.dart`는 `GoogleService-Info.plist`와 `firebase.json`을 삭제한다.

FCM 설정을 시작하기 전에 이 release cleanup을 수정해야 한다. 단, 과거 Firebase 백엔드 의존성을 다시 허용하는 방식이 아니라 Push에 필요한 설정 파일만 명시적으로 보존하도록 변경한다.

## 7. 구현 순서

1. 알림 스키마/RLS/idempotency 설계
2. 알림 대상 event mapping 검증
3. migration 작성 및 로컬/QA DB 검증
4. Push sender Edge Function
5. Firebase FCM 및 APNs credential 연결
6. Flutter FCM token/permission lifecycle
7. 설정 화면
8. Auth lifecycle 개선
9. app_events telemetry
10. Android/iOS 실기기 E2E
11. 개인정보/Data Safety 검토
12. 스토어 제출

## 8. 운영 변경 정책

운영 DB/Edge Function 변경은 다음 조건 전에는 수행하지 않는다.

- migration SQL 검토 완료
- 로컬 또는 분리된 QA 환경에서 검증
- RLS/권한 검토
- 기존 수업 RPC 회귀 테스트
- 중복/누락 알림 테스트

## 9. Release Blocker

다음 중 하나라도 재현되면 스토어 제출하지 않는다.

- 실제로 발생하지 않은 수업 사건의 Push
- 다른 사용자/선생님의 Push 수신
- 동일 업무 이벤트의 중복 Push
- 정규 학생 취소/재예약 중 한 사건 누락
- 알림 OFF 사용자의 Push 수신
- 로그아웃 후 이전 사용자 Push 수신
- 기존 수업 예약/취소/보강 기능의 회귀
