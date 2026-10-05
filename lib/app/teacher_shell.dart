import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/notifications/notification_destination_resolver.dart';
import '../core/notifications/notification_navigation_coordinator.dart';
import '../core/notifications/notification_payload.dart';
import '../core/theme/forestring_theme.dart';
import '../features/auth/domain/current_profile.dart';
import '../features/lessons/presentation/lesson_controller.dart';
import '../features/lessons/presentation/teacher_home_page.dart';
import '../features/lessons/presentation/teacher_my_page.dart';
import '../features/lessons/presentation/week_schedule_page.dart';

class TeacherShell extends StatefulWidget {
  const TeacherShell({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  static const int _scheduleIndex = 1;

  int _currentIndex = _scheduleIndex;
  int _weekFocusRevision = 0;
  NotificationNavigationIntent? _notificationLessonFocus;
  int _notificationLessonFocusRevision = 0;
  String? _notificationStudentId;
  int _notificationStudentRevision = 0;
  bool _notificationResolutionScheduled = false;

  void _selectTab(int index) {
    if (index == 0) {
      setState(() {
        _currentIndex = index;
        _weekFocusRevision += 1;
        _notificationLessonFocus = null;
      });
      return;
    }

    if (_currentIndex == index) {
      return;
    }

    setState(() {
      _currentIndex = index;
    });
  }

  void _scheduleNotificationResolution(
    NotificationNavigationCoordinator coordinator,
    LessonController lessonController,
  ) {
    if (_notificationResolutionScheduled ||
        lessonController.isLoading ||
        !coordinator.hasPendingNavigation) {
      return;
    }

    _notificationResolutionScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _notificationResolutionScheduled = false;
        return;
      }

      await lessonController.reload();

      if (!mounted) {
        _notificationResolutionScheduled = false;
        return;
      }

      _notificationResolutionScheduled = false;

      final intent = coordinator.takePendingForProfile(
        widget.profile.id,
      );
      if (intent == null) {
        return;
      }

      final destination = NotificationDestinationResolver.resolve(
        profile: widget.profile,
        intent: intent,
      );
      if (destination == null) {
        return;
      }

      Navigator.of(context).popUntil((route) => route.isFirst);

      switch (destination.kind) {
        case NotificationDestinationKind.teacherWeek:
          setState(() {
            _currentIndex = 0;
            _notificationLessonFocus = intent;
            _notificationLessonFocusRevision += 1;
          });
          return;
        case NotificationDestinationKind.teacherStudentDetail:
          setState(() {
            _currentIndex = 2;
            _notificationStudentId = intent.studentId;
            _notificationStudentRevision += 1;
          });
          return;
        case NotificationDestinationKind.managementWeek:
        case NotificationDestinationKind.managementStudentDetail:
          return;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lessonController = context.watch<LessonController>();
    final notificationCoordinator =
        context.watch<NotificationNavigationCoordinator>();

    _scheduleNotificationResolution(
      notificationCoordinator,
      lessonController,
    );

    return PopScope(
        canPop: _currentIndex == _scheduleIndex,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop || _currentIndex == _scheduleIndex) {
            return;
          }

          setState(() {
            _currentIndex = _scheduleIndex;
          });
        },
        child: Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: [
              WeekSchedulePage(
                profile: widget.profile,
                focusRevision: _weekFocusRevision,
                notificationFocus: _notificationLessonFocus,
                notificationFocusRevision:
                    _notificationLessonFocusRevision,
              ),
              TeacherHomePage(
                profile: widget.profile,
              ),
              TeacherMyPage(
                profile: widget.profile,
                notificationStudentId: _notificationStudentId,
                notificationStudentRevision:
                    _notificationStudentRevision,
              ),
            ],
          ),
          bottomNavigationBar: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
              backgroundColor: primaryColor,
              indicatorColor: const Color(0xffDDE9E0),
              labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
                (states) {
                  final selected = states.contains(WidgetState.selected);

                  return forestringTextStyle.copyWith(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 10,
                    fontWeight:
                        selected ? FontWeight.w500 : FontWeight.w300,
                  );
                },
              ),
              iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
                (states) {
                  final selected = states.contains(WidgetState.selected);

                  return IconThemeData(
                    color: selected ? primaryColor : Colors.white70,
                    size: 22,
                  );
                },
              ),
            ),
              child: NavigationBar(
                height: 58,
                selectedIndex: _currentIndex,
                onDestinationSelected: _selectTab,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.view_week_outlined),
                    selectedIcon: Icon(Icons.view_week_rounded),
                    label: '주간',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month_rounded),
                    label: '일정',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: '마이페이지',
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}
