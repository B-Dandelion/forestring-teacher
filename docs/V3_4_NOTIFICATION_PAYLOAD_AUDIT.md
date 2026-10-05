# Forestring v3.4 Teacher v1 Push Payload 감사

작성일: 2026-10-05  
기준 문서: `docs/V3_4_NOTIFICATION_POLICY_V1.md`  
범위: 일반 선생님 첫 출시 ON 이벤트 9종  
상태: DB / audit / outbox / dispatcher / Flutter 현행 구현 대조 완료

## 1. 결론

현재 Notification transport 자체는 iPhone 실기기에서 E2E 성공했지만, 새로 확정한 v1 payload 계약과 비교하면 **현재 알림 도메인 모델은 부분 구현 상태**다.

핵심 결론:

- 기존 audit 데이터는 9종 중 대부분의 원천 데이터를 이미 충분히 보존한다.
- 가장 큰 부족은 **audit 데이터 자체보다 audit → notification 변환 계층**이다.
- `REGULAR_SCHEDULE_ENDED`는 계약에 필요한 기존 정규 일정 snapshot이 audit에 보존되지 않아 source 보강이 필요하다.
- 최초 담당 배정(`student_assigned`)은 현재 별도 semantic audit event가 없고 raw assignment trigger에서 바로 outbox로 간다.
- 담당 선생님 변경(`student_teacher_assigned`)은 `STUDENT_TEACHER_CHANGED` audit이 충분한 정보를 갖고 있지만 현재 notification trigger가 이 audit을 사용하지 않는다.
- 현재 outbox event key 6종은 확정한 event key 9종을 표현하지 못한다.
- 현재 FCM data에는 공통 envelope(`schemaVersion`, `notificationId`, `targetKind`, `targetId`, `navigationKind`, `recipientProfileId`, `teacherId`, `occurredAt`)가 없다.
- Flutter 수신부는 아직 payload parser/navigation이 없고 debug log만 남긴다.

따라서 payload 계약을 약화할 필요는 없으며, **DB에 이미 있는 원천 데이터를 이용해 notification domain event 변환 계층을 정리하는 것이 맞다.**

---

## 2. 현행 공통 구조 감사

### 2.1 notification_outbox

현재 outbox는 다음을 별도 컬럼으로 보유한다.

- `id`
- `recipient_profile_id`
- `event_key`
- `source_kind`
- `source_id`
- `dedupe_key`
- `title`
- `body`
- `data jsonb`
- 발송 상태/시도/시간 필드

`data`는 JSON object이므로 새 payload 계약을 담을 공간 자체는 충분하다.

그러나 현재 `event_key` CHECK constraint는 다음 6개만 허용한다.

```text
lesson_assignment
lesson_schedule_changed
lesson_canceled
makeup_created
makeup_canceled
flex_booking
```

확정 계약의 9개 event key로 확장/교체가 필요하다.

### 2.2 FCM dispatcher

현재 Edge Function은 outbox `data`에 다음 두 값만 중앙 주입한다.

```text
eventKey = outbox.event_key
outboxId = outbox.id
```

현재 누락:

- `schemaVersion`
- `notificationId`
- `recipientProfileId`
- `occurredAt`

`notificationId`는 outbox `id`, `recipientProfileId`는 outbox `recipient_profile_id`, `occurredAt`은 outbox `created_at`을 이용해 dispatcher/claim 단계에서 중앙 주입할 수 있다.

### 2.3 현재 DB enqueue helper

`private.enqueue_teacher_notification()`은:

- role=teacher
- active=true
- review=false

만 수신자로 인정한다.

현재 QA 분리 후 `is_qa_account=true / is_review_account=false`인 QA 선생님은 정상 recipient가 된다.

다만 manager/master 장기 설계를 위한 role policy는 아직 없으며 함수명과 구현 모두 teacher 전용으로 하드코딩되어 있다.

### 2.4 notification_preferences

현재는 다음 5개 category boolean 컬럼 구조다.

```text
lesson_assignment_enabled
lesson_schedule_change_enabled
lesson_cancellation_enabled
makeup_enabled
flex_booking_enabled
```

따라서:
- 개별 수업 변경 / 정규 일정 변경 / 정규 일정 종료가 하나의 setting에 묶임
- 최초 배정 / 담당교사 변경이 하나의 setting에 묶임

v1 grouped UI로는 사용할 수 있으나, 장기적으로 확정한 event catalog / role policy / event preference 구조와는 맞지 않는다.

### 2.5 Flutter

현재 `PushMessagingService`는:

- `onMessage`
- `onMessageOpenedApp`
- `getInitialMessage()`

를 연결했지만 실제로는 debug log만 남긴다.

payload parser, `targetKind`, `navigationKind`, pending intent/coordinator는 아직 없다.

---

## 3. 이벤트별 감사

### 1. student_assigned

계약:

```text
eventKey = student_assigned
targetKind = assignment
targetId = assignmentId
navigationKind = student_detail

assignmentStartsOn
studentType
```

현재 source:

- `public.assign_student_teacher()`가 `teacher_student_assignments` INSERT
- 별도 assignment semantic audit event는 생성하지 않음
- table trigger `private.enqueue_teacher_assignment_notification()`이 직접 outbox enqueue

현재 payload:

```text
eventKey = lesson_assignment
assignmentId
studentId
startsOn
branchId
```

판정: **부분 충족 / source 구조 보강 권장**

충족:
- assignmentId
- studentId
- branchId
- startsOn

부족:
- eventKey 분리
- studentType
- targetKind / targetId
- navigationKind
- teacherId
- 공통 envelope

구조 문제:
raw assignment INSERT가 바로 Push로 연결되어 최초 배정과 담당교사 변경을 semantic event 수준에서 구분하지 못한다.

권장:
`assign_student_teacher()`가 최초 배정용 semantic audit/domain event를 명시적으로 만들고 notification 변환 계층이 이를 소비하도록 정리한다.

---

### 2. lesson_changed

원천 audit:
`LESSON_MANUALLY_UPDATED`

운영 DB 확인:
- 모든 현행 샘플에 `lessonId`, `teacherId`, `before`, `after` 존재
- `before/after`에 `startsAt`, `durationMinutes` 존재
- audit row 자체에 student, branch, actor, effective date, created time 존재

현재 notification:
`lesson_schedule_changed`

판정: **원천 데이터 충족 / 변환 계층 미충족**

현재 audit 데이터만으로 확정 계약의:
- previousStartsAt
- startsAt
- previousDurationMinutes
- durationMinutes
- lessonId
- teacherId
- studentId
- branchId
- occurredAt

전부 생성 가능하다.

필요 작업:
event key를 `lesson_changed`로 분리하고 target/navigation/common envelope를 생성하면 된다.

---

### 3. lesson_canceled

원천 audit:
`LESSON_CANCELED`

audit 자체:
- lessonId 있음
- student/branch/effective date/created time 있음
- `actualLessonDurationMinutes`, `reason` 있음
- teacherId / startsAt은 audit details에 직접 없음

현재 transformer는 canceled lesson row를 조회해:
- teacherId
- startsAt
- endsAt

을 가져오고 있다.

현재 Push data:
- lessonId
- startsAt
- endsAt
- studentId
- branchId
- lessonType
- cancellationOrigin

판정: **원천 데이터 충분 / 변환 계층 일부 부족**

현재 DB row + audit 조합으로 계약을 충족할 수 있다.

추가 필요:
- durationMinutes
- reason(optional)
- target/navigation/common envelope

취소 lesson row가 유지되는 현재 모델에서는 teacher/time lookup도 안정적이다. 단 fallback snapshot은 outbox 생성 시 저장한다.

---

### 4. makeup_created

원천 audit:
`MAKEUP_LESSON_CREATED`

audit에 이미:
- lessonId
- teacherId
- startsAt
- endsAt
- durationMinutes
- student / branch / created time

존재.

현재 Push data는 durationMinutes를 버리고 있다.

판정: **원천 데이터 완전 충족 / 변환 계층 미충족**

필요 작업:
- durationMinutes 전달
- target/navigation/common envelope

---

### 5. makeup_canceled

원천 audit:
`MAKEUP_LESSON_CANCELED`

audit에:
- lessonId
- teacherId
- startsAt
- endsAt
- durationMinutes
- reason
- student / branch / created time

존재.

현재 Push data는 durationMinutes와 reason을 전달하지 않는다.

판정: **원천 데이터 완전 충족 / 변환 계층 미충족**

---

### 6. flex_lesson_booked

원천 audit:
`LESSON_RIGHT_BOOKED`

현재 notification transformer는 lesson row의 `lesson_type=flex`일 때만 Push를 생성한다.

audit에:
- lessonId
- teacherId
- startsAt
- endsAt
- durationMinutes
- lessonType
- student / branch / created time

존재.

현재 event key:
`flex_booking`

확정 event key:
`flex_lesson_booked`

판정: **원천 데이터 완전 충족 / 변환 계층 미충족**

추가 필요:
- event key 변경
- durationMinutes 전달
- target/navigation/common envelope

참고:
현재 필터는 "학생 actor인지"가 아니라 "결과 lesson이 flex인지"를 기준으로 한다. 따라서 향후 학생 직접 예약만 별도로 구분해야 한다면 `actor_id` 기반 recipient/event policy를 추가할 수 있다. v1에서 모든 flex 예약 발생을 선생님에게 알려주는 정책이라면 현 source로 충분하다.

---

### 7. regular_schedule_changed

원천 audit:
`REGULAR_SCHEDULE_CHANGED`

audit에:
- scheduleSlotId
- effective_on
- before.teacherId
- before.weekday
- before.startTime
- before.durationMinutes
- after.teacherId
- after.weekday
- after.startTime
- after.durationMinutes
- student / branch / created time

존재.

현재 transformer는 teacher가 바뀐 REGULAR_SCHEDULE_CHANGED는 Push를 억제한다. 담당교사 변경 알림과 중복되지 않도록 하기 위한 것으로 현재 정책과 일치한다.

현재 문제:
- event key가 개별 수업 변경과 동일한 `lesson_schedule_changed`
- effective_on을 payload로 전달하지 않음
- navigation이 구분되지 않음

판정: **원천 데이터 완전 충족 / 변환 계층 미충족**

확정 계약의 모든 필드를 현재 audit만으로 생성 가능하다.

---

### 8. regular_schedule_ended

원천 audit:
`REGULAR_SCHEDULE_ENDED`

현재 audit에:
- scheduleSlotId
- effective_on
- student / branch / actor / created time
- 종료/삭제 처리 개수

존재.

그러나 확정 계약에 필요한 종료 직전 schedule snapshot:
- teacherId
- weekday
- startTime
- durationMinutes

은 audit details에 보존되지 않는다.

현재 notification trigger는 teacherId를:
1. `lesson_series`의 해당 scheduleSlotId 최신 row
2. assignment fallback

으로 사후 조회한다.

판정: **source 보강 필요 — 9종 중 가장 명확한 payload 원천 부족**

문제:
종료 처리 이후 관련 series가 정리되는 경우 사후 조회에 의존하면 historical snapshot 안정성이 떨어진다.

권장:
`end_regular_schedule()`가 mutation 전에 active series snapshot을 잡고 `REGULAR_SCHEDULE_ENDED.details`에 최소 다음을 기록한다.

```text
teacherId
weekday
startTime
durationMinutes
```

그 후 notification transformer는 audit snapshot만 사용한다.

현재 schedule 종료 시 내부 child notification 폭주를 막는 dedupe/suppression 설계는 유지 가치가 있다.

---

### 9. student_teacher_assigned

원천 audit:
`STUDENT_TEACHER_CHANGED`

audit에:
- previousTeacherId
- newTeacherId
- previousAssignmentId
- newAssignmentId
- studentType
- effective_on
- student / branch / created time

존재.

즉 확정 계약의:
- targetId = newAssignmentId
- teacherId = newTeacherId
- studentId
- branchId
- effectiveFrom
- occurredAt

을 모두 생성 가능하다.

현재 notification은 이 audit을 사용하지 않는다.

대신 assignment table trigger가 변경 과정의 INSERT 또는 teacher_id UPDATE를 감지하여 새 teacher에게 generic `lesson_assignment`을 보낸다.

수신 정책:
- 기존 teacher에게 Push를 보내지 않음
- 새 teacher에게만 보냄

은 현재 trigger 동작과 이미 일치한다.

판정: **원천 데이터 완전 충족 / notification source 전환 필요**

권장:
담당교사 변경은 raw assignment trigger보다 `STUDENT_TEACHER_CHANGED` semantic audit/domain event를 notification source로 사용한다.

또한 teacher 변경 과정에서 생성되는 `REGULAR_SCHEDULE_CHANGED`는 현재처럼 별도 schedule-change Push를 억제하여 중복을 방지한다.

---

## 4. 9종 종합 판정

| 이벤트 | Source 데이터 | 현재 event 분리 | 현재 payload 계약 | 최종 판정 |
| --- | --- | --- | --- | --- |
| student_assigned | 부분 | X | X | source semantic event 보강 권장 |
| lesson_changed | 충분 | X | X | transformer 수정 |
| lesson_canceled | 충분(lesson row 조회 포함) | O | 부분 | transformer 수정 |
| makeup_created | 충분 | O | 부분 | transformer 수정 |
| makeup_canceled | 충분 | O | 부분 | transformer 수정 |
| flex_lesson_booked | 충분 | O(이름 변경 필요) | 부분 | transformer 수정 |
| regular_schedule_changed | 충분 | X | X | transformer/event key 분리 |
| regular_schedule_ended | **부족** | X | X | **source audit snapshot 보강 필요** |
| student_teacher_assigned | 충분 | X | X | semantic audit source로 전환 |

---

## 5. 공통 payload를 만드는 위치

공통 값을 각 audit branch마다 반복 조립하지 않는 것이 좋다.

권장 분리:

### notification domain transformer가 생성

```text
eventKey
targetKind
targetId
navigationKind
teacherId
studentId
branchId
event-specific context
```

### outbox / dispatcher가 중앙 보장

```text
schemaVersion
notificationId = outbox.id
recipientProfileId = outbox.recipient_profile_id
occurredAt = outbox.created_at (또는 명시적 event occurred_at)
eventKey = outbox.event_key
```

이 방식이면 새 이벤트 추가 시 공통 필드 누락을 줄일 수 있다.

---

## 6. 구현 전에 필요한 DB 구조 변경

payload 감사를 기준으로 다음 변경이 필요하다.

1. outbox event key constraint를 확정 event catalog와 맞춘다.
2. 개별 수업 변경 / 정규 일정 변경 / 정규 일정 종료의 event key를 분리한다.
3. 최초 assignment와 teacher reassignment를 semantic event로 분리한다.
4. `REGULAR_SCHEDULE_ENDED` audit에 종료 직전 schedule snapshot을 추가한다.
5. notification domain transformer가 `targetKind/targetId/navigationKind`를 생성하도록 한다.
6. dispatcher가 common envelope를 중앙 주입한다.
7. manager/master를 향후 켤 수 있도록 teacher-only hardcode를 role policy 구조로 옮긴다.
8. preference 구조는 당장 grouped UX를 유지할 수 있으나 DB는 event catalog와 확장 가능하도록 재설계한다.
9. Flutter는 payload parser + pending navigation intent + destination resolver를 추가한다.

이 감사 단계에서는 운영 데이터 mutation이나 notification schema 변경을 수행하지 않았다.
