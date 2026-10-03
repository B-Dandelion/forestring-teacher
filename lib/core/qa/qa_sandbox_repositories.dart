import '../../features/branches/data/branch_repository.dart';
import '../../features/branches/domain/academy_branch.dart';
import '../../features/lessons/data/lesson_repository.dart';
import '../../features/lessons/domain/lesson.dart';
import '../../features/semesters/data/semester_repository.dart';
import '../../features/semesters/domain/managed_semester.dart';
import '../../features/students/data/student_admin_repository.dart';
import '../../features/students/data/student_management_repository.dart';
import '../../features/students/data/student_next_semester_type_repository.dart';
import '../../features/students/data/student_regular_schedule_repository.dart';
import '../../features/students/data/student_teacher_management_repository.dart';
import '../../features/teachers/data/teacher_repository.dart';
import 'qa_sandbox_store.dart';

class QaBranchRepository extends BranchRepository {
  QaBranchRepository(this.store);

  final QaSandboxStore store;

  @override
  Future<List<AcademyBranch>> fetchBranches() async {
    return List<AcademyBranch>.from(store.branches);
  }
}

class QaSemesterRepository extends SemesterRepository {
  QaSemesterRepository(this.store);

  final QaSandboxStore store;

  @override
  Future<List<ManagedSemester>> fetchSemesters() async {
    return List<ManagedSemester>.from(store.semesters);
  }
}

class QaLessonRepository extends LessonRepository {
  QaLessonRepository(this.store);

  final QaSandboxStore store;

  @override
  Future<List<Lesson>> fetchVisibleLessons({
    DateTime? from,
    DateTime? to,
    String? teacherId,
    String? studentId,
  }) async {
    return store.lessons.where((lesson) {
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
    return store.visibleTeachers;
  }

  @override
  Future<List<VisibleStudent>> fetchVisibleStudents() async {
    return store.visibleStudents;
  }

  @override
  Future<List<TeacherBlockedPeriod>> fetchVisibleBlockedPeriods({
    DateTime? from,
    DateTime? to,
    String? teacherId,
  }) async {
    return store.blockedPeriods.where((period) {
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
    }).map((period) {
      final teacher = store.teacherById(period.teacherId);
      return TeacherBlockedPeriod(
        id: period.id,
        teacherId: period.teacherId,
        startsAt: period.startsAt,
        endsAt: period.endsAt,
        createdAt: period.createdAt,
        reason: period.reason,
        teacherName: teacher?.displayName,
      );
    }).toList();
  }

  @override
  Future<Map<String, List<TeacherWorkHour>>> fetchVisibleWorkHours({
    String? teacherId,
  }) async {
    final all = store.visibleWorkHours;
    if (teacherId == null || teacherId.isEmpty) {
      return all;
    }
    final hours = all[teacherId];
    if (hours == null) return const {};
    return {teacherId: hours};
  }

  @override
  Future<int> fetchAvailableLessonRightCount({
    required String studentId,
    required String semesterId,
    required int durationMinutes,
  }) async {
    final student = store.studentById(studentId);
    if (student == null || !student.isActive) return 0;
    return student.isFlex ? (student.flexBaseRightCount ?? 0) : 3;
  }

  @override
  Future<void> cancelLesson({
    required String lessonId,
    String? reason,
  }) async {
    if (!store.lessons.any((lesson) => lesson.id == lessonId)) {
      throw const LessonFailure('QA 수업을 찾을 수 없습니다.');
    }
    store.cancelLesson(lessonId, reason: reason);
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
    if (store.studentById(studentId) == null) {
      throw const LessonFailure('QA 학생을 찾을 수 없습니다.');
    }
    if (store.teacherById(teacherId) == null) {
      throw const LessonFailure('QA 선생님을 찾을 수 없습니다.');
    }

    store.createMakeupLesson(
      studentId: studentId,
      teacherId: teacherId,
      startsAt: startsAt,
      durationMinutes: durationMinutes,
      deductLessonRight: deductLessonRight,
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
    if (!store.lessons.any((lesson) => lesson.id == lessonId)) {
      throw const LessonFailure('QA 수업을 찾을 수 없습니다.');
    }

    store.updateLessonOnce(
      lessonId: lessonId,
      startsAt: startsAt,
      durationMinutes: durationMinutes,
    );

    return const LessonMutationResult(
      changed: true,
      requiresConfirmation: false,
    );
  }
}

class QaStudentManagementRepository extends StudentManagementRepository {
  QaStudentManagementRepository(this.store);

  final QaSandboxStore store;

  @override
  Future<List<ManagedStudent>> fetchStudents({
    String? branchId,
  }) async {
    return store.students
        .where(
          (student) =>
              branchId == null || student.branchId == branchId,
        )
        .toList();
  }

  @override
  Future<void> updateStudentName({
    required String studentId,
    required String name,
  }) async {
    final student = _requireStudent(studentId);
    store.updateStudent(
      _copyStudent(
        student,
        displayName: name.trim(),
      ),
    );
  }

  @override
  Future<void> resetStudentPin({
    required String studentId,
    required String pin,
  }) async {
    _requireStudent(studentId);
    store.savePin(studentId, pin);
  }

  @override
  Future<FlexRightCountChangeResult> changeFlexBaseRightCount({
    required String studentId,
    required int newBaseRightCount,
  }) async {
    final student = _requireStudent(studentId);
    if (!student.isFlex) {
      throw const StudentManagementFailure(
        'QA 정규 학생은 자율 수업권 개수를 변경할 수 없습니다.',
      );
    }

    final oldCount = student.flexBaseRightCount ?? 0;
    store.updateStudent(
      _copyStudent(
        student,
        flexBaseRightCount: newBaseRightCount,
      ),
    );

    return FlexRightCountChangeResult(
      changed: oldCount != newBaseRightCount,
      oldBaseRightCount: oldCount,
      newBaseRightCount: newBaseRightCount,
      insertedCount:
          newBaseRightCount > oldCount ? newBaseRightCount - oldCount : 0,
      removedCount:
          oldCount > newBaseRightCount ? oldCount - newBaseRightCount : 0,
      newCancellationLimit: newBaseRightCount,
      newCarryoverCap: newBaseRightCount,
    );
  }

  @override
  Future<StudentWithdrawalResult> scheduleWithdrawal({
    required String studentId,
    required DateTime withdrawalDate,
  }) async {
    final student = _requireStudent(studentId);
    store.updateStudent(
      _copyStudent(
        student,
        withdrawalDate: withdrawalDate,
        replaceWithdrawalDate: true,
      ),
    );
    return StudentWithdrawalResult(
      withdrawalDate: withdrawalDate,
      finalized: false,
    );
  }

  @override
  Future<StudentWithdrawalResult> finalizeWithdrawal({
    required String studentId,
  }) async {
    final student = _requireStudent(studentId);
    final withdrawalDate = student.withdrawalDate ?? DateTime.now();
    store.updateStudent(
      _copyStudent(
        student,
        status: 'withdrawn',
        profileIsActive: false,
        withdrawalDate: withdrawalDate,
        replaceWithdrawalDate: true,
      ),
    );
    return StudentWithdrawalResult(
      withdrawalDate: withdrawalDate,
      finalized: true,
      deletedLessonCount: 0,
      revokedRightCount: student.flexBaseRightCount ?? 0,
    );
  }

  @override
  Future<void> cancelWithdrawal({
    required String studentId,
  }) async {
    final student = _requireStudent(studentId);
    store.updateStudent(
      _copyStudent(
        student,
        withdrawalDate: null,
        replaceWithdrawalDate: true,
      ),
    );
  }

  ManagedStudent _requireStudent(String id) {
    final student = store.studentById(id);
    if (student == null) {
      throw const StudentManagementFailure(
        'QA 수강생을 찾을 수 없습니다.',
      );
    }
    return student;
  }

  ManagedStudent _copyStudent(
    ManagedStudent source, {
    String? displayName,
    String? status,
    bool? profileIsActive,
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
      teacherId: source.teacherId,
      teacherName: source.teacherName,
      withdrawalDate: replaceWithdrawalDate
          ? withdrawalDate
          : source.withdrawalDate,
      flexBaseRightCount:
          flexBaseRightCount ?? source.flexBaseRightCount,
      flexDurationMinutes: source.flexDurationMinutes,
    );
  }
}

class QaTeacherRepository extends TeacherRepository {
  QaTeacherRepository(this.store);

  final QaSandboxStore store;

  @override
  Future<List<ManagedTeacher>> fetchTeachers({
    String? branchId,
  }) async {
    return store.teachers
        .where(
          (teacher) =>
              branchId == null || teacher.branchId == branchId,
        )
        .toList();
  }

  @override
  Future<List<AssignedStudentSummary>> fetchAssignedStudents(
    String teacherId,
  ) async {
    final now = DateTime.now();
    return store.students
        .where((student) => student.teacherId == teacherId)
        .map(
          (student) => AssignedStudentSummary(
            id: student.id,
            displayName: student.displayName,
            studentType: student.studentType,
            assignmentStartsOn:
                DateTime(now.year, now.month - 2, 1),
            isActive: student.isActive,
            regularSchedules: student.isRegular
                ? const [
                    AssignedStudentRegularSchedule(
                      weekday: DateTime.thursday,
                      startTime: '17:00',
                      durationMinutes: 30,
                    ),
                  ]
                : const [],
            flexBaseRightCount: student.flexBaseRightCount,
          ),
        )
        .toList();
  }

  @override
  Future<CreatedTeacher> createTeacher({
    required String name,
    required String pin,
    required String branchId,
    required List<TeacherWorkHourInput> workHours,
  }) async {
    final id = 'qa-teacher-${DateTime.now().microsecondsSinceEpoch}';
    final teacher = ManagedTeacher(
      id: id,
      displayName: name.trim(),
      branchId: branchId,
      branchName: _branchName(branchId),
      profileIsActive: true,
      workHours: workHours
          .map(
            (hour) => ManagedTeacherWorkHour(
              weekday: hour.weekday,
              startTime: hour.startTime,
              endTime: hour.endTime,
            ),
          )
          .toList(),
      assignedStudentCount: 0,
    );
    store.addTeacher(teacher);
    store.savePin(id, pin);
    return CreatedTeacher(
      id: id,
      displayName: teacher.displayName,
    );
  }

  @override
  Future<void> updateTeacherName({
    required String teacherId,
    required String name,
  }) async {
    final teacher = _requireTeacher(teacherId);
    store.updateTeacher(
      _copyTeacher(
        teacher,
        displayName: name.trim(),
      ),
    );
  }

  @override
  Future<void> resetTeacherPin({
    required String teacherId,
    required String pin,
  }) async {
    _requireTeacher(teacherId);
    store.savePin(teacherId, pin);
  }

  @override
  Future<bool> replaceTeacherWorkHours({
    required String teacherId,
    required List<TeacherWorkHourInput> workHours,
  }) async {
    _requireTeacher(teacherId);
    store.replaceTeacherWorkHours(
      teacherId,
      workHours
          .map(
            (hour) => ManagedTeacherWorkHour(
              weekday: hour.weekday,
              startTime: hour.startTime,
              endTime: hour.endTime,
            ),
          )
          .toList(),
    );
    return true;
  }

  @override
  Future<List<ManagedTeacherBlockedPeriod>>
      fetchTeacherBlockedPeriods(
    String teacherId,
  ) async {
    return store.blockedPeriods
        .where((period) => period.teacherId == teacherId)
        .toList();
  }

  @override
  Future<void> saveTeacherBlockedPeriod({
    required String teacherId,
    required DateTime startsAt,
    required DateTime endsAt,
    String? reason,
    String? blockedPeriodId,
  }) async {
    _requireTeacher(teacherId);
    store.saveBlockedPeriod(
      ManagedTeacherBlockedPeriod(
        id: blockedPeriodId ??
            'qa-blocked-${DateTime.now().microsecondsSinceEpoch}',
        teacherId: teacherId,
        startsAt: startsAt,
        endsAt: endsAt,
        createdAt: DateTime.now(),
        reason: reason,
      ),
    );
  }

  @override
  Future<void> deleteTeacherBlockedPeriod(
    String blockedPeriodId,
  ) async {
    store.deleteBlockedPeriod(blockedPeriodId);
  }

  @override
  Future<TeacherLessonStats> fetchTeacherLessonStats(
    String teacherId,
  ) async {
    final teacher = _requireTeacher(teacherId);
    final semesterStats = <TeacherSemesterLessonStats>[];

    for (final semester in store.semesters) {
      final rows = store.lessons
          .where(
            (lesson) =>
                lesson.teacherId == teacherId &&
                !lesson.startsAt.isBefore(semester.startsOn) &&
                !lesson.startsAt.isAfter(
                  semester.endsOn.add(const Duration(days: 1)),
                ),
          )
          .toList();
      final groups = <int, int>{};
      for (final lesson in rows) {
        groups.update(
          lesson.durationMinutes,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      semesterStats.add(
        TeacherSemesterLessonStats(
          semesterId: semester.id,
          code: semester.code,
          startsOn: semester.startsOn,
          endsOn: semester.endsOn,
          isCurrent: semester.isCurrent,
          totalLessonCount: rows.length,
          totalMinutes: rows.fold(
            0,
            (sum, lesson) => sum + lesson.durationMinutes,
          ),
          durationGroups: groups.entries
              .map(
                (entry) => TeacherLessonDurationGroup(
                  durationMinutes: entry.key,
                  lessonCount: entry.value,
                ),
              )
              .toList(),
        ),
      );
    }

    return TeacherLessonStats(
      teacherId: teacher.id,
      teacherName: teacher.displayName,
      employmentStartsOn:
          DateTime(DateTime.now().year, DateTime.now().month - 6, 1),
      calculatedAt: DateTime.now(),
      withdrawalDate: teacher.withdrawalDate,
      semesters: semesterStats,
    );
  }

  @override
  Future<StaffDepartureState> fetchStaffDepartureState(
    String staffId,
  ) async {
    final teacher = _requireTeacher(staffId);
    final date = teacher.withdrawalDate ??
        DateTime.now().add(const Duration(days: 30));
    final assignmentCount = store.students
        .where((student) => student.isActive && student.teacherId == staffId)
        .length;
    final scheduledLessonCount = store.lessons
        .where(
          (lesson) =>
              lesson.teacherId == staffId &&
              !lesson.isCanceled &&
              lesson.startsAt.isAfter(DateTime.now()),
        )
        .length;

    return StaffDepartureState(
      staffId: staffId,
      withdrawalDate: date,
      assignmentCount: assignmentCount,
      seriesCount: assignmentCount,
      scheduledLessonCount: scheduledLessonCount,
      canFinalize:
          assignmentCount == 0 && scheduledLessonCount == 0,
    );
  }

  @override
  Future<StaffDepartureState> scheduleStaffDeparture({
    required String staffId,
    required DateTime withdrawalDate,
  }) async {
    final teacher = _requireTeacher(staffId);
    store.updateTeacher(
      _copyTeacher(
        teacher,
        withdrawalDate: withdrawalDate,
        replaceWithdrawalDate: true,
      ),
    );
    return fetchStaffDepartureState(staffId);
  }

  @override
  Future<bool> cancelStaffDeparture(String staffId) async {
    final teacher = _requireTeacher(staffId);
    store.updateTeacher(
      _copyTeacher(
        teacher,
        withdrawalDate: null,
        replaceWithdrawalDate: true,
      ),
    );
    return true;
  }

  @override
  Future<bool> finalizeStaffDeparture(String staffId) async {
    final teacher = _requireTeacher(staffId);
    store.updateTeacher(
      _copyTeacher(
        teacher,
        profileIsActive: false,
      ),
    );
    return true;
  }

  ManagedTeacher _requireTeacher(String id) {
    final teacher = store.teacherById(id);
    if (teacher == null) {
      throw const TeacherFailure('QA 선생님을 찾을 수 없습니다.');
    }
    return teacher;
  }

  ManagedTeacher _copyTeacher(
    ManagedTeacher source, {
    String? displayName,
    bool? profileIsActive,
    DateTime? withdrawalDate,
    bool replaceWithdrawalDate = false,
  }) {
    return ManagedTeacher(
      id: source.id,
      displayName: displayName ?? source.displayName,
      branchId: source.branchId,
      branchName: source.branchName,
      profileIsActive: profileIsActive ?? source.profileIsActive,
      workHours: source.workHours,
      assignedStudentCount: source.assignedStudentCount,
      withdrawalDate: replaceWithdrawalDate
          ? withdrawalDate
          : source.withdrawalDate,
    );
  }

  String _branchName(String branchId) {
    for (final branch in store.branches) {
      if (branch.id == branchId) return branch.name;
    }
    return 'QA 지점';
  }
}


class QaStudentTeacherManagementRepository
    extends StudentTeacherManagementRepository {
  QaStudentTeacherManagementRepository(this.store);

  final QaSandboxStore store;

  @override
  Future<List<ManagedTeacherOption>> fetchBranchTeachers(
    String branchId,
  ) async {
    return store.teachers
        .where(
          (teacher) =>
              teacher.isActive && teacher.branchId == branchId,
        )
        .map(
          (teacher) => ManagedTeacherOption(
            id: teacher.id,
            displayName: teacher.displayName,
            branchId: branchId,
          ),
        )
        .toList();
  }

  @override
  Future<Map<String, dynamic>> changeStudentTeacher({
    required String studentId,
    required String teacherId,
    required DateTime effectiveOn,
    required String? currentTeacherId,
    required bool isFlex,
  }) async {
    final student = store.studentById(studentId);
    final teacher = store.teacherById(teacherId);
    if (student == null) {
      throw const StudentTeacherManagementFailure(
        'QA 학생을 찾을 수 없습니다.',
      );
    }
    if (teacher == null || !teacher.isActive) {
      throw const StudentTeacherManagementFailure(
        'QA 선생님을 찾을 수 없습니다.',
      );
    }

    store.assignStudentTeacher(
      studentId: studentId,
      teacherId: teacherId,
    );

    return {
      'changed': currentTeacherId != teacherId,
      'studentId': studentId,
      'teacherId': teacherId,
      'effectiveOn': _qaDateText(effectiveOn),
    };
  }
}

class QaStudentRegularScheduleRepository
    extends StudentRegularScheduleRepository {
  QaStudentRegularScheduleRepository(this.store);

  final QaSandboxStore store;

  @override
  Future<List<ManagedRegularSchedule>> fetchSchedules(
    String studentId,
  ) async {
    return List<ManagedRegularSchedule>.from(
      store.regularSchedules[studentId] ?? const [],
    );
  }

  @override
  Future<RegularScheduleTeacher> fetchTeacherAtDate({
    required String studentId,
    required DateTime date,
  }) async {
    final student = store.studentById(studentId);
    final teacherId = student?.teacherId;
    final teacher =
        teacherId == null ? null : store.teacherById(teacherId);
    if (teacher == null) {
      throw const StudentRegularScheduleFailure(
        '선택한 적용일의 QA 담당 선생님을 찾지 못했습니다.',
      );
    }
    return RegularScheduleTeacher(
      id: teacher.id,
      displayName: teacher.displayName,
    );
  }

  @override
  Future<List<TeacherWorkWindow>> fetchTeacherWorkHours(
    String teacherId,
  ) async {
    final teacher = store.teacherById(teacherId);
    if (teacher == null) {
      throw const StudentRegularScheduleFailure(
        'QA 선생님의 근무시간을 찾지 못했습니다.',
      );
    }
    return teacher.workHours
        .map(
          (hour) => TeacherWorkWindow(
            weekday: hour.weekday,
            startMinutes: _qaTimeMinutes(hour.startTime),
            endMinutes: _qaTimeMinutes(hour.endTime),
          ),
        )
        .toList();
  }

  @override
  Future<List<RegularScheduleSemesterOption>> fetchUpcomingSemesters(
    String? branchId, {
    bool includeCurrent = false,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = store.semesters
        .map(
          (semester) => RegularScheduleSemesterOption(
            id: semester.id,
            code: semester.code,
            startsOn: semester.startsOn,
            endsOn: semester.endsOn,
          ),
        )
        .where(
          (semester) => semester.isSelectableOn(
            today,
            includeCurrent: includeCurrent,
          ),
        )
        .toList()
      ..sort((a, b) => a.startsOn.compareTo(b.startsOn));
    return result;
  }

  @override
  Future<Map<String, dynamic>> addSchedule({
    required String studentId,
    required String teacherId,
    required int weekday,
    required int startMinutes,
    required int durationMinutes,
    required DateTime effectiveOn,
  }) async {
    final teacher = store.teacherById(teacherId);
    if (store.studentById(studentId) == null || teacher == null) {
      throw const StudentRegularScheduleFailure(
        'QA 정규 일정 대상 정보를 찾지 못했습니다.',
      );
    }

    final schedule = ManagedRegularSchedule(
      slotId:
          'qa-regular-${DateTime.now().microsecondsSinceEpoch}',
      teacherId: teacherId,
      teacherName: teacher.displayName,
      weekday: weekday,
      startMinutes: startMinutes,
      durationMinutes: durationMinutes,
      slotStartsOn: _qaDateOnly(effectiveOn),
      effectiveFrom: _qaDateOnly(effectiveOn),
      hasFutureVersion: false,
    );
    store.addRegularSchedule(
      studentId: studentId,
      schedule: schedule,
    );

    return {
      'changed': true,
      'scheduleSlotId': schedule.slotId,
      'canceledLessonCount': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> endSchedule({
    required String scheduleSlotId,
    required DateTime effectiveOn,
  }) async {
    store.removeRegularSchedule(scheduleSlotId);
    return {
      'changed': true,
      'scheduleSlotId': scheduleSlotId,
      'effectiveOn': _qaDateText(effectiveOn),
      'canceledLessonCount': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> changeSchedule({
    required String scheduleSlotId,
    required String teacherId,
    required int weekday,
    required int startMinutes,
    required int durationMinutes,
    required DateTime effectiveOn,
  }) async {
    final teacher = store.teacherById(teacherId);
    if (teacher == null) {
      throw const StudentRegularScheduleFailure(
        'QA 선생님을 찾지 못했습니다.',
      );
    }

    String? studentId;
    ManagedRegularSchedule? current;
    for (final entry in store.regularSchedules.entries) {
      for (final schedule in entry.value) {
        if (schedule.slotId == scheduleSlotId) {
          studentId = entry.key;
          current = schedule;
          break;
        }
      }
      if (current != null) break;
    }

    if (studentId == null || current == null) {
      throw const StudentRegularScheduleFailure(
        'QA 정규 일정을 찾지 못했습니다.',
      );
    }

    store.replaceRegularSchedule(
      studentId: studentId,
      schedule: ManagedRegularSchedule(
        slotId: current.slotId,
        teacherId: teacherId,
        teacherName: teacher.displayName,
        weekday: weekday,
        startMinutes: startMinutes,
        durationMinutes: durationMinutes,
        slotStartsOn: current.slotStartsOn,
        slotEndsOn: current.slotEndsOn,
        effectiveFrom: _qaDateOnly(effectiveOn),
        effectiveUntil: current.effectiveUntil,
        hasFutureVersion: false,
      ),
    );

    return {
      'changed': true,
      'scheduleSlotId': scheduleSlotId,
      'effectiveOn': _qaDateText(effectiveOn),
      'canceledLessonCount': 0,
    };
  }
}

class QaStudentNextSemesterTypeRepository
    extends StudentNextSemesterTypeRepository {
  QaStudentNextSemesterTypeRepository(this.store);

  final QaSandboxStore store;

  @override
  Future<NextSemesterStudentTypePlan> fetchPlan(
    String studentId,
  ) async {
    final student = store.studentById(studentId);
    if (student == null) {
      throw const StudentNextSemesterTypeFailure(
        'QA 학생을 찾을 수 없습니다.',
      );
    }

    ManagedSemester? current;
    final upcoming = <ManagedSemester>[];
    for (final semester in store.semesters) {
      if (semester.isCurrent) current = semester;
      if (semester.isUpcoming) upcoming.add(semester);
    }
    upcoming.sort((a, b) => a.startsOn.compareTo(b.startsOn));
    if (current == null || upcoming.isEmpty) {
      throw const StudentNextSemesterTypeFailure(
        'QA 학기 정보를 찾을 수 없습니다.',
      );
    }

    final next = upcoming.first;
    final plannedType =
        store.nextStudentTypes[studentId] ?? student.studentType;
    final teacher = student.teacherId == null
        ? null
        : store.teacherById(student.teacherId!);

    return NextSemesterStudentTypePlan(
      studentId: student.id,
      currentStudentType: student.studentType,
      currentSemesterCode: current.code,
      currentSemesterStartsOn: current.startsOn,
      currentSemesterEndsOn: current.endsOn,
      nextSemesterId: next.id,
      nextSemesterCode: next.code,
      nextSemesterStartsOn: next.startsOn,
      nextSemesterEndsOn: next.endsOn,
      plannedStudentType: plannedType,
      regularScheduleCount:
          store.nextRegularScheduleCounts[studentId] ?? 0,
      teacherAssignmentCoversSemester: teacher != null,
      canChange: student.isActive,
      defaultFlexBaseRightCount: 4,
      defaultFlexDurationMinutes: 30,
      nextPlanId: 'qa-next-plan-${student.id}',
      nextPlanStatus: 'planned',
      flexBaseRightCount: plannedType == 'flex'
          ? (store.nextFlexRightCounts[studentId] ?? 4)
          : null,
      flexDurationMinutes: plannedType == 'flex'
          ? (store.nextFlexDurations[studentId] ?? 30)
          : null,
      teacherId: teacher?.id,
      teacherName: teacher?.displayName,
      withdrawalDate: student.withdrawalDate,
    );
  }

  @override
  Future<List<NextSemesterTeacherWorkWindow>>
      fetchTeacherWorkHours({
    required String teacherId,
    required DateTime onDate,
  }) async {
    final teacher = store.teacherById(teacherId);
    if (teacher == null) {
      throw const StudentNextSemesterTypeFailure(
        'QA 선생님 근무시간을 찾지 못했습니다.',
      );
    }
    return teacher.workHours
        .map(
          (hour) => NextSemesterTeacherWorkWindow(
            weekday: hour.weekday,
            startMinutes: _qaTimeMinutes(hour.startTime),
            endMinutes: _qaTimeMinutes(hour.endTime),
          ),
        )
        .toList();
  }

  @override
  Future<NextSemesterStudentTypeChangeResult> save({
    required String studentId,
    required String targetType,
    int? flexBaseRightCount,
    int? flexDurationMinutes,
    List<Map<String, dynamic>>? regularSchedules,
  }) async {
    final plan = await fetchPlan(studentId);
    final regularCount =
        targetType == 'regular' ? (regularSchedules?.length ?? 0) : 0;

    store.saveNextSemesterPlan(
      studentId: studentId,
      studentType: targetType,
      flexRightCount: flexBaseRightCount,
      flexDurationMinutes: flexDurationMinutes,
      regularScheduleCount: regularCount,
    );

    return NextSemesterStudentTypeChangeResult(
      changed: plan.plannedStudentType != targetType,
      currentStudentType: plan.currentStudentType,
      plannedStudentType: targetType,
      nextSemesterCode: plan.nextSemesterCode,
      nextSemesterStartsOn: plan.nextSemesterStartsOn,
      regularScheduleCount: regularCount,
      flexBaseRightCount:
          targetType == 'flex' ? flexBaseRightCount : null,
      flexDurationMinutes:
          targetType == 'flex' ? flexDurationMinutes : null,
    );
  }
}

class QaStudentAdminRepository extends StudentAdminRepository {
  QaStudentAdminRepository(this.store);

  final QaSandboxStore store;

  @override
  Future<List<StudentAdminTeacher>> fetchTeachers(
    String branchId,
  ) async {
    return store.teachers
        .where(
          (teacher) =>
              teacher.isActive && teacher.branchId == branchId,
        )
        .map(
          (teacher) => StudentAdminTeacher(
            id: teacher.id,
            displayName: teacher.displayName,
            branchId: branchId,
          ),
        )
        .toList();
  }

  @override
  Future<List<StudentSemesterOption>> fetchSemesters(
    String branchId,
  ) async {
    return store.semesters
        .map(
          (semester) => StudentSemesterOption(
            id: semester.id,
            code: semester.code,
            startsOn: semester.startsOn,
            endsOn: semester.endsOn,
          ),
        )
        .toList();
  }

  @override
  Future<String> createStudentAccount({
    required String name,
    required String pin,
    required String branchId,
    required String studentType,
  }) async {
    final id =
        'qa-student-${DateTime.now().microsecondsSinceEpoch}';
    final branchName = store.branches
        .where((branch) => branch.id == branchId)
        .map((branch) => branch.name)
        .first;

    store.addStudent(
      ManagedStudent(
        id: id,
        displayName: name.trim(),
        branchId: branchId,
        branchName: branchName,
        studentType: studentType,
        status: 'active',
        profileIsActive: true,
        flexBaseRightCount: studentType == 'flex' ? 4 : null,
        flexDurationMinutes: studentType == 'flex' ? 30 : null,
      ),
    );
    store.savePin(id, pin);
    store.nextStudentTypes[id] = studentType;
    store.nextRegularScheduleCounts[id] = 0;
    return id;
  }

  @override
  Future<Map<String, dynamic>> initializeFlexSemester({
    required String studentId,
    required String teacherId,
    required String semesterId,
    required int baseRightCount,
    required int durationMinutes,
  }) async {
    final student = _qaRequireStudent(store, studentId);
    final teacher = _qaRequireTeacher(store, teacherId);
    store.updateStudent(
      ManagedStudent(
        id: student.id,
        displayName: student.displayName,
        branchId: student.branchId,
        branchName: student.branchName,
        studentType: 'flex',
        status: student.status,
        profileIsActive: student.profileIsActive,
        teacherId: teacher.id,
        teacherName: teacher.displayName,
        withdrawalDate: student.withdrawalDate,
        flexBaseRightCount: baseRightCount,
        flexDurationMinutes: durationMinutes,
      ),
    );

    return {
      'changed': true,
      'baseRightCount': baseRightCount,
      'durationMinutes': durationMinutes,
    };
  }

  @override
  Future<Map<String, dynamic>> initializeRegularSemester({
    required String studentId,
    required String teacherId,
    required String semesterId,
    required List<Map<String, dynamic>> schedules,
  }) async {
    final student = _qaRequireStudent(store, studentId);
    final teacher = _qaRequireTeacher(store, teacherId);
    final semester = store.semesters
        .where((item) => item.id == semesterId)
        .first;

    store.updateStudent(
      ManagedStudent(
        id: student.id,
        displayName: student.displayName,
        branchId: student.branchId,
        branchName: student.branchName,
        studentType: 'regular',
        status: student.status,
        profileIsActive: student.profileIsActive,
        teacherId: teacher.id,
        teacherName: teacher.displayName,
        withdrawalDate: student.withdrawalDate,
      ),
    );

    store.regularSchedules[studentId] = [];
    for (var index = 0; index < schedules.length; index++) {
      final raw = schedules[index];
      store.addRegularSchedule(
        studentId: studentId,
        schedule: ManagedRegularSchedule(
          slotId:
              'qa-regular-$studentId-${index + 1}',
          teacherId: teacher.id,
          teacherName: teacher.displayName,
          weekday: (raw['weekday'] as num?)?.toInt() ?? 1,
          startMinutes:
              _qaTimeMinutes(raw['startTime']?.toString() ?? '10:00'),
          durationMinutes:
              (raw['durationMinutes'] as num?)?.toInt() ?? 30,
          slotStartsOn: semester.startsOn,
          effectiveFrom: semester.startsOn,
          hasFutureVersion: false,
        ),
      );
    }

    return {
      'changed': true,
      'activation': {
        'slotCount': schedules.length,
        'rightCount': schedules.length * 4,
        'lessonCount': schedules.length * 4,
      },
    };
  }
}

ManagedStudent _qaRequireStudent(
  QaSandboxStore store,
  String studentId,
) {
  final student = store.studentById(studentId);
  if (student == null) {
    throw const StudentAdminFailure('QA 학생을 찾을 수 없습니다.');
  }
  return student;
}

ManagedTeacher _qaRequireTeacher(
  QaSandboxStore store,
  String teacherId,
) {
  final teacher = store.teacherById(teacherId);
  if (teacher == null) {
    throw const StudentAdminFailure('QA 선생님을 찾을 수 없습니다.');
  }
  return teacher;
}

DateTime _qaDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _qaDateText(DateTime value) {
  final date = _qaDateOnly(value);
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

int _qaTimeMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60 +
      (int.tryParse(parts[1]) ?? 0);
}
