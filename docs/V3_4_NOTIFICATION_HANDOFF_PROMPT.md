# 포레스트링 v3.4 알림 기능 — 새 채팅 인수인계 프롬프트

아래 내용을 새 ChatGPT 프로젝트 채팅의 첫 메시지로 그대로 사용하세요.

---

저는 Flutter/Dart로 운영 중인 바이올린 학원 일정 관리 앱 **포레스트링**을 개발하고 있습니다.  
이 채팅에서는 **포레스트링 v3.4 Push 알림 기능 개발을 이어서 진행**해주세요.

반드시 존댓말을 사용하고, 설명만 길게 하지 말고 실제 GitHub/Supabase 상태를 확인한 뒤 필요한 작업을 직접 이어서 진행해주세요.  
현재 구현 방식보다 더 나은 방식이 있으면 알려주시되, 기존 동작을 불필요하게 바꾸지 마세요.

## 1. 저장소 / 브랜치 / 백엔드

- GitHub: `B-Dandelion/forestring-teacher`
- 작업 브랜치: `feature/notifications-v3.4`
- `main`은 현재 스토어 제출된 v3.3.1 기준
- Supabase production project id: `lgfvpgrcvhfxqkdrdndy`
- Firebase project id: `forestring1-1`
- Firebase sender/project number: `849518778373`
- Teacher app package / bundle id: `forestring.teacher.app`
- Student app package / bundle id: `forestring.student.app`

관련 GitHub 이슈:
- #10 `[v3.4] 알림·인증·운영관측성 개선 Release Tracking`
- #17 `[v3.4][Phase 0] Firebase 정리 및 FCM/APNs 기반 점검`
- #5 알림 백엔드
- #6 Flutter Push/device/settings

## 2. 우리가 지금 하려는 일

v3.4의 1차 목표는 **일반 선생님에게 실제 수업 변경 Push 알림이 안정적으로 도착하는 end-to-end 흐름을 완성하는 것**입니다.

개발 순서는:

1. 공통 Push 기반
2. 일반 선생님
3. 매니저 / 관리자
4. 학생
5. QA / 운영관측성 / 배포

일반 선생님 1차 알림 범위는 다음으로 확정했습니다.

- 새 수업 배정
- 수업 일정 변경
- 수업 취소
- 보강 등록
- 보강 취소
- 자율 학생 예약

일반 선생님은 자신의 수업을 직접 변경하는 기능이 없으므로, 1차 단계에서 자기 행동 알림 제외 문제는 핵심이 아닙니다.

핵심 아키텍처 원칙은 반드시 유지해주세요.

```text
Flutter 동작 / 시스템 자동화
        ↓
Supabase RPC / DB transaction 성공
        ↓
audit/domain event 생성
        ↓
recipient 결정
        ↓
notification_outbox
        ↓
Supabase Edge Function
        ↓
FCM
        ↓
Android
또는
FCM → APNs → iOS
```

**Flutter 버튼 탭 자체에서 Push를 직접 보내면 안 됩니다.**  
Supabase/PostgreSQL이 계속 단일 source of truth이고 Firebase는 Push transport로만 사용합니다.

## 3. Firebase / APNs 정리 완료 상태

기존 Firebase는 Supabase 이전 전 DB 역할을 하던 프로젝트입니다.

완료된 작업:

- 구 Firebase Cloud Functions 12개 전부 삭제 완료
- `firebase functions:list --project forestring1-1` 결과 비어 있음 확인
- Firebase project 자체와 teacher/student app registration은 유지
- FCM HTTP v1 활성화 확인
- Apple Developer에서 Push Notifications 활성화
- APNs Authentication Key 생성
  - Sandbox & Production
  - Team Scoped (All Topics)
- Firebase의 teacher iOS app에 APNs key 업로드 완료
- 절대 Git에 올리면 안 되는 것:
  - APNs `.p8`
  - Google service account private key JSON
  - 서버용 FCM credential
  - 내부 dispatch secret

## 4. FlutterFire 연결 상태

사용자가 직접 `flutterfire configure --project=forestring1-1` 실행 완료.

확인된 설정:

- `lib/firebase_options.dart`
  - projectId: `forestring1-1`
  - messagingSenderId: `849518778373`
  - Android teacher appId:
    `1:849518778373:android:372b26308094675482646c`
  - iOS teacher appId:
    `1:849518778373:ios:674fbf5cf465887c82646c`
  - iOS bundleId: `forestring.teacher.app`
- `firebase.json`도 동일 teacher Android/iOS app을 가리킴
- `android/app/google-services.json`에는 student/teacher Android client 둘 다 존재하지만
  `forestring.teacher.app` client가 정상 포함되어 있음
- `firebase_core 4.7.0`
- `firebase_messaging 16.2.0`
- 현재 Flutter/Dart SDK 호환성 때문에 이 버전으로 고정

Release cleanup도 수정됨:
- 더 이상 `GoogleService-Info.plist` / `firebase.json`을 삭제하지 않음
- release 준비 시 teacher bundle/project가 맞는지 검증

주요 커밋:
- `b59cece` release cleanup에서 FCM config 보존
- `9910ecd` FlutterFire dependencies
- `814c26e` 사용자가 FlutterFire config 생성/커밋
- `92220a7` shared FCM messaging foundation
- `b644dd3` Firebase messaging startup initialization
- `2ba519d` Android notification permission
- `633fef6` raw Push token 로그 출력 제거

## 5. FCM client 검증 완료

iOS 실기기에서 확인:

- 알림 권한 팝업 정상
- authorization = authorized
- APNs token 발급
- FCM registration token 발급

Android 에뮬레이터에서 확인:

- 알림 권한 팝업 정상
- authorization = authorized
- APNs token = not available → Android에서는 정상
- FCM registration token 발급
- onTokenRefresh 발생
- FlutterFirebaseMessagingBackgroundService 시작 확인

실제 Android 기기는 배포 QA에서 한 번 더 확인하면 됨.

## 6. Flutter Push registration 구현 상태

브랜치에 다음이 이미 구현되어 있습니다.

- `lib/core/notifications/push_messaging_service.dart`
- `lib/core/notifications/push_device_repository.dart`
- `lib/core/notifications/push_device_registration_service.dart`
- auth lifecycle과 Push 설치 등록/해제 연결
- 강제 로그아웃에도 installation unbind
- pre-login 단계에서 권한 팝업이 뜨지 않도록 조정
- 선생님 마이페이지에 알림 설정 sheet 추가

주요 커밋:

- `d984267` Push device repository
- `a33d1a4` FCM installation ↔ Supabase session sync
- `4b5868f` auth lifecycle binding
- `a3282fb` pre-login permission prompt 제거
- `9da686f` teacher notification settings sheet
- `5c2d37f` teacher My Page 설정 연결
- `d5e5f13` forced logout Push unbind 보강

새 채팅에서는 이 코드를 먼저 읽고 중복 구현하지 마세요.

## 7. Supabase notification backend — 이미 production 적용됨

아래 migration은 Git에 있고 **production Supabase에도 적용 완료**되어 있습니다.

실제 production migration 기록:

- `20261004113735 add_notification_foundation`
- `20261004114249 index_notification_delivery_tokens`
- `20261004114445 add_notification_outbox_claim_rpc`
- `20261004115208 dispatch_notification_outbox`
- `20261004115453 dedupe_regular_schedule_end_notifications`

Git 파일명:

- `supabase/migrations/20261004124000_add_notification_foundation.sql`
- `supabase/migrations/20261004125500_index_notification_delivery_tokens.sql`
- `supabase/migrations/20261004131000_add_notification_outbox_claim_rpc.sql`
- `supabase/migrations/20261004133000_dispatch_notification_outbox.sql`
- `supabase/migrations/20261004134500_dedupe_regular_schedule_end_notifications.sql`

구현된 DB 구성:

### device_push_tokens
- Forestring profile ↔ 앱 installation ↔ FCM token
- app_id / installation_id / platform / fcm_token
- disabled_at
- 로그인 계정 변경 시 재바인딩 가능

### notification_preferences
일반 선생님 v1 event toggle:
- push_enabled
- lesson_assignment_enabled
- lesson_schedule_change_enabled
- lesson_cancellation_enabled
- makeup_enabled
- flex_booking_enabled

### notification_outbox
- durable queue
- dedupe_key unique
- status / attempt_count / available_at / locked_at / sent_at / last_error
- client direct write 차단

### notification_deliveries
- device별 delivery attempt 기록
- provider message id
- FCM error code/detail
- accepted / failed / skipped

### RPC
- `register_push_device`
- `unregister_push_device`
- `get_notification_preferences`
- `update_notification_preferences`
- `claim_notification_outbox`

### Trigger / recipient logic
- teacher assignment → `lesson_assignment`
- `LESSON_MANUALLY_UPDATED` → schedule changed
- `REGULAR_SCHEDULE_CHANGED` → regular schedule changed
- `LESSON_CANCELED` → canceled
- `MAKEUP_LESSON_CREATED` → makeup created
- `MAKEUP_LESSON_CANCELED` → makeup canceled
- `LESSON_RIGHT_BOOKED` 중 실제 lesson_type=flex만 → flex booking

Phase 1에서는 recipient를 **role=teacher인 일반 선생님으로 제한**함.
manager/master 알림 정책은 다음 단계에서 별도로 확장.

## 8. regular schedule 종료 Push storm 방지

`end_regular_schedule()`은 내부적으로 미래 수업 여러 건을 취소하면서
`LESSON_CANCELED` audit를 여러 개 생성할 수 있습니다.

이걸 그대로 Push로 보내면 알림 폭탄이 되므로 production에 보정 migration이 적용되어 있습니다.

정책:
- reason=`regular_schedule_ended`인 child `LESSON_CANCELED` 알림은 suppress
- 단일 `REGULAR_SCHEDULE_ENDED` event에서 teacher에게
  `lesson_schedule_changed` Push 1개만 enqueue

커밋:
- `7f106b6` regular schedule end Push dedupe

## 9. notification-dispatch Edge Function 상태

이미 구현 및 production deploy 완료.

- function slug: `notification-dispatch`
- production status: ACTIVE
- 현재 production version: 3
- verify_jwt: false
  - 대신 내부 전용 secret header로 보호
- FCM HTTP v1 사용
- invalid/unregistered token 자동 disable
- transient error retry
- outbox atomic claim
- pg_net 즉시 dispatch
- pg_cron 1분 recovery/retry heartbeat
- Push 실패가 수업 transaction을 rollback시키지 않도록 safe failure

주요 커밋:

- `af1cd5b` atomic outbox claim
- `664c036` FCM outbox dispatcher
- `7c34db9` internal secret protection
- `64ae369` pg_net + cron dispatch/retry
- `ae01364` Supabase server context admin access
- `90c170b` dispatcher runtime dependency 수정

중요:
`supabase/functions/notification-dispatch/index.ts`를 반드시 읽고 이어서 작업할 것.

## 10. 현재 남은 핵심 blocker: production secrets

현재 구조는 secret이 없으면 **일부러 아무 Push도 전송하지 않는 safe no-op**입니다.

필요한 secret:

### Supabase Edge Function Secret

`FCM_SERVICE_ACCOUNT_JSON`

- Firebase/Google project `forestring1-1`용
- 전용 service account를 새로 만들 것
- 권한은 가능하면 최소 권한:
  `Firebase Cloud Messaging API Admin`
  (`roles/firebasecloudmessaging.admin`)
- 전체 JSON private key를 Supabase secret에만 저장
- 절대 Git / ChatGPT / issue / Flutter env에 넣지 말 것

`NOTIFICATION_DISPATCH_SECRET`

- Postgres → Edge Function 내부 호출 인증용 랜덤 secret
- 예:
  `openssl rand -hex 32`

### Supabase Vault

secret name:
`notification_dispatch_secret`

값:
`NOTIFICATION_DISPATCH_SECRET`과 정확히 동일

DB trigger가 runtime에 Vault에서 읽음.

관련 문서:
`docs/V3_4_NOTIFICATION_FOUNDATION.md`

새 채팅에서 **가장 먼저 해야 할 실질적인 다음 작업은 이 secret provisioning을 사용자에게 안전하게 안내하는 것**입니다.

사용자에게 private key 원문을 채팅에 붙이라고 하면 안 됩니다.

## 11. remote regression test

추가되어 있음:

`supabase/tests/remote/notification_foundation.sql`

검증 대상:
- device registration
- default preference
- preference OFF시 enqueue 차단
- dedupe_key idempotency
- unregister → disabled_at
- transaction rollback 후 test row 잔존 없음

최신 브랜치 head 기준 관련 커밋:
- `dca1eff` `test: add notification foundation remote regression`

이 테스트가 실제 remote DB에서 실행되어 PASS됐는지는 새 채팅에서 **확인 후 판단**하세요.
커밋이 존재한다고 테스트 통과했다고 가정하지 마세요.

## 12. 현재 브랜치 head

인수인계 작성 시점 branch:
`feature/notifications-v3.4`

HEAD:
`dca1effac89fe2cdd7fd3507a42a7610c27e2d26`

새 채팅 시작 시 반드시 먼저 GitHub branch head를 다시 확인하고,
사용자 로컬에도 최신 브랜치를 pull하도록 필요하면 안내하세요.

## 13. 반드시 이어서 해야 할 작업

새 채팅에서는 추상적인 계획을 다시 세우지 말고 다음 순서로 진행해주세요.

1. GitHub `feature/notifications-v3.4` 최신 상태 확인
2. production Supabase migration / `notification-dispatch` 상태 확인
3. production secret이 아직 없다면:
   - dedicated Google service account 생성 절차 안내
   - `FCM_SERVICE_ACCOUNT_JSON`을 Supabase Edge Function secret에 등록
   - 랜덤 `NOTIFICATION_DISPATCH_SECRET` 생성
   - 같은 값을 Vault `notification_dispatch_secret`에 등록
4. remote regression test 실행 / 검증
5. 테스트용 일반 선생님 계정으로 앱 로그인
6. `device_push_tokens`에 실제 installation이 정상 등록되는지 확인
7. 실제 하나의 domain event로 end-to-end Push 검증
   - 추천 첫 vertical slice: 자율 학생 예약 또는 보강 등록
   - DB event → outbox 1건 → delivery 1건 → FCM → teacher phone
8. 중복 Push / 잘못된 recipient / preference OFF / logout 후 old token 차단 검증
9. 일반 선생님 1차 event 6종을 순서대로 검증
10. 완료 후 manager/master 단계로 확장

## 14. 개발 / 운영 주의사항

- production DB를 건드릴 때는 기존 운영 수업 동작을 바꾸지 않는 것이 최우선
- Push 실패 때문에 수업 등록/변경 transaction이 실패하면 안 됨
- raw FCM token을 로그에 찍지 말 것
- private credential을 Git에 넣지 말 것
- user logout / account switch 후 이전 사용자가 Push를 받는 것은 release blocker
- 한 domain event에 Push가 중복 발송되면 release blocker
- 잘못된 선생님에게 Push가 가면 release blocker
- 필요한 event가 outbox를 만들지 않으면 release blocker
- 일반 선생님 → manager/master → student 순서 유지
- Firebase DB/Auth/Functions를 다시 업무 로직에 도입하지 말 것

## 15. 참고

v3.3.1은 이미 iOS/Android 스토어 제출 상태이고,
v3.4 작업은 별도 branch에서 진행 중입니다.

사용자는 구현 과정과 이유를 Git에 상세히 남기는 것을 중요하게 생각합니다.
작업 후에는 관련 issue와 `docs/V3_4_NOTIFICATION_FOUNDATION.md`를 갱신해주세요.

그리고 사용자는 존댓말을 원합니다.

---

이제 위 상태를 기준으로 **secret provisioning부터 이어서 일반 선생님 Push end-to-end 검증을 완성해주세요.**
