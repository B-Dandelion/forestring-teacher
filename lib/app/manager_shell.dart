import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/notifications/notification_destination_resolver.dart';
import '../core/notifications/notification_navigation_coordinator.dart';
import '../core/notifications/notification_payload.dart';
import '../core/qa/qa_sandbox_repositories.dart';
import '../core/qa/qa_sandbox_store.dart';
import '../core/theme/forestring_theme.dart';
import '../core/theme/student_accent_controller.dart';
import '../core/widgets/schedule_display_mode_sheet.dart';
import '../features/auth/domain/current_profile.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/lessons/presentation/lesson_controller.dart';
import '../features/lessons/presentation/lesson_management_page.dart';
import '../features/lessons/presentation/master_schedule_page.dart';
import '../features/master/presentation/master_management_page.dart';
import '../features/students/presentation/student_management_page.dart';
import '../features/teachers/presentation/teacher_management_page.dart';

class ManagerShell extends StatefulWidget {
  const ManagerShell({
    super.key,
    required this.profile,
    this.isQaSandbox = false,
    this.onQaExit,
  });

  final CurrentProfile profile;
  final bool isQaSandbox;
  final VoidCallback? onQaExit;

  @override
  State<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends State<ManagerShell> {
  static const _scheduleIndex = 0;

  int _currentIndex = _scheduleIndex;
  late final List<Widget?> _pages;
  NotificationNavigationIntent? _notificationLessonFocus;
  int _notificationLessonFocusRevision = 0;
  String? _notificationStudentId;
  String? _notificationStudentBranchId;
  int _notificationStudentRevision = 0;
  bool _notificationResolutionScheduled = false;

  @override
  void initState() {
    super.initState();
    _pages = List<Widget?>.filled(
      widget.profile.isMaster ? 5 : 4,
      null,
    );
  }

  void _selectTab(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  Future<void> _resetQaData() async {
    if (!widget.isQaSandbox) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('QA 데이터 초기화'),
        content: const Text(
          '현재 QA 세션에서 변경한 수업, 수강생, 선생님 데이터를 '
          '모두 초기 상태로 되돌립니다.\n\n'
          '운영 데이터에는 영향을 주지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
            ),
            child: const Text('초기화'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    context.read<QaSandboxStore>().reset();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QA 데이터가 초기 상태로 복구되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _exit() async {
    if (widget.isQaSandbox) {
      final onQaExit = widget.onQaExit;
      if (onQaExit != null) {
        onQaExit();
      } else {
        await Navigator.of(context).maybePop();
      }
      return;
    }

    await context.read<AuthController>().signOut();
  }

  Future<void> _handleMenu(String value) async {
    switch (value) {
      case 'schedule_display':
        final controller = context.read<StudentAccentController>();
        await showScheduleDisplayModeSheet(
          context: context,
          controller: controller,
        );
      case 'reset':
        await _resetQaData();
      case 'exit':
        await _exit();
    }
  }

  Widget _buildPage(
    int index, {
    required LessonController controller,
    required QaSandboxStore? qaStore,
  }) {
    return switch (index) {
      0 => MasterSchedulePage(
          profile: widget.profile,
          isQaSandbox: widget.isQaSandbox,
          onQaExit: widget.onQaExit,
          embeddedInShell: true,
          notificationFocus: _notificationLessonFocus,
          notificationFocusRevision:
              _notificationLessonFocusRevision,
        ),
      1 => StudentManagementPage(
          profile: widget.profile,
          repository: qaStore == null
              ? null
              : QaStudentManagementRepository(qaStore),
          branchRepository:
              qaStore == null ? null : QaBranchRepository(qaStore),
          lessonRepository:
              qaStore == null ? null : QaLessonRepository(qaStore),
          adminRepository:
              qaStore == null ? null : QaStudentAdminRepository(qaStore),
          nextSemesterRepository: qaStore == null
              ? null
              : QaStudentNextSemesterTypeRepository(qaStore),
          regularScheduleRepository: qaStore == null
              ? null
              : QaStudentRegularScheduleRepository(qaStore),
          teacherManagementRepository: qaStore == null
              ? null
              : QaStudentTeacherManagementRepository(qaStore),
          isQaSandbox: widget.isQaSandbox,
          embeddedInShell: true,
          notificationStudentId: _notificationStudentId,
          notificationBranchId: _notificationStudentBranchId,
          notificationRevision: _notificationStudentRevision,
        ),
      2 => TeacherManagementPage(
          profile: widget.profile,
          repository:
              qaStore == null ? null : QaTeacherRepository(qaStore),
          branchRepository:
              qaStore == null ? null : QaBranchRepository(qaStore),
          workHoursRepository: qaStore == null
              ? null
              : QaTeacherWorkHoursScheduleRepository(qaStore),
          isQaSandbox: widget.isQaSandbox,
          embeddedInShell: true,
        ),
      3 => LessonManagementPage(
          profile: widget.profile,
          controller: controller,
          initialBranchId: controller.selectedBranchId,
          repository:
              qaStore == null ? null : QaLessonRepository(qaStore),
          semesterRepository:
              qaStore == null ? null : QaSemesterRepository(qaStore),
          branchRepository:
              qaStore == null ? null : QaBranchRepository(qaStore),
          isQaSandbox: widget.isQaSandbox,
          embeddedInShell: true,
        ),
      4 when widget.profile.isMaster => MasterManagementPage(
          profile: widget.profile,
        ),
      _ => const SizedBox.shrink(),
    };
  }

  void _scheduleNotificationResolution(
    NotificationNavigationCoordinator coordinator,
    LessonController lessonController,
  ) {
    if (widget.isQaSandbox ||
        _notificationResolutionScheduled ||
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
        case NotificationDestinationKind.managementWeek:
          if (widget.profile.isMaster) {
            lessonController.selectBranch(intent.branchId);
          }
          lessonController.selectTeacher(intent.teacherId);

          setState(() {
            _currentIndex = _scheduleIndex;
            _notificationLessonFocus = intent;
            _notificationLessonFocusRevision += 1;
            _pages[_scheduleIndex] = null;
          });
          return;
        case NotificationDestinationKind.managementStudentDetail:
          setState(() {
            _currentIndex = 1;
            _notificationStudentId = intent.studentId;
            _notificationStudentBranchId = intent.branchId;
            _notificationStudentRevision += 1;
            _pages[1] = null;
          });
          return;
        case NotificationDestinationKind.teacherWeek:
        case NotificationDestinationKind.teacherStudentDetail:
          return;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LessonController>();
    final notificationCoordinator =
        context.watch<NotificationNavigationCoordinator>();

    _scheduleNotificationResolution(
      notificationCoordinator,
      controller,
    );
    final accentController = context.watch<StudentAccentController>();
    final qaStore = widget.isQaSandbox
        ? context.read<QaSandboxStore>()
        : null;

    _pages[_currentIndex] ??= _buildPage(
      _currentIndex,
      controller: controller,
      qaStore: qaStore,
    );

    final pages = List<Widget>.generate(
      _pages.length,
      (index) => _pages[index] ?? const SizedBox.shrink(),
    );

    return PopScope(
      canPop: _currentIndex == _scheduleIndex,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _currentIndex == _scheduleIndex) return;
        setState(() => _currentIndex = _scheduleIndex);
      },
      child: Scaffold(
        backgroundColor: neutralIvory,
        appBar: widget.profile.isMaster
            ? null
            : AppBar(
                automaticallyImplyLeading: false,
                toolbarHeight: 44,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: neutralIvory,
                surfaceTintColor: Colors.transparent,
                foregroundColor: primaryColor,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: PopupMenuButton<String>(
                      tooltip: '더보기',
                      onSelected: _handleMenu,
                      icon: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.08),
                          ),
                        ),
                        child: const Icon(
                          Icons.more_horiz_rounded,
                          color: primaryColor,
                          size: 21,
                        ),
                      ),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'schedule_display',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              accentController.displayMode.icon,
                              color: primaryColor,
                            ),
                            title: const Text('시간표 표시 방식'),
                            subtitle: Text(
                              accentController.displayMode.label,
                              style: forestringTextStyle.copyWith(
                                color: Colors.black45,
                                fontSize: 10.5,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.black38,
                            ),
                          ),
                        ),
                        if (widget.isQaSandbox)
                          const PopupMenuItem(
                            value: 'reset',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.restart_alt_rounded),
                              title: Text('QA 데이터 초기화'),
                            ),
                          ),
                        PopupMenuItem(
                          value: 'exit',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              widget.isQaSandbox
                                  ? Icons.close_rounded
                                  : Icons.logout_rounded,
                            ),
                            title: Text(
                              widget.isQaSandbox ? 'QA 종료' : '로그아웃',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        body: SafeArea(
          top: widget.profile.isMaster,
          bottom: false,
          child: Column(
            children: [
            if (widget.isQaSandbox)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5),
                color: primaryColor.withValues(alpha: 0.08),
                child: Text(
                  'QA Sandbox · 로컬 데이터',
                  textAlign: TextAlign.center,
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: pages,
              ),
            ),
          ],
        ),
      ),
        bottomNavigationBar: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: primaryColor,
              indicatorColor: const Color(0xffDDE9E0),
              labelTextStyle:
                  WidgetStateProperty.resolveWith<TextStyle?>(
                (states) {
                  final selected =
                      states.contains(WidgetState.selected);
                  return forestringTextStyle.copyWith(
                    color:
                        selected ? Colors.white : Colors.white70,
                    fontSize: 10,
                    fontWeight: selected
                        ? FontWeight.w500
                        : FontWeight.w300,
                  );
                },
              ),
              iconTheme:
                  WidgetStateProperty.resolveWith<IconThemeData?>(
                (states) {
                  final selected =
                      states.contains(WidgetState.selected);
                  return IconThemeData(
                    color: selected
                        ? primaryColor
                        : Colors.white70,
                    size: 22,
                  );
                },
              ),
            ),
            child: NavigationBar(
              height: 58,
              selectedIndex: _currentIndex,
              onDestinationSelected: _selectTab,
              labelBehavior:
                  NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon:
                      Icon(Icons.calendar_month_rounded),
                  label: '일정',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups_rounded),
                  label: '수강생',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.co_present_outlined),
                  selectedIcon: Icon(Icons.co_present_rounded),
                  label: '선생님',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  selectedIcon: Icon(Icons.event_note_rounded),
                  label: '수업',
                ),
                if (widget.profile.isMaster)
                  const NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: '관리',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
