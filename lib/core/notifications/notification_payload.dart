enum NotificationNavigationKind {
  lessonWeek,
  studentDetail;

  static NotificationNavigationKind? tryParse(String value) {
    return switch (value) {
      'lesson_week' => NotificationNavigationKind.lessonWeek,
      'student_detail' => NotificationNavigationKind.studentDetail,
      _ => null,
    };
  }
}

class NotificationNavigationIntent {
  const NotificationNavigationIntent({
    required this.schemaVersion,
    required this.notificationId,
    required this.eventKey,
    required this.targetKind,
    required this.targetId,
    required this.navigationKind,
    required this.recipientProfileId,
    required this.branchId,
    required this.teacherId,
    required this.studentId,
    required this.occurredAt,
    required this.data,
    this.startsAt,
    this.effectiveFrom,
  });

  static const Set<String> supportedEventKeys = {
    'student_assigned',
    'lesson_changed',
    'lesson_canceled',
    'makeup_created',
    'makeup_canceled',
    'flex_lesson_booked',
    'regular_schedule_changed',
    'student_teacher_assigned',
  };

  final int schemaVersion;
  final String notificationId;
  final String eventKey;
  final String targetKind;
  final String targetId;
  final NotificationNavigationKind navigationKind;
  final String recipientProfileId;
  final String branchId;
  final String teacherId;
  final String studentId;
  final DateTime occurredAt;
  final DateTime? startsAt;
  final DateTime? effectiveFrom;
  final Map<String, String> data;

  static NotificationNavigationIntent? tryParse(
    Map<String, dynamic> raw,
  ) {
    final data = <String, String>{};

    for (final entry in raw.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      data[entry.key] = value.toString();
    }

    String? read(String key) {
      final value = data[key]?.trim();
      if (value == null ||
          value.isEmpty ||
          value.toLowerCase() == 'null') {
        return null;
      }
      return value;
    }

    final schemaVersion = int.tryParse(read('schemaVersion') ?? '');
    final notificationId = read('notificationId');
    final eventKey = read('eventKey');
    final targetKind = read('targetKind');
    final targetId = read('targetId');
    final navigationValue = read('navigationKind');
    final recipientProfileId = read('recipientProfileId');
    final branchId = read('branchId');
    final teacherId = read('teacherId');
    final studentId = read('studentId');
    final occurredAt = DateTime.tryParse(read('occurredAt') ?? '');

    if (schemaVersion != 1 ||
        notificationId == null ||
        eventKey == null ||
        !supportedEventKeys.contains(eventKey) ||
        targetKind == null ||
        targetId == null ||
        navigationValue == null ||
        recipientProfileId == null ||
        branchId == null ||
        teacherId == null ||
        studentId == null ||
        occurredAt == null) {
      return null;
    }

    final navigationKind =
        NotificationNavigationKind.tryParse(navigationValue);
    if (navigationKind == null) {
      return null;
    }

    return NotificationNavigationIntent(
      schemaVersion: schemaVersion,
      notificationId: notificationId,
      eventKey: eventKey,
      targetKind: targetKind,
      targetId: targetId,
      navigationKind: navigationKind,
      recipientProfileId: recipientProfileId,
      branchId: branchId,
      teacherId: teacherId,
      studentId: studentId,
      occurredAt: occurredAt,
      startsAt: DateTime.tryParse(read('startsAt') ?? ''),
      effectiveFrom: DateTime.tryParse(read('effectiveFrom') ?? ''),
      data: Map.unmodifiable(data),
    );
  }
}
