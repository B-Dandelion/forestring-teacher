# Forestring v3.4 Teacher v1 Push Payload 감사 및 DB 정리 결과

작성일: 2026-10-05  
기준 문서: `docs/V3_4_NOTIFICATION_POLICY_V1.md`  
범위: 일반 선생님 첫 출시 ON 이벤트 8종  
상태: payload 감사 완료 / notification domain DB 구조 반영 완료

## 1. 최종 결론

iPhone 실기기에서 Push transport E2E는 이미 성공했고, 이후 확정한 payload 계약을 기준으로 production DB의 audit/RPC/trigger/outbox/dispatcher/Flutter 수신부를 대조했다.

감사 결과 대부분의 이벤트는 기존 audit 데이터가 필요한 원천 정보를 이미 보존하고 있었다. 따라서 business RPC를 대규모로 수정하지 않고 **audit → notification domain event 변환 계층을 정리하는 방식**으로 반영했다.

정규 일정 종료(`REGULAR_SCHEDULE_ENDED`)는 사용자 결정에 따라 Push 대상에서 제외했다. 감사 이력은 그대로 유지하며, 일정 종료 과정에서 파생되는 `LESSON_CANCELED(reason=regular_schedule_ended)`도 개별 Push로 변환하지 않는다.

최종 teacher v1 Push event는 다음 8종이다.

```text
student_assigned
lesson_changed
lesson_canceled
makeup_created
makeup_canceled
flex_lesson_booked
regular_schedule_changed
student_teacher_assigned
```

---

## 2. DB 구조 반영

### 2.1 notification event catalog

내부 테이블:

`private.notification_event_catalog`

필드 역할:
- `event_key`: semantic notification event
- `target_kind`: assignment / lesson / regularSchedule
- `navigation_kind`: lesson_week / student_detail
- `preference_group`: 기존 Flutter 그룹형 알림 설정과의 호환
- `is_deprecated`: 기존 outbox history key 보존용

활성 8종 외에 과거 outbox history의 referential integrity를 위해 다음 legacy key를 deprecated 상태로 남겼다.

```text
lesson_assignment
lesson_schedule_changed
flex_booking
```

기존 `notification_outbox.event_key` CHECK constraint는 제거하고 catalog FK로 교체했다.

### 2.2 role policy

내부 테이블:

`private.notification_role_policy`

현재 정책:
- teacher: 활성 8종 `enabled_by_default=true`, `release_enabled=true`
- manager: `release_enabled=false`
- master: `release_enabled=false`
- legacy event: 모든 role `release_enabled=false`

따라서 DB 구조는 manager/master 확장을 수용하지만 첫 출시에서는 일반 선생님 Push만 실제 enqueue된다.

### 2.3 event-level preferences

내부 테이블:

`private.notification_event_preferences`

기존 Flutter 설정 UI와 RPC는 그대로 유지한다.

현재 그룹 매핑:

```text
새 수업 배정
→ student_assigned
→ student_teacher_assigned

수업 일정 변경
→ lesson_changed
→ regular_schedule_changed

수업 취소
→ lesson_canceled

보강
→ makeup_created
→ makeup_canceled

자율 학생 예약
→ flex_lesson_booked
```

`public.notification_preferences`가 생성/수정되면 DB trigger가 이벤트 단위 설정으로 자동 동기화한다.

---

## 3. 공통 payload envelope

`private.enqueue_notification()`이 outbox INSERT 전에 공통 payload를 중앙 생성한다.

필수 공통 값:

```text
schemaVersion = 1
notificationId
eventKey
targetKind
targetId
navigationKind
recipientProfileId
branchId
teacherId
studentId
occurredAt
```

이벤트별 context는 공통 envelope와 병합된다.

이 구조로 새 이벤트를 추가할 때 각 audit branch에서 공통 필드를 반복 생성하지 않아도 된다.

FCM dispatcher는 기존처럼 outbox `data`를 문자열 data payload로 전달하며 `eventKey`와 `outboxId`를 추가한다. 새 계약의 필수 공통 필드는 이미 DB outbox data에 들어가므로 dispatcher에 별도 business-domain 로직을 추가하지 않았다.

---

## 4. 이벤트별 source 및 결과

| eventKey | source | target/navigation | 결과 |
| --- | --- | --- | --- |
| `student_assigned` | 최초 `teacher_student_assignments` INSERT → `STUDENT_ASSIGNED` audit | assignment / student_detail | 구현 |
| `lesson_changed` | `LESSON_MANUALLY_UPDATED` | lesson / lesson_week | 구현 |
| `lesson_canceled` | `LESSON_CANCELED` | lesson / lesson_week | 구현 |
| `makeup_created` | `MAKEUP_LESSON_CREATED` | lesson / lesson_week | 구현 |
| `makeup_canceled` | `MAKEUP_LESSON_CANCELED` | lesson / lesson_week | 구현 |
| `flex_lesson_booked` | `LESSON_RIGHT_BOOKED` 중 lesson_type=flex | lesson / lesson_week | 구현 |
| `regular_schedule_changed` | `REGULAR_SCHEDULE_CHANGED` | regularSchedule / student_detail | 구현 |
| `student_teacher_assigned` | `STUDENT_TEACHER_CHANGED` | assignment / student_detail | 구현 |

### student_assigned

기존에는 assignment table trigger가 raw INSERT/teacher update를 바로 `lesson_assignment` Push로 변환했다.

현재는 최초 assignment INSERT일 때만 `STUDENT_ASSIGNED` semantic audit을 만든 뒤 공통 transformer가 `student_assigned`로 변환한다.

다른 assignment row가 이미 존재하면 최초 배정으로 보지 않는다.

### student_teacher_assigned

담당 선생님 변경은 raw assignment trigger가 아니라 기존 `STUDENT_TEACHER_CHANGED` audit을 사용한다.

recipient는 `newTeacherId`만 사용한다.

기존 선생님에는 v1 Push를 발송하지 않는다.

담당 선생님 변경 과정에서 같이 발생하는 `REGULAR_SCHEDULE_CHANGED` 중 before/after teacher가 다른 이벤트는 별도 정규 일정 변경 Push로 보내지 않아 중복을 막는다.

### lesson_changed

기존 audit의 `before/after`에서:

- previousStartsAt
- startsAt
- previousDurationMinutes
- durationMinutes

를 그대로 payload snapshot으로 만든다.

### lesson_canceled

취소된 lesson row에서 teacher/start/duration을 읽어 payload snapshot을 만든다.

`reason=regular_schedule_ended`인 내부 취소는 Push로 변환하지 않는다.

### makeup_created / makeup_canceled

기존 audit에 이미 있는 lessonId/teacherId/startsAt/durationMinutes/reason을 사용한다.

### flex_lesson_booked

`LESSON_RIGHT_BOOKED` 중 실제 lesson type이 flex인 경우만 변환한다.

### regular_schedule_changed

기존 audit의:
- effective_on
- before weekday/startTime/durationMinutes
- after weekday/startTime/durationMinutes
- scheduleSlotId

를 사용한다.

navigation은 주간 수업 포커스가 아니라 `student_detail`이다.

---

## 5. 정규 일정 종료 제외 결정

`REGULAR_SCHEDULE_ENDED`는 notification catalog에 활성 event로 등록하지 않았다.

동작:

```text
정규 일정 종료
→ REGULAR_SCHEDULE_ENDED audit: 유지
→ notification domain event: 생성하지 않음
→ 내부 future lesson cancellation:
   reason=regular_schedule_ended 이면 Push 억제
```

따라서 정규 일정 종료 1회 때문에 미래 수업 수만큼 취소 Push가 발생하지 않으며, 별도의 일정 종료 Push도 없다.

---

## 6. QA / review recipient

review와 QA 역할 분리 이후:

- `is_review_account=true`: 실운영 Push 대상 제외
- `is_qa_account=true`: 정상 business / Supabase / FCM 경로 사용 가능

generic enqueue는 `is_review_account=false`만 요구하므로 real-backend QA 계정은 정상 recipient가 된다.

검증 시 QA 계정에 활성 8개 event preference가 모두 생성되고 `release_enabled=true`인 것을 확인했다.

---

## 7. 기존 Flutter 설정 호환

기존 Flutter:
- 전체 알림
- 새 수업 배정
- 수업 일정 변경
- 수업 취소
- 보강 등록·취소
- 자율 학생 예약

UI와 RPC는 이번 DB 정리에서 변경하지 않았다.

DB 내부에서 grouped preference를 event-level preference로 동기화하므로 현재 앱 빌드를 깨지 않는다.

향후 이벤트별 세분화 UI가 필요하면 Flutter에서 `private.notification_event_preferences`를 직접 읽는 것이 아니라 별도 public RPC 계약을 추가한다.

---

## 8. 검증 결과

적용 migration:

```text
20261005071810 normalize_notification_domain_events
20261005072045 index_notification_event_foreign_keys
```

검증:
- active notification catalog: 8종
- teacher: 8종 release enabled
- manager/master: release disabled
- legacy event key: deprecated / release disabled
- outbox historical rows: 보존
- outbox event key integrity: catalog FK 적용
- legacy enqueue trigger/functions: 제거
- 새 audit → notification transformer trigger: 1개
- 최초 assignment semantic audit trigger: 1개
- grouped preference → event preference sync trigger: 1개
- QA teacher event preferences: 8종 enabled
- QA/review 분리 유지

Performance Advisor가 새 FK 2개에 covering index를 권고하여 후속 migration으로 추가했고, 재검사에서 해당 두 경고가 사라진 것을 확인했다.

Security Advisor의 새 항목은 private notification table에 RLS가 켜져 있으나 policy가 없다는 INFO다. 세 테이블은 private schema 내부용이며 direct access를 모두 revoke하고 SECURITY DEFINER 내부 함수만 접근하도록 설계했으므로 의도한 deny-by-default 상태다.

기존 프로젝트의 다른 GraphQL 노출/SECURITY DEFINER 관련 Advisor 경고는 이번 notification 변경과 별개이며 이번 작업에서 범위를 확장해 수정하지 않았다.

---

## 9. 다음 단계

DB payload 생성 구조는 준비됐다.

다음 구현은 Flutter에서 진행한다.

1. Push payload parser
2. NotificationNavigationIntent
3. pending intent coordinator
4. `lesson_week` resolver
5. `student_detail` resolver
6. foreground 인앱 알림
7. background 알림 탭 navigation
8. terminated → session/profile/Shell/data 준비 후 pending intent 소비
9. iPhone 실기기 E2E
