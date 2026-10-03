import '../../features/branches/data/branch_repository.dart';
import '../../features/branches/domain/academy_branch.dart';
import '../../features/lessons/data/lesson_repository.dart';
import '../../features/lessons/domain/lesson.dart';

const managerQaBranchId = 'qa-manager-branch';
const managerQaProfileId = 'qa-manager-profile';

class ManagerQaBranchRepository extends BranchRepository {
  @override
  Future<List<AcademyBranch>> fetchBranches() async {
    return const [
      AcademyBranch(
        id: managerQaBranchId,
        name: '포레스트링 테스트점',
        isActive: true,
      ),
    ];
  }
}

class ManagerQaLessonRepository extends LessonRepository {
  ManagerQaLessonRepository() {
    _lessons = _buildLessons();
    _blockedPeriods = _buildBlockedPeriods();
  }

  static const _teachers = <VisibleTeacher>[
    VisibleTeacher(
      id: 'qa-teacher-1',
      displayName: '김하늘',
      branchId: managerQaBranchId,
    ),
    VisibleTeacher(
      id: 'qa-teacher-2',
      displayName: '박소연',
      branchId: managerQaBranchId,
    ),
    VisibleTeacher(
      id: 'qa-teacher-3',
      displayName: '이지우',
      branchId: managerQaBranchId,
    ),
    VisibleTeacher(
      id: 'qa-teacher-4',
      displayName: '최민서',
      branchId: managerQaBranchId,
    ),
  ];

  static const _students = <VisibleStudent>[
    VisibleStudent(
      id: 'qa-student-1',
      displayName: '강지아',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-2',
      displayName: '김도윤',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-3',
      displayName: '김서아',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-4',
      displayName: '문하린',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-5',
      displayName: '박유나',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-6',
      displayName: '서준호',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-7',
      displayName: '오채원',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-8',
      displayName: '윤서진',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-9',
      displayName: '이시우',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-10',
      displayName: '정다은',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-11',
      displayName: '최예린',
      branchId: managerQaBranchId,
      isActive: true,
    ),
    VisibleStudent(
      id: 'qa-student-12',
      displayName: '한지호',
      branchId: managerQaBranchId,
      isActive: true,
    ),
  ];

  late List<Lesson> _lessons;
  late List<TeacherBlockedPeriod> _blockedPeriods;

  @override
  Future<List<Lesson>> fetchVisibleLessons({
    DateTime? from,
    DateTime? to,
    String? teacherId,
    String? studentId,
  }) async {
    return _lessons.where((lesson) {
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
  Future<List<VisibleTeacher>> fetchVisibleTeachers() async {
    return List<VisibleTeacher>.from(_teachers);
  }

  @override
  Future<List<VisibleStudent>> fetchVisibleStudents() async {
    return List<VisibleStudent>.from(_students);
  }

  @override
  Future<List<TeacherBlockedPeriod>> fetchVisibleBlockedPeriods({
    DateTime? from,
    DateTime? to,
    String? teacherId,
  }) async {
    return _blockedPeriods.where((period) {
      if (teacherId != null &&
          teacherId.isNotEmpty &&
          period.teacherId != teacherId) {
        return false;
      }
      if (from != null && !period.endsAt.isAfter(from)) {
        return false;
      }
      if (to != null && !period.startsAt.isBefore(to)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<Map<String, List<TeacherWorkHour>>> fetchVisibleWorkHours({
    String? teacherId,
  }) async {
    final result = <String, List<TeacherWorkHour>>{};

    for (final teacher in _teachers) {
      if (teacherId != null &&
          teacherId.isNotEmpty &&
          teacher.id != teacherId) {
        continue;
      }

      result[teacher.id] = [
        for (var weekday = DateTime.monday;
            weekday <= DateTime.friday;
            weekday++)
          TeacherWorkHour(
            teacherId: teacher.id,
            weekday: weekday,
            startTime: '09:00:00',
            endTime: '20:00:00',
          ),
        if (teacher.id == 'qa-teacher-2' ||
            teacher.id == 'qa-teacher-4')
          TeacherWorkHour(
            teacherId: teacher.id,
            weekday: DateTime.saturday,
            startTime: '10:00:00',
            endTime: '17:00:00',
          ),
      ];
    }

    return result;
  }

  @override
  Future<int> fetchAvailableLessonRightCount({
    required String studentId,
    required String semesterId,
    required int durationMinutes,
  }) async {
    return 3;
  }

  @override
  Future<void> cancelLesson({
    required String lessonId,
    String? reason,
  }) async {
    final index = _lessons.indexWhere((lesson) => lesson.id == lessonId);
    if (index < 0) {
      throw const LessonFailure('QA 수업을 찾을 수 없습니다.');
    }

    final original = _lessons[index];
    _lessons[index] = _copyLesson(
      original,
      status: LessonStatus.canceled,
      canceledAt: DateTime.now(),
      cancellationReason: reason ?? 'QA 취소 테스트',
    );
  }

  @override
  Future<void> cancelStandaloneMakeupLesson({
    required String lessonId,
    String? reason,
  }) {
    return cancelLesson(
      lessonId: lessonId,
      reason: reason,
    );
  }

  @override
  Future<LessonMutationResult> createMakeupLesson({
    required String studentId,
    required String teacherId,
    required DateTime startsAt,
    required int durationMinutes,
    bool confirmWarnings = false,
    bool deductLessonRight = false,
    String? reason,
  }) async {
    final student = _students
        .where((item) => item.id == studentId)
        .firstOrNull;
    final teacher = _teachers
        .where((item) => item.id == teacherId)
        .firstOrNull;

    _lessons.add(
      Lesson(
        id: 'qa-makeup-${DateTime.now().microsecondsSinceEpoch}',
        studentId: studentId,
        teacherId: teacherId,
        startsAt: startsAt,
        endsAt: startsAt.add(Duration(minutes: durationMinutes)),
        durationMinutes: durationMinutes,
        type: LessonType.makeup,
        status: LessonStatus.scheduled,
        occurrenceAt: startsAt,
        lessonRightId:
            deductLessonRight ? 'qa-lesson-right' : null,
        branchId: managerQaBranchId,
        studentName: student?.displayName ?? 'QA 학생',
        teacherName: teacher?.displayName ?? 'QA 선생님',
      ),
    );

    return const LessonMutationResult(
      changed: true,
      requiresConfirmation: false,
    );
  }

  @override
  Future<LessonMutationResult> updateLessonOnce({
    required String lessonId,
    required DateTime startsAt,
    required int durationMinutes,
    bool confirmWarnings = false,
    String? reason,
  }) async {
    final index = _lessons.indexWhere((lesson) => lesson.id == lessonId);
    if (index < 0) {
      throw const LessonFailure('QA 수업을 찾을 수 없습니다.');
    }

    final original = _lessons[index];
    _lessons[index] = _copyLesson(
      original,
      startsAt: startsAt,
      endsAt: startsAt.add(Duration(minutes: durationMinutes)),
      durationMinutes: durationMinutes,
      rescheduledBy: managerQaProfileId,
    );

    return const LessonMutationResult(
      changed: true,
      requiresConfirmation: false,
    );
  }

  List<Lesson> _buildLessons() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );
    final result = <Lesson>[];
    var lessonIndex = 0;

    for (var week = -1; week <= 3; week++) {
      for (var teacherIndex = 0;
          teacherIndex < _teachers.length;
          teacherIndex++) {
        final teacher = _teachers[teacherIndex];

        for (var slot = 0; slot < 3; slot++) {
          final studentIndex =
              (teacherIndex * 3 + slot) % _students.length;
          final student = _students[studentIndex];
          final weekdayOffset =
              (teacherIndex + slot * 2) % DateTime.saturday;
          final day = weekStart.add(
            Duration(days: week * 7 + weekdayOffset),
          );
          final hour = 10 + teacherIndex * 2 + slot;
          final minute = slot.isOdd ? 30 : 0;
          final startsAt = DateTime(
            day.year,
            day.month,
            day.day,
            hour,
            minute,
          );
          final isSpecialWeek = week == 0;
          final type = isSpecialWeek && slot == 2
              ? LessonType.makeup
              : teacherIndex == 3 && slot == 1
                  ? LessonType.flex
                  : LessonType.regular;
          final durationMinutes =
              type == LessonType.flex ? 45 : 30;
          final rescheduledBy = isSpecialWeek && slot == 1
              ? managerQaProfileId
              : null;

          result.add(
            Lesson(
              id: 'qa-lesson-${lessonIndex++}',
              studentId: student.id,
              teacherId: teacher.id,
              startsAt: startsAt,
              endsAt:
                  startsAt.add(Duration(minutes: durationMinutes)),
              durationMinutes: durationMinutes,
              type: type,
              status: LessonStatus.scheduled,
              occurrenceAt: startsAt,
              rescheduledBy: rescheduledBy,
              lessonRightId:
                  type == LessonType.makeup ? 'qa-right-$lessonIndex' : null,
              branchId: managerQaBranchId,
              studentName: student.displayName,
              teacherName: teacher.displayName,
            ),
          );
        }
      }
    }

    return result;
  }

  List<TeacherBlockedPeriod> _buildBlockedPeriods() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );

    return [
      for (var index = 0; index < _teachers.length; index++)
        TeacherBlockedPeriod(
          id: 'qa-blocked-$index',
          teacherId: _teachers[index].id,
          startsAt: DateTime(
            weekStart.year,
            weekStart.month,
            weekStart.day + index,
            13,
          ),
          endsAt: DateTime(
            weekStart.year,
            weekStart.month,
            weekStart.day + index,
            14,
          ),
          createdAt: now,
          reason: index.isEven ? '개인 일정' : '외부 일정',
          teacherName: _teachers[index].displayName,
        ),
    ];
  }

  Lesson _copyLesson(
    Lesson source, {
    DateTime? startsAt,
    DateTime? endsAt,
    int? durationMinutes,
    LessonStatus? status,
    String? rescheduledBy,
    DateTime? canceledAt,
    String? cancellationReason,
  }) {
    return Lesson(
      id: source.id,
      studentId: source.studentId,
      teacherId: source.teacherId,
      startsAt: startsAt ?? source.startsAt,
      endsAt: endsAt ?? source.endsAt,
      durationMinutes: durationMinutes ?? source.durationMinutes,
      type: source.type,
      status: status ?? source.status,
      occurrenceAt: source.occurrenceAt,
      rescheduledBy: rescheduledBy ?? source.rescheduledBy,
      lessonRightId: source.lessonRightId,
      branchId: source.branchId,
      studentName: source.studentName,
      teacherName: source.teacherName,
      canceledAt: canceledAt ?? source.canceledAt,
      cancellationReason:
          cancellationReason ?? source.cancellationReason,
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
