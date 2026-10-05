import 'package:flutter/material.dart';

import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../lessons/data/lesson_repository.dart';
import '../data/student_admin_repository.dart';
import '../data/student_management_repository.dart';
import '../data/student_next_semester_type_repository.dart';
import '../data/student_regular_schedule_repository.dart';
import '../data/student_teacher_management_repository.dart';
import 'student_management_v2_page.dart';

/// Compatibility entry point used by the master/manager navigation.
///
/// Student management now uses a dedicated full-page detail flow instead of
/// the previous bottom sheet so additional management actions remain stable
/// as the feature set grows.
class StudentManagementPage extends StatelessWidget {
  const StudentManagementPage({
    super.key,
    required this.profile,
    this.repository,
    this.branchRepository,
    this.lessonRepository,
    this.adminRepository,
    this.nextSemesterRepository,
    this.regularScheduleRepository,
    this.teacherManagementRepository,
    this.isQaSandbox = false,
    this.embeddedInShell = false,
    this.notificationStudentId,
    this.notificationBranchId,
    this.notificationRevision = 0,
  });

  final CurrentProfile profile;
  final StudentManagementRepository? repository;
  final BranchRepository? branchRepository;
  final LessonRepository? lessonRepository;
  final StudentAdminRepository? adminRepository;
  final StudentNextSemesterTypeRepository? nextSemesterRepository;
  final StudentRegularScheduleRepository? regularScheduleRepository;
  final StudentTeacherManagementRepository? teacherManagementRepository;
  final bool isQaSandbox;
  final bool embeddedInShell;
  final String? notificationStudentId;
  final String? notificationBranchId;
  final int notificationRevision;

  @override
  Widget build(BuildContext context) {
    if (isQaSandbox &&
        (repository == null ||
            branchRepository == null ||
            lessonRepository == null ||
            adminRepository == null ||
            nextSemesterRepository == null ||
            regularScheduleRepository == null ||
            teacherManagementRepository == null)) {
      throw StateError(
        'QA student management requires sandbox repositories.',
      );
    }

    return StudentManagementV2Page(
      profile: profile,
      repository: repository,
      branchRepository: branchRepository,
      lessonRepository: lessonRepository,
      adminRepository: adminRepository,
      nextSemesterRepository: nextSemesterRepository,
      regularScheduleRepository: regularScheduleRepository,
      teacherManagementRepository: teacherManagementRepository,
      embeddedInShell: embeddedInShell,
      notificationStudentId: notificationStudentId,
      notificationBranchId: notificationBranchId,
      notificationRevision: notificationRevision,
    );
  }
}
