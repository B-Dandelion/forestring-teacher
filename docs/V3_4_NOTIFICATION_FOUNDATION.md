# Forestring v3.4 Notification Foundation

## 1. Goal

v3.4 introduces Push notifications while keeping Supabase/PostgreSQL as the single source of truth.

Firebase is not reintroduced as the application database, authentication provider, or business-logic runtime.

Firebase Cloud Messaging (FCM) and Apple Push Notification service (APNs) are used only as delivery infrastructure.

Development order:

1. Shared notification foundation
2. Regular teacher
3. Manager / master
4. Student
5. Observability / QA / release

---

## 2. Teacher v1 notification scope

The first production slice for regular teachers is limited to:

- new lesson assignment
- lesson schedule changed
- lesson canceled
- makeup lesson created
- makeup lesson canceled
- flex student reservation

Regular teachers do not mutate their own assigned lessons in the current product flow, so self-notification suppression is not a first-phase requirement for the teacher role.

---

## 3. Firebase baseline audit

Audit date: 2026-10-04

Firebase project:

- project id: `forestring1-1`
- sender / project number: `849518778373`

Registered Firebase apps observed in Firebase Console:

### Android

- `forestring_student_1 (android)`
  - package: `forestring.student.app`
- `forestring_teacher_2 (android)`
  - package: `forestring.teacher.app`

### Apple

- legacy data helper app
  - bundle id: `com.example.forestringData`
- Forestring teacher
  - bundle id: `forestring.teacher.app`
- Forestring student
  - bundle id: `forestring.student.app`

### Cloud Messaging

- Firebase Cloud Messaging API (HTTP v1): enabled
- legacy Cloud Messaging API: disabled
- current sender id: `849518778373`

### APNs

At audit time:

- no APNs authentication key uploaded
- no APNs certificate uploaded
- Apple Developer Push Notifications capability not yet enabled
- no APNs private key created yet

---

## 4. Current Flutter repository state

The teacher app currently has no active Firebase Flutter runtime dependencies.

Not present in `pubspec.yaml`:

- `firebase_core`
- `firebase_messaging`
- `firebase_auth`
- `cloud_firestore`
- `firebase_database`

Therefore the current 3.3.1 runtime does not depend on Firebase Database / Firestore / Firebase Auth.

An old iOS Firebase configuration is still present:

- `ios/Runner/GoogleService-Info.plist`
- bundle id: `forestring.teacher.app`
- project id: `forestring1-1`
- GCM sender id: `849518778373`

The Xcode project also still contains a resource reference to this plist.

Android `google-services.json` is not currently committed in the repository.

---

## 5. Release cleanup conflict

`tool/prepare_teacher_release.dart` currently removes Firebase configuration during release cleanup.

It removes:

- the Xcode `GoogleService-Info.plist` reference
- `ios/Runner/GoogleService-Info.plist`
- `firebase.json`

This behavior was correct after the Firebase-to-Supabase migration, but it conflicts with FCM.

Before FCM is added, this script must be changed so valid messaging configuration survives a production archive.

The script must continue to guard against:

- wrong bundle identifiers
- hardcoded Flutter build name / build number
- obsolete Firebase database configuration

but must no longer treat valid FCM client configuration as a release error.

---

## 6. Legacy Firebase runtime inventory

Legacy Cloud Functions still visible in Firebase Console:

- `removeLessonsInHolidayRange`
- `repairBookedSlotsForRun`
- `deleteFriday3pmLessons`
- `deleteLessonsAfterDate`
- `deleteMidnightLessons`
- `rebuildCode0LessonsFrom20260119`
- `autoFillFutureLessons`
- `manualCreateRestoredLessons`
- `generateLessonsCustom`
- `cleanupLeftoverLessons`
- `autoArchiveStudents`
- `fixLessonTimes`

Most showed 0 requests during the observed 24-hour window.

`autoArchiveStudents` showed 1 request during the observed 24-hour window and appears to still have a scheduled invocation.

These functions are considered legacy cleanup targets, but they must not be deleted blindly.

Required cleanup sequence:

1. confirm archived Firebase data is complete
2. confirm current Flutter apps no longer call the functions
3. inspect scheduled triggers / Cloud Scheduler jobs
4. disable or delete active scheduler bindings
5. verify no required external caller remains
6. delete legacy Cloud Functions
7. observe Firebase / Supabase production for unexpected effects

The current production business logic lives in Supabase/PostgreSQL, so these Firebase functions must not be reused for v3.4 Push.

---

## 7. Firebase resources to keep

Keep:

- Firebase project `forestring1-1`
- teacher Android Firebase app registration
- teacher iOS Firebase app registration
- student app registrations for later student Push work
- Firebase Cloud Messaging HTTP v1
- FCM client configuration
- APNs authentication key connection
- Google Cloud identity needed for FCM HTTP v1

Do not use Firebase as:

- primary database
- authentication provider
- lesson scheduling runtime
- source of notification business rules

---

## 8. Legacy resources to remove after verification

Cleanup candidates:

- obsolete Firebase / Firestore application data after archive verification
- unused Realtime Database instances
- unused Firebase Authentication users
- unused Storage content
- legacy Cloud Functions
- obsolete scheduler triggers
- obsolete Firebase Hosting / Extensions if any
- old DB-specific rules / indexes that are no longer attached to active products

Deleting the Firebase project or current teacher/student Firebase app registrations is explicitly not part of cleanup.

---

## 9. Apple / APNs setup plan

For teacher iOS:

1. Apple Developer > Certificates, Identifiers & Profiles
2. select App ID `forestring.teacher.app`
3. enable Push Notifications
4. create an APNs authentication key
5. download the `.p8` private key once
6. record Key ID and Team ID
7. upload the APNs key to Firebase Console for Forestring teacher iOS
8. enable Push Notifications capability in Xcode
9. enable Background Modes > Remote notifications if required by the final messaging behavior
10. validate APNs token and FCM registration token on a physical iPhone

The same APNs signing key may later be reused for the student iOS app if appropriate for the same Apple Developer team.

---

## 10. Credential policy

Never commit:

- APNs `.p8` private key
- Firebase / Google service-account private key JSON
- FCM server private credentials
- access / refresh tokens

Safe client configuration is distinct from server credentials.

Client configuration may include values such as Firebase project/app identifiers required by the app SDK, while private server credentials must be stored in secret management.

For the planned Supabase Edge Function sender, server-side credentials must be stored as Supabase secrets.

---

## 11. Shared backend design after Phase 0

After FCM/APNs connectivity is proven, the Push backend is implemented in Supabase.

Planned entities:

### device_push_tokens

Maps authenticated Forestring profiles to concrete app installations and FCM registration tokens.

Expected responsibilities:

- profile ownership
- platform
- app role / app package
- token lifecycle
- enabled / invalidated state
- last-seen timestamp

### notification_preferences

Stores per-profile notification preferences.

Initial teacher version can use a simple global Push toggle and expand later by event type.

### notification_outbox

Durable queue generated only after a business event succeeds.

Push must not be created from a Flutter button tap alone.

### notification_deliveries

Tracks delivery attempts and error outcomes.

Required for:

- duplicate prevention
- invalid token cleanup
- retry analysis
- operational debugging

---

## 12. Core architectural rule

The correct event flow is:

```text
Flutter action / system automation
        ↓
Supabase RPC / database transaction succeeds
        ↓
domain event / audit event exists
        ↓
notification recipient resolution
        ↓
notification_outbox
        ↓
Supabase Edge Function sender
        ↓
FCM
        ↓
Android
or
FCM → APNs → iOS
```

Do not use:

```text
Flutter button tap → directly send Push
```

because a Push could be sent even if the underlying lesson mutation later fails.

---

## 13. Release-blocking notification failures

v3.4 must not ship when any of the following is reproducible:

- Push sent to the wrong profile
- old user receives Push after logout / account switch
- duplicate Push for one idempotent event
- required event silently produces no Push
- invalid token is retried indefinitely
- Push preference OFF is ignored
- production credentials are committed to source control

---

## 14. Phase 0 completion checklist

- [ ] teacher Android Firebase registration verified
- [ ] teacher iOS Firebase registration verified
- [x] FCM HTTP v1 enabled
- [ ] Apple Push Notifications capability enabled
- [ ] APNs auth key created
- [ ] APNs auth key uploaded to teacher Firebase iOS app
- [x] legacy Firebase runtime inventory started
- [ ] active scheduler bindings inspected
- [ ] legacy Cloud Functions removed after dependency check
- [ ] release cleanup script updated for FCM
- [ ] FlutterFire configuration regenerated
- [ ] `firebase_core` added
- [ ] `firebase_messaging` added
- [ ] Android physical-device FCM token verified
- [ ] iOS physical-device APNs + FCM token verified
- [ ] proceed to notification outbox / sender implementation
