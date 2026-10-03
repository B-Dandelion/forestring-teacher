import '../domain/lesson.dart';
import 'lesson_repository.dart';

class ReviewLessonRepository extends LessonRepository {
  ReviewLessonRepository({
    required this.teacherId,
    this.teacherName = '박지은',
  });

  final String teacherId;
  final String teacherName;

  List<Lesson> get _demoLessons {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    final specs = <({int dayOffset, int hour, int minute, String student, LessonType type})>[
      (dayOffset: 0, hour: 10, minute: 0, student: '김서윤', type: LessonType.regular),
      (dayOffset: 1, hour: 14, minute: 30, student: '이도윤', type: LessonType.regular),
      (dayOffset: 2, hour: 11, minute: 0, student: '최하린', type: LessonType.regular),
      (dayOffset: 4, hour: 16, minute: 0, student: '윤지호', type: LessonType.flex),
      (dayOffset: 7, hour: 10, minute: 0, student: '김서윤', type: LessonType.regular),
      (dayOffset: 8, hour: 14, minute: 30, student: '이도윤', type: LessonType.regular),
      (dayOffset: 9, hour: 11, minute: 0, student: '최하린', type: LessonType.regular),
      (dayOffset: 11, hour: 16, minute: 0, student: '윤지호', type: LessonType.makeup),
      (dayOffset: 14, hour: 10, minute: 0, student: '김서윤', type: LessonType.regular),
      (dayOffset: 16, hour: 11, minute: 0, student: '최하린', type: LessonType.regular),
    ];

    return [
      for (var index = 0; index < specs.length; index++)
        _lessonFromSpec(
          index: index,
          weekStart: weekStart,
          spec: specs[index],
        ),
    ];
  }

  Lesson _lessonFromSpec({
    required int index,
    required DateTime weekStart,
    required ({int dayOffset, int hour, int minute, String student, LessonType type}) spec,
  }) {
    final day = weekStart.add(Duration(days: spec.dayOffset));
    final startsAt = DateTime(
      day.year,
      day.month,
      day.day,
      spec.hour,
      spec.minute,
    );
    final durationMinutes = spec.type == LessonType.flex ? 45 : 30;

    return Lesson(
      id: 'review-lesson-$index',
      studentId: 'review-student-$index',
      teacherId: teacherId,
      startsAt: startsAt,
      endsAt: startsAt.add(Duration(minutes: durationMinutes)),
      durationMinutes: durationMinutes,
      type: spec.type,
      status: LessonStatus.scheduled,
      occurrenceAt: startsAt,
      studentName: spec.student,
      teacherName: teacherName,
    );
  }

  @override
  Future<List<Lesson>> fetchVisibleLessons({
    DateTime? from,
    DateTime? to,
    String? teacherId,
    String? studentId,
  }) async {
    return _demoLessons.where((lesson) {
      if (teacherId != null &&
          teacherId.isNotEmpty &&
          lesson.teacherId != teacherId) {
        return false;
      }
      if (studentId != null &&
          studentId.isNotEmpty &&
          lesson.studentId != studentId) {
        return false;
      }
      if (from != null && lesson.startsAt.isBefore(from)) {
        return false;
      }
      if (to != null && !lesson.startsAt.isBefore(to)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<List<LessonActivityRecord>> fetchLessonActivity({
    required Lesson lesson,
  }) async {
    final eventType = switch (lesson.type) {
      LessonType.makeup => 'MAKEUP_LESSON_CREATED',
      LessonType.flex => 'LESSON_RIGHT_BOOKED',
      LessonType.regular => 'LESSON_ORIGINAL_SCHEDULE',
    };

    return [
      LessonActivityRecord(
        eventType: eventType,
        eventAt: lesson.startsAt.subtract(const Duration(days: 2)),
        actorId: teacherId,
        actorName: teacherName,
        actorRole: 'teacher',
        details: {
          'lessonId': lesson.id,
          'startsAt': lesson.startsAt.toUtc().toIso8601String(),
          'endsAt': lesson.endsAt.toUtc().toIso8601String(),
          'durationMinutes': lesson.durationMinutes,
        },
      ),
    ];
  }

  @override
  Future<List<VisibleTeacher>> fetchVisibleTeachers() async {
    return [
      VisibleTeacher(
        id: teacherId,
        displayName: teacherName,
      ),
    ];
  }

  @override
  Future<Map<String, List<TeacherWorkHour>>> fetchVisibleWorkHours({
    String? teacherId,
  }) async {
    final id = teacherId ?? this.teacherId;
    if (id != this.teacherId) {
      return const {};
    }

    return {
      this.teacherId: [
        for (var weekday = DateTime.monday;
            weekday <= DateTime.friday;
            weekday++)
          TeacherWorkHour(
            teacherId: this.teacherId,
            weekday: weekday,
            startTime: '09:00:00',
            endTime: '19:00:00',
          ),
      ],
    };
  }

  @override
  Future<void> cancelLesson({
    required String lessonId,
    String? reason,
  }) {
    throw const LessonFailure('심사용 계정에서는 수업을 변경할 수 없습니다.');
  }

  @override
  Future<LessonMutationResult> updateLessonOnce({
    required String lessonId,
    required DateTime startsAt,
    required int durationMinutes,
    bool confirmWarnings = false,
    String? reason,
  }) {
    throw const LessonFailure('심사용 계정에서는 수업을 변경할 수 없습니다.');
  }
}
