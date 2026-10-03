import 'package:supabase_flutter/supabase_flutter.dart';

class StudentManagementFailure implements Exception {
  const StudentManagementFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManagedStudent {
  const ManagedStudent({
    required this.id,
    required this.displayName,
    required this.branchId,
    required this.branchName,
    required this.studentType,
    required this.status,
    required this.profileIsActive,
    this.teacherId,
    this.teacherName,
    this.withdrawalDate,
    this.flexBaseRightCount,
    this.flexDurationMinutes,
  });

  final String id;
  final String displayName;
  final String? branchId;
  final String branchName;
  final String studentType;
  final String status;
  final bool profileIsActive;
  final String? teacherId;
  final String? teacherName;
  final DateTime? withdrawalDate;
  final int? flexBaseRightCount;
  final int? flexDurationMinutes;

  bool get isRegular => studentType == 'regular';
  bool get isFlex => studentType == 'flex';
  bool get isActive => status == 'active' && profileIsActive;
  bool get hasScheduledWithdrawal => isActive && withdrawalDate != null;

  bool get withdrawalIsDue {
    final date = withdrawalDate;
    if (!hasScheduledWithdrawal || date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final withdrawalDay = DateTime(date.year, date.month, date.day);
    return !withdrawalDay.isAfter(today);
  }

  String get typeLabel => isFlex ? '자율 예약 학생' : '정규 학생';

  String get statusLabel {
    if (!isActive) return '퇴원';
    if (hasScheduledWithdrawal) return '퇴원 예정';
    return '재원';
  }
}

class FlexRightCountChangeResult {
  const FlexRightCountChangeResult({
    required this.changed,
    required this.oldBaseRightCount,
    required this.newBaseRightCount,
    required this.insertedCount,
    required this.removedCount,
    required this.newCancellationLimit,
    required this.newCarryoverCap,
  });

  final bool changed;
  final int oldBaseRightCount;
  final int newBaseRightCount;
  final int insertedCount;
  final int removedCount;
  final int newCancellationLimit;
  final int newCarryoverCap;
}

class StudentWithdrawalResult {
  const StudentWithdrawalResult({
    required this.withdrawalDate,
    required this.finalized,
    this.deletedLessonCount = 0,
    this.revokedRightCount = 0,
  });

  final DateTime withdrawalDate;
  final bool finalized;
  final int deletedLessonCount;
  final int revokedRightCount;
}

class StudentManagementRepository {
  StudentManagementRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ManagedStudent>> fetchStudents({
    String? branchId,
  }) async {
    try {
      final profileRows = branchId == null
          ? await _client
              .from('profiles')
              .select('id, display_name, branch_id, is_active')
              .eq('role', 'student')
              .eq('is_review_account', false)
              .order('display_name')
          : await _client
              .from('profiles')
              .select('id, display_name, branch_id, is_active')
              .eq('role', 'student')
              .eq('is_review_account', false)
              .eq('branch_id', branchId)
              .order('display_name');

      final profiles = (profileRows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      if (profiles.isEmpty) {
        return const [];
      }

      final studentIds = profiles.map((row) => row['id'] as String).toList();
      final branchIds = profiles
          .map((row) => row['branch_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final results = await Future.wait([
        _client
            .from('students')
            .select('id, status, withdrawal_date, student_type')
            .inFilter('id', studentIds),
        _client
            .from('teacher_student_assignments')
            .select('student_id, teacher_id, branch_id, starts_on, ends_on')
            .inFilter('student_id', studentIds)
            .order('starts_on', ascending: false),
        if (branchIds.isEmpty)
          Future.value(<dynamic>[])
        else
          _client
              .from('branches')
              .select('id, name')
              .inFilter('id', branchIds)
              .order('name'),
        _client
            .from('student_semester_plans')
            .select(
              'student_id, flex_base_right_count, flex_duration_minutes, '
              'updated_at',
            )
            .inFilter('student_id', studentIds)
            .eq('student_type_snapshot', 'flex')
            .eq('status', 'active')
            .order('updated_at', ascending: false),
      ]);

      final studentRows = results[0]
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final assignmentRows = results[1]
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final branchRows = results[2]
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final activeFlexPlanByStudent = <String, Map<String, dynamic>>{};

      for (final raw in results[3]) {
        final row = Map<String, dynamic>.from(raw as Map);
        activeFlexPlanByStudent.putIfAbsent(
          row['student_id'] as String,
          () => row,
        );
      }

      final studentsById = <String, Map<String, dynamic>>{
        for (final row in studentRows) row['id'] as String: row,
      };
      final branchNames = <String, String>{
        for (final row in branchRows)
          row['id'] as String: row['name'].toString(),
      };

      final today = DateTime.now();
      final localToday = DateTime(today.year, today.month, today.day);
      final activeAssignmentByStudent = <String, Map<String, dynamic>>{};

      for (final row in assignmentRows) {
        final studentId = row['student_id'] as String;
        if (activeAssignmentByStudent.containsKey(studentId)) {
          continue;
        }

        final startsOn = DateTime.parse(row['starts_on'].toString());
        final endsOn = row['ends_on'] == null
            ? null
            : DateTime.parse(row['ends_on'].toString());

        final hasStarted = !startsOn.isAfter(localToday);
        final hasNotEnded = endsOn == null || !endsOn.isBefore(localToday);
        if (hasStarted && hasNotEnded) {
          activeAssignmentByStudent[studentId] = row;
        }
      }

      final teacherIds = activeAssignmentByStudent.values
          .map((row) => row['teacher_id'] as String)
          .toSet()
          .toList();

      final teacherNames = <String, String>{};
      if (teacherIds.isNotEmpty) {
        final teacherRows = await _client
            .from('profiles')
            .select('id, display_name')
            .inFilter('id', teacherIds)
            .eq('is_review_account', false)
            .order('display_name');

        for (final raw in teacherRows as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          teacherNames[row['id'] as String] = row['display_name'].toString();
        }
      }

      return profiles.map((profile) {
        final id = profile['id'] as String;
        final student = studentsById[id];
        final assignment = activeAssignmentByStudent[id];
        final teacherId = assignment?['teacher_id'] as String?;
        final branchId = profile['branch_id'] as String?;
        final withdrawalRaw = student?['withdrawal_date'];
        final flexPlan = activeFlexPlanByStudent[id];

        return ManagedStudent(
          id: id,
          displayName: profile['display_name'].toString(),
          branchId: branchId,
          branchName: branchId == null
              ? '지점 미지정'
              : (branchNames[branchId] ?? '지점 확인 필요'),
          studentType: student?['student_type']?.toString() ?? 'regular',
          status: student?['status']?.toString() ?? 'active',
          profileIsActive: profile['is_active'] == true,
          teacherId: teacherId,
          teacherName: teacherId == null ? null : teacherNames[teacherId],
          withdrawalDate: withdrawalRaw == null
              ? null
              : DateTime.parse(withdrawalRaw.toString()),
          flexBaseRightCount:
              (flexPlan?['flex_base_right_count'] as num?)?.toInt(),
          flexDurationMinutes:
              (flexPlan?['flex_duration_minutes'] as num?)?.toInt(),
        );
      }).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
    } on PostgrestException {
      throw const StudentManagementFailure(
        '수강생 목록을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    } catch (_) {
      throw const StudentManagementFailure(
        '수강생 목록을 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<void> updateStudentName({
    required String studentId,
    required String name,
  }) async {
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedName.isEmpty) {
      throw const StudentManagementFailure('이름을 입력해주세요.');
    }
    if (normalizedName.length > 100) {
      throw const StudentManagementFailure('이름은 100자 이하로 입력해주세요.');
    }

    try {
      final response = await _client.functions.invoke(
        'staff-update-account-name',
        body: {
          'profileId': studentId,
          'name': normalizedName,
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300) {
        throw StudentManagementFailure(
          data is Map && data['message'] != null
              ? data['message'].toString()
              : '이름을 변경하지 못했습니다.',
        );
      }
    } on StudentManagementFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw StudentManagementFailure(details['message'].toString());
      }
      throw const StudentManagementFailure(
        '이름 변경 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const StudentManagementFailure(
        '이름을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<void> resetStudentPin({
    required String studentId,
    required String pin,
  }) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const StudentManagementFailure(
        'PIN은 4자리 숫자로 입력해주세요.',
      );
    }

    try {
      final response = await _client.functions.invoke(
        'staff-reset-account-pin',
        body: {
          'profileId': studentId,
          'pin': pin,
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300) {
        throw StudentManagementFailure(
          data is Map && data['message'] != null
              ? data['message'].toString()
              : 'PIN을 변경하지 못했습니다.',
        );
      }
    } on StudentManagementFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw StudentManagementFailure(details['message'].toString());
      }
      throw const StudentManagementFailure(
        'PIN 변경 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const StudentManagementFailure(
        'PIN을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<FlexRightCountChangeResult> changeFlexBaseRightCount({
    required String studentId,
    required int newBaseRightCount,
  }) async {
    if (newBaseRightCount <= 0) {
      throw const StudentManagementFailure(
        '수업권 개수는 1개 이상이어야 합니다.',
      );
    }

    try {
      final result = await _client.rpc(
        'change_flex_base_right_count',
        params: {
          'p_student_id': studentId,
          'p_new_base_right_count': newBaseRightCount,
        },
      );

      if (result is! Map) {
        throw const StudentManagementFailure(
          '수업권 변경 결과를 확인하지 못했습니다.',
        );
      }

      final row = Map<String, dynamic>.from(result);
      return FlexRightCountChangeResult(
        changed: row['changed'] == true,
        oldBaseRightCount:
            (row['oldBaseRightCount'] as num?)?.toInt() ?? newBaseRightCount,
        newBaseRightCount:
            (row['newBaseRightCount'] as num?)?.toInt() ?? newBaseRightCount,
        insertedCount: (row['insertedCount'] as num?)?.toInt() ?? 0,
        removedCount: (row['removedCount'] as num?)?.toInt() ?? 0,
        newCancellationLimit:
            (row['newCancellationLimit'] as num?)?.toInt() ??
                (row['cancellationLimit'] as num?)?.toInt() ??
                0,
        newCarryoverCap:
            (row['newCarryoverCap'] as num?)?.toInt() ??
                (row['carryoverCap'] as num?)?.toInt() ??
                0,
      );
    } on StudentManagementFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentManagementFailure(
        _friendlyFlexRightCountMessage(error.message),
      );
    } catch (_) {
      throw const StudentManagementFailure(
        '수업권을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<StudentWithdrawalResult> scheduleWithdrawal({
    required String studentId,
    required DateTime withdrawalDate,
  }) async {
    final day = DateTime(
      withdrawalDate.year,
      withdrawalDate.month,
      withdrawalDate.day,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (day.isBefore(today)) {
      throw const StudentManagementFailure(
        '과거 날짜로 퇴원 처리할 수 없습니다.',
      );
    }

    try {
      await _client.rpc(
        'schedule_student_withdrawal',
        params: {
          'p_student_id': studentId,
          'p_withdrawal_date': _dateOnly(day),
        },
      );

      if (day == today) {
        return await finalizeWithdrawal(studentId: studentId);
      }

      return StudentWithdrawalResult(
        withdrawalDate: day,
        finalized: false,
      );
    } on PostgrestException catch (error) {
      throw StudentManagementFailure(
        _friendlyWithdrawalMessage(error.message),
      );
    }
  }

  Future<StudentWithdrawalResult> finalizeWithdrawal({
    required String studentId,
  }) async {
    try {
      final result = await _client.rpc(
        'finalize_student_withdrawal',
        params: {'p_student_id': studentId},
      );

      if (result is! Map) {
        throw const StudentManagementFailure(
          '퇴원 처리 결과를 확인하지 못했습니다.',
        );
      }

      final row = Map<String, dynamic>.from(result);
      final withdrawalDateRaw = row['withdrawalDate'];
      if (withdrawalDateRaw == null) {
        throw const StudentManagementFailure(
          '퇴원일을 확인하지 못했습니다.',
        );
      }

      return StudentWithdrawalResult(
        withdrawalDate: DateTime.parse(withdrawalDateRaw.toString()),
        finalized: true,
        deletedLessonCount: (row['deletedLessonCount'] as num?)?.toInt() ?? 0,
        revokedRightCount: (row['revokedRightCount'] as num?)?.toInt() ?? 0,
      );
    } on StudentManagementFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentManagementFailure(
        _friendlyWithdrawalMessage(error.message),
      );
    }
  }

  Future<void> cancelWithdrawal({
    required String studentId,
  }) async {
    try {
      await _client.rpc(
        'cancel_student_withdrawal',
        params: {'p_student_id': studentId},
      );
    } on PostgrestException catch (error) {
      throw StudentManagementFailure(
        _friendlyWithdrawalMessage(error.message),
      );
    }
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _friendlyWithdrawalMessage(String message) {
    String? userMessage;

    if (message.contains('FORESTRING_AUTH_REQUIRED')) {
      userMessage = '로그인이 필요합니다.';
    } else if (message.contains('FORESTRING_ACTIVE_USER_REQUIRED') ||
        message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED')) {
      userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
    } else if (message.contains('FORESTRING_STUDENT_WITHDRAWAL_DATE_IN_PAST')) {
      userMessage = '과거 날짜로 퇴원 처리할 수 없습니다.';
    } else if (message.contains('FORESTRING_STUDENT_WITHDRAWAL_FORBIDDEN') ||
        message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
      userMessage = '이 수강생의 퇴원 처리 권한이 없습니다.';
    } else if (message.contains('FORESTRING_STUDENT_NOT_ACTIVE')) {
      userMessage = '이미 퇴원했거나 현재 재원 상태가 아닌 수강생입니다.';
    } else if (message.contains('FORESTRING_STUDENT_WITHDRAWAL_NOT_READY')) {
      userMessage = '아직 퇴원 예정일이 되지 않았습니다.';
    } else if (message.contains('FORESTRING_STUDENT_WITHDRAWAL_ALREADY_EFFECTIVE')) {
      userMessage = '퇴원 예정일이 이미 도래했습니다. 퇴원 확정을 진행해주세요.';
    } else if (message.contains('FORESTRING_STUDENT_WITHDRAWAL_DATE_REQUIRED')) {
      userMessage = '퇴원일을 먼저 지정해주세요.';
    } else if (message.contains('FORESTRING_STUDENT_WITHDRAWAL_INVALID_STATE')) {
      userMessage = '현재 학생 상태에서는 퇴원을 확정할 수 없습니다. 학생 상태를 새로고침한 뒤 확인해주세요.';
    } else if (message.contains('FORESTRING_STUDENT_BRANCH_REQUIRED')) {
      userMessage = '학생의 지점 정보를 확인해주세요.';
    } else if (message.contains('FORESTRING_STUDENT_NOT_FOUND')) {
      userMessage = '수강생 정보를 찾지 못했습니다.';
    } else if (message.contains('FORESTRING_WITHDRAWAL_LESSON_DELETE_COUNT_MISMATCH')) {
      userMessage = '퇴원 처리 중 예정 수업 정리가 완료되지 않았습니다. 다시 시도해주세요.';
    }

    return _withErrorCode(
      userMessage ?? '퇴원 처리를 완료하지 못했습니다.',
      message,
    );
  }

  String _friendlyFlexRightCountMessage(String message) {
    String? userMessage;

    if (message.contains('FORESTRING_AUTH_REQUIRED')) {
      userMessage = '로그인이 필요합니다.';
    } else if (message.contains('FORESTRING_INVALID_FLEX_RIGHT_COUNT')) {
      userMessage = '수업권 개수는 1개 이상이어야 합니다.';
    } else if (message.contains('FORESTRING_ACTIVE_FLEX_PLAN_REQUIRED') ||
        message.contains('FORESTRING_FLEX_PLAN_CONFIGURATION_REQUIRED')) {
      userMessage = '현재 학기의 자율 수업권 설정을 찾지 못했습니다.';
    } else if (message.contains('FORESTRING_FLEX_STUDENT_REQUIRED')) {
      userMessage = '자율 예약 학생의 수업권만 변경할 수 있습니다.';
    } else if (message.contains('FORESTRING_ACTIVE_STUDENT_REQUIRED')) {
      userMessage = '현재 재원 중인 학생의 수업권만 변경할 수 있습니다.';
    } else if (message.contains('FORESTRING_STUDENT_NOT_FOUND')) {
      userMessage = '학생 정보를 찾을 수 없습니다.';
    } else if (message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN') ||
        message.contains('FORESTRING_STAFF_REQUIRED')) {
      userMessage = '이 학생의 수업권을 변경할 권한이 없습니다.';
    } else if (message.contains('FORESTRING_FLEX_RIGHT_COUNT_DECREASE_BLOCKED')) {
      userMessage = '예약 중이거나 이미 완료된 수업이 많아 이 개수까지 줄일 수 없습니다. '
          '예정 수업을 관리자 취소한 뒤 다시 시도해주세요.';
    } else if (message.contains('FORESTRING_ACTIVE_PLAN_BRANCH_MISMATCH')) {
      userMessage = '현재 학기 수업권의 지점 정보가 학생 정보와 일치하지 않습니다.';
    } else if (message.contains('FORESTRING_FLEX_RIGHTS_PLAN_MISMATCH') ||
        message.contains('FORESTRING_FLEX_RIGHT_COUNT_MISMATCH')) {
      userMessage = '현재 학기 수업권 원장과 설정이 일치하지 않아 변경할 수 없습니다.';
    } else if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED')) {
      userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
    }

    return _withErrorCode(
      userMessage ?? '수업권을 변경하지 못했습니다.',
      message,
    );
  }

  String _withErrorCode(String userMessage, String rawMessage) {
    final match = RegExp(r'FORESTRING_[A-Z0-9_]+').firstMatch(rawMessage);
    final code = match?.group(0);
    if (code == null) return userMessage;
    return '$userMessage\n오류 코드: $code';
  }
}
