enum AppRole {
  master,
  manager,
  teacher,
  student;

  factory AppRole.fromValue(String value) {
    return switch (value) {
      'master' => AppRole.master,
      'manager' => AppRole.manager,
      'teacher' => AppRole.teacher,
      'student' => AppRole.student,
      _ => throw ArgumentError(
          'Unknown Forestring role: $value',
        ),
    };
  }

  String get label {
    return switch (this) {
      AppRole.master => '전체 관리자',
      AppRole.manager => '지점 관리자',
      AppRole.teacher => '선생님',
      AppRole.student => '학생',
    };
  }
}

class CurrentProfile {
  const CurrentProfile({
    required this.id,
    required this.displayName,
    required this.role,
    required this.isActive,
    this.branchId,
    this.isReviewAccount = false,
    this.isQaAccount = false,
  });

  final String id;
  final String displayName;
  final AppRole role;
  final String? branchId;
  final bool isActive;
  final bool isReviewAccount;
  final bool isQaAccount;

  bool get isMaster => role == AppRole.master;
  bool get isManager => role == AppRole.manager;
  bool get isTeacher => role == AppRole.teacher;
  bool get isStudent => role == AppRole.student;

  factory CurrentProfile.fromJson(
    Map<String, dynamic> json,
  ) {
    return CurrentProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      role: AppRole.fromValue(
        json['role'] as String,
      ),
      branchId: json['branch_id'] as String?,
      isActive: json['is_active'] as bool,
      isReviewAccount: json['is_review_account'] == true,
      isQaAccount: json['is_qa_account'] == true,
    );
  }
}
