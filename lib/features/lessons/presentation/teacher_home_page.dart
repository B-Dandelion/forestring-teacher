import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../domain/lesson.dart';
import 'lesson_controller.dart';
import 'widgets/blocked_period_card.dart';
import 'widgets/blocked_period_info_dialog.dart';
import 'widgets/lesson_card.dart';
import 'widgets/lesson_info_dialog.dart';

class TeacherHomePage extends StatefulWidget {
  const TeacherHomePage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  State<TeacherHomePage> createState() => _TeacherHomePageState();
}

class _TeacherHomePageState extends State<TeacherHomePage> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LessonController>();
    final selectedLessons = controller.lessonsOn(_selectedDate);
    final selectedBlockedPeriods = controller.blockedPeriodsOn(_selectedDate);
    final selectedEntries = <Object>[
      ...selectedLessons,
      ...selectedBlockedPeriods,
    ]..sort((a, b) {
        final aStart = a is Lesson
            ? a.startsAt
            : (a as TeacherBlockedPeriod).startsAt;
        final bStart = b is Lesson
            ? b.startsAt
            : (b as TeacherBlockedPeriod).startsAt;
        return aStart.compareTo(bStart);
      });
    final now = DateTime.now();

    return Scaffold(
      appBar: ForestringAppBar(
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: controller.isLoading ? null : controller.reload,
            icon: controller.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            TableCalendar<Object>(
              firstDay: DateTime(now.year, now.month - 2, 1),
              lastDay: DateTime(now.year, now.month + 4, 0),
              focusedDay: _focusedDate,
              selectedDayPredicate: (day) =>
                  isSameDay(_selectedDate, day),
              eventLoader: (day) => <Object>[
                ...controller.lessonsOn(day),
                ...controller.blockedPeriodsOn(day),
              ],
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDate = selectedDay;
                  _focusedDate = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                _focusedDate = focusedDay;
              },
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonVisible: false,
                titleTextFormatter: (date, locale) => '${date.month}월',
                titleTextStyle: const TextStyle(
                  color: primaryColor,
                  fontFamily: 'ELAND',
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                ),
                leftChevronIcon: const Icon(
                  Icons.chevron_left,
                  color: primaryColor,
                ),
                rightChevronIcon: const Icon(
                  Icons.chevron_right,
                  color: primaryColor,
                ),
              ),
              calendarStyle: const CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: secondaryColor,
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: Color(0xff2E8B57),
                  shape: BoxShape.circle,
                ),
              ),
              calendarBuilders: CalendarBuilders(
                dowBuilder: (context, day) {
                  final text = switch (day.weekday) {
                    DateTime.monday => '월',
                    DateTime.tuesday => '화',
                    DateTime.wednesday => '수',
                    DateTime.thursday => '목',
                    DateTime.friday => '금',
                    DateTime.saturday => '토',
                    DateTime.sunday => '일',
                    _ => '',
                  };

                  return Center(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontFamily: 'ELAND',
                        fontWeight: FontWeight.w500,
                        color: day.weekday == DateTime.sunday
                            ? Colors.red
                            : day.weekday == DateTime.saturday
                                ? Colors.blue
                                : Colors.black,
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: neutralIvory,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${DateFormat('M월 d일').format(_selectedDate)} · '
                '${selectedLessons.where((e) => !e.isCanceled).length}개 수업 · '
                '${selectedBlockedPeriods.length}개 개인 일정',
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (controller.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  controller.errorMessage!,
                  style: forestringTextStyle.copyWith(
                    color: Colors.redAccent,
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.reload,
                child: controller.isLoading && controller.lessons.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(child: CircularProgressIndicator()),
                        ],
                      )
                    : selectedEntries.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              const SizedBox(height: 70),
                              Text(
                                '등록된 수업이나 개인 일정이 없습니다.',
                                textAlign: TextAlign.center,
                                style: forestringTextStyle.copyWith(
                                  color: Colors.black54,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            itemCount: selectedEntries.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final entry = selectedEntries[index];
                              if (entry is TeacherBlockedPeriod) {
                                return BlockedPeriodCard(
                                  period: entry,
                                  onTap: () =>
                                      showBlockedPeriodInfoDialog(
                                    context: context,
                                    period: entry,
                                  ),
                                );
                              }

                              final lesson = entry as Lesson;
                              return LessonCard(
                                lesson: lesson,
                                personName: lesson.studentName ?? '학생',
                                onTap: () => showLessonInfoDialog(
                                  context: context,
                                  lesson: lesson,
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
