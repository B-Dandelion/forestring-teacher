import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/domain/current_profile.dart';
import '../../features/lessons/presentation/lesson_controller.dart';
import '../../features/lessons/presentation/master_schedule_page.dart';
import 'manager_qa_repositories.dart';

class ManagerQaEntry extends StatelessWidget {
  const ManagerQaEntry({
    super.key,
  });

  static const profile = CurrentProfile(
    id: managerQaProfileId,
    displayName: 'QA 지점장',
    role: AppRole.manager,
    branchId: managerQaBranchId,
    isActive: true,
    isReviewAccount: true,
  );

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LessonController(
        ManagerQaLessonRepository(),
        profile,
        branchRepository: ManagerQaBranchRepository(),
      )..initialize(),
      child: Builder(
        builder: (context) {
          return MasterSchedulePage(
            profile: profile,
            isQaSandbox: true,
            onQaExit: () => Navigator.of(context).pop(),
          );
        },
      ),
    );
  }
}
