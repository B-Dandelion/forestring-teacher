import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/theme/student_accent_controller.dart';
import '../../auth/domain/current_profile.dart';
import '../domain/lesson.dart';
import 'lesson_controller.dart';
import 'lesson_visual_style.dart';
import 'widgets/blocked_period_calendar_appointment.dart';
import 'widgets/blocked_period_info_dialog.dart';
import 'widgets/lesson_calendar_appointment.dart';
import 'widgets/lesson_info_dialog.dart';

class WeekSchedulePage extends StatefulWidget {
  const WeekSchedulePage({
    super.key,
    required this.profile,
    required this.focusRevision,
  });

  final CurrentProfile profile;
  final int focusRevision;

  @override
  State<WeekSchedulePage> createState() => _WeekSchedulePageState();
}

class _WeekSchedulePageState extends State<WeekSchedulePage> {
  final CalendarController _calendarController = CalendarController();
  int _lastAppliedFocusRevision = -1;

  @override
  void dispose() {
    _calendarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LessonController>();
    final teacherId = controller.selectedTeacherId ?? widget.profile.id;
    final accentController = context.watch<StudentAccentController>();
    final studentAccents = accentController.isEnabled
        ? accentController.assignments(
            controller.visibleLessons.map((lesson) => lesson.studentId),
          )
        : const <String, Color>{};
    final meetings = <Object>[
      ...controller.visibleLessons
          .where((lesson) => !lesson.isCanceled)
          .map(
            (lesson) => _LessonMeeting(
              lesson,
              studentAccents[lesson.studentId],
            ),
          ),
      ...controller.visibleBlockedPeriods.map(
        (period) => _BlockedMeeting(period),
      ),
    ];

    final focusTarget = DateTime.now();

    if (!controller.isLoading &&
        _lastAppliedFocusRevision != widget.focusRevision) {
      _lastAppliedFocusRevision = widget.focusRevision;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        _calendarController.displayDate = focusTarget;
      });
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'teacher-week-refresh',
        tooltip: '새로고침',
        onPressed: controller.isLoading
            ? null
            : controller.reload,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 3,
        child: controller.isLoading
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.refresh_rounded,
                size: 20,
              ),
      ),
      body: SafeArea(
        child: controller.isLoading && controller.lessons.isEmpty
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : SfCalendar(
                      controller: _calendarController,
                      minDate: DateTime(
                        DateTime.now().year,
                        DateTime.now().month - 2,
                        1,
                      ),
                      maxDate: DateTime(
                        DateTime.now().year,
                        DateTime.now().month + 4,
                        0,
                      ),
                      initialDisplayDate: focusTarget,
                      timeZone: 'Korea Standard Time',
                      view: CalendarView.week,
                      cellBorderColor: Colors.black12,
                      todayHighlightColor: primaryColor,
                      showCurrentTimeIndicator: true,
                      showNavigationArrow: true,
                      cellEndPadding: 0,
                      dataSource: _LessonDataSource(meetings),
                      appointmentBuilder: (context, details) {
                        if (details.appointments.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        final meeting = details.appointments.first;
                        if (meeting is! _LessonMeeting) {
                          if (meeting is _BlockedMeeting) {
                            return BlockedPeriodCalendarAppointment(
                              period: meeting.period,
                            );
                          }
                          return const SizedBox.shrink();
                        }

                        return LessonCalendarAppointment(
                          lesson: meeting.lesson,
                          accentColor: meeting.accentColor,
                        );
                      },
                      specialRegions: _timeRegions(
                        controller.workHoursFor(teacherId),
                      ),
                      viewHeaderHeight: 50,
                      headerDateFormat: 'M월',
                      headerStyle: const CalendarHeaderStyle(
                        backgroundColor: Colors.transparent,
                        textAlign: TextAlign.center,
                        textStyle: TextStyle(
                          color: primaryColor,
                          fontFamily: 'ELAND',
                          fontWeight: FontWeight.w500,
                          fontSize: 20,
                        ),
                      ),
                      viewHeaderStyle: const ViewHeaderStyle(
                        dateTextStyle: TextStyle(
                          color: Colors.black,
                          fontFamily: 'ELAND',
                          fontWeight: FontWeight.w500,
                        ),
                        dayTextStyle: TextStyle(
                          color: Colors.black,
                          fontFamily: 'ELAND',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      timeSlotViewSettings: const TimeSlotViewSettings(
                        dayFormat: 'EEE',
                        timeTextStyle: TextStyle(
                          fontFamily: 'OpenSans',
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                          fontSize: 11,
                        ),
                        timeInterval: Duration(minutes: 15),
                        timeIntervalHeight: 36,
                        timeFormat: 'H:mm',
                        startHour: 7,
                        endHour: 23,
                      ),
                      onTap: (details) {
                        final appointments = details.appointments;
                        if (appointments == null || appointments.isEmpty) {
                          return;
                        }

                        final meeting = appointments.first;
                        if (meeting is _BlockedMeeting) {
                          showBlockedPeriodInfoDialog(
                            context: context,
                            period: meeting.period,
                          );
                          return;
                        }

                        if (meeting is! _LessonMeeting) {
                          return;
                        }

                        showLessonInfoDialog(
                          context: context,
                          lesson: meeting.lesson,
                        );
                      },
              ),
      ),
    );
  }

  List<TimeRegion> _timeRegions(
    List<TeacherWorkHour> workHours,
  ) {
    return workHours.map((workHour) {
      final startParts = workHour.startTime.split(':');
      final endParts = workHour.endTime.split(':');

      return TimeRegion(
        startTime: DateTime(
          2024,
          1,
          1,
          int.parse(startParts[0]),
          int.parse(startParts[1]),
        ),
        endTime: DateTime(
          2024,
          1,
          1,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
        ),
        recurrenceRule:
            'FREQ=WEEKLY;BYDAY=${_weekdayCode(workHour.weekday)}',
        color: primaryColor.withValues(alpha: 0.12),
      );
    }).toList();
  }

  String _weekdayCode(int weekday) {
    return switch (weekday) {
      1 => 'MO',
      2 => 'TU',
      3 => 'WE',
      4 => 'TH',
      5 => 'FR',
      6 => 'SA',
      7 => 'SU',
      _ => 'MO',
    };
  }
}

class _LessonMeeting {
  const _LessonMeeting(
    this.lesson,
    this.accentColor,
  );

  final Lesson lesson;
  final Color? accentColor;
}

class _BlockedMeeting {
  const _BlockedMeeting(this.period);

  final TeacherBlockedPeriod period;
}

class _LessonDataSource extends CalendarDataSource {
  _LessonDataSource(List<Object> source) {
    appointments = source;
  }

  Object _entry(int index) => appointments![index];

  @override
  DateTime getStartTime(int index) {
    final entry = _entry(index);
    return entry is _LessonMeeting
        ? entry.lesson.startsAt
        : (entry as _BlockedMeeting).period.startsAt;
  }

  @override
  DateTime getEndTime(int index) {
    final entry = _entry(index);
    return entry is _LessonMeeting
        ? entry.lesson.endsAt
        : (entry as _BlockedMeeting).period.endsAt;
  }

  @override
  String getSubject(int index) {
    final entry = _entry(index);
    return entry is _LessonMeeting
        ? (entry.lesson.studentName ?? '학생')
        : (entry as _BlockedMeeting).period.displayLabel;
  }

  @override
  Color getColor(int index) {
    final entry = _entry(index);
    if (entry is _BlockedMeeting) {
      return personalScheduleColor;
    }
    final meeting = entry as _LessonMeeting;
    return meeting.accentColor ?? lessonStatusSurfaceColor(meeting.lesson);
  }
}
