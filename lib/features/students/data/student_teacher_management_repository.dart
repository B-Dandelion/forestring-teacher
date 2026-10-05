import 'package:supabase_flutter/supabase_flutter.dart';

class StudentTeacherManagementFailure implements Exception {
  const StudentTeacherManagementFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManagedTeacherOption {
  const ManagedTeacherOption({
    required this.id,
    required this.displayName,
    required this.branchId,
  });

  final String id;
  final String displayName;
  final String branchId;
}

class StudentTeacherManagementRepository {
  StudentTeacherManagementRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ManagedTeacherOption>> fetchBranchTeachers(String branchId) async {
    try {
      final rawRows = await _client
          .from('profiles')
          .select('id, display_name, branch_id, role, is_active')
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .eq('is_review_account', false)
          .eq('is_qa_account', false)
          .inFilter('role', ['teacher', 'manager'])
          .order('display_name');

      final rows = rawRows
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      final managerIds = rows
          .where((row) => row['role']?.toString() == 'manager')
          .map((row) => row['id'] as String)
          .toList();

      final teachingManagerIds = <String>{};
      if (managerIds.isNotEmpty) {
        final workHourRows = await _client
            .from('teacher_work_hours')
            .select('teacher_id')
            .inFilter('teacher_id', managerIds);

        for (final raw in workHourRows) {
          teachingManagerIds.add(raw['teacher_id'] as String);
        }
      }

      return rows
          .where((row) {
            final role = row['role']?.toString();
            return role == 'teacher' ||
                (role == 'manager' &&
                    teachingManagerIds.contains(row['id'] as String));
          })
          .map(
            (row) => ManagedTeacherOption(
              id: row['id'] as String,
              displayName: row['display_name'].toString(),
              branchId: row['branch_id'] as String,
            ),
          )
          .toList();
    } on PostgrestException {
      throw const StudentTeacherManagementFailure(
        '선생님 목록을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    } catch (_) {
      throw const StudentTeacherManagementFailure(
        '선생님 목록을 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<Map<String, dynamic>> changeStudentTeacher({
    required String studentId,
    required String teacherId,
    required DateTime effectiveOn,
    required String? currentTeacherId,
    required bool isFlex,
  }) async {
    final date = _dateOnly(effectiveOn);

    try {
      if (currentTeacherId == null) {
        if (!isFlex) {
          throw const StudentTeacherManagementFailure(
            '정규 학생의 기존 담당 선생님 배정이 없습니다.\n'
            '먼저 학생의 정규 일정 상태를 확인해주세요.',
          );
        }

        final result = await _client.rpc(
          'assign_student_teacher',
          params: {
            'p_student_id': studentId,
            'p_teacher_id': teacherId,
            'p_starts_on': date,
          },
        );

        return {
          'changed': true,
          'assignmentId': result,
          'teacherId': teacherId,
          'effectiveOn': date,
        };
      }

      final result = await _client.rpc(
        'change_student_teacher',
        params: {
          'p_student_id': studentId,
          'p_teacher_id': teacherId,
          'p_effective_on': date,
        },
      );

      if (result is! Map) {
        throw const StudentTeacherManagementFailure(
          '담당 선생님 변경 결과를 확인하지 못했습니다.',
        );
      }

      return Map<String, dynamic>.from(result);
    } on StudentTeacherManagementFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentTeacherManagementFailure(
        _friendlyDatabaseMessage(error.message),
      );
    } catch (_) {
      throw const StudentTeacherManagementFailure(
        '담당 선생님을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  String _dateOnly(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _friendlyDatabaseMessage(String message) {
    String? userMessage;

    if (message.contains('FORESTRING_AUTH_REQUIRED')) {
      userMessage = '로그인이 필요합니다.';
    } else if (message.contains('FORESTRING_ACTIVE_USER_REQUIRED')) {
      userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
    } else if (message.contains('FORESTRING_BACKDATED_TEACHER_CHANGE_FORBIDDEN')) {
      userMessage = '과거 날짜로 담당 선생님을 변경할 수 없습니다.';
    } else if (message.contains('FORESTRING_EFFECTIVE_DATE_REQUIRED')) {
      userMessage = '담당 선생님 변경 적용일을 선택해주세요.';
    } else if (message.contains('FORESTRING_BRANCH_MISMATCH') ||
        message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
      userMessage = '같은 지점의 선생님만 담당 선생님으로 지정할 수 있습니다.';
    } else if (message.contains('FORESTRING_FUTURE_TEACHER_ASSIGNMENT_EXISTS')) {
      userMessage = '이미 예정된 담당 선생님 변경이 있습니다. 기존 변경 일정을 먼저 확인해주세요.';
    } else if (message.contains('FORESTRING_CURRENT_TEACHER_ASSIGNMENT_NOT_FOUND')) {
      userMessage = '현재 담당 선생님 배정을 찾지 못했습니다.';
    } else if (message.contains('FORESTRING_ASSIGNMENT_PERIOD_OVERLAP')) {
      userMessage = '담당 선생님 배정 기간이 기존 배정과 겹칩니다.';
    } else if (message.contains('FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL') ||
        message.contains('FORESTRING_TEACHER_INACTIVE')) {
      userMessage = '선택한 선생님은 해당 날짜에 담당 선생님으로 지정할 수 없습니다.';
    } else if (message.contains('FORESTRING_TEACHER_CHANGE_AFTER_STUDENT_WITHDRAWAL') ||
        message.contains('FORESTRING_STUDENT_INACTIVE')) {
      userMessage = '퇴원했거나 퇴원 예정일 이후인 학생의 담당 선생님은 변경할 수 없습니다.';
    } else if (message.contains('FORESTRING_STUDENT_NOT_FOUND')) {
      userMessage = '학생 정보를 찾을 수 없습니다.';
    } else if (message.contains('FORESTRING_TEACHER_NOT_FOUND')) {
      userMessage = '선생님 정보를 찾을 수 없습니다.';
    } else if (message.contains('FORESTRING_REGULAR_SERIES_NOT_FOUND_FOR_TEACHER_CHANGE')) {
      userMessage = '변경할 정규 수업 일정을 찾지 못했습니다. 학생의 정규 일정 상태를 확인해주세요.';
    } else if (message.contains('FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS')) {
      userMessage = '기존 정규 수업 시간이 새 선생님의 근무시간 밖입니다.';
    } else if (message.contains('TIME_CONFLICT') ||
        message.contains('FORESTRING_REGULAR_INITIAL_SETUP_CONFLICT')) {
      userMessage = '새 선생님의 기존 수업과 시간이 겹칩니다.';
    } else if (message.contains('FORESTRING_TEACHER_CHANGE_FORBIDDEN')) {
      userMessage = '담당 선생님 변경 권한이 없습니다.';
    }

    return _withErrorCode(
      userMessage ?? '담당 선생님을 변경하지 못했습니다.',
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
