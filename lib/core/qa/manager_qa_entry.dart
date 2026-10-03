import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/domain/current_profile.dart';
import '../../features/lessons/presentation/lesson_controller.dart';
import '../../features/lessons/presentation/master_schedule_page.dart';
import 'qa_sandbox_repositories.dart';
import 'qa_sandbox_store.dart';

class ManagerQaEntry extends StatelessWidget {
  const ManagerQaEntry({
    super.key,
  });

  static const profile = CurrentProfile(
    id: qaManagerProfileId,
    displayName: 'QA 지점장',
    role: AppRole.manager,
    branchId: qaManagerBranchId,
    isActive: true,
    isReviewAccount: true,
  );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => QaSandboxStore(),
        ),
        ChangeNotifierProvider(
          create: (context) {
            final store = context.read<QaSandboxStore>();
            return LessonController(
              QaLessonRepository(store),
              profile,
              branchRepository: QaBranchRepository(store),
            )..initialize();
          },
        ),
      ],
      child: const _ManagerQaShell(),
    );
  }
}

class _ManagerQaShell extends StatelessWidget {
  const _ManagerQaShell();

  @override
  Widget build(BuildContext context) {
    context.watch<QaSandboxStore>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(context.read<LessonController>().reload());
    });

    return MasterSchedulePage(
      profile: ManagerQaEntry.profile,
      isQaSandbox: true,
      onQaExit: () => Navigator.of(context).pop(),
    );
  }
}
