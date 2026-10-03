import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../domain/lesson.dart';
import 'lesson_controller.dart';
import 'widgets/blocked_period_calendar_appointment.dart';
import 'widgets/blocked_period_info_dialog.dart';
import 'widgets/lesson_calendar_appointment.dart';
import 'widgets/lesson_info_dialog.dart';

class WeekSchedulePage extends StatelessWidget {
  const WeekSchedulePage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LessonController>();
    final teacherId = controller.selectedTeacherId ?? profile.id;
    final meetings = <Object>[
      ...controller.visibleLessons
          .where((lesson) => !lesson.isCanceled)
          .map((lesson) => _LessonMeeting(lesson)),
      ...controller.visibleBlockedPeriods.map(
        (period) => _BlockedMeeting(period),
      ),
    ];

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
        child: RefreshIndicator(
          onRefresh: controller.reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height - 100,
                child: controller.isLoading && controller.lessons.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : SfCalendar(
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
                        initialDisplayDate: DateTime.now(),
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
            ],
          ),
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
  const _LessonMeeting(this.lesson);

  final Lesson lesson;
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
    final lesson = (entry as _LessonMeeting).lesson;
    if (lesson.type == LessonType.makeup) {
      return secondaryColor;
    }
    if (lesson.isRescheduled) {
      return const Color(0xff4F7E67);
    }
    return primaryColor;
  }
}
