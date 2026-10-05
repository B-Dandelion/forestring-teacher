import 'package:flutter_test/flutter_test.dart';
import 'package:forestring_teacher_2/core/notifications/notification_destination_resolver.dart';
import 'package:forestring_teacher_2/core/notifications/notification_payload.dart';
import 'package:forestring_teacher_2/features/auth/domain/current_profile.dart';

Map<String, dynamic> _basePayload({
  String eventKey = 'lesson_changed',
  String targetKind = 'lesson',
  String targetId = 'lesson-1',
  String navigationKind = 'lesson_week',
}) {
  return {
    'schemaVersion': '1',
    'notificationId': 'notification-1',
    'eventKey': eventKey,
    'targetKind': targetKind,
    'targetId': targetId,
    'navigationKind': navigationKind,
    'recipientProfileId': 'teacher-1',
    'branchId': 'branch-1',
    'teacherId': 'teacher-1',
    'studentId': 'student-1',
    'occurredAt': '2026-10-05T07:30:00Z',
    'startsAt': '2026-10-06T16:00:00+09:00',
  };
}

void main() {
  group('NotificationNavigationIntent', () {
    test('parses the v1 lesson payload', () {
      final intent = NotificationNavigationIntent.tryParse(
        _basePayload(),
      );

      expect(intent, isNotNull);
      expect(
        intent!.navigationKind,
        NotificationNavigationKind.lessonWeek,
      );
      expect(intent.targetId, 'lesson-1');
      expect(intent.startsAt, isNotNull);
    });

    test('parses a student detail payload', () {
      final intent = NotificationNavigationIntent.tryParse(
        _basePayload(
          eventKey: 'regular_schedule_changed',
          targetKind: 'regularSchedule',
          targetId: 'slot-1',
          navigationKind: 'student_detail',
        ),
      );

      expect(intent, isNotNull);
      expect(
        intent!.navigationKind,
        NotificationNavigationKind.studentDetail,
      );
    });

    test('rejects unsupported schema versions', () {
      final payload = _basePayload();
      payload['schemaVersion'] = '2';

      expect(
        NotificationNavigationIntent.tryParse(payload),
        isNull,
      );
    });

    test('does not support regular schedule end push', () {
      final payload = _basePayload(
        eventKey: 'regular_schedule_ended',
        targetKind: 'regularSchedule',
        targetId: 'slot-1',
        navigationKind: 'student_detail',
      );

      expect(
        NotificationNavigationIntent.tryParse(payload),
        isNull,
      );
    });
  });

  group('NotificationDestinationResolver', () {
    const teacher = CurrentProfile(
      id: 'teacher-1',
      displayName: '선생님',
      role: AppRole.teacher,
      branchId: 'branch-1',
      isActive: true,
    );

    const manager = CurrentProfile(
      id: 'manager-1',
      displayName: '지점장',
      role: AppRole.manager,
      branchId: 'branch-1',
      isActive: true,
    );

    test('teacher lesson notification resolves to teacher week', () {
      final intent = NotificationNavigationIntent.tryParse(
        _basePayload(),
      )!;

      final destination = NotificationDestinationResolver.resolve(
        profile: teacher,
        intent: intent,
      );

      expect(
        destination?.kind,
        NotificationDestinationKind.teacherWeek,
      );
    });

    test('manager rejects a notification from another branch', () {
      final payload = _basePayload();
      payload['recipientProfileId'] = 'manager-1';
      payload['teacherId'] = 'teacher-2';
      payload['branchId'] = 'branch-2';

      final intent = NotificationNavigationIntent.tryParse(
        payload,
      )!;

      expect(
        NotificationDestinationResolver.resolve(
          profile: manager,
          intent: intent,
        ),
        isNull,
      );
    });
  });
}
