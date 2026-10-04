import 'package:supabase_flutter/supabase_flutter.dart';

class StudentAdminFailure implements Exception {
  const StudentAdminFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class StudentAdminWorkWindow {
  const StudentAdminWorkWindow({
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
  });

  final int weekday;
  final int startMinutes;
  final int endMinutes;
}

class StudentAdminTeacher {
  const StudentAdminTeacher({
    required this.id,
    required this.displayName,
    required this.branchId,
  });

  final String id;
  final String displayName;
  final String branchId;
}

class StudentSemesterOption {
  const StudentSemesterOption({
    required this.id,
    required this.code,
    required this.startsOn,
    required this.endsOn,
  });

  final String id;
  final String code;
  final DateTime startsOn;
  final DateTime endsOn;

  String get label {
    final parts = code.split('-');
    if (parts.length == 2) {
      final month = int.tryParse(parts[1]);
      if (month != null) {
        return '${parts[0]}년 $month월 학기';
      }
    }
    return '$code 학기';
  }
}

class StudentAdminRepository {
  StudentAdminRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<StudentAdminTeacher>> fetchTeachers(String branchId) async {
    try {
      final rows = await _client
          .from('profiles')
          .select('id, display_name, branch_id, role, is_active')
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .inFilter('role', ['teacher', 'manager'])
          .order('display_name');

      return (rows as List)
          .where((raw) => (raw as Map)['branch_id'] != null)
          .map(
            (raw) {
              final row = Map<String, dynamic>.from(raw as Map);
              return StudentAdminTeacher(
                id: row['id'] as String,
                displayName: row['display_name'] as String,
                branchId: row['branch_id'] as String,
              );
            },
          )
          .toList();
    } on PostgrestException {
      throw const StudentAdminFailure(
        '선생님 목록을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<List<StudentAdminWorkWindow>> fetchTeacherWorkHours(
    String teacherId,
  ) async {
    try {
      final rows = await _client
          .from('teacher_work_hours')
          .select('weekday, start_time, end_time')
          .eq('teacher_id', teacherId)
          .order('weekday');

      int parseMinutes(dynamic raw) {
        final parts = raw.toString().split(':');
        final hour = int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0;
        final minute = int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;
        return hour * 60 + minute;
      }

      return (rows as List)
          .map(
            (raw) {
              final row = Map<String, dynamic>.from(raw as Map);
              return StudentAdminWorkWindow(
                weekday: (row['weekday'] as num).toInt(),
                startMinutes: parseMinutes(row['start_time']),
                endMinutes: parseMinutes(row['end_time']),
              );
            },
          )
          .toList();
    } on PostgrestException {
      throw const StudentAdminFailure(
        '선생님 근무시간을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<List<StudentSemesterOption>> fetchSemesters(String branchId) async {
    try {
      final semesterRows = await _client
          .from('semesters')
          .select('id, code, starts_on, ends_on')
          .order('starts_on', ascending: true);

      List<dynamic> overrideRows = const [];
      try {
        overrideRows = await _client
            .from('branch_semester_overrides')
            .select('semester_id, starts_on, ends_on')
            .eq('branch_id', branchId);
      } on PostgrestException {
        overrideRows = const [];
      }

      final overrides = <String, Map<String, dynamic>>{
        for (final raw in overrideRows)
          (raw as Map)['semester_id'] as String: Map<String, dynamic>.from(raw),
      };

      final today = DateTime.now();
      final localToday = DateTime(today.year, today.month, today.day);
      final result = <StudentSemesterOption>[];

      for (final raw in semesterRows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id'] as String;
        final override = overrides[id];
        final startsOn = DateTime.parse(
          (override?['starts_on'] ?? row['starts_on']).toString(),
        );
        final endsOn = DateTime.parse(
          (override?['ends_on'] ?? row['ends_on']).toString(),
        );

        if (endsOn.isBefore(localToday)) {
          continue;
        }

        result.add(
          StudentSemesterOption(
            id: id,
            code: row['code'].toString(),
            startsOn: startsOn,
            endsOn: endsOn,
          ),
        );
      }

      result.sort((a, b) => a.startsOn.compareTo(b.startsOn));
      return result;
    } on PostgrestException {
      throw const StudentAdminFailure(
        '학기 목록을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<String> createStudentAccount({
    required String name,
    required String pin,
    required String branchId,
    required String studentType,
  }) async {
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedName.isEmpty) {
      throw const StudentAdminFailure('학생 이름을 입력해주세요.');
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const StudentAdminFailure('PIN은 4자리 숫자로 입력해주세요.');
    }
    if (studentType != 'regular' && studentType != 'flex') {
      throw const StudentAdminFailure('수강 형태를 확인해주세요.');
    }

    try {
      final response = await _client.functions.invoke(
        'staff-create-student',
        body: {
          'name': normalizedName,
          'pin': pin,
          'branchId': branchId,
          'studentType': studentType,
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map) {
        throw StudentAdminFailure(
          data is Map && data['message'] != null
              ? data['message'].toString()
              : '학생 계정을 생성하지 못했습니다.',
        );
      }

      final studentId = data['studentId']?.toString();
      if (studentId == null || studentId.isEmpty) {
        throw const StudentAdminFailure('생성된 학생 계정을 확인하지 못했습니다.');
      }
      return studentId;
    } on StudentAdminFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw StudentAdminFailure(details['message'].toString());
      }
      throw const StudentAdminFailure(
        '학생 생성 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const StudentAdminFailure(
        '학생 계정을 생성하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<Map<String, dynamic>> initializeFlexSemester({
    required String studentId,
    required String teacherId,
    required String semesterId,
    required int baseRightCount,
    required int durationMinutes,
  }) async {
    if (baseRightCount <= 0) {
      throw const StudentAdminFailure('수강권 횟수는 1회 이상이어야 합니다.');
    }
    if (durationMinutes <= 0 ||
        durationMinutes > 720 ||
        durationMinutes % 15 != 0) {
      throw const StudentAdminFailure('수업 길이는 15분 단위로 선택해주세요.');
    }

    try {
      final result = await _client.rpc(
        'initialize_flex_student_semester',
        params: {
          'p_student_id': studentId,
          'p_teacher_id': teacherId,
          'p_semester_id': semesterId,
          'p_base_right_count': baseRightCount,
          'p_duration_minutes': durationMinutes,
        },
      );

      if (result is! Map) {
        throw const StudentAdminFailure('자율 예약 설정 결과를 확인하지 못했습니다.');
      }
      return Map<String, dynamic>.from(result);
    } on StudentAdminFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentAdminFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '자율 예약 설정을 완료하지 못했습니다.',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> initializeRegularSemester({
    required String studentId,
    required String teacherId,
    required String semesterId,
    required List<Map<String, dynamic>> schedules,
  }) async {
    try {
      final result = await _client.rpc(
        'initialize_regular_student_semester',
        params: {
          'p_student_id': studentId,
          'p_teacher_id': teacherId,
          'p_semester_id': semesterId,
          'p_schedules': schedules,
        },
      );

      if (result is! Map) {
        throw const StudentAdminFailure('정규 일정 생성 결과를 확인하지 못했습니다.');
      }
      return Map<String, dynamic>.from(result);
    } on StudentAdminFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentAdminFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '정규 일정 설정을 완료하지 못했습니다.',
        ),
      );
    }
  }

  String _friendlyDatabaseMessage(
    String message, {
    required String fallback,
  }) {
    String? userMessage;

    if (message.contains('FORESTRING_AUTH_REQUIRED')) {
      userMessage = '로그인이 필요합니다.';
    } else if (message.contains('FORESTRING_STAFF_REQUIRED')) {
      userMessage = '학생의 학기 설정을 관리할 권한이 없습니다.';
    } else if (message.contains('FORESTRING_STUDENT_NOT_FOUND')) {
      userMessage = '학생 정보를 찾을 수 없습니다.';
    } else if (message.contains('FORESTRING_STUDENT_INACTIVE')) {
      userMessage = '현재 재원 중인 학생만 학기 설정을 진행할 수 있습니다.';
    } else if (message.contains('FORESTRING_SEMESTER_NOT_FOUND')) {
      userMessage = '선택한 학기 정보를 찾을 수 없습니다.';
    } else if (message.contains('FORESTRING_FLEX_INITIAL_SETUP_ALREADY_EXISTS')) {
      userMessage = '이미 이 학기의 자율 예약 설정이 완료되어 있습니다.';
    } else if (message.contains('FORESTRING_INVALID_FLEX_RIGHT_COUNT')) {
      userMessage = '수강권 횟수는 1회 이상이어야 합니다.';
    } else if (message.contains('FORESTRING_INVALID_FLEX_DURATION')) {
      userMessage = '자율 예약 수업 길이는 15분 단위로 설정해주세요.';
    } else if (message.contains('FORESTRING_FLEX_STUDENT_REQUIRED')) {
      userMessage = '자율 예약 학생에게만 이 설정을 적용할 수 있습니다.';
    } else if (message.contains('FORESTRING_REGULAR_INITIAL_SETUP_ALREADY_EXISTS')) {
      userMessage = '이미 이 학기의 정규 일정이 설정되어 있습니다.';
    } else if (message.contains('FORESTRING_REGULAR_STUDENT_REQUIRED')) {
      userMessage = '정규 학생에게만 정규 일정을 설정할 수 있습니다.';
    } else if (message.contains('FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS')) {
      userMessage = '선택한 정규 시간이 담당 선생님의 근무시간 밖입니다.';
    } else if (message.contains('FORESTRING_INVALID_REGULAR_DURATION')) {
      userMessage = '정규 수업 길이를 확인해주세요.';
    } else if (message.contains('FORESTRING_INVALID_WEEKDAY')) {
      userMessage = '정규 수업 요일을 확인해주세요.';
    } else if (message.contains('FORESTRING_REGULAR_START_NOT_15_MINUTE_ALIGNED')) {
      userMessage = '정규 수업 시작 시간은 15분 단위로 선택해주세요.';
    } else if (message.contains('FORESTRING_INVALID_REGULAR_SCHEDULE') ||
        message.contains('FORESTRING_REGULAR_SCHEDULES_REQUIRED')) {
      userMessage = '정규 수업 일정을 하나 이상 올바르게 입력해주세요.';
    } else if (message.contains('FORESTRING_REGULAR_INITIAL_SETUP_CONFLICT') ||
        message.contains('FORESTRING_FLEX_INITIAL_SETUP_CONFLICT') ||
        message.contains('FORESTRING_ASSIGNMENT_PERIOD_OVERLAP') ||
        message.contains('TIME_CONFLICT')) {
      userMessage = '겹치는 담당 배정 또는 수업 일정이 있습니다.';
    } else if (message.contains('FORESTRING_MANAGER_BRANCH_MISMATCH') ||
        message.contains('FORESTRING_BRANCH_MISMATCH')) {
      userMessage = '학생과 담당 선생님의 지점이 일치하지 않습니다.';
    } else if (message.contains('FORESTRING_TEACHER_NOT_FOUND')) {
      userMessage = '담당 선생님 정보를 찾을 수 없습니다.';
    } else if (message.contains('FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL')) {
      userMessage = '퇴사 예정일 이후에는 해당 선생님을 배정할 수 없습니다.';
    }

    return _withErrorCode(userMessage ?? fallback, message);
  }

  String _withErrorCode(String userMessage, String rawMessage) {
    final match = RegExp(r'FORESTRING_[A-Z0-9_]+').firstMatch(rawMessage);
    final code = match?.group(0);
    if (code == null) return userMessage;
    return '$userMessage\n오류 코드: $code';
  }
}
