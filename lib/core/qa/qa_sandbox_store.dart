import 'package:flutter/foundation.dart';

import '../../features/branches/domain/academy_branch.dart';
import '../../features/lessons/data/lesson_repository.dart';
import '../../features/lessons/domain/lesson.dart';
import '../../features/semesters/domain/managed_semester.dart';
import '../../features/students/data/student_management_repository.dart';
import '../../features/students/data/student_regular_schedule_repository.dart';
import '../../features/teachers/data/teacher_repository.dart';

const qaManagerBranchId = 'qa-manager-branch';
const qaManagerProfileId = 'qa-manager-profile';

/// Shared in-memory state for the local interactive QA sandbox.
///
/// This store deliberately uses the same domain/view models as the production
/// app, but never talks to Supabase. All QA repositories receive the same
/// instance so mutations are visible across screens during the same session.
class QaSandboxStore extends ChangeNotifier {
  QaSandboxStore() {
    reset();
  }

  late List<AcademyBranch> branches;
  late List<ManagedStudent> students;
  late List<ManagedTeacher> teachers;
  late List<Lesson> lessons;
  late List<ManagedTeacherBlockedPeriod> blockedPeriods;
  late List<ManagedSemester> semesters;
  late Map<String, List<ManagedRegularSchedule>> regularSchedules;
  late Map<String, String> nextStudentTypes;
  late Map<String, int> nextFlexRightCounts;
  late Map<String, int> nextFlexDurations;
  late Map<String, int> nextRegularScheduleCounts;
  late Map<String, String> pins;

  void reset() {
    branches = _buildBranches();
    students = _buildStudents();
    teachers = _buildTeachers(students);
    lessons = _buildLessons(students, teachers);
    blockedPeriods = _buildBlockedPeriods(teachers);
    semesters = _buildSemesters();
    regularSchedules = _buildRegularSchedules(students);
    nextStudentTypes = {
      for (final student in students) student.id: student.studentType,
    };
    nextFlexRightCounts = {
      for (final student in students)
        if (student.isFlex)
          student.id: student.flexBaseRightCount ?? 4,
    };
    nextFlexDurations = {
      for (final student in students)
        if (student.isFlex)
          student.id: student.flexDurationMinutes ?? 30,
    };
    nextRegularScheduleCounts = {
      for (final student in students)
        student.id: student.isRegular
            ? (regularSchedules[student.id]?.length ?? 0)
            : 0,
    };
    pins = {
      for (final student in students) student.id: '1234',
      for (final teacher in teachers) teacher.id: '1234',
      qaManagerProfileId: '1234',
    };
    notifyListeners();
  }

  List<VisibleStudent> get visibleStudents => students
      .map(
        (student) => VisibleStudent(
          id: student.id,
          displayName: student.displayName,
          branchId: student.branchId,
          isActive: student.isActive,
        ),
      )
      .toList();

  List<VisibleTeacher> get visibleTeachers => teachers
      .where((teacher) => teacher.isActive)
      .map(
        (teacher) => VisibleTeacher(
          id: teacher.id,
          displayName: teacher.displayName,
          branchId: teacher.branchId,
        ),
      )
      .toList();

  Map<String, List<TeacherWorkHour>> get visibleWorkHours {
    return {
      for (final teacher in teachers)
        teacher.id: teacher.workHours
            .map(
              (hour) => TeacherWorkHour(
                teacherId: teacher.id,
                weekday: hour.weekday,
                startTime: _withSeconds(hour.startTime),
                endTime: _withSeconds(hour.endTime),
              ),
            )
            .toList(),
    };
  }

  ManagedStudent? studentById(String id) {
    for (final student in students) {
      if (student.id == id) return student;
    }
    return null;
  }

  ManagedTeacher? teacherById(String id) {
    for (final teacher in teachers) {
      if (teacher.id == id) return teacher;
    }
    return null;
  }

  void addStudent(ManagedStudent student) {
    students.add(student);
    pins[student.id] = '1234';
    _rebuildTeacherCounts();
    notifyListeners();
  }

  void updateStudent(ManagedStudent next) {
    final index = students.indexWhere((student) => student.id == next.id);
    if (index < 0) return;
    students[index] = next;
    _syncLessonNames();
    _rebuildTeacherCounts();
    notifyListeners();
  }

  void assignStudentTeacher({
    required String studentId,
    required String teacherId,
  }) {
    final student = studentById(studentId);
    final teacher = teacherById(teacherId);
    if (student == null || teacher == null) return;
    updateStudent(
      _copyStudent(
        student,
        teacherId: teacher.id,
        teacherName: teacher.displayName,
        replaceTeacherName: true,
      ),
    );
  }

  void addRegularSchedule({
    required String studentId,
    required ManagedRegularSchedule schedule,
  }) {
    regularSchedules.putIfAbsent(studentId, () => []).add(schedule);
    notifyListeners();
  }

  void replaceRegularSchedule({
    required String studentId,
    required ManagedRegularSchedule schedule,
  }) {
    final schedules = regularSchedules.putIfAbsent(studentId, () => []);
    final index =
        schedules.indexWhere((item) => item.slotId == schedule.slotId);
    if (index < 0) {
      schedules.add(schedule);
    } else {
      schedules[index] = schedule;
    }
    notifyListeners();
  }

  void removeRegularSchedule(String scheduleSlotId) {
    for (final schedules in regularSchedules.values) {
      schedules.removeWhere((item) => item.slotId == scheduleSlotId);
    }
    notifyListeners();
  }

  void addTeacher(ManagedTeacher teacher) {
    teachers.add(teacher);
    pins[teacher.id] = '1234';
    notifyListeners();
  }

  void updateTeacher(ManagedTeacher next) {
    final index = teachers.indexWhere((teacher) => teacher.id == next.id);
    if (index < 0) return;
    teachers[index] = next;
    students = students
        .map(
          (student) => student.teacherId == next.id
              ? _copyStudent(
                  student,
                  teacherName: next.displayName,
                  replaceTeacherName: true,
                )
              : student,
        )
        .toList();
    _syncLessonNames();
    notifyListeners();
  }

  void savePin(String profileId, String pin) {
    pins[profileId] = pin;
    notifyListeners();
  }

  void saveNextSemesterPlan({
    required String studentId,
    required String studentType,
    int? flexRightCount,
    int? flexDurationMinutes,
    int regularScheduleCount = 0,
  }) {
    nextStudentTypes[studentId] = studentType;
    nextRegularScheduleCounts[studentId] = regularScheduleCount;
    if (studentType == 'flex') {
      nextFlexRightCounts[studentId] = flexRightCount ?? 4;
      nextFlexDurations[studentId] = flexDurationMinutes ?? 30;
    } else {
      nextFlexRightCounts.remove(studentId);
      nextFlexDurations.remove(studentId);
    }
    notifyListeners();
  }

  void cancelLesson(String lessonId, {String? reason}) {
    final index = lessons.indexWhere((lesson) => lesson.id == lessonId);
    if (index < 0) return;
    final lesson = lessons[index];
    lessons[index] = _copyLesson(
      lesson,
      status: LessonStatus.canceled,
      canceledAt: DateTime.now(),
      cancellationReason: reason ?? 'QA 취소 테스트',
    );
    notifyListeners();
  }

  void updateLessonOnce({
    required String lessonId,
    required DateTime startsAt,
    required int durationMinutes,
  }) {
    final index = lessons.indexWhere((lesson) => lesson.id == lessonId);
    if (index < 0) return;
    lessons[index] = _copyLesson(
      lessons[index],
      startsAt: startsAt,
      endsAt: startsAt.add(Duration(minutes: durationMinutes)),
      durationMinutes: durationMinutes,
      rescheduledBy: qaManagerProfileId,
    );
    notifyListeners();
  }

  Lesson createMakeupLesson({
    required String studentId,
    required String teacherId,
    required DateTime startsAt,
    required int durationMinutes,
    required bool deductLessonRight,
  }) {
    final student = studentById(studentId);
    final teacher = teacherById(teacherId);
    final lesson = Lesson(
      id: 'qa-makeup-${DateTime.now().microsecondsSinceEpoch}',
      studentId: studentId,
      teacherId: teacherId,
      startsAt: startsAt,
      endsAt: startsAt.add(Duration(minutes: durationMinutes)),
      durationMinutes: durationMinutes,
      type: LessonType.makeup,
      status: LessonStatus.scheduled,
      occurrenceAt: startsAt,
      lessonRightId: deductLessonRight ? 'qa-lesson-right' : null,
      branchId: qaManagerBranchId,
      studentName: student?.displayName ?? 'QA 학생',
      teacherName: teacher?.displayName ?? 'QA 선생님',
    );
    lessons.add(lesson);
    notifyListeners();
    return lesson;
  }

  void replaceTeacherWorkHours(
    String teacherId,
    List<ManagedTeacherWorkHour> workHours,
  ) {
    final teacher = teacherById(teacherId);
    if (teacher == null) return;
    updateTeacher(
      ManagedTeacher(
        id: teacher.id,
        displayName: teacher.displayName,
        branchId: teacher.branchId,
        branchName: teacher.branchName,
        profileIsActive: teacher.profileIsActive,
        workHours: List.unmodifiable(workHours),
        assignedStudentCount: teacher.assignedStudentCount,
        withdrawalDate: teacher.withdrawalDate,
      ),
    );
  }

  void saveBlockedPeriod(ManagedTeacherBlockedPeriod period) {
    final index =
        blockedPeriods.indexWhere((current) => current.id == period.id);
    if (index < 0) {
      blockedPeriods.add(period);
    } else {
      blockedPeriods[index] = period;
    }
    notifyListeners();
  }

  void deleteBlockedPeriod(String id) {
    blockedPeriods.removeWhere((period) => period.id == id);
    notifyListeners();
  }

  void _syncLessonNames() {
    lessons = lessons
        .map(
          (lesson) => _copyLesson(
            lesson,
            studentName: studentById(lesson.studentId)?.displayName,
            teacherName: teacherById(lesson.teacherId)?.displayName,
            replaceNames: true,
          ),
        )
        .toList();
  }

  void _rebuildTeacherCounts() {
    teachers = teachers
        .map(
          (teacher) => ManagedTeacher(
            id: teacher.id,
            displayName: teacher.displayName,
            branchId: teacher.branchId,
            branchName: teacher.branchName,
            profileIsActive: teacher.profileIsActive,
            workHours: teacher.workHours,
            assignedStudentCount: students
                .where(
                  (student) =>
                      student.isActive && student.teacherId == teacher.id,
                )
                .length,
            withdrawalDate: teacher.withdrawalDate,
          ),
        )
        .toList();
  }

  static List<AcademyBranch> _buildBranches() {
    return const [
      AcademyBranch(
        id: qaManagerBranchId,
        name: '포레스트링 테스트점',
        isActive: true,
      ),
    ];
  }

  static List<ManagedStudent> _buildStudents() {
    const names = [
      '강지아',
      '김도윤',
      '김서아',
      '문하린',
      '박유나',
      '서준호',
      '오채원',
      '윤서진',
      '이시우',
      '정다은',
      '최예린',
      '한지호',
    ];
    const teachers = [
      ('qa-teacher-1', '김하늘'),
      ('qa-teacher-2', '박소연'),
      ('qa-teacher-3', '이지우'),
      ('qa-teacher-4', '최민서'),
    ];

    return [
      for (var i = 0; i < names.length; i++)
        ManagedStudent(
          id: 'qa-student-${i + 1}',
          displayName: names[i],
          branchId: qaManagerBranchId,
          branchName: '포레스트링 테스트점',
          studentType: i == 3 || i == 7 || i == 10 ? 'flex' : 'regular',
          status: 'active',
          profileIsActive: true,
          teacherId: teachers[i % teachers.length].$1,
          teacherName: teachers[i % teachers.length].$2,
          withdrawalDate: i == 9
              ? DateTime.now().add(const Duration(days: 18))
              : null,
          flexBaseRightCount: i == 3 || i == 7 || i == 10 ? 4 : null,
          flexDurationMinutes: i == 3 || i == 7 || i == 10 ? 45 : null,
        ),
    ];
  }

  static List<ManagedTeacher> _buildTeachers(
    List<ManagedStudent> students,
  ) {
    const names = ['김하늘', '박소연', '이지우', '최민서'];
    return [
      for (var i = 0; i < names.length; i++)
        ManagedTeacher(
          id: 'qa-teacher-${i + 1}',
          displayName: names[i],
          branchId: qaManagerBranchId,
          branchName: '포레스트링 테스트점',
          profileIsActive: true,
          workHours: [
            for (var weekday = DateTime.monday;
                weekday <= DateTime.friday;
                weekday++)
              ManagedTeacherWorkHour(
                weekday: weekday,
                startTime: '09:00',
                endTime: '20:00',
              ),
            if (i == 1 || i == 3)
              const ManagedTeacherWorkHour(
                weekday: DateTime.saturday,
                startTime: '10:00',
                endTime: '17:00',
              ),
          ],
          assignedStudentCount: students
              .where(
                (student) =>
                    student.isActive &&
                    student.teacherId == 'qa-teacher-${i + 1}',
              )
              .length,
        ),
    ];
  }

  static List<Lesson> _buildLessons(
    List<ManagedStudent> students,
    List<ManagedTeacher> teachers,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );
    final result = <Lesson>[];
    var lessonIndex = 0;

    for (var week = -2; week <= 4; week++) {
      for (var teacherIndex = 0;
          teacherIndex < teachers.length;
          teacherIndex++) {
        final teacher = teachers[teacherIndex];

        for (var slot = 0; slot < 3; slot++) {
          final studentIndex =
              (teacherIndex * 3 + slot) % students.length;
          final student = students[studentIndex];
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
          final currentWeek = week == 0;
          final type = currentWeek && slot == 2
              ? LessonType.makeup
              : student.isFlex
                  ? LessonType.flex
                  : LessonType.regular;
          final durationMinutes = student.isFlex ? 45 : 30;

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
              rescheduledBy:
                  currentWeek && slot == 1 ? qaManagerProfileId : null,
              lessonRightId: type == LessonType.makeup
                  ? 'qa-right-$lessonIndex'
                  : null,
              branchId: qaManagerBranchId,
              studentName: student.displayName,
              teacherName: teacher.displayName,
            ),
          );
        }
      }
    }

    return result;
  }

  static List<ManagedTeacherBlockedPeriod> _buildBlockedPeriods(
    List<ManagedTeacher> teachers,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );

    return [
      for (var i = 0; i < teachers.length; i++)
        ManagedTeacherBlockedPeriod(
          id: 'qa-blocked-$i',
          teacherId: teachers[i].id,
          startsAt: DateTime(
            weekStart.year,
            weekStart.month,
            weekStart.day + i,
            13,
          ),
          endsAt: DateTime(
            weekStart.year,
            weekStart.month,
            weekStart.day + i,
            14,
          ),
          createdAt: now,
          reason: i.isEven ? '개인 일정' : '외부 일정',
        ),
    ];
  }

  static Map<String, List<ManagedRegularSchedule>>
      _buildRegularSchedules(List<ManagedStudent> students) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return {
      for (var i = 0; i < students.length; i++)
        if (students[i].isRegular)
          students[i].id: [
            ManagedRegularSchedule(
              slotId: 'qa-regular-slot-${i + 1}',
              teacherId: students[i].teacherId ?? 'qa-teacher-1',
              teacherName: students[i].teacherName ?? '김하늘',
              weekday: (i % 5) + 1,
              startMinutes: 16 * 60 + (i % 4) * 30,
              durationMinutes: 30,
              slotStartsOn: DateTime(today.year, today.month, 1),
              effectiveFrom: DateTime(today.year, today.month, 1),
              hasFutureVersion: i == 1,
              nextVersionDate: i == 1
                  ? DateTime(today.year, today.month + 1, 1)
                  : null,
            ),
          ],
    };
  }

  static List<ManagedSemester> _buildSemesters() {
    final now = DateTime.now();
    final currentStart = DateTime(now.year, now.month, 1);
    final currentEnd = DateTime(now.year, now.month + 1, 0);
    final nextStart = DateTime(now.year, now.month + 1, 1);
    final nextEnd = DateTime(now.year, now.month + 2, 0);
    final previousStart = DateTime(now.year, now.month - 1, 1);
    final previousEnd = DateTime(now.year, now.month, 0);

    String code(DateTime date) =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}';

    return [
      ManagedSemester(
        id: 'qa-semester-previous',
        code: code(previousStart),
        startsOn: previousStart,
        endsOn: previousEnd,
        branchOverrides: const [],
      ),
      ManagedSemester(
        id: 'qa-semester-current',
        code: code(currentStart),
        startsOn: currentStart,
        endsOn: currentEnd,
        branchOverrides: const [],
      ),
      ManagedSemester(
        id: 'qa-semester-next',
        code: code(nextStart),
        startsOn: nextStart,
        endsOn: nextEnd,
        branchOverrides: const [],
      ),
    ];
  }

  static ManagedStudent _copyStudent(
    ManagedStudent source, {
    String? displayName,
    String? status,
    bool? profileIsActive,
    String? teacherId,
    String? teacherName,
    bool replaceTeacherName = false,
    DateTime? withdrawalDate,
    bool replaceWithdrawalDate = false,
    int? flexBaseRightCount,
  }) {
    return ManagedStudent(
      id: source.id,
      displayName: displayName ?? source.displayName,
      branchId: source.branchId,
      branchName: source.branchName,
      studentType: source.studentType,
      status: status ?? source.status,
      profileIsActive: profileIsActive ?? source.profileIsActive,
      teacherId: teacherId ?? source.teacherId,
      teacherName:
          replaceTeacherName ? teacherName : source.teacherName,
      withdrawalDate: replaceWithdrawalDate
          ? withdrawalDate
          : source.withdrawalDate,
      flexBaseRightCount:
          flexBaseRightCount ?? source.flexBaseRightCount,
      flexDurationMinutes: source.flexDurationMinutes,
    );
  }

  static Lesson _copyLesson(
    Lesson source, {
    DateTime? startsAt,
    DateTime? endsAt,
    int? durationMinutes,
    LessonStatus? status,
    String? rescheduledBy,
    DateTime? canceledAt,
    String? cancellationReason,
    String? studentName,
    String? teacherName,
    bool replaceNames = false,
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
      studentName:
          replaceNames ? studentName : source.studentName,
      teacherName:
          replaceNames ? teacherName : source.teacherName,
      canceledAt: canceledAt ?? source.canceledAt,
      cancellationReason:
          cancellationReason ?? source.cancellationReason,
    );
  }

  static String _withSeconds(String value) {
    return value.split(':').length == 2 ? '$value:00' : value;
  }
}
