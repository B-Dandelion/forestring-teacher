import 'package:flutter/material.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../../teachers/data/teacher_work_hours_schedule_repository.dart';
import '../../data/lesson_repository.dart';
import '../../domain/lesson.dart';
import '../lesson_controller.dart';

Future<TimeOfDay?> showLessonTimeSlotPicker({
  required BuildContext context,
  required Lesson lesson,
  required LessonController controller,
  required DateTime selectedDate,
  required TimeOfDay initialTime,
  required int durationMinutes,
}) {
  final workHours = controller.workHoursFor(lesson.teacherId);

  final slots = _buildSlots(
    teacherId: lesson.teacherId,
    studentId: lesson.studentId,
    excludedLessonId: lesson.id,
    selectedDate: selectedDate,
    durationMinutes: durationMinutes,
    workHours: workHours,
    lessons: controller.lessons,
    blockedPeriods: controller.blockedPeriods,
  );

  return _showSlotSheet(
    context: context,
    slots: slots,
    selectedDate: selectedDate,
    initialTime: initialTime,
    durationMinutes: durationMinutes,
  );
}

Future<TimeOfDay?> showMakeupLessonTimeSlotPicker({
  required BuildContext context,
  required LessonRepository repository,
  required String teacherId,
  required String studentId,
  required DateTime selectedDate,
  required TimeOfDay initialTime,
  required int durationMinutes,
}) async {
  final dayStart = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final dayEnd = dayStart.add(const Duration(days: 1));

  var loadFailed = false;
  List<TeacherWorkHour> workHours = const [];
  List<Lesson> lessons = const [];
  List<TeacherBlockedPeriod> blockedPeriods = const [];

  try {
    final results = await Future.wait([
      TeacherWorkHoursScheduleRepository().fetchForDate(
        teacherId: teacherId,
        onDate: selectedDate,
      ),
      repository.fetchVisibleLessons(
        from: dayStart,
        to: dayEnd,
        teacherId: teacherId,
      ),
      repository.fetchVisibleLessons(
        from: dayStart,
        to: dayEnd,
        studentId: studentId,
      ),
      repository.fetchVisibleBlockedPeriods(
        from: dayStart,
        to: dayEnd,
        teacherId: teacherId,
      ),
    ]);

    final rawWorkHours = results[0] as List;
    workHours = rawWorkHours
        .map(
          (raw) => TeacherWorkHour(
            teacherId: teacherId,
            weekday: raw.weekday as int,
            startTime: raw.startTime.toString(),
            endTime: raw.endTime.toString(),
          ),
        )
        .toList();

    final mergedLessons = <String, Lesson>{};
    for (final raw in results[1] as List) {
      final lesson = raw as Lesson;
      mergedLessons[lesson.id] = lesson;
    }
    for (final raw in results[2] as List) {
      final lesson = raw as Lesson;
      mergedLessons[lesson.id] = lesson;
    }
    lessons = mergedLessons.values.toList();
    blockedPeriods = List<TeacherBlockedPeriod>.from(results[3] as List);
  } catch (_) {
    loadFailed = true;
  }

  if (!context.mounted) return null;

  final slots = _buildSlots(
    teacherId: teacherId,
    studentId: studentId,
    selectedDate: selectedDate,
    durationMinutes: durationMinutes,
    workHours: workHours,
    lessons: lessons,
    blockedPeriods: blockedPeriods,
  );

  return _showSlotSheet(
    context: context,
    slots: slots,
    selectedDate: selectedDate,
    initialTime: initialTime,
    durationMinutes: durationMinutes,
    emptyMessage: loadFailed
        ? '가능한 시간을 불러오지 못했습니다.'
        : '이 날짜에 등록된 근무시간이 없습니다.',
  );
}

Future<TimeOfDay?> _showSlotSheet({
  required BuildContext context,
  required List<_LessonTimeSlot> slots,
  required DateTime selectedDate,
  required TimeOfDay initialTime,
  required int durationMinutes,
  String emptyMessage = '이 날짜에 등록된 근무시간이 없습니다.',
}) {
  final morningSlots = slots
      .where((slot) => _minutes(slot.time) < 12 * 60)
      .toList();
  final afternoonSlots = slots
      .where((slot) => _minutes(slot.time) >= 12 * 60)
      .toList();

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.58,
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            decoration: BoxDecoration(
              color: const Color(0xffFCFDF9),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.07),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '시간 선택',
                        style: forestringTextStyle.copyWith(
                          color: primaryColor,
                          fontSize: 21,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    _TimeSheetCloseButton(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.055),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${selectedDate.month}월 ${selectedDate.day}일 · '
                      '$durationMinutes분 수업',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: slots.isEmpty
                      ? SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 22,
                            ),
                            child: Text(
                              emptyMessage,
                              textAlign: TextAlign.center,
                              style: forestringTextStyle.copyWith(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              if (morningSlots.isNotEmpty)
                                _TimeSlotSection(
                                  title: '오전',
                                  slots: morningSlots,
                                  initialTime: initialTime,
                                  onSelected: (time) =>
                                      Navigator.of(sheetContext)
                                          .pop(time),
                                ),
                              if (morningSlots.isNotEmpty &&
                                  afternoonSlots.isNotEmpty)
                                const SizedBox(height: 16),
                              if (afternoonSlots.isNotEmpty)
                                _TimeSlotSection(
                                  title: '오후',
                                  slots: afternoonSlots,
                                  initialTime: initialTime,
                                  onSelected: (time) =>
                                      Navigator.of(sheetContext)
                                          .pop(time),
                                ),
                            ],
                          ),
                        ),
                ),
                if (slots.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.07),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '회색 시간은 기존 수업 또는 '
                          '개인 일정과 겹칩니다.',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black45,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

List<_LessonTimeSlot> _buildSlots({
  required String teacherId,
  required String studentId,
  required DateTime selectedDate,
  required int durationMinutes,
  required List<TeacherWorkHour> workHours,
  required List<Lesson> lessons,
  required List<TeacherBlockedPeriod> blockedPeriods,
  String? excludedLessonId,
}) {
  final dayWorkHours = workHours
      .where((workHour) => workHour.weekday == selectedDate.weekday)
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final result = <_LessonTimeSlot>[];
  final seenMinutes = <int>{};

  for (final workHour in dayWorkHours) {
    final startMinutes = _parseMinutes(workHour.startTime);
    final endMinutes = _parseMinutes(workHour.endTime);
    if (startMinutes == null || endMinutes == null) continue;

    for (var minute = _ceilToQuarter(startMinutes);
        minute + durationMinutes <= endMinutes;
        minute += 15) {
      if (!seenMinutes.add(minute)) continue;

      final startsAt = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        minute ~/ 60,
        minute % 60,
      );
      final endsAt = startsAt.add(Duration(minutes: durationMinutes));

      final lessonConflict = lessons.any((other) {
        if (other.id == excludedLessonId || other.isCanceled) return false;
        if (other.teacherId != teacherId && other.studentId != studentId) {
          return false;
        }
        return _overlaps(startsAt, endsAt, other.startsAt, other.endsAt);
      });

      final blockedConflict = blockedPeriods.any((period) {
        if (period.teacherId != teacherId) return false;
        return _overlaps(startsAt, endsAt, period.startsAt, period.endsAt);
      });

      result.add(
        _LessonTimeSlot(
          time: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
          available: !lessonConflict && !blockedConflict,
        ),
      );
    }
  }

  result.sort((a, b) => _minutes(a.time).compareTo(_minutes(b.time)));
  return result;
}

int? _parseMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

int _ceilToQuarter(int minutes) => ((minutes + 14) ~/ 15) * 15;

bool _overlaps(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) {
  return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
}

bool _sameTime(TimeOfDay a, TimeOfDay b) =>
    a.hour == b.hour && a.minute == b.minute;

String _formatTime(TimeOfDay value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;

class _LessonTimeSlot {
  const _LessonTimeSlot({
    required this.time,
    required this.available,
  });

  final TimeOfDay time;
  final bool available;
}
