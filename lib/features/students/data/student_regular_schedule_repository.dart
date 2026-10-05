import 'package:supabase_flutter/supabase_flutter.dart';

class StudentRegularScheduleFailure implements Exception {
  const StudentRegularScheduleFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManagedRegularSchedule {
  const ManagedRegularSchedule({
    required this.slotId,
    required this.teacherId,
    required this.teacherName,
    required this.weekday,
    required this.startMinutes,
    required this.durationMinutes,
    required this.slotStartsOn,
    required this.effectiveFrom,
    required this.hasFutureVersion,
    this.slotEndsOn,
    this.effectiveUntil,
    this.nextVersionDate,
  });

  final String slotId;
  final String teacherId;
  final String teacherName;
  final int weekday;
  final int startMinutes;
  final int durationMinutes;
  final DateTime slotStartsOn;
  final DateTime? slotEndsOn;
  final DateTime effectiveFrom;
  final DateTime? effectiveUntil;
  final bool hasFutureVersion;
  final DateTime? nextVersionDate;

  String get weekdayLabel => switch (weekday) {
        1 => '월요일',
        2 => '화요일',
        3 => '수요일',
        4 => '목요일',
        5 => '금요일',
        6 => '토요일',
        7 => '일요일',
        _ => '요일 확인 필요',
      };

  String get timeLabel => _formatMinutes(startMinutes);

  static String _formatMinutes(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class RegularScheduleTeacher {
  const RegularScheduleTeacher({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;
}

class TeacherWorkWindow {
  const TeacherWorkWindow({
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
  });

  final int weekday;
  final int startMinutes;
  final int endMinutes;
}

class RegularScheduleSemesterOption {
  const RegularScheduleSemesterOption({
    required this.id,
    required this.code,
    required this.startsOn,
    required this.endsOn,
  });

  final String id;
  final String code;
  final DateTime startsOn;
  final DateTime endsOn;

  bool isSelectableOn(
    DateTime date, {
    bool includeCurrent = false,
  }) {
    final day = DateTime(date.year, date.month, date.day);
    return includeCurrent ? !endsOn.isBefore(day) : startsOn.isAfter(day);
  }

  bool isInProgressOn(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !startsOn.isAfter(day) && !endsOn.isBefore(day);
  }

  DateTime effectiveOnFor(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return startsOn.isAfter(day) ? startsOn : day;
  }
}

class StudentRegularScheduleRepository {
  StudentRegularScheduleRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ManagedRegularSchedule>> fetchSchedules(String studentId) async {
    try {
      final slotRows = await _client
          .from('regular_schedule_slots')
          .select('id, starts_on, ends_on')
          .eq('student_id', studentId)
          .order('starts_on');

      if (slotRows.isEmpty) {
        return const [];
      }

      final slotIds = slotRows.map((row) => row['id'] as String).toList();
      final seriesRows = await _client
          .from('lesson_series')
          .select(
            'id, schedule_slot_id, teacher_id, weekday, start_time, '
            'duration_minutes, effective_from, effective_until',
          )
          .inFilter('schedule_slot_id', slotIds)
          .order('effective_from');

      final teacherIds = seriesRows
          .map((row) => row['teacher_id'] as String)
          .toSet()
          .toList();

      final teacherNames = <String, String>{};
      if (teacherIds.isNotEmpty) {
        final profileRows = await _client
            .from('profiles')
            .select('id, display_name')
            .inFilter('id', teacherIds)
            .eq('is_review_account', false)
            .eq('is_qa_account', false);

        for (final row in profileRows) {
          teacherNames[row['id'] as String] = row['display_name'].toString();
        }
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final versionsBySlot = <String, List<Map<String, dynamic>>>{};

      for (final raw in seriesRows) {
        final row = Map<String, dynamic>.from(raw);
        final slotId = row['schedule_slot_id'] as String;
        versionsBySlot.putIfAbsent(slotId, () => []).add(row);
      }

      final schedules = <ManagedRegularSchedule>[];

      for (final rawSlot in slotRows) {
        final slot = Map<String, dynamic>.from(rawSlot);
        final slotId = slot['id'] as String;
        final slotStartsOn = DateTime.parse(slot['starts_on'].toString());
        final slotEndsOn = slot['ends_on'] == null
            ? null
            : DateTime.parse(slot['ends_on'].toString());

        if (slotEndsOn != null && slotEndsOn.isBefore(today)) {
          continue;
        }

        final referenceDate = slotStartsOn.isAfter(today) ? slotStartsOn : today;
        final versions = versionsBySlot[slotId] ?? const [];

        Map<String, dynamic>? current;
        DateTime? nextVersionDate;

        for (final version in versions) {
          final from = DateTime.parse(version['effective_from'].toString());
          final until = version['effective_until'] == null
              ? null
              : DateTime.parse(version['effective_until'].toString());

          final coversReference = !from.isAfter(referenceDate) &&
              (until == null || !until.isBefore(referenceDate));
          if (coversReference) {
            current = version;
          } else if (from.isAfter(referenceDate) &&
              (nextVersionDate == null || from.isBefore(nextVersionDate))) {
            nextVersionDate = from;
          }
        }

        current ??= versions.isEmpty ? null : versions.first;
        if (current == null) {
          continue;
        }

        final teacherId = current['teacher_id'] as String;
        final startMinutes = _parseTimeMinutes(current['start_time'].toString());

        schedules.add(
          ManagedRegularSchedule(
            slotId: slotId,
            teacherId: teacherId,
            teacherName: teacherNames[teacherId] ?? '선생님 확인 필요',
            weekday: (current['weekday'] as num).toInt(),
            startMinutes: startMinutes,
            durationMinutes: (current['duration_minutes'] as num).toInt(),
            slotStartsOn: slotStartsOn,
            slotEndsOn: slotEndsOn,
            effectiveFrom: DateTime.parse(current['effective_from'].toString()),
            effectiveUntil: current['effective_until'] == null
                ? null
                : DateTime.parse(current['effective_until'].toString()),
            hasFutureVersion: nextVersionDate != null,
            nextVersionDate: nextVersionDate,
          ),
        );
      }

      schedules.sort((a, b) {
        final weekday = a.weekday.compareTo(b.weekday);
        if (weekday != 0) return weekday;
        return a.startMinutes.compareTo(b.startMinutes);
      });
      return schedules;
    } on PostgrestException {
      throw const StudentRegularScheduleFailure(
        '정규 일정을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    } catch (_) {
      throw const StudentRegularScheduleFailure(
        '정규 일정을 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<RegularScheduleTeacher> fetchTeacherAtDate({
    required String studentId,
    required DateTime date,
  }) async {
    try {
      final rows = await _client
          .from('teacher_student_assignments')
          .select('teacher_id, starts_on, ends_on')
          .eq('student_id', studentId)
          .order('starts_on', ascending: false);

      final target = DateTime(date.year, date.month, date.day);
      String? teacherId;

      for (final row in rows) {
        final startsOn = DateTime.parse(row['starts_on'].toString());
        final endsOn = row['ends_on'] == null
            ? null
            : DateTime.parse(row['ends_on'].toString());
        if (!startsOn.isAfter(target) &&
            (endsOn == null || !endsOn.isBefore(target))) {
          teacherId = row['teacher_id'] as String;
          break;
        }
      }

      if (teacherId == null) {
        throw const StudentRegularScheduleFailure(
          '선택한 적용일의 담당 선생님을 찾지 못했습니다.',
        );
      }

      final profile = await _client
          .from('profiles')
          .select('id, display_name')
          .eq('id', teacherId)
          .eq('is_active', true)
          .single();

      return RegularScheduleTeacher(
        id: teacherId,
        displayName: profile['display_name'].toString(),
      );
    } on StudentRegularScheduleFailure {
      rethrow;
    } on PostgrestException {
      throw const StudentRegularScheduleFailure(
        '담당 선생님 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<List<TeacherWorkWindow>> fetchTeacherWorkHours(
    String teacherId,
  ) async {
    try {
      final rows = await _client
          .from('teacher_work_hours')
          .select('weekday, start_time, end_time')
          .eq('teacher_id', teacherId)
          .order('weekday')
          .order('start_time');

      return rows
          .map(
            (row) => TeacherWorkWindow(
              weekday: (row['weekday'] as num).toInt(),
              startMinutes: _parseTimeMinutes(row['start_time'].toString()),
              endMinutes: _parseTimeMinutes(row['end_time'].toString()),
            ),
          )
          .toList();
    } on PostgrestException {
      throw const StudentRegularScheduleFailure(
        '선생님 근무시간을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<List<RegularScheduleSemesterOption>> fetchUpcomingSemesters(
    String? branchId, {
    bool includeCurrent = false,
  }) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final rows = await _client
          .from('semesters')
          .select('id, code, starts_on, ends_on')
          .order('starts_on', ascending: true);

      final overrides = <String, Map<String, dynamic>>{};
      if (branchId != null) {
        try {
          final overrideRows = await _client
              .from('branch_semester_overrides')
              .select('semester_id, starts_on, ends_on')
              .eq('branch_id', branchId);
          for (final row in overrideRows) {
            overrides[row['semester_id'] as String] =
                Map<String, dynamic>.from(row);
          }
        } on PostgrestException {
          // Global semester dates are the fallback when no branch override
          // is readable or configured.
        }
      }

      final result = <RegularScheduleSemesterOption>[];
      for (final row in rows) {
        final id = row['id'] as String;
        final override = overrides[id];
        final startsOn = DateTime.parse(
          (override?['starts_on'] ?? row['starts_on']).toString(),
        );
        final endsOn = DateTime.parse(
          (override?['ends_on'] ?? row['ends_on']).toString(),
        );
        final option = RegularScheduleSemesterOption(
          id: id,
          code: row['code'].toString(),
          startsOn: startsOn,
          endsOn: endsOn,
        );
        if (!option.isSelectableOn(today, includeCurrent: includeCurrent)) {
          continue;
        }

        result.add(option);
      }

      result.sort((a, b) => a.startsOn.compareTo(b.startsOn));
      return result.length <= 12 ? result : result.take(12).toList();
    } on PostgrestException {
      throw const StudentRegularScheduleFailure(
        '적용할 학기를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<Map<String, dynamic>> addSchedule({
    required String studentId,
    required String teacherId,
    required int weekday,
    required int startMinutes,
    required int durationMinutes,
    required DateTime effectiveOn,
  }) async {
    try {
      final result = await _client.rpc(
        'add_regular_schedule',
        params: {
          'p_student_id': studentId,
          'p_teacher_id': teacherId,
          'p_weekday': weekday,
          'p_start_time': _formatTime(startMinutes),
          'p_duration_minutes': durationMinutes,
          'p_effective_on': _formatDate(effectiveOn),
        },
      );

      if (result is! Map) {
        throw const StudentRegularScheduleFailure(
          '정규 일정 추가 결과를 확인하지 못했습니다.',
        );
      }
      return Map<String, dynamic>.from(result);
    } on StudentRegularScheduleFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentRegularScheduleFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '정규 일정을 추가하지 못했습니다.',
        ),
      );
    } catch (_) {
      throw const StudentRegularScheduleFailure(
        '정규 일정을 추가하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<Map<String, dynamic>> endSchedule({
    required String scheduleSlotId,
    required DateTime effectiveOn,
  }) async {
    try {
      final result = await _client.rpc(
        'end_regular_schedule',
        params: {
          'p_schedule_slot_id': scheduleSlotId,
          'p_effective_on': _formatDate(effectiveOn),
        },
      );

      if (result is! Map) {
        throw const StudentRegularScheduleFailure(
          '정규 일정 종료 결과를 확인하지 못했습니다.',
        );
      }
      return Map<String, dynamic>.from(result);
    } on StudentRegularScheduleFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentRegularScheduleFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '정규 일정을 종료하지 못했습니다.',
        ),
      );
    } catch (_) {
      throw const StudentRegularScheduleFailure(
        '정규 일정을 종료하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<Map<String, dynamic>> changeSchedule({
    required String scheduleSlotId,
    required String teacherId,
    required int weekday,
    required int startMinutes,
    required int durationMinutes,
    required DateTime effectiveOn,
  }) async {
    try {
      final result = await _client.rpc(
        'change_regular_schedule',
        params: {
          'p_schedule_slot_id': scheduleSlotId,
          'p_teacher_id': teacherId,
          'p_weekday': weekday,
          'p_start_time': _formatTime(startMinutes),
          'p_duration_minutes': durationMinutes,
          'p_effective_on': _formatDate(effectiveOn),
        },
      );

      if (result is! Map) {
        throw const StudentRegularScheduleFailure(
          '정규 일정 변경 결과를 확인하지 못했습니다.',
        );
      }
      return Map<String, dynamic>.from(result);
    } on StudentRegularScheduleFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StudentRegularScheduleFailure(
        _friendlyDatabaseMessage(
          error.message,
          fallback: '정규 일정을 변경하지 못했습니다.',
        ),
      );
    } catch (_) {
      throw const StudentRegularScheduleFailure(
        '정규 일정을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  int _parseTimeMinutes(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 +
        (int.tryParse(parts[1]) ?? 0);
  }

  String _formatTime(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _friendlyDatabaseMessage(
    String message, {
    required String fallback,
  }) {
    String? userMessage;

    if (message.contains('FORESTRING_BACKDATED_REGULAR_SCHEDULE_CHANGE_FORBIDDEN')) {
      userMessage = '과거 날짜부터 정규 일정을 변경하거나 종료할 수 없습니다.';
    } else if (message.contains('FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS')) {
      userMessage = '선택한 요일과 시간이 담당 선생님의 근무시간 밖입니다.';
    } else if (message.contains('FORESTRING_REGULAR_SCHEDULE_FUTURE_VERSION_EXISTS')) {
      userMessage = '이미 예정된 정규 일정 변경이 있습니다. 기존 변경 일정을 먼저 확인해주세요.';
    } else if (message.contains('FORESTRING_REGULAR_ADD_REQUIRES_SEMESTER_START')) {
      userMessage = '정규 수업 추가는 새 학기 시작일부터 적용할 수 있습니다.';
    } else if (message.contains('FORESTRING_REGULAR_ADD_ACTIVE_SEMESTER_FORBIDDEN')) {
      userMessage = '이미 시작된 학기에는 정규 수업을 추가할 수 없습니다. 다음 학기를 선택해주세요.';
    } else if (message.contains('FORESTRING_TARGET_SEMESTER_NOT_REGULAR')) {
      userMessage = '선택한 학기는 정규 학생 일정으로 설정되어 있지 않습니다.';
    } else if (message.contains('FORESTRING_REGULAR_SCHEDULE_MATERIALIZED_UNDO_UNSAFE')) {
      userMessage = '이미 변경하거나 취소한 수업 이력이 있어 이 정규 일정을 시작일부터 삭제할 수 없습니다.';
    } else if (message.contains('FORESTRING_REGULAR_SCHEDULE_ALREADY_MATERIALIZED')) {
      userMessage = '이미 생성된 수업이 있어 이 정규 일정을 시작일부터 삭제할 수 없습니다.';
    } else if (message.contains('FORESTRING_REGULAR_TEACHER_ASSIGNMENT_MISMATCH') ||
        message.contains('FORESTRING_REGULAR_RECONCILIATION_ASSIGNMENT_MISMATCH')) {
      userMessage = '선택한 적용일의 담당 선생님 정보와 정규 일정이 일치하지 않습니다.';
    } else if (message.contains('FORESTRING_REGULAR_RECONCILIATION_TIME_CONFLICT') ||
        message.contains('FORESTRING_REGULAR_SERIES_TIME_CONFLICT') ||
        message.contains('TIME_CONFLICT')) {
      userMessage = '변경하려는 시간에 다른 수업이 있어 저장할 수 없습니다.';
    } else if (message.contains('FORESTRING_REGULAR_RECONCILIATION_BLOCKED')) {
      userMessage = '변경하려는 시간은 담당 선생님의 예약 불가 시간과 겹칩니다.';
    } else if (message.contains('FORESTRING_REGULAR_RECONCILIATION_ON_CLOSURE')) {
      userMessage = '변경되는 수업 중 학원 휴원일과 겹치는 일정이 있습니다.';
    } else if (message.contains('FORESTRING_REGULAR_RECONCILIATION_COUNT_MISMATCH')) {
      userMessage = '학기 내 정규 수업 횟수를 맞출 수 없습니다. 학기/휴원 설정을 확인해주세요.';
    } else if (message.contains('FORESTRING_REGULAR_CHANGE_BEFORE_SLOT_START') ||
        message.contains('FORESTRING_REGULAR_CHANGE_AFTER_SLOT_END')) {
      userMessage = '이 정규 수업이 적용되는 기간 밖의 날짜입니다.';
    } else if (message.contains('FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN') ||
        message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
      userMessage = '이 정규 일정을 관리할 권한이 없습니다.';
    }

    return userMessage ?? fallback;
  }
}
