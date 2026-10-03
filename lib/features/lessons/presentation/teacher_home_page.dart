import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/theme/student_accent_controller.dart';
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
  late DateTime _selectedDate;
  late DateTime _focusedDate;

  static const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];
  static const _fullWeekdayLabels = [
    '월요일',
    '화요일',
    '수요일',
    '목요일',
    '금요일',
    '토요일',
    '일요일',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _selectedDate = today;
    _focusedDate = today;
  }

  Future<void> _pickCalendarDate(
    DateTime firstDay,
    DateTime lastDay,
  ) async {
    final initialMonth = DateTime(
      _focusedDate.year,
      _focusedDate.month,
    );
    final firstMonth = DateTime(firstDay.year, firstDay.month);
    final lastMonth = DateTime(lastDay.year, lastDay.month);

    final pickedMonth = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        var selectedYear = initialMonth.year
            .clamp(firstMonth.year, lastMonth.year)
            .toInt();

        return StatefulBuilder(
          builder: (context, setModalState) {
            final availableYears = List<int>.generate(
              lastMonth.year - firstMonth.year + 1,
              (index) => firstMonth.year + index,
            );

            bool monthEnabled(int month) {
              final candidate = DateTime(selectedYear, month);
              return !candidate.isBefore(firstMonth) &&
                  !candidate.isAfter(lastMonth);
            }

            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '날짜 이동',
                            style: forestringTextStyle.copyWith(
                              color: Colors.black87,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final now = DateTime.now();
                            final today = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            );
                            if (!today.isBefore(firstDay) &&
                                !today.isAfter(lastDay)) {
                              Navigator.of(context).pop(
                                DateTime(today.year, today.month),
                              );
                            }
                          },
                          child: Text(
                            '오늘',
                            style: forestringTextStyle.copyWith(
                              color: primaryColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: availableYears.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final year = availableYears[index];
                          final selected = year == selectedYear;

                          return ChoiceChip(
                            label: Text('$year년'),
                            selected: selected,
                            showCheckmark: false,
                            onSelected: (_) {
                              setModalState(() {
                                selectedYear = year;
                              });
                            },
                            selectedColor:
                                primaryColor.withValues(alpha: 0.12),
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.04),
                            side: BorderSide(
                              color: selected
                                  ? primaryColor.withValues(alpha: 0.18)
                                  : Colors.transparent,
                            ),
                            labelStyle: forestringTextStyle.copyWith(
                              color: selected
                                  ? primaryColor
                                  : Colors.black54,
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisExtent: 44,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: 12,
                      itemBuilder: (context, index) {
                        final month = index + 1;
                        final enabled = monthEnabled(month);
                        final selected =
                            selectedYear == initialMonth.year &&
                                month == initialMonth.month;

                        return OutlinedButton(
                          onPressed: enabled
                              ? () => Navigator.of(context).pop(
                                    DateTime(selectedYear, month),
                                  )
                              : null,
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor:
                                selected ? primaryColor : Colors.white,
                            foregroundColor:
                                selected ? Colors.white : Colors.black87,
                            disabledForegroundColor: Colors.black26,
                            side: BorderSide(
                              color: selected
                                  ? primaryColor
                                  : primaryColor.withValues(alpha: 0.10),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            '$month월',
                            style: forestringTextStyle.copyWith(
                              color: enabled
                                  ? selected
                                      ? Colors.white
                                      : Colors.black87
                                  : Colors.black26,
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (pickedMonth == null || !mounted) {
      return;
    }

    final now = DateTime.now();
    final isCurrentMonth =
        pickedMonth.year == now.year && pickedMonth.month == now.month;
    final preferredDay = isCurrentMonth ? now.day : 1;
    final daysInMonth = DateTime(
      pickedMonth.year,
      pickedMonth.month + 1,
      0,
    ).day;

    var picked = DateTime(
      pickedMonth.year,
      pickedMonth.month,
      preferredDay.clamp(1, daysInMonth).toInt(),
    );

    if (picked.isBefore(firstDay)) {
      picked = firstDay;
    } else if (picked.isAfter(lastDay)) {
      picked = lastDay;
    }

    setState(() {
      _selectedDate = picked;
      _focusedDate = picked;
    });
  }

  void _moveCalendarMonth(
    int delta,
    DateTime firstDay,
    DateTime lastDay,
  ) {
    final target = DateTime(
      _focusedDate.year,
      _focusedDate.month + delta,
      1,
    );
    final firstMonth = DateTime(firstDay.year, firstDay.month);
    final lastMonth = DateTime(lastDay.year, lastDay.month);

    if (target.isBefore(firstMonth) || target.isAfter(lastMonth)) {
      return;
    }

    setState(() {
      _focusedDate = target;
    });
  }

  Widget _calendarHeader(
    LessonController controller,
    DateTime firstDay,
    DateTime lastDay,
  ) {
    final currentMonth = DateTime(
      _focusedDate.year,
      _focusedDate.month,
    );
    final firstMonth = DateTime(firstDay.year, firstDay.month);
    final lastMonth = DateTime(lastDay.year, lastDay.month);
    final canGoPrevious = currentMonth.isAfter(firstMonth);
    final canGoNext = currentMonth.isBefore(lastMonth);

    Widget roundButton({
      required VoidCallback? onPressed,
      required Widget child,
      String? tooltip,
    }) {
      return Tooltip(
        message: tooltip ?? '',
        child: SizedBox(
          width: 36,
          height: 36,
          child: Material(
            color: primaryColor.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Center(child: child),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: roundButton(
              tooltip: '이전 달',
              onPressed: canGoPrevious
                  ? () => _moveCalendarMonth(-1, firstDay, lastDay)
                  : null,
              child: Icon(
                Icons.chevron_left_rounded,
                color: canGoPrevious ? primaryColor : Colors.black26,
                size: 22,
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pickCalendarDate(firstDay, lastDay),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_focusedDate.year}년 ${_focusedDate.month}월',
                    style: forestringTextStyle.copyWith(
                      color: primaryColor,
                      fontSize: 19,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: primaryColor,
                    size: 19,
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                roundButton(
                  tooltip: '새로고침',
                  onPressed: controller.isLoading
                      ? null
                      : controller.reload,
                  child: controller.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primaryColor,
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: primaryColor,
                          size: 19,
                        ),
                ),
                const SizedBox(width: 6),
                roundButton(
                  tooltip: '다음 달',
                  onPressed: canGoNext
                      ? () => _moveCalendarMonth(1, firstDay, lastDay)
                      : null,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: canGoNext ? primaryColor : Colors.black26,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendar(
    LessonController controller,
    DateTime firstDay,
    DateTime lastDay,
  ) {
    final safeFocusedDay = _focusedDate.isBefore(firstDay)
        ? firstDay
        : _focusedDate.isAfter(lastDay)
            ? lastDay
            : _focusedDate;

    return Column(
      children: [
        _calendarHeader(
          controller,
          firstDay,
          lastDay,
        ),
        TableCalendar<Object>(
      key: ValueKey<String>(
        'teacher-schedule-calendar-${firstDay.toIso8601String()}-${lastDay.toIso8601String()}',
      ),
      firstDay: firstDay,
      lastDay: lastDay,
      focusedDay: safeFocusedDay,
      startingDayOfWeek: StartingDayOfWeek.sunday,
      selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
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
      rowHeight: 48,
      daysOfWeekHeight: 34,
      headerVisible: false,
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        cellMargin: const EdgeInsets.all(5),
        todayDecoration: const BoxDecoration(
          color: Color(0xffE7EFE4),
          shape: BoxShape.circle,
        ),
        todayTextStyle: const TextStyle(
          color: primaryColor,
          fontFamily: 'ELAND',
          fontWeight: FontWeight.w500,
        ),
        selectedDecoration: const BoxDecoration(
          color: primaryColor,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: 'ELAND',
          fontWeight: FontWeight.w500,
        ),
        defaultTextStyle: forestringTextStyle.copyWith(
          color: Colors.black87,
          fontSize: 14,
        ),
        weekendTextStyle: forestringTextStyle.copyWith(
          color: Colors.black87,
          fontSize: 14,
        ),
        markerDecoration: const BoxDecoration(
          color: secondaryColor,
          shape: BoxShape.circle,
        ),
        markerSize: 8,
        markersMaxCount: 1,
        markersAlignment: Alignment.bottomCenter,
        markerMargin: const EdgeInsets.only(top: 2),
      ),
      calendarBuilders: CalendarBuilders<Object>(
        dowBuilder: (context, day) {
          final label = _weekdayLabels[day.weekday - 1];
          final color = day.weekday == DateTime.sunday
              ? Colors.redAccent
              : day.weekday == DateTime.saturday
                  ? Colors.blueAccent
                  : Colors.black45;

          return Center(
            child: Text(
              label,
              style: forestringTextStyle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          );
        },
        defaultBuilder: (context, day, focusedDay) {
          final color = day.weekday == DateTime.sunday
              ? Colors.redAccent
              : day.weekday == DateTime.saturday
                  ? Colors.blueAccent
                  : Colors.black87;

          return Center(
            child: Text(
              '${day.day}',
              style: forestringTextStyle.copyWith(
                color: color,
                fontSize: 14,
              ),
            ),
          );
        },
        todayBuilder: (context, day, focusedDay) {
          final color = day.weekday == DateTime.sunday
              ? Colors.redAccent
              : day.weekday == DateTime.saturday
                  ? Colors.blueAccent
                  : primaryColor;

          return Center(
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xffE7EFE4),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: forestringTextStyle.copyWith(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
        ),
      ],
    );
  }

  Widget _scheduleSectionHeader(
    int lessonCount,
    int personalScheduleCount,
  ) {
    final weekday = _fullWeekdayLabels[_selectedDate.weekday - 1];

    return Row(
      children: [
        Expanded(
          child: Text(
            '${DateFormat('M월 d일').format(_selectedDate)} $weekday',
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: const Color(0xffF7FAF5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$lessonCount개 수업 · $personalScheduleCount개 개인 일정',
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyScheduleCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 30,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xffF1F5ED),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_available_outlined,
              color: primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '등록된 수업이나 개인 일정이 없습니다.',
            style: forestringTextStyle.copyWith(
              color: Colors.black45,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleContent(
    BuildContext context,
    LessonController controller,
    List<Object> entries,
    Map<String, Color> studentAccents,
  ) {
    if (controller.isLoading &&
        controller.lessons.isEmpty &&
        controller.blockedPeriods.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 54),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (entries.isEmpty) {
      return _emptyScheduleCard();
    }

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (entries[i] is TeacherBlockedPeriod)
            BlockedPeriodCard(
              period: entries[i] as TeacherBlockedPeriod,
              onTap: () => showBlockedPeriodInfoDialog(
                context: context,
                period: entries[i] as TeacherBlockedPeriod,
              ),
            )
          else
            LessonCard(
              lesson: entries[i] as Lesson,
              personName:
                  (entries[i] as Lesson).studentName ?? '학생',
              accentColor:
                  studentAccents[(entries[i] as Lesson).studentId],
              onTap: () => showLessonInfoDialog(
                context: context,
                lesson: entries[i] as Lesson,
              ),
            ),
          if (i != entries.length - 1)
            const SizedBox(height: 10),
        ],
      ],
    );
  }

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

    final studentAccents = context
        .watch<StudentAccentController>()
        .assignments(
          controller.visibleLessons.map((lesson) => lesson.studentId),
        );

    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month - 2, 1);
    final lastDay = DateTime(now.year, now.month + 4, 0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
          children: [
                  _calendar(
                    controller,
                    firstDay,
                    lastDay,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                    decoration: BoxDecoration(
                      color: const Color(0xffE8F0E4),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      children: [
                        _scheduleSectionHeader(
                          selectedLessons.length,
                          selectedBlockedPeriods.length,
                        ),
                        const SizedBox(height: 12),
                        if (controller.errorMessage != null) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              controller.errorMessage!,
                              textAlign: TextAlign.center,
                              style: forestringTextStyle.copyWith(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        _scheduleContent(
                          context,
                          controller,
                          selectedEntries,
                          studentAccents,
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
