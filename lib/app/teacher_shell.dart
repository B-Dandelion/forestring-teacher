import 'package:flutter/material.dart';
import '../core/theme/forestring_theme.dart';
import '../features/auth/domain/current_profile.dart';
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

  void _selectTab(int index) {
    if (index == 0) {
      setState(() {
        _currentIndex = index;
        _weekFocusRevision += 1;
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

  @override
  Widget build(BuildContext context) {
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
              ),
              TeacherHomePage(
                profile: widget.profile,
              ),
              TeacherMyPage(
                profile: widget.profile,
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
