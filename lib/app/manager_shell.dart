import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/qa/qa_sandbox_repositories.dart';
import '../core/qa/qa_sandbox_store.dart';
import '../core/theme/forestring_theme.dart';
import '../core/widgets/forestring_navigation.dart';
import '../features/auth/domain/current_profile.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/lessons/presentation/lesson_controller.dart';
import '../features/lessons/presentation/lesson_management_page.dart';
import '../features/lessons/presentation/master_schedule_page.dart';
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

  static const _titles = [
    '일정',
    '수강생',
    '선생님',
    '수업',
  ];

  int _currentIndex = _scheduleIndex;

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
      case 'reset':
        await _resetQaData();
      case 'exit':
        await _exit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LessonController>();
    final qaStore = widget.isQaSandbox
        ? context.read<QaSandboxStore>()
        : null;

    final pages = [
      MasterSchedulePage(
        profile: widget.profile,
        isQaSandbox: widget.isQaSandbox,
        onQaExit: widget.onQaExit,
        embeddedInShell: true,
      ),
      StudentManagementPage(
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
      ),
      TeacherManagementPage(
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
      LessonManagementPage(
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
    ];

    return PopScope(
      canPop: _currentIndex == _scheduleIndex,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _currentIndex == _scheduleIndex) return;
        setState(() => _currentIndex = _scheduleIndex);
      },
      child: Scaffold(
        backgroundColor: neutralIvory,
        appBar: ForestringAppBar(
          title: _titles[_currentIndex],
          automaticallyImplyLeading: false,
          actions: [
            PopupMenuButton<String>(
              tooltip: '더보기',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: _handleMenu,
              itemBuilder: (context) => [
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
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
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
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon:
                      Icon(Icons.calendar_month_rounded),
                  label: '일정',
                ),
                NavigationDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups_rounded),
                  label: '수강생',
                ),
                NavigationDestination(
                  icon: Icon(Icons.co_present_outlined),
                  selectedIcon: Icon(Icons.co_present_rounded),
                  label: '선생님',
                ),
                NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  selectedIcon: Icon(Icons.event_note_rounded),
                  label: '수업',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
