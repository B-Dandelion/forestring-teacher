import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/academy_branch.dart';
import '../domain/branch_closure.dart';

class BranchFailure implements Exception {
  const BranchFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class BranchRepository {
  BranchRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _closureSelect =
      'id, branch_id, semester_id, starts_on, ends_on, reason, '
      'closure_kind, default_closure_id, is_overridden';

  Future<List<AcademyBranch>> fetchBranches() async {
    try {
      final rows = await _client
          .from('branches')
          .select('id, name, is_active')
          .order('name', ascending: true);

      return rows.map(AcademyBranch.fromJson).toList();
    } on PostgrestException {
      throw const BranchFailure(
        '지점 목록을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<String> createBranch({
    required String name,
  }) async {
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (normalizedName.isEmpty) {
      throw const BranchFailure('지점명을 입력해주세요.');
    }

    try {
      final result = await _client.rpc(
        'create_branch',
        params: {'p_name': normalizedName},
      );

      if (result is! String || result.isEmpty) {
        throw const BranchFailure('지점 생성 결과를 확인하지 못했습니다.');
      }

      return result;
    } on BranchFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '지점을 생성하지 못했습니다.',
      );
    }
  }

  Future<BranchManagementDetails> fetchBranchDetails({
    required String branchId,
  }) async {
    try {
      final result = await _client.rpc(
        'get_branch_management_details',
        params: {'p_branch_id': branchId},
      );

      return _detailsFromResult(result);
    } on BranchFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '지점 정보를 불러오지 못했습니다.',
      );
    }
  }

  Future<List<String>> fetchActiveManagerNames({
    required String branchId,
  }) async {
    try {
      final rows = await _client
          .from('profiles')
          .select('display_name')
          .eq('branch_id', branchId)
          .eq('role', 'manager')
          .eq('is_active', true)
          .eq('is_review_account', false)
          .eq('is_qa_account', false)
          .order('display_name', ascending: true);

      return rows
          .map((row) => (row['display_name'] as String?)?.trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '지점장 정보를 불러오지 못했습니다.',
      );
    }
  }

  Future<BranchManagementDetails> renameBranch({
    required String branchId,
    required String name,
  }) async {
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (normalizedName.isEmpty) {
      throw const BranchFailure('지점명을 입력해주세요.');
    }

    try {
      final result = await _client.rpc(
        'rename_branch',
        params: {
          'p_branch_id': branchId,
          'p_name': normalizedName,
        },
      );

      return _detailsFromResult(result);
    } on BranchFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '지점명을 변경하지 못했습니다.',
      );
    }
  }

  Future<BranchManagementDetails> setBranchActive({
    required String branchId,
    required bool isActive,
  }) async {
    try {
      final result = await _client.rpc(
        'set_branch_active',
        params: {
          'p_branch_id': branchId,
          'p_is_active': isActive,
        },
      );

      return _detailsFromResult(result);
    } on BranchFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: isActive
            ? '지점을 다시 활성화하지 못했습니다.'
            : '지점을 비활성화하지 못했습니다.',
      );
    }
  }

  Future<List<BranchClosure>> fetchBranchClosures({
    required String branchId,
  }) async {
    try {
      final today = _dateText(DateTime.now());
      final rows = await _client
          .from('closure_periods')
          .select(_closureSelect)
          .eq('branch_id', branchId)
          .gte('ends_on', today)
          .order('starts_on', ascending: true);

      return rows.map(BranchClosure.fromJson).toList();
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '휴원 일정을 불러오지 못했습니다.',
      );
    }
  }

  Future<List<BranchClosure>> fetchBranchClosuresInRange({
    required String branchId,
    required DateTime startsOn,
    required DateTime endsOn,
  }) async {
    try {
      final rows = await _client
          .from('closure_periods')
          .select(_closureSelect)
          .eq('branch_id', branchId)
          .lte('starts_on', _dateText(endsOn))
          .gte('ends_on', _dateText(startsOn))
          .order('starts_on', ascending: true);

      return rows.map(BranchClosure.fromJson).toList();
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '학기 휴원 일정을 불러오지 못했습니다.',
      );
    }
  }

  Future<List<DefaultClosure>> fetchDefaultClosuresForSemester({
    required String semesterId,
  }) async {
    try {
      final rows = await _client
          .from('default_closure_periods')
          .select(
            'id, semester_id, starts_on, ends_on, reason, closure_kind',
          )
          .eq('semester_id', semesterId)
          .order('starts_on', ascending: true);

      return rows.map(DefaultClosure.fromJson).toList();
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '기본 휴원 일정을 불러오지 못했습니다.',
      );
    }
  }

  Future<List<AcademySemester>> fetchSemesters() async {
    try {
      final rows = await _client
          .from('semesters')
          .select('id, code, starts_on, ends_on')
          .order('starts_on', ascending: true);

      return rows.map(AcademySemester.fromJson).toList();
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '학기 정보를 불러오지 못했습니다.',
      );
    }
  }

  Future<void> saveDefaultClosure({
    String? defaultClosureId,
    required String semesterId,
    required DateTime startsOn,
    required DateTime endsOn,
    required BranchClosureKind kind,
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'upsert_default_closure_period',
        params: {
          'p_default_closure_id': defaultClosureId,
          'p_semester_id': semesterId,
          'p_starts_on': _dateText(startsOn),
          'p_ends_on': _dateText(endsOn),
          'p_closure_kind': kind.value,
          'p_reason': reason?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '기본 휴원 일정을 저장하지 못했습니다.',
      );
    }
  }

  Future<void> deleteDefaultClosure({
    required String defaultClosureId,
  }) async {
    try {
      await _client.rpc(
        'delete_default_closure_period',
        params: {'p_default_closure_id': defaultClosureId},
      );
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '기본 휴원 일정을 삭제하지 못했습니다.',
      );
    }
  }

  Future<void> resetClosureOverride({
    required String closureId,
  }) async {
    try {
      await _client.rpc(
        'reset_branch_closure_override',
        params: {'p_closure_id': closureId},
      );
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '기본 휴원 설정으로 복원하지 못했습니다.',
      );
    }
  }

  Future<void> saveClosure({
    String? closureId,
    required String branchId,
    String? semesterId,
    required DateTime startsOn,
    required DateTime endsOn,
    required BranchClosureKind kind,
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'upsert_closure_period',
        params: {
          'p_closure_id': closureId,
          'p_branch_id': branchId,
          'p_semester_id': semesterId,
          'p_starts_on': _dateText(startsOn),
          'p_ends_on': _dateText(endsOn),
          'p_closure_kind': kind.value,
          'p_reason': reason?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '휴원 일정을 저장하지 못했습니다.',
      );
    }
  }

  Future<void> deleteClosure({
    required String closureId,
  }) async {
    try {
      await _client.rpc(
        'delete_closure_period',
        params: {'p_closure_id': closureId},
      );
    } on PostgrestException catch (error) {
      throw _failureFromPostgrest(
        error,
        fallback: '휴원 일정을 삭제하지 못했습니다.',
      );
    }
  }

  BranchManagementDetails _detailsFromResult(dynamic result) {
    if (result is! Map) {
      throw const BranchFailure('지점 관리 결과를 확인하지 못했습니다.');
    }

    return BranchManagementDetails.fromJson(
      Map<String, dynamic>.from(result),
    );
  }

  BranchFailure _failureFromPostgrest(
    PostgrestException error, {
    required String fallback,
  }) {
    final message = error.message;
    String? userMessage;

    if (message.contains('FORESTRING_AUTH_REQUIRED')) {
      userMessage = '로그인이 필요합니다.';
    } else if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED') ||
        message.contains('FORESTRING_ACTIVE_USER_REQUIRED')) {
      userMessage = '현재 계정은 더 이상 사용할 수 없습니다.';
    } else if (message.contains('FORESTRING_MASTER_REQUIRED') ||
        message.contains('FORESTRING_CALENDAR_MASTER_REQUIRED')) {
      userMessage = '전체 관리자만 기본 일정을 관리할 수 있습니다.';
    } else if (message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
      userMessage = '이 지점을 관리할 권한이 없습니다.';
    } else if (message.contains('FORESTRING_BRANCH_NOT_FOUND')) {
      userMessage = '지점을 찾을 수 없습니다.';
    } else if (message.contains('FORESTRING_INVALID_BRANCH_NAME')) {
      userMessage = '지점명은 1~100자로 입력해주세요.';
    } else if (message.contains('FORESTRING_BRANCH_NAME_ALREADY_EXISTS')) {
      userMessage = '이미 같은 이름의 지점이 있습니다.';
    } else if (message.contains('FORESTRING_BRANCH_DEACTIVATION_BLOCKED')) {
      userMessage = '활성 계정이나 남은 일정이 있어 지점을 비활성화할 수 없습니다.';
    } else if (message.contains('FORESTRING_DEFAULT_CLOSURE_OVERLAP')) {
      userMessage = '다른 기본 휴원 일정과 날짜가 겹칩니다.';
    } else if (message.contains('FORESTRING_DEFAULT_CLOSURE_BRANCH_OVERLAP')) {
      userMessage = '지점별 휴원과 날짜가 겹쳐 기본 휴원을 적용할 수 없습니다.';
    } else if (message.contains('FORESTRING_CLOSURE_OVERLAP')) {
      userMessage = '이미 등록된 휴원 일정과 날짜가 겹칩니다.';
    } else if (message.contains('FORESTRING_INVALID_CLOSURE_RANGE')) {
      userMessage = '휴원 시작일과 종료일을 확인해주세요.';
    } else if (message.contains('FORESTRING_CLOSURE_KIND_REQUIRED')) {
      userMessage = '휴원 종류를 선택해주세요.';
    } else if (message.contains('FORESTRING_INVALID_INSTRUCTIONAL_BREAK_WEEK_STRUCTURE')) {
      userMessage = '휴원 주간은 7일 단위로 설정해야 합니다.';
    } else if (message.contains('FORESTRING_INSTRUCTIONAL_BREAK_REQUIRES_SEMESTER')) {
      userMessage = '휴원 주간에 해당하는 학기를 찾지 못했습니다.';
    } else if (message.contains('FORESTRING_CLOSURE_OUTSIDE_EFFECTIVE_SEMESTER')) {
      userMessage = '휴원 일정은 해당 학기 기간 안에 포함되어야 합니다.';
    } else if (message.contains('FORESTRING_DEFAULT_CLOSURE_OUTSIDE_SEMESTER') ||
        message.contains('FORESTRING_DEFAULT_CLOSURE_OUTSIDE_BRANCH_SEMESTER')) {
      userMessage = '기본 휴원은 모든 지점의 해당 학기 기간 안에 포함되어야 합니다.';
    } else if (message.contains('FORESTRING_MATERIALIZED_DEFAULT_CLOSURE_IMMUTABLE')) {
      userMessage = '이미 수업 생성에 반영된 기본 휴원은 날짜를 변경하거나 삭제할 수 없습니다.';
    } else if (message.contains('FORESTRING_MATERIALIZED_INSTRUCTIONAL_BREAK_IMMUTABLE')) {
      userMessage = '이미 수업 생성에 반영된 휴원 주간은 날짜를 변경하거나 삭제할 수 없습니다.';
    } else if (message.contains('FORESTRING_DEFAULT_CLOSURE_BRANCH_DELETE_FORBIDDEN')) {
      userMessage = '기본 휴원은 지점에서 삭제할 수 없습니다. 별도 설정하거나 기본값으로 복원해주세요.';
    } else if (message.contains('FORESTRING_DEFAULT_CLOSURE_NOT_FOUND')) {
      userMessage = '기본 휴원 일정을 찾을 수 없습니다.';
    } else if (message.contains('FORESTRING_CLOSURE_HAS_NO_DEFAULT')) {
      userMessage = '이 휴원은 지점에서 직접 추가한 일정입니다.';
    } else if (message.contains('FORESTRING_CLOSURE_NOT_FOUND')) {
      userMessage = '휴원 일정을 찾을 수 없습니다.';
    }

    return BranchFailure(_withErrorCode(userMessage ?? fallback, message));
  }
}

String _withErrorCode(String userMessage, String rawMessage) {
  final match = RegExp(r'FORESTRING_[A-Z0-9_]+').firstMatch(rawMessage);
  final code = match?.group(0);
  if (code == null) return userMessage;
  return '$userMessage\n오류 코드: $code';
}

String _dateText(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
