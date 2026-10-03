import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/forestring_theme.dart';
import '../core/widgets/forestring_navigation.dart';
import '../features/auth/domain/current_profile.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/lessons/data/lesson_repository.dart';
import '../features/lessons/data/review_lesson_repository.dart';
import '../features/lessons/presentation/lesson_controller.dart';
import '../features/lessons/presentation/master_schedule_page.dart';
import 'teacher_shell.dart';

class AppGate extends StatelessWidget {
  const AppGate({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (auth.isInitializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final profile = auth.profile;

    if (!auth.isSignedIn || profile == null) {
      return const LoginPage();
    }

    if (profile.isReviewAccount &&
        profile.role != AppRole.manager &&
        profile.role != AppRole.master) {
      final reviewProfile = CurrentProfile(
        id: profile.id,
        displayName: '박지은',
        role: AppRole.teacher,
        isActive: true,
        isReviewAccount: true,
      );

      return _LessonEntry(
        profile: reviewProfile,
        repository: ReviewLessonRepository(
          teacherId: reviewProfile.id,
          teacherName: reviewProfile.displayName,
        ),
        child: TeacherShell(
          profile: reviewProfile,
        ),
      );
    }

    return switch (profile.role) {
      AppRole.master || AppRole.manager => _LessonEntry(
          profile: profile,
          child: MasterSchedulePage(
            profile: profile,
          ),
        ),
      AppRole.teacher => _LessonEntry(
          profile: profile,
          child: TeacherShell(
            profile: profile,
          ),
        ),
      AppRole.student => _UnavailableRolePage(
          profile: profile,
          title: '접근할 수 없습니다',
          message: '학생 계정은 학생용 포레스트링 앱을 이용해주세요.',
        ),
    };
  }
}

class _LessonEntry extends StatelessWidget {
  const _LessonEntry({
    required this.profile,
    required this.child,
    this.repository,
  });

  final CurrentProfile profile;
  final Widget child;
  final LessonRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LessonController(
        repository ?? LessonRepository(),
        profile,
      )..initialize(),
      child: child,
    );
  }
}

class _UnavailableRolePage extends StatelessWidget {
  const _UnavailableRolePage({
    required this.profile,
    required this.title,
    required this.message,
  });

  final CurrentProfile profile;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ForestringAppBar(),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${profile.displayName}님\n$message',
                  textAlign: TextAlign.center,
                  style: forestringTextStyle.copyWith(
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () =>
                      context.read<AuthController>().signOut(),
                  child: const Text('로그아웃'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
