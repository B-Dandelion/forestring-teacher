import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherFailure implements Exception {
  const TeacherFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManagedTeacherWorkHour {
  const ManagedTeacherWorkHour({
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  final int weekday;
  final String startTime;
  final String endTime;
}

class ManagedTeacherBlockedPeriod {
  const ManagedTeacherBlockedPeriod({
    required this.id,
    required this.teacherId,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    this.reason,
  });

  final String id;
  final String teacherId;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime createdAt;
  final String? reason;

  int get durationMinutes => endsAt.difference(startsAt).inMinutes;

  factory ManagedTeacherBlockedPeriod.fromJson(
    Map<String, dynamic> json,
  ) {
    return ManagedTeacherBlockedPeriod(
      id: json['id'] as String,
      teacherId: json['teacher_id'] as String,
      startsAt: DateTime.parse(json['starts_at'].toString()).toLocal(),
      endsAt: DateTime.parse(json['ends_at'].toString()).toLocal(),
      createdAt: DateTime.parse(json['created_at'].toString()).toLocal(),
      reason: json['reason'] as String?,
    );
  }
}

class TeacherLessonDurationGroup {
  const TeacherLessonDurationGroup({
    required this.durationMinutes,
    required this.lessonCount,
  });

  final int durationMinutes;
  final int lessonCount;

  factory TeacherLessonDurationGroup.fromJson(
    Map<String, dynamic> json,
  ) {
    return TeacherLessonDurationGroup(
      durationMinutes: (json['durationMinutes'] as num).toInt(),
      lessonCount: (json['lessonCount'] as num).toInt(),
    );
  }
}

class TeacherSemesterLessonStats {
  const TeacherSemesterLessonStats({
    required this.semesterId,
    required this.code,
    required this.startsOn,
    required this.endsOn,
    required this.isCurrent,
    required this.totalLessonCount,
    required this.totalMinutes,
    required this.durationGroups,
  });

  final String semesterId;
  final String code;
  final DateTime startsOn;
  final DateTime endsOn;
  final bool isCurrent;
  final int totalLessonCount;
  final int totalMinutes;
  final List<TeacherLessonDurationGroup> durationGroups;

  factory TeacherSemesterLessonStats.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawGroups = json['durationGroups'];

    return TeacherSemesterLessonStats(
      semesterId: json['semesterId'] as String,
      code: json['code'] as String,
      startsOn: DateTime.parse(json['startsOn'].toString()),
      endsOn: DateTime.parse(json['endsOn'].toString()),
      isCurrent: json['isCurrent'] == true,
      totalLessonCount: (json['totalLessonCount'] as num).toInt(),
      totalMinutes: (json['totalMinutes'] as num).toInt(),
      durationGroups: rawGroups is List
          ? rawGroups
              .map(
                (raw) => TeacherLessonDurationGroup.fromJson(
                  Map<String, dynamic>.from(raw as Map),
                ),
              )
              .toList()
          : const [],
    );
  }
}

class TeacherLessonStats {
  const TeacherLessonStats({
    required this.teacherId,
    required this.teacherName,
    required this.employmentStartsOn,
    required this.calculatedAt,
    required this.semesters,
    this.withdrawalDate,
  });

  final String teacherId;
  final String teacherName;
  final DateTime employmentStartsOn;
  final DateTime calculatedAt;
  final DateTime? withdrawalDate;
  final List<TeacherSemesterLessonStats> semesters;

  int get totalLessonCount => semesters.fold(
        0,
        (sum, semester) => sum + semester.totalLessonCount,
      );

  int get totalMinutes => semesters.fold(
        0,
        (sum, semester) => sum + semester.totalMinutes,
      );

  factory TeacherLessonStats.fromJson(Map<String, dynamic> json) {
    final rawSemesters = json['semesters'];

    return TeacherLessonStats(
      teacherId: json['teacherId'] as String,
      teacherName: json['teacherName'] as String,
      employmentStartsOn: DateTime.parse(
        json['employmentStartsOn'].toString(),
      ),
      calculatedAt: DateTime.parse(
        json['calculatedAt'].toString(),
      ).toLocal(),
      withdrawalDate: json['withdrawalDate'] == null
          ? null
          : DateTime.parse(json['withdrawalDate'].toString()),
      semesters: rawSemesters is List
          ? rawSemesters
              .map(
                (raw) => TeacherSemesterLessonStats.fromJson(
                  Map<String, dynamic>.from(raw as Map),
                ),
              )
              .toList()
          : const [],
    );
  }
}

class StaffDepartureState {
  const StaffDepartureState({
    required this.staffId,
    required this.withdrawalDate,
    required this.assignmentCount,
    required this.seriesCount,
    required this.scheduledLessonCount,
    required this.canFinalize,
  });

  final String staffId;
  final DateTime withdrawalDate;
  final int assignmentCount;
  final int seriesCount;
  final int scheduledLessonCount;
  final bool canFinalize;

  int get totalBlockerCount =>
      assignmentCount + seriesCount + scheduledLessonCount;

  factory StaffDepartureState.fromJson(Map<String, dynamic> json) {
    return StaffDepartureState(
      staffId: json['staffId'] as String,
      withdrawalDate: DateTime.parse(json['withdrawalDate'].toString()),
      assignmentCount: (json['assignmentCount'] as num).toInt(),
      seriesCount: (json['seriesCount'] as num).toInt(),
      scheduledLessonCount:
          (json['scheduledLessonCount'] as num).toInt(),
      canFinalize: json['canFinalize'] == true,
    );
  }
}

class ManagedTeacher {
  const ManagedTeacher({
    required this.id,
    required this.displayName,
    required this.branchId,
    required this.branchName,
    required this.profileIsActive,
    required this.workHours,
    required this.assignedStudentCount,
    this.withdrawalDate,
  });

  final String id;
  final String displayName;
  final String? branchId;
  final String branchName;
  final bool profileIsActive;
  final List<ManagedTeacherWorkHour> workHours;
  final int assignedStudentCount;
  final DateTime? withdrawalDate;

  bool get isActive => profileIsActive;
  bool get hasScheduledWithdrawal => isActive && withdrawalDate != null;

  String get statusLabel {
    if (!isActive) return '퇴사';
    if (hasScheduledWithdrawal) return '퇴사 예정';
    return '재직';
  }
}

class AssignedStudentRegularSchedule {
  const AssignedStudentRegularSchedule({
    required this.weekday,
    required this.startTime,
    required this.durationMinutes,
  });

  final int weekday;
  final String startTime;
  final int durationMinutes;
}

class AssignedStudentSummary {
  const AssignedStudentSummary({
    required this.id,
    required this.displayName,
    required this.studentType,
    required this.assignmentStartsOn,
    required this.isActive,
    required this.regularSchedules,
    this.flexBaseRightCount,
  });

  final String id;
  final String displayName;
  final String studentType;
  final DateTime assignmentStartsOn;
  final bool isActive;
  final List<AssignedStudentRegularSchedule> regularSchedules;
  final int? flexBaseRightCount;

  bool get isFlex => studentType == 'flex';
  String get typeLabel => isFlex ? '자율 예약 학생' : '정규 학생';
  String get statusLabel => isActive ? '재원' : '퇴원';
}

class TeacherWorkHourInput {
  const TeacherWorkHourInput({
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  final int weekday;
  final String startTime;
  final String endTime;

  Map<String, dynamic> toJson() {
    return {
      'weekday': weekday,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

class CreatedTeacher {
  const CreatedTeacher({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;
}

class TeacherRepository {
  TeacherRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ManagedTeacher>> fetchTeachers({
    String? branchId,
  }) async {
    try {
      final profileRows = branchId == null
          ? await _client
              .from('profiles')
              .select('id, display_name, branch_id, is_active')
              .eq('role', 'teacher')
              .eq('is_review_account', false)
              .eq('is_qa_account', false)
              .order('display_name')
          : await _client
              .from('profiles')
              .select('id, display_name, branch_id, is_active')
              .eq('role', 'teacher')
              .eq('is_review_account', false)
              .eq('is_qa_account', false)
              .eq('branch_id', branchId)
              .order('display_name');

      final profiles = (profileRows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      if (profiles.isEmpty) {
        return const [];
      }

      final teacherIds = profiles.map((row) => row['id'] as String).toList();
      final branchIds = profiles
          .map((row) => row['branch_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final results = await Future.wait([
        _client
            .from('teachers')
            .select('id, withdrawal_date')
            .inFilter('id', teacherIds),
        _client
            .from('teacher_work_hours')
            .select('teacher_id, weekday, start_time, end_time')
            .inFilter('teacher_id', teacherIds),
        _client
            .from('teacher_student_assignments')
            .select('teacher_id, student_id, starts_on, ends_on')
            .inFilter('teacher_id', teacherIds),
        if (branchIds.isEmpty)
          Future.value(<dynamic>[])
        else
          _client
              .from('branches')
              .select('id, name')
              .inFilter('id', branchIds)
              .order('name'),
      ]);

      final teacherRows = results[0]
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final workHourRows = results[1]
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final assignmentRows = results[2]
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final branchRows = results[3]
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      final withdrawalByTeacher = <String, DateTime?>{
        for (final row in teacherRows)
          row['id'] as String: row['withdrawal_date'] == null
              ? null
              : DateTime.parse(row['withdrawal_date'].toString()),
      };
      final branchNames = <String, String>{
        for (final row in branchRows)
          row['id'] as String: row['name'].toString(),
      };
      final workHoursByTeacher = <String, List<ManagedTeacherWorkHour>>{};

      for (final row in workHourRows) {
        final teacherId = row['teacher_id'] as String;
        workHoursByTeacher.putIfAbsent(teacherId, () => []).add(
              ManagedTeacherWorkHour(
                weekday: (row['weekday'] as num).toInt(),
                startTime: _shortTime(row['start_time']),
                endTime: _shortTime(row['end_time']),
              ),
            );
      }

      for (final workHours in workHoursByTeacher.values) {
        workHours.sort((a, b) {
          final weekdayCompare = a.weekday.compareTo(b.weekday);
          return weekdayCompare != 0
              ? weekdayCompare
              : a.startTime.compareTo(b.startTime);
        });
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final activeStudentsByTeacher = <String, Set<String>>{};

      for (final row in assignmentRows) {
        final startsOn = DateTime.parse(row['starts_on'].toString());
        final endsOn = row['ends_on'] == null
            ? null
            : DateTime.parse(row['ends_on'].toString());
        final isCurrent = !startsOn.isAfter(today) &&
            (endsOn == null || !endsOn.isBefore(today));
        if (!isCurrent) continue;

        final teacherId = row['teacher_id'] as String;
        activeStudentsByTeacher
            .putIfAbsent(teacherId, () => <String>{})
            .add(row['student_id'] as String);
      }

      return profiles.map((profile) {
        final id = profile['id'] as String;
        final branchId = profile['branch_id'] as String?;

        return ManagedTeacher(
          id: id,
          displayName: profile['display_name'].toString(),
          branchId: branchId,
          branchName: branchId == null
              ? '지점 미지정'
              : (branchNames[branchId] ?? '지점 확인 필요'),
          profileIsActive: profile['is_active'] == true,
          workHours: List.unmodifiable(workHoursByTeacher[id] ?? const []),
          assignedStudentCount: activeStudentsByTeacher[id]?.length ?? 0,
          withdrawalDate: withdrawalByTeacher[id],
        );
      }).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
    } on PostgrestException {
      throw const TeacherFailure(
        '선생님 목록을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    } catch (_) {
      throw const TeacherFailure(
        '선생님 목록을 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<List<AssignedStudentSummary>> fetchAssignedStudents(
    String teacherId,
  ) async {
    try {
      final assignmentRows = await _client
          .from('teacher_student_assignments')
          .select('student_id, starts_on, ends_on')
          .eq('teacher_id', teacherId)
          .order('starts_on', ascending: false);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final currentAssignmentByStudent = <String, Map<String, dynamic>>{};

      for (final raw in assignmentRows) {
        final row = Map<String, dynamic>.from(raw);
        final startsOn = DateTime.parse(row['starts_on'].toString());
        final endsOn = row['ends_on'] == null
            ? null
            : DateTime.parse(row['ends_on'].toString());
        final isCurrent = !startsOn.isAfter(today) &&
            (endsOn == null || !endsOn.isBefore(today));
        if (!isCurrent) continue;

        final studentId = row['student_id'] as String;
        currentAssignmentByStudent.putIfAbsent(studentId, () => row);
      }

      if (currentAssignmentByStudent.isEmpty) {
        return const [];
      }

      final studentIds = currentAssignmentByStudent.keys.toList();
      final results = await Future.wait([
        _client
            .from('profiles')
            .select('id, display_name, is_active')
            .inFilter('id', studentIds)
            .eq('role', 'student')
            .eq('is_review_account', false)
            .eq('is_qa_account', false),
        _client
            .from('students')
            .select('id, student_type, status')
            .inFilter('id', studentIds),
        _client
            .from('regular_schedule_slots')
            .select('id, student_id, starts_on, ends_on')
            .inFilter('student_id', studentIds)
            .order('starts_on'),
        _client
            .from('student_semester_plans')
            .select('student_id, flex_base_right_count, updated_at')
            .inFilter('student_id', studentIds)
            .eq('student_type_snapshot', 'flex')
            .eq('status', 'active')
            .order('updated_at', ascending: false),
      ]);

      final profilesById = <String, Map<String, dynamic>>{
        for (final raw in results[0])
          (raw['id'] as String): Map<String, dynamic>.from(raw),
      };
      final studentsById = <String, Map<String, dynamic>>{
        for (final raw in results[1])
          (raw['id'] as String): Map<String, dynamic>.from(raw),
      };
      final flexBaseRightCountByStudent = <String, int>{};

      for (final raw in results[3]) {
        final row = Map<String, dynamic>.from(raw);
        final studentId = row['student_id'] as String;
        final rightCount = row['flex_base_right_count'];
        if (rightCount is! num) continue;

        flexBaseRightCountByStudent.putIfAbsent(
          studentId,
          () => rightCount.toInt(),
        );
      }

      final studentIdByCurrentSlot = <String, String>{};

      for (final raw in results[2]) {
        final row = Map<String, dynamic>.from(raw);
        final studentId = row['student_id'] as String;
        if (studentsById[studentId]?['student_type']?.toString() != 'regular') {
          continue;
        }

        final startsOn = DateTime.parse(row['starts_on'].toString());
        final endsOn = row['ends_on'] == null
            ? null
            : DateTime.parse(row['ends_on'].toString());
        final isCurrent = !startsOn.isAfter(today) &&
            (endsOn == null || !endsOn.isBefore(today));
        if (!isCurrent) continue;

        studentIdByCurrentSlot[row['id'] as String] = studentId;
      }

      final schedulesByStudent =
          <String, List<AssignedStudentRegularSchedule>>{};

      if (studentIdByCurrentSlot.isNotEmpty) {
        final seriesRows = await _client
            .from('lesson_series')
            .select(
              'schedule_slot_id, teacher_id, weekday, start_time, '
              'duration_minutes, effective_from, effective_until',
            )
            .inFilter('schedule_slot_id', studentIdByCurrentSlot.keys.toList())
            .order('effective_from', ascending: false);
        final currentSeriesBySlot = <String, Map<String, dynamic>>{};

        for (final raw in seriesRows) {
          final row = Map<String, dynamic>.from(raw);
          if (row['teacher_id'] != teacherId) continue;

          final effectiveFrom = DateTime.parse(
            row['effective_from'].toString(),
          );
          final effectiveUntil = row['effective_until'] == null
              ? null
              : DateTime.parse(row['effective_until'].toString());
          final isCurrent = !effectiveFrom.isAfter(today) &&
              (effectiveUntil == null || !effectiveUntil.isBefore(today));
          if (!isCurrent) continue;

          final slotId = row['schedule_slot_id'] as String;
          currentSeriesBySlot.putIfAbsent(slotId, () => row);
        }

        for (final entry in currentSeriesBySlot.entries) {
          final studentId = studentIdByCurrentSlot[entry.key];
          if (studentId == null) continue;

          schedulesByStudent.putIfAbsent(studentId, () => []).add(
                AssignedStudentRegularSchedule(
                  weekday: (entry.value['weekday'] as num).toInt(),
                  startTime: _shortTime(entry.value['start_time']),
                  durationMinutes:
                      (entry.value['duration_minutes'] as num).toInt(),
                ),
              );
        }

        for (final schedules in schedulesByStudent.values) {
          schedules.sort((a, b) {
            final weekday = a.weekday.compareTo(b.weekday);
            return weekday != 0
                ? weekday
                : a.startTime.compareTo(b.startTime);
          });
        }
      }

      final students = <AssignedStudentSummary>[];

      for (final entry in currentAssignmentByStudent.entries) {
        final profile = profilesById[entry.key];
        final student = studentsById[entry.key];
        if (profile == null || student == null) continue;

        students.add(
          AssignedStudentSummary(
            id: entry.key,
            displayName: profile['display_name'].toString(),
            studentType: student['student_type']?.toString() ?? 'regular',
            assignmentStartsOn: DateTime.parse(
              entry.value['starts_on'].toString(),
            ),
            isActive: profile['is_active'] == true &&
                student['status']?.toString() == 'active',
            regularSchedules: List.unmodifiable(
              schedulesByStudent[entry.key] ?? const [],
            ),
            flexBaseRightCount: flexBaseRightCountByStudent[entry.key],
          ),
        );
      }

      students.sort((a, b) => a.displayName.compareTo(b.displayName));
      return students;
    } on PostgrestException {
      throw const TeacherFailure(
        '담당 수강생을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    } catch (_) {
      throw const TeacherFailure(
        '담당 수강생을 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<CreatedTeacher> createTeacher({
    required String name,
    required String pin,
    required String branchId,
    required List<TeacherWorkHourInput> workHours,
  }) async {
    final normalizedName = name.normalizeName();

    if (normalizedName.isEmpty) {
      throw const TeacherFailure(
        '선생님 이름을 입력해주세요.',
      );
    }

    if (branchId.isEmpty) {
      throw const TeacherFailure(
        '지점을 선택해주세요.',
      );
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const TeacherFailure(
        'PIN은 4자리 숫자로 입력해주세요.',
      );
    }

    final session = _client.auth.currentSession;

    if (session == null) {
      throw const TeacherFailure(
        '로그인이 필요합니다.',
      );
    }

    try {
      final response = await _client.functions.invoke(
        'master-create-teacher',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: {
          'name': normalizedName,
          'pin': pin,
          'branchId': branchId,
          'workHours': workHours.map((item) => item.toJson()).toList(),
        },
      );

      final data = response.data;

      if (data is! Map) {
        throw const TeacherFailure(
          '선생님 생성 서버 응답을 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
        );
      }

      final teacherId = data['teacherId'];
      final displayName = data['displayName'];

      if (teacherId is! String || teacherId.isEmpty) {
        final message = data['message'];

        throw TeacherFailure(
          message is String ? message : '선생님 계정을 생성하지 못했습니다.',
        );
      }

      return CreatedTeacher(
        id: teacherId,
        displayName: displayName is String ? displayName : normalizedName,
      );
    } on TeacherFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw TeacherFailure(details['message'].toString());
      }
      throw const TeacherFailure(
        '선생님 생성 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const TeacherFailure(
        '선생님 계정을 생성하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<void> updateTeacherName({
    required String teacherId,
    required String name,
  }) async {
    final normalizedName = name.normalizeName();

    if (normalizedName.isEmpty) {
      throw const TeacherFailure('이름을 입력해주세요.');
    }

    if (normalizedName.length > 100) {
      throw const TeacherFailure('이름은 100자 이하로 입력해주세요.');
    }

    try {
      final response = await _client.functions.invoke(
        'staff-update-account-name',
        body: {
          'profileId': teacherId,
          'name': normalizedName,
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300) {
        throw TeacherFailure(
          data is Map && data['message'] != null
              ? data['message'].toString()
              : '이름을 변경하지 못했습니다.',
        );
      }
    } on TeacherFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw TeacherFailure(details['message'].toString());
      }
      throw const TeacherFailure(
        '이름 변경 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const TeacherFailure(
        '이름을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<void> resetTeacherPin({
    required String teacherId,
    required String pin,
  }) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const TeacherFailure(
        'PIN은 4자리 숫자로 입력해주세요.',
      );
    }

    try {
      final response = await _client.functions.invoke(
        'staff-reset-account-pin',
        body: {
          'profileId': teacherId,
          'pin': pin,
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300) {
        throw TeacherFailure(
          data is Map && data['message'] != null
              ? data['message'].toString()
              : 'PIN을 변경하지 못했습니다.',
        );
      }
    } on TeacherFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw TeacherFailure(details['message'].toString());
      }
      throw const TeacherFailure(
        'PIN 변경 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const TeacherFailure(
        'PIN을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<bool> replaceTeacherWorkHours({
    required String teacherId,
    required List<TeacherWorkHourInput> workHours,
  }) async {
    try {
      final data = await _client.rpc(
        'replace_teacher_work_hours',
        params: {
          'p_teacher_id': teacherId,
          'p_segments': workHours.map((item) => item.toJson()).toList(),
        },
      );

      if (data is! Map) {
        throw const TeacherFailure(
          '근무시간 저장 결과를 확인하지 못했습니다.',
        );
      }

      return data['changed'] == true;
    } on TeacherFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw TeacherFailure(
        _workHourFailureMessage(error.message),
      );
    } catch (_) {
      throw const TeacherFailure(
        '근무시간을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<List<ManagedTeacherBlockedPeriod>> fetchTeacherBlockedPeriods(
    String teacherId,
  ) async {
    try {
      final rows = await _client
          .from('blocked_periods')
          .select('id, teacher_id, starts_at, ends_at, reason, created_at')
          .eq('teacher_id', teacherId)
          .order('starts_at', ascending: false);

      return (rows as List)
          .map(
            (row) => ManagedTeacherBlockedPeriod.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } on PostgrestException {
      throw const TeacherFailure(
        '개인 일정을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    } catch (_) {
      throw const TeacherFailure(
        '개인 일정을 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<void> saveTeacherBlockedPeriod({
    required String teacherId,
    required DateTime startsAt,
    required DateTime endsAt,
    String? reason,
    String? blockedPeriodId,
  }) async {
    try {
      await _client.rpc(
        'upsert_teacher_blocked_period',
        params: {
          'p_teacher_id': teacherId,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_ends_at': endsAt.toUtc().toIso8601String(),
          'p_reason': _nullIfBlank(reason),
          'p_blocked_period_id': blockedPeriodId,
        },
      );
    } on PostgrestException catch (error) {
      throw TeacherFailure(
        _blockedPeriodFailureMessage(error.message),
      );
    } catch (_) {
      throw const TeacherFailure(
        '개인 일정을 저장하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<void> deleteTeacherBlockedPeriod(String blockedPeriodId) async {
    try {
      await _client.rpc(
        'delete_teacher_blocked_period',
        params: {
          'p_blocked_period_id': blockedPeriodId,
        },
      );
    } on PostgrestException catch (error) {
      throw TeacherFailure(
        _blockedPeriodFailureMessage(error.message),
      );
    } catch (_) {
      throw const TeacherFailure(
        '개인 일정을 삭제하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<TeacherLessonStats> fetchTeacherLessonStats(
    String teacherId,
  ) async {
    try {
      final data = await _client.rpc(
        'get_teacher_semester_lesson_stats',
        params: {
          'p_teacher_id': teacherId,
        },
      );

      if (data is! Map) {
        throw const TeacherFailure(
          '수업 통계 결과를 확인하지 못했습니다.',
        );
      }

      return TeacherLessonStats.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on TeacherFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw TeacherFailure(
        _lessonStatsFailureMessage(error.message),
      );
    } catch (_) {
      throw const TeacherFailure(
        '수업 통계를 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<StaffDepartureState> fetchStaffDepartureState(
    String staffId,
  ) async {
    try {
      final data = await _client.rpc(
        'get_staff_departure_blockers',
        params: {
          'p_staff_id': staffId,
        },
      );

      if (data is! Map) {
        throw const TeacherFailure(
          '퇴사 관리 정보를 확인하지 못했습니다.',
        );
      }

      return StaffDepartureState.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on TeacherFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw TeacherFailure(
        _staffDepartureFailureMessage(error.message),
      );
    } catch (_) {
      throw const TeacherFailure(
        '퇴사 관리 정보를 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<StaffDepartureState> scheduleStaffDeparture({
    required String staffId,
    required DateTime withdrawalDate,
  }) async {
    try {
      final data = await _client.rpc(
        'schedule_staff_departure',
        params: {
          'p_staff_id': staffId,
          'p_withdrawal_date': _dateOnlyText(withdrawalDate),
        },
      );

      if (data is! Map) {
        throw const TeacherFailure(
          '퇴사 예약 결과를 확인하지 못했습니다.',
        );
      }

      return StaffDepartureState.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on TeacherFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw TeacherFailure(
        _staffDepartureFailureMessage(error.message),
      );
    } catch (_) {
      throw const TeacherFailure(
        '퇴사를 예약하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<bool> cancelStaffDeparture(String staffId) async {
    try {
      final data = await _client.rpc(
        'cancel_staff_departure',
        params: {
          'p_staff_id': staffId,
        },
      );

      if (data is! Map) {
        throw const TeacherFailure(
          '퇴사 예약 취소 결과를 확인하지 못했습니다.',
        );
      }

      return data['changed'] == true;
    } on TeacherFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw TeacherFailure(
        _staffDepartureFailureMessage(error.message),
      );
    } catch (_) {
      throw const TeacherFailure(
        '퇴사 예약을 취소하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<bool> finalizeStaffDeparture(String staffId) async {
    try {
      final data = await _client.rpc(
        'finalize_staff_departure',
        params: {
          'p_staff_id': staffId,
        },
      );

      if (data is! Map) {
        throw const TeacherFailure(
          '퇴사 확정 결과를 확인하지 못했습니다.',
        );
      }

      return data['changed'] == true;
    } on TeacherFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw TeacherFailure(
        _staffDepartureFailureMessage(error.message),
      );
    } catch (_) {
      throw const TeacherFailure(
        '퇴사를 확정하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

String _shortTime(dynamic value) {
  final raw = value.toString();
  return raw.length >= 5 ? raw.substring(0, 5) : raw;
}

String _workHourFailureMessage(String message) {
  String? userMessage;

  if (message.contains('FORESTRING_AUTH_REQUIRED')) {
    userMessage = '로그인이 필요합니다.';
  } else if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED') ||
      message.contains('FORESTRING_ACTIVE_USER_REQUIRED')) {
    userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_REQUIRED')) {
    userMessage = '근무시간을 변경할 권한이 없습니다.';
  } else if (message.contains('FORESTRING_TEACHER_NOT_FOUND')) {
    userMessage = '선생님 정보를 찾을 수 없습니다.';
  } else if (message.contains('FORESTRING_TEACHER_BRANCH_REQUIRED')) {
    userMessage = '선생님의 지점 정보를 확인해주세요.';
  } else if (message.contains('FORESTRING_ACTIVE_TEACHER_REQUIRED')) {
    userMessage = '재직 중인 선생님의 근무시간만 변경할 수 있습니다.';
  } else if (message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
    userMessage = '다른 지점 선생님의 근무시간은 변경할 수 없습니다.';
  } else if (message.contains('FORESTRING_WORK_HOURS_OVERLAP')) {
    userMessage = '같은 요일에 서로 겹치는 근무시간이 있습니다.';
  } else if (message.contains('FORESTRING_INVALID_WORK_HOURS_RANGE')) {
    userMessage = '종료시간은 시작시간보다 뒤여야 합니다.';
  } else if (message.contains('FORESTRING_WORK_HOURS_NOT_ON_15_MINUTE_GRID')) {
    userMessage = '근무시간은 15분 단위로 입력해주세요.';
  } else if (message.contains('FORESTRING_WORK_HOURS_ARRAY_REQUIRED') ||
      message.contains('FORESTRING_INVALID_WORK_HOURS_FORMAT')) {
    userMessage = '근무시간 입력 형식이 올바르지 않습니다.';
  }

  return _withErrorCode(
    userMessage ?? '근무시간을 변경하지 못했습니다.',
    message,
  );
}

String _blockedPeriodFailureMessage(String message) {
  String? userMessage;

  if (message.contains('FORESTRING_AUTH_REQUIRED')) {
    userMessage = '로그인이 필요합니다.';
  } else if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED') ||
      message.contains('FORESTRING_ACTIVE_USER_REQUIRED')) {
    userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_REQUIRED')) {
    userMessage = '개인 일정을 관리할 권한이 없습니다.';
  } else if (message.contains('FORESTRING_TEACHER_NOT_FOUND')) {
    userMessage = '선생님 정보를 찾을 수 없습니다.';
  } else if (message.contains('FORESTRING_ACTIVE_TEACHER_REQUIRED')) {
    userMessage = '재직 중인 선생님의 개인 일정만 등록할 수 있습니다.';
  } else if (message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
    userMessage = '다른 지점 선생님의 개인 일정은 관리할 수 없습니다.';
  } else if (message.contains('FORESTRING_BLOCKED_PERIOD_LESSON_CONFLICT') ||
      message.contains('FORESTRING_BLOCKED_PERIOD_HAS_EXISTING_LESSONS')) {
    userMessage = '해당 시간에 예정된 수업이 있습니다. 수업을 먼저 변경하거나 취소해주세요.';
  } else if (message.contains('FORESTRING_BLOCKED_PERIOD_OVERLAP')) {
    userMessage = '이미 등록된 개인 일정과 시간이 겹칩니다.';
  } else if (message.contains('FORESTRING_INVALID_BLOCKED_PERIOD_RANGE')) {
    userMessage = '개인 일정의 종료시간은 시작시간보다 뒤여야 합니다.';
  } else if (message.contains('FORESTRING_BLOCKED_PERIOD_NOT_FOUND')) {
    userMessage = '개인 일정을 찾을 수 없습니다.';
  } else if (message.contains('FORESTRING_BLOCKED_PERIOD_TEACHER_MISMATCH')) {
    userMessage = '선택한 개인 일정과 선생님 정보가 일치하지 않습니다.';
  }

  return _withErrorCode(
    userMessage ?? '개인 일정을 처리하지 못했습니다.',
    message,
  );
}

String _lessonStatsFailureMessage(String message) {
  String? userMessage;

  if (message.contains('FORESTRING_AUTH_REQUIRED')) {
    userMessage = '로그인이 필요합니다.';
  } else if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED') ||
      message.contains('FORESTRING_ACTIVE_USER_REQUIRED')) {
    userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
  } else if (message.contains('FORESTRING_TEACHER_STATS_FORBIDDEN')) {
    userMessage = '수업 통계를 조회할 권한이 없습니다.';
  } else if (message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
    userMessage = '다른 지점 선생님의 통계는 조회할 수 없습니다.';
  } else if (message.contains('FORESTRING_TEACHER_NOT_FOUND')) {
    userMessage = '선생님 정보를 찾을 수 없습니다.';
  }

  return _withErrorCode(
    userMessage ?? '수업 통계를 불러오지 못했습니다.',
    message,
  );
}

String _staffDepartureFailureMessage(String message) {
  String? userMessage;

  if (message.contains('FORESTRING_AUTH_REQUIRED')) {
    userMessage = '로그인이 필요합니다.';
  } else if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED') ||
      message.contains('FORESTRING_ACTIVE_USER_REQUIRED')) {
    userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_DEPARTURE_FORBIDDEN') ||
      message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
    userMessage = '이 선생님의 퇴사를 관리할 권한이 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_NOT_FOUND') ||
      message.contains('FORESTRING_TARGET_NOT_STAFF')) {
    userMessage = '선생님 정보를 찾을 수 없습니다.';
  } else if (message.contains('FORESTRING_ACTIVE_STAFF_REQUIRED')) {
    userMessage = '재직 중인 선생님만 퇴사를 예약할 수 있습니다.';
  } else if (message.contains('FORESTRING_STAFF_DEPARTURE_DATE_IN_PAST')) {
    userMessage = '오늘보다 이전 날짜로는 퇴사를 예약할 수 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_DEPARTURE_ALREADY_EFFECTIVE')) {
    userMessage = '이미 퇴사 예정일이 되어 예약을 변경하거나 취소할 수 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_DEPARTURE_NOT_SCHEDULED')) {
    userMessage = '예약된 퇴사가 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_DEPARTURE_NOT_EFFECTIVE_YET')) {
    userMessage = '퇴사 예정일 전에는 퇴사를 확정할 수 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_DEPARTURE_BLOCKED')) {
    userMessage = '담당 학생, 정규 일정 또는 예정 수업이 남아 있어 퇴사를 확정할 수 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_DEPARTURE_INPUT_REQUIRED')) {
    userMessage = '퇴사 예정일을 선택해주세요.';
  }

  return _withErrorCode(
    userMessage ?? '퇴사 관리 작업을 처리하지 못했습니다.',
    message,
  );
}

String _withErrorCode(String userMessage, String rawMessage) {
  final match = RegExp(r'FORESTRING_[A-Z0-9_]+').firstMatch(rawMessage);
  final code = match?.group(0);
  if (code == null) return userMessage;
  return '$userMessage\n오류 코드: $code';
}

String _dateOnlyText(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

extension on String {
  String normalizeName() {
    return trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }
}
