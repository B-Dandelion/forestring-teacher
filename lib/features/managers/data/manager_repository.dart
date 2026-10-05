import 'package:supabase_flutter/supabase_flutter.dart';

class ManagerFailure implements Exception {
  const ManagerFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ManagerWorkHourInput {
  const ManagerWorkHourInput({
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  final int weekday;
  final String startTime;
  final String endTime;

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'startTime': startTime,
        'endTime': endTime,
      };
}

class ManagedManagerWorkHour {
  const ManagedManagerWorkHour({
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  final int weekday;
  final String startTime;
  final String endTime;
}

class CreatedManager {
  const CreatedManager({
    required this.id,
    required this.displayName,
    required this.branchId,
  });

  final String id;
  final String displayName;
  final String branchId;
}

class ManagedManager {
  const ManagedManager({
    required this.id,
    required this.displayName,
    required this.branchId,
    required this.branchName,
    required this.isActive,
    required this.workHours,
    required this.assignedStudentCount,
    this.withdrawalDate,
  });

  final String id;
  final String displayName;
  final String branchId;
  final String branchName;
  final bool isActive;
  final List<ManagedManagerWorkHour> workHours;
  final int assignedStudentCount;
  final DateTime? withdrawalDate;

  bool get hasScheduledWithdrawal => isActive && withdrawalDate != null;

  /// In the current schema, work hours are the opt-in signal that a manager
  /// also participates in teaching/scheduling.
  bool get teachesLessons => workHours.isNotEmpty;

  String get statusLabel {
    if (!isActive) return '퇴사';
    if (hasScheduledWithdrawal) return '퇴사 예정';
    return '재직';
  }
}

class ManagerDepartureState {
  const ManagerDepartureState({
    required this.managerId,
    required this.withdrawalDate,
    required this.assignmentCount,
    required this.seriesCount,
    required this.scheduledLessonCount,
    required this.canFinalize,
  });

  final String managerId;
  final DateTime withdrawalDate;
  final int assignmentCount;
  final int seriesCount;
  final int scheduledLessonCount;
  final bool canFinalize;

  int get blockerCount =>
      assignmentCount + seriesCount + scheduledLessonCount;

  factory ManagerDepartureState.fromJson(Map<String, dynamic> json) {
    return ManagerDepartureState(
      managerId: json['staffId'] as String,
      withdrawalDate: DateTime.parse(json['withdrawalDate'].toString()),
      assignmentCount: (json['assignmentCount'] as num).toInt(),
      seriesCount: (json['seriesCount'] as num).toInt(),
      scheduledLessonCount: (json['scheduledLessonCount'] as num).toInt(),
      canFinalize: json['canFinalize'] == true,
    );
  }
}

class ManagerRepository {
  ManagerRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ManagedManager>> fetchManagers() async {
    try {
      final profileRows = await _client
          .from('profiles')
          .select('id, display_name, branch_id, is_active')
          .eq('role', 'manager')
          .eq('is_review_account', false)
          .eq('is_qa_account', false)
          .order('display_name');

      final profiles = (profileRows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      if (profiles.isEmpty) return const [];

      final managerIds = profiles.map((row) => row['id'] as String).toList();
      final branchIds = profiles
          .map((row) => row['branch_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final results = await Future.wait([
        _client
            .from('teachers')
            .select('id, withdrawal_date')
            .inFilter('id', managerIds),
        _client
            .from('teacher_work_hours')
            .select('teacher_id, weekday, start_time, end_time')
            .inFilter('teacher_id', managerIds),
        _client
            .from('teacher_student_assignments')
            .select('teacher_id, student_id, starts_on, ends_on')
            .inFilter('teacher_id', managerIds),
        if (branchIds.isEmpty)
          Future.value(<dynamic>[])
        else
          _client
              .from('branches')
              .select('id, name')
              .inFilter('id', branchIds),
      ]);

      final withdrawalByManager = <String, DateTime?>{
        for (final raw in results[0])
          raw['id'] as String: raw['withdrawal_date'] == null
              ? null
              : DateTime.parse(raw['withdrawal_date'].toString()),
      };
      final branchNames = <String, String>{
        for (final raw in results[3])
          raw['id'] as String: raw['name'].toString(),
      };
      final workHoursByManager = <String, List<ManagedManagerWorkHour>>{};

      for (final raw in results[1]) {
        final row = Map<String, dynamic>.from(raw as Map);
        final managerId = row['teacher_id'] as String;
        workHoursByManager.putIfAbsent(managerId, () => []).add(
              ManagedManagerWorkHour(
                weekday: (row['weekday'] as num).toInt(),
                startTime: _shortTime(row['start_time']),
                endTime: _shortTime(row['end_time']),
              ),
            );
      }

      for (final workHours in workHoursByManager.values) {
        workHours.sort((a, b) {
          final weekdayCompare = a.weekday.compareTo(b.weekday);
          return weekdayCompare != 0
              ? weekdayCompare
              : a.startTime.compareTo(b.startTime);
        });
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final activeStudentsByManager = <String, Set<String>>{};

      for (final raw in results[2]) {
        final row = Map<String, dynamic>.from(raw as Map);
        final startsOn = DateTime.parse(row['starts_on'].toString());
        final endsOn = row['ends_on'] == null
            ? null
            : DateTime.parse(row['ends_on'].toString());
        final isCurrent = !startsOn.isAfter(today) &&
            (endsOn == null || !endsOn.isBefore(today));
        if (!isCurrent) continue;

        final managerId = row['teacher_id'] as String;
        activeStudentsByManager
            .putIfAbsent(managerId, () => <String>{})
            .add(row['student_id'] as String);
      }

      return profiles.map((row) {
        final id = row['id'] as String;
        final branchId = row['branch_id'] as String?;

        return ManagedManager(
          id: id,
          displayName: row['display_name'].toString(),
          branchId: branchId ?? '',
          branchName: branchId == null
              ? '지점 미지정'
              : (branchNames[branchId] ?? '지점 확인 필요'),
          isActive: row['is_active'] == true,
          workHours: List.unmodifiable(workHoursByManager[id] ?? const []),
          assignedStudentCount: activeStudentsByManager[id]?.length ?? 0,
          withdrawalDate: withdrawalByManager[id],
        );
      }).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
    } on PostgrestException {
      throw const ManagerFailure(
        '지점장 목록을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    } catch (_) {
      throw const ManagerFailure(
        '지점장 목록을 불러오는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<CreatedManager> createManager({
    required String name,
    required String pin,
    required String branchId,
    List<ManagerWorkHourInput> workHours = const [],
  }) async {
    final normalizedName = _normalizeName(name);

    if (normalizedName.isEmpty) {
      throw const ManagerFailure('지점장 이름을 입력해주세요.');
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const ManagerFailure('PIN은 4자리 숫자로 입력해주세요.');
    }
    if (branchId.isEmpty) {
      throw const ManagerFailure('지점을 선택해주세요.');
    }

    final session = _client.auth.currentSession;
    if (session == null) {
      throw const ManagerFailure('로그인이 필요합니다.');
    }

    try {
      final response = await _client.functions.invoke(
        'master-create-manager',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {
          'name': normalizedName,
          'pin': pin,
          'branchId': branchId,
          'workHours': workHours.map((item) => item.toJson()).toList(),
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300) {
        throw ManagerFailure(
          data is Map && data['message'] != null
              ? data['message'].toString()
              : '지점장 계정을 생성하지 못했습니다.',
        );
      }
      if (data is! Map) {
        throw const ManagerFailure(
          '지점장 생성 서버 응답을 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
        );
      }

      final managerId = data['managerId'];
      if (managerId is! String || managerId.isEmpty) {
        throw const ManagerFailure('지점장 생성 결과를 확인하지 못했습니다.');
      }

      return CreatedManager(
        id: managerId,
        displayName: data['displayName'] is String
            ? data['displayName'] as String
            : normalizedName,
        branchId: data['branchId'] is String
            ? data['branchId'] as String
            : branchId,
      );
    } on ManagerFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw ManagerFailure(details['message'].toString());
      }
      throw const ManagerFailure(
        '지점장 생성 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const ManagerFailure(
        '지점장 계정을 생성하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<void> updateManagerName({
    required String managerId,
    required String name,
  }) async {
    final normalizedName = _normalizeName(name);
    if (normalizedName.isEmpty) {
      throw const ManagerFailure('이름을 입력해주세요.');
    }
    if (normalizedName.length > 100) {
      throw const ManagerFailure('이름은 100자 이하로 입력해주세요.');
    }

    try {
      final response = await _client.functions.invoke(
        'staff-update-account-name',
        body: {
          'profileId': managerId,
          'name': normalizedName,
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300) {
        throw ManagerFailure(
          data is Map && data['message'] != null
              ? data['message'].toString()
              : '이름을 변경하지 못했습니다.',
        );
      }
    } on ManagerFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw ManagerFailure(details['message'].toString());
      }
      throw const ManagerFailure(
        '이름 변경 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const ManagerFailure(
        '이름을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<void> resetManagerPin({
    required String managerId,
    required String pin,
  }) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const ManagerFailure('PIN은 4자리 숫자로 입력해주세요.');
    }

    try {
      final response = await _client.functions.invoke(
        'staff-reset-account-pin',
        body: {
          'profileId': managerId,
          'pin': pin,
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300) {
        throw ManagerFailure(
          data is Map && data['message'] != null
              ? data['message'].toString()
              : 'PIN을 변경하지 못했습니다.',
        );
      }
    } on ManagerFailure {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw ManagerFailure(details['message'].toString());
      }
      throw const ManagerFailure(
        'PIN 변경 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const ManagerFailure(
        'PIN을 변경하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<void> changeManagerBranch({
    required String managerId,
    required String branchId,
  }) async {
    try {
      await _client.rpc(
        'change_manager_branch',
        params: {
          'p_manager_id': managerId,
          'p_branch_id': branchId,
        },
      );
    } on PostgrestException catch (error) {
      throw ManagerFailure(
        _managerBranchMessage(error.message),
      );
    }
  }

  Future<ManagerDepartureState> fetchDepartureState(String managerId) async {
    try {
      final data = await _client.rpc(
        'get_staff_departure_blockers',
        params: {'p_staff_id': managerId},
      );
      if (data is! Map) {
        throw const ManagerFailure('퇴사 관리 정보를 확인하지 못했습니다.');
      }
      return ManagerDepartureState.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on ManagerFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw ManagerFailure(_departureMessage(error.message));
    }
  }

  Future<ManagerDepartureState> scheduleDeparture({
    required String managerId,
    required DateTime withdrawalDate,
  }) async {
    try {
      final data = await _client.rpc(
        'schedule_staff_departure',
        params: {
          'p_staff_id': managerId,
          'p_withdrawal_date': _dateText(withdrawalDate),
        },
      );
      if (data is! Map) {
        throw const ManagerFailure('퇴사 예약 결과를 확인하지 못했습니다.');
      }
      return ManagerDepartureState.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on ManagerFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw ManagerFailure(_departureMessage(error.message));
    }
  }

  Future<void> cancelDeparture(String managerId) async {
    try {
      await _client.rpc(
        'cancel_staff_departure',
        params: {'p_staff_id': managerId},
      );
    } on PostgrestException catch (error) {
      throw ManagerFailure(_departureMessage(error.message));
    }
  }

  Future<void> finalizeDeparture(String managerId) async {
    try {
      await _client.rpc(
        'finalize_staff_departure',
        params: {'p_staff_id': managerId},
      );
    } on PostgrestException catch (error) {
      throw ManagerFailure(_departureMessage(error.message));
    }
  }
}

String _normalizeName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

String _shortTime(dynamic value) {
  final text = value?.toString() ?? '';
  return text.length >= 5 ? text.substring(0, 5) : text;
}

String _dateText(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _managerBranchMessage(String message) {
  String? userMessage;

  if (message.contains('FORESTRING_AUTH_REQUIRED')) {
    userMessage = '로그인이 필요합니다.';
  } else if (message.contains('FORESTRING_MASTER_REQUIRED')) {
    userMessage = '전체 관리자만 담당 지점을 변경할 수 있습니다.';
  } else if (message.contains('FORESTRING_MANAGER_BRANCH_CHANGE_BLOCKED')) {
    userMessage = '담당 학생, 정규 일정 또는 예정 수업이 남아 있어 지점을 변경할 수 없습니다.';
  } else if (message.contains('FORESTRING_MANAGER_BRANCH_CHANGE_PENDING_DEPARTURE')) {
    userMessage = '퇴사 예정인 지점장은 담당 지점을 변경할 수 없습니다.';
  } else if (message.contains('FORESTRING_ACTIVE_BRANCH_REQUIRED')) {
    userMessage = '운영 중인 지점만 선택할 수 있습니다.';
  } else if (message.contains('FORESTRING_MANAGER_NOT_FOUND')) {
    userMessage = '지점장 정보를 찾을 수 없습니다.';
  } else if (message.contains('FORESTRING_ACTIVE_MANAGER_REQUIRED')) {
    userMessage = '재직 중인 지점장의 담당 지점만 변경할 수 있습니다.';
  } else if (message.contains('FORESTRING_MANAGER_BRANCH_INPUT_REQUIRED')) {
    userMessage = '변경할 지점을 선택해주세요.';
  }

  return _withErrorCode(
    userMessage ?? '담당 지점을 변경하지 못했습니다.',
    message,
  );
}

String _departureMessage(String message) {
  String? userMessage;

  if (message.contains('FORESTRING_AUTH_REQUIRED')) {
    userMessage = '로그인이 필요합니다.';
  } else if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED') ||
      message.contains('FORESTRING_ACTIVE_USER_REQUIRED')) {
    userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
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
  } else if (message.contains('FORESTRING_STAFF_DEPARTURE_FORBIDDEN') ||
      message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN') ||
      message.contains('FORESTRING_MASTER_REQUIRED')) {
    userMessage = '지점장 퇴사를 관리할 권한이 없습니다.';
  } else if (message.contains('FORESTRING_STAFF_NOT_FOUND') ||
      message.contains('FORESTRING_TARGET_NOT_STAFF')) {
    userMessage = '지점장 정보를 찾을 수 없습니다.';
  } else if (message.contains('FORESTRING_ACTIVE_STAFF_REQUIRED')) {
    userMessage = '재직 중인 지점장만 퇴사를 예약할 수 있습니다.';
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
