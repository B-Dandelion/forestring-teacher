import 'package:supabase_flutter/supabase_flutter.dart';

class StaffWorkReportFailure implements Exception {
  const StaffWorkReportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class StaffWorkDurationGroup {
  const StaffWorkDurationGroup({
    required this.durationMinutes,
    required this.lessonCount,
  });

  final int durationMinutes;
  final int lessonCount;

  factory StaffWorkDurationGroup.fromJson(Map<String, dynamic> json) {
    return StaffWorkDurationGroup(
      durationMinutes: (json['durationMinutes'] as num).toInt(),
      lessonCount: (json['lessonCount'] as num).toInt(),
    );
  }
}

class StaffWorkTypeGroup {
  const StaffWorkTypeGroup({
    required this.lessonType,
    required this.lessonCount,
    required this.totalMinutes,
  });

  final String lessonType;
  final int lessonCount;
  final int totalMinutes;

  String get label => switch (lessonType) {
        'flex' => '자율',
        'makeup' => '보강',
        _ => '정규',
      };

  factory StaffWorkTypeGroup.fromJson(Map<String, dynamic> json) {
    return StaffWorkTypeGroup(
      lessonType: json['lessonType'].toString(),
      lessonCount: (json['lessonCount'] as num).toInt(),
      totalMinutes: (json['totalMinutes'] as num).toInt(),
    );
  }
}

class BranchWorkSummary {
  const BranchWorkSummary({
    required this.branchId,
    required this.branchName,
    required this.startsOn,
    required this.endsOn,
    required this.lessonCount,
    required this.totalMinutes,
    required this.staffCount,
  });

  final String branchId;
  final String branchName;
  final DateTime startsOn;
  final DateTime endsOn;
  final int lessonCount;
  final int totalMinutes;
  final int staffCount;

  factory BranchWorkSummary.fromJson(Map<String, dynamic> json) {
    return BranchWorkSummary(
      branchId: json['branchId'].toString(),
      branchName: json['branchName'].toString(),
      startsOn: DateTime.parse(json['startsOn'].toString()),
      endsOn: DateTime.parse(json['endsOn'].toString()),
      lessonCount: (json['lessonCount'] as num).toInt(),
      totalMinutes: (json['totalMinutes'] as num).toInt(),
      staffCount: (json['staffCount'] as num).toInt(),
    );
  }
}

class StaffWorkSummary {
  const StaffWorkSummary({
    required this.staffId,
    required this.staffName,
    required this.staffRole,
    required this.branchId,
    required this.branchName,
    required this.lessonCount,
    required this.totalMinutes,
    required this.durationGroups,
    required this.typeGroups,
  });

  final String staffId;
  final String staffName;
  final String staffRole;
  final String branchId;
  final String branchName;
  final int lessonCount;
  final int totalMinutes;
  final List<StaffWorkDurationGroup> durationGroups;
  final List<StaffWorkTypeGroup> typeGroups;

  bool get isManager => staffRole == 'manager';

  factory StaffWorkSummary.fromJson(Map<String, dynamic> json) {
    final rawDurations = json['durationGroups'];
    final rawTypes = json['typeGroups'];

    return StaffWorkSummary(
      staffId: json['staffId'].toString(),
      staffName: json['staffName'].toString(),
      staffRole: json['staffRole'].toString(),
      branchId: json['branchId'].toString(),
      branchName: json['branchName'].toString(),
      lessonCount: (json['lessonCount'] as num).toInt(),
      totalMinutes: (json['totalMinutes'] as num).toInt(),
      durationGroups: rawDurations is List
          ? rawDurations
              .map(
                (raw) => StaffWorkDurationGroup.fromJson(
                  Map<String, dynamic>.from(raw as Map),
                ),
              )
              .toList()
          : const [],
      typeGroups: rawTypes is List
          ? rawTypes
              .map(
                (raw) => StaffWorkTypeGroup.fromJson(
                  Map<String, dynamic>.from(raw as Map),
                ),
              )
              .toList()
          : const [],
    );
  }
}

class StaffWorkReport {
  const StaffWorkReport({
    required this.semesterId,
    required this.semesterCode,
    required this.calculatedAt,
    required this.totalLessonCount,
    required this.totalMinutes,
    required this.staffCount,
    required this.workedBranchCount,
    required this.branches,
    required this.staff,
    this.branchId,
  });

  final String semesterId;
  final String semesterCode;
  final String? branchId;
  final DateTime calculatedAt;
  final int totalLessonCount;
  final int totalMinutes;
  final int staffCount;
  final int workedBranchCount;
  final List<BranchWorkSummary> branches;
  final List<StaffWorkSummary> staff;

  factory StaffWorkReport.fromJson(Map<String, dynamic> json) {
    final rawBranches = json['branches'];
    final rawStaff = json['staff'];

    return StaffWorkReport(
      semesterId: json['semesterId'].toString(),
      semesterCode: json['semesterCode'].toString(),
      branchId: json['branchId']?.toString(),
      calculatedAt:
          DateTime.parse(json['calculatedAt'].toString()).toLocal(),
      totalLessonCount: (json['totalLessonCount'] as num).toInt(),
      totalMinutes: (json['totalMinutes'] as num).toInt(),
      staffCount: (json['staffCount'] as num).toInt(),
      workedBranchCount: (json['workedBranchCount'] as num).toInt(),
      branches: rawBranches is List
          ? rawBranches
              .map(
                (raw) => BranchWorkSummary.fromJson(
                  Map<String, dynamic>.from(raw as Map),
                ),
              )
              .toList()
          : const [],
      staff: rawStaff is List
          ? rawStaff
              .map(
                (raw) => StaffWorkSummary.fromJson(
                  Map<String, dynamic>.from(raw as Map),
                ),
              )
              .toList()
          : const [],
    );
  }
}

class StaffWorkReportRepository {
  StaffWorkReportRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<StaffWorkReport> fetchReport({
    required String semesterId,
    String? branchId,
  }) async {
    try {
      final data = await _client.rpc(
        'get_staff_work_report',
        params: {
          'p_semester_id': semesterId,
          'p_branch_id': branchId,
        },
      );

      if (data is! Map) {
        throw const StaffWorkReportFailure(
          '근무 리포트 응답 형식을 확인할 수 없습니다.',
        );
      }

      return StaffWorkReport.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on StaffWorkReportFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw StaffWorkReportFailure(
        _messageFor(error.message),
      );
    } catch (_) {
      throw const StaffWorkReportFailure(
        '근무 리포트를 불러오지 못했습니다.',
      );
    }
  }

  String _messageFor(String message) {
    if (message.contains('FORESTRING_WORK_REPORT_FORBIDDEN')) {
      return '근무 리포트를 조회할 권한이 없습니다.';
    }
    if (message.contains('FORESTRING_MANAGER_BRANCH_FORBIDDEN')) {
      return '다른 지점의 근무 리포트는 조회할 수 없습니다.';
    }
    if (message.contains('FORESTRING_SEMESTER_NOT_FOUND')) {
      return '선택한 학기 정보를 찾을 수 없습니다.';
    }
    if (message.contains('FORESTRING_BRANCH_NOT_FOUND')) {
      return '선택한 지점 정보를 찾을 수 없습니다.';
    }
    return '근무 리포트를 불러오지 못했습니다.';
  }
}
