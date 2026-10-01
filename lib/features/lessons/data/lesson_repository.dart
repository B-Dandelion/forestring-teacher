import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/lesson.dart';

class LessonFailure implements Exception {
  const LessonFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class VisibleStudent {
  const VisibleStudent({
    required this.id,
    required this.displayName,
    required this.isActive,
    this.branchId,
  });

  final String id;
  final String displayName;
  final String? branchId;
  final bool isActive;
}

class LessonRepository {
  LessonRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Lesson>> fetchVisibleLessons({
    DateTime? from,
    DateTime? to,
    String? teacherId,
    String? studentId,
  }) async {
    try {
      const pageSize = 500;
      final rows = <dynamic>[];

      for (var offset = 0;; offset += pageSize) {
        dynamic query = _client.from('lessons').select(
              'id, student_id, teacher_id, occurrence_at, starts_at, '
              'duration_minutes, ends_at, lesson_type, status, branch_id, '
              'lesson_right_id, rescheduled_by, canceled_at, '
              'cancellation_reason',
            );

        if (from != null) {
          query = query.gte('starts_at', from.toUtc().toIso8601String());
        }
        if (to != null) {
          query = query.lt('starts_at', to.toUtc().toIso8601String());
        }
        if (teacherId != null && teacherId.isNotEmpty) {
          query = query.eq('teacher_id', teacherId);
        }
        if (studentId != null && studentId.isNotEmpty) {
          query = query.eq('student_id', studentId);
        }

        final page = await query
            .order('starts_at', ascending: true)
            .range(offset, offset + pageSize - 1);
        final pageRows = page as List;
        rows.addAll(pageRows);

        if (pageRows.length < pageSize) {
          break;
        }
      }

      final lessons = rows
          .map(
            (row) => Lesson.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
      final names = await _fetchVisibleProfileNames();

      return lessons
          .map(
            (lesson) => lesson.copyWithNames(
              studentName: names[lesson.studentId],
              teacherName: names[lesson.teacherId],
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '수업 정보를 불러오지 못했습니다.',
        ),
      );
    } catch (_) {
      throw const LessonFailure(
        '수업 정보를 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<List<VisibleTeacher>> fetchVisibleTeachers() async {
    try {
      final rawRows = await _client
          .from('profiles')
          .select('id, display_name, branch_id, role, is_active')
          .inFilter('role', ['teacher', 'manager'])
          .eq('is_active', true)
          .order('display_name');

      final rows = (rawRows as List)
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
        for (final raw in workHourRows as List) {
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
            (row) => VisibleTeacher(
              id: row['id'] as String,
              displayName: row['display_name'] as String,
              branchId: row['branch_id'] as String?,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '선생님 목록을 불러오지 못했습니다.',
        ),
      );
    }
  }

  Future<List<VisibleStudent>> fetchVisibleStudents() async {
    try {
      final profileRows = await _client
          .from('profiles')
          .select('id, display_name, branch_id, is_active')
          .eq('role', 'student')
          .eq('is_review_account', false)
          .order('display_name');

      final profiles = (profileRows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      if (profiles.isEmpty) return const [];

      final ids = profiles.map((row) => row['id'] as String).toList();
      final studentRows = await _client
          .from('students')
          .select('id, status')
          .inFilter('id', ids);
      final statusById = <String, String>{
        for (final raw in studentRows as List)
          raw['id'] as String: raw['status'].toString(),
      };

      return profiles
          .map(
            (row) => VisibleStudent(
              id: row['id'] as String,
              displayName: row['display_name'].toString(),
              branchId: row['branch_id'] as String?,
              isActive: row['is_active'] == true &&
                  statusById[row['id']] == 'active',
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '수강생 정보를 불러오지 못했습니다.',
        ),
      );
    } catch (_) {
      throw const LessonFailure(
        '수강생 정보를 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<List<TeacherBlockedPeriod>> fetchVisibleBlockedPeriods({
    DateTime? from,
    DateTime? to,
    String? teacherId,
  }) async {
    try {
      dynamic query = _client.from('blocked_periods').select(
            'id, teacher_id, starts_at, ends_at, reason, created_at',
          );

      if (from != null) {
        query = query.gt('ends_at', from.toUtc().toIso8601String());
      }
      if (to != null) {
        query = query.lt('starts_at', to.toUtc().toIso8601String());
      }
      if (teacherId != null && teacherId.isNotEmpty) {
        query = query.eq('teacher_id', teacherId);
      }

      final rows = await query.order('starts_at', ascending: true);
      final periods = (rows as List)
          .map(
            (row) => TeacherBlockedPeriod.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
      final names = await _fetchVisibleProfileNames();

      return periods
          .map(
            (period) => period.copyWithTeacherName(names[period.teacherId]),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '개인 일정을 불러오지 못했습니다.',
        ),
      );
    } catch (_) {
      throw const LessonFailure(
        '개인 일정을 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<Map<String, List<TeacherWorkHour>>> fetchVisibleWorkHours({
    String? teacherId,
  }) async {
    try {
      dynamic query = _client.from('teacher_work_hours').select(
            'teacher_id, weekday, start_time, end_time',
          );
      if (teacherId != null && teacherId.isNotEmpty) {
        query = query.eq('teacher_id', teacherId);
      }

      final rows = await query.order('weekday');
      final result = <String, List<TeacherWorkHour>>{};
      for (final raw in rows as List) {
        final workHour = TeacherWorkHour.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
        result.putIfAbsent(workHour.teacherId, () => []).add(workHour);
      }
      return result;
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '근무시간을 불러오지 못했습니다.',
        ),
      );
    }
  }

  Future<int> fetchAvailableLessonRightCount({
    required String studentId,
    required String semesterId,
    required int durationMinutes,
  }) async {
    try {
      final rows = await _client
          .from('lesson_rights')
          .select('id')
          .eq('student_id', studentId)
          .eq('usable_semester_id', semesterId)
          .eq('duration_minutes', durationMinutes)
          .eq('status', 'available');
      return (rows as List).length;
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '사용 가능한 수업권을 확인하지 못했습니다.',
        ),
      );
    }
  }

  Future<void> cancelLesson({
    required String lessonId,
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'cancel_lesson',
        params: {
          'p_lesson_id': lessonId,
          'p_reason': _nullIfBlank(reason),
        },
      );
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '수업을 취소하지 못했습니다.',
        ),
      );
    }
  }

  Future<void> cancelStandaloneMakeupLesson({
    required String lessonId,
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'cancel_standalone_makeup_lesson',
        params: {
          'p_lesson_id': lessonId,
          'p_reason': _nullIfBlank(reason),
        },
      );
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '보강 수업을 취소하지 못했습니다.',
        ),
      );
    }
  }

  Future<LessonMutationResult> createMakeupLesson({
    required String studentId,
    required String teacherId,
    required DateTime startsAt,
    required int durationMinutes,
    bool confirmWarnings = false,
    bool deductLessonRight = false,
    String? reason,
  }) async {
    try {
      final data = await _client.rpc(
        'create_managed_makeup_lesson',
        params: {
          'p_student_id': studentId,
          'p_teacher_id': teacherId,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_duration_minutes': durationMinutes,
          'p_confirm_warnings': confirmWarnings,
          'p_reason': _nullIfBlank(reason),
          'p_deduct_lesson_right': deductLessonRight,
        },
      );

      if (data is! Map) {
        throw const LessonFailure('보강 수업 등록 결과를 확인하지 못했습니다.');
      }

      return LessonMutationResult.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on LessonFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '보강 수업을 등록하지 못했습니다.',
        ),
      );
    }
  }

  Future<LessonMutationResult> updateLessonOnce({
    required String lessonId,
    required DateTime startsAt,
    required int durationMinutes,
    bool confirmWarnings = false,
    String? reason,
  }) async {
    try {
      final data = await _client.rpc(
        'update_lesson_once',
        params: {
          'p_lesson_id': lessonId,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_duration_minutes': durationMinutes,
          'p_confirm_warnings': confirmWarnings,
          'p_reason': _nullIfBlank(reason),
        },
      );

      if (data is! Map) {
        throw const LessonFailure('수업 수정 결과를 확인하지 못했습니다.');
      }

      return LessonMutationResult.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on LessonFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '수업을 변경하지 못했습니다.',
        ),
      );
    }
  }

  Future<Map<String, String>> _fetchVisibleProfileNames() async {
    final rows = await _client.from('profiles').select('id, display_name');
    return {
      for (final row in rows as List)
        row['id'] as String: row['display_name'] as String,
    };
  }

  String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _friendlyDatabaseMessage(
    String message, {
    required String fallback,
  }) {
    String? userMessage;

    if (message.contains('FORESTRING_AUTH_REQUIRED')) {
      userMessage = '로그인이 필요합니다.';
    } else if (message.contains('FORESTRING_ACTIVE_USER_REQUIRED') ||
        message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED')) {
      userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
    } else if (message.contains('FORESTRING_LESSON_MANAGEMENT_REQUIRED')) {
      userMessage = '마스터 또는 지점장만 수업을 관리할 수 있습니다.';
    } else if (message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
      userMessage = '다른 지점의 수업은 관리할 수 없습니다.';
    } else if (message.contains('FORESTRING_LESSON_UPDATE_FORBIDDEN') ||
        message.contains('FORESTRING_CANCELLATION_FORBIDDEN') ||
        message.contains('FORESTRING_LESSON_FORBIDDEN')) {
      userMessage = '이 수업을 변경하거나 취소할 권한이 없습니다.';
    } else if (message.contains('FORESTRING_ACTIVE_STUDENT_REQUIRED')) {
      userMessage = '현재 재원 중인 학생만 보강 수업을 등록할 수 있습니다.';
    } else if (message.contains('FORESTRING_ACTIVE_TEACHER_REQUIRED')) {
      userMessage = '현재 수업 가능한 선생님 또는 지점장을 선택해주세요.';
    } else if (message.contains('FORESTRING_MAKEUP_START_IN_PAST')) {
      userMessage = '과거 시간으로 보강 수업을 등록할 수 없습니다.';
    } else if (message.contains('FORESTRING_MAKEUP_CROSSES_DAY')) {
      userMessage = '보강 수업은 자정을 넘길 수 없습니다.';
    } else if (message.contains('FORESTRING_MAKEUP_INPUT_REQUIRED')) {
      userMessage = '보강 수업의 학생, 선생님, 시간 정보를 확인해주세요.';
    } else if (message.contains('FORESTRING_MAKEUP_LESSON_NOT_FOUND_AFTER_CREATE')) {
      userMessage = '보강 수업은 생성되었지만 결과를 확인하지 못했습니다. 새로고침 후 확인해주세요.';
    } else if (message.contains('FORESTRING_SEMESTER_NOT_FOUND_FOR_DATE')) {
      userMessage = '선택한 날짜에 적용되는 학기가 없습니다.';
    } else if (message.contains('FORESTRING_NO_MATCHING_AVAILABLE_LESSON_RIGHT')) {
      userMessage = '선택한 수업 길이와 같은 사용 가능한 수업권이 없습니다.';
    } else if (message.contains('FORESTRING_CLOSURE_CONFLICT')) {
      userMessage = '휴원 기간에는 보강 수업을 등록할 수 없습니다.';
    } else if (message.contains('FORESTRING_TEACHER_LESSON_OVERLAP') ||
        message.contains('FORESTRING_STUDENT_LESSON_OVERLAP') ||
        message.contains('FORESTRING_LESSON_TIME_CONFLICT')) {
      userMessage = '겹치는 수업이 있어 해당 시간을 사용할 수 없습니다.';
    } else if (message.contains('FORESTRING_LESSON_BLOCKED_PERIOD_CONFLICT') ||
        message.contains('FORESTRING_OVERLAPS_BLOCKED_PERIOD')) {
      userMessage = '선생님의 개인 일정과 겹쳐 해당 시간을 사용할 수 없습니다.';
    } else if (message.contains('FORESTRING_OUTSIDE_WORK_HOURS')) {
      userMessage = '선택한 시간이 선생님의 근무시간 밖입니다.';
    } else if (message.contains('FORESTRING_LESSON_AFTER_STUDENT_WITHDRAWAL')) {
      userMessage = '학생의 퇴원일 이후에는 수업을 등록할 수 없습니다.';
    } else if (message.contains('FORESTRING_LESSON_AFTER_TEACHER_WITHDRAWAL')) {
      userMessage = '선생님의 퇴사일 이후에는 수업을 등록할 수 없습니다.';
    } else if (message.contains('FORESTRING_STANDALONE_MAKEUP_REQUIRED')) {
      userMessage = '이 수업은 보강 수업 취소 기능으로 처리할 수 없습니다.';
    } else if (message.contains('FORESTRING_ONLY_SCHEDULED_LESSON_EDITABLE') ||
        message.contains('FORESTRING_LESSON_NOT_SCHEDULED')) {
      userMessage = '예정된 수업만 수정하거나 취소할 수 있습니다.';
    } else if (message.contains('FORESTRING_CANCELLATION_TOO_LATE')) {
      userMessage = '취소 가능 시간이 지나 이 수업을 취소할 수 없습니다.';
    } else if (message.contains('FORESTRING_CANCELLATION_LIMIT_REACHED')) {
      userMessage = '이번 학기의 수업 취소 가능 횟수를 모두 사용했습니다.';
    } else if (message.contains('FORESTRING_INVALID_LESSON_DURATION')) {
      userMessage = '수업 시간은 15분 단위로 입력해주세요.';
    } else if (message.contains('FORESTRING_NONSTANDARD_DURATION')) {
      userMessage = '일반적이지 않은 수업 길이입니다. 내용을 확인한 뒤 다시 진행해주세요.';
    } else if (message.contains('FORESTRING_LESSON_START_REQUIRED')) {
      userMessage = '변경할 수업 시작 시간을 선택해주세요.';
    } else if (message.contains('FORESTRING_LESSON_BRANCH_REQUIRED')) {
      userMessage = '수업의 지점 정보를 확인해주세요.';
    } else if (message.contains('FORESTRING_LESSON_NOT_FOUND')) {
      userMessage = '수업을 찾을 수 없습니다. 새로고침 후 다시 확인해주세요.';
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
