import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
}) async {
  final workHours = await _loadDateAwareWorkHours(
    teacherId: lesson.teacherId,
    selectedDate: selectedDate,
    fallback: controller.workHoursFor(lesson.teacherId),
  );

  if (!context.mounted) return null;

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
        ? '가능한 시간을 불러오지 못했습니다. 직접 입력을 이용해주세요.'
        : '이 날짜에 등록된 근무시간이 없습니다.',
  );
}

Future<List<TeacherWorkHour>> _loadDateAwareWorkHours({
  required String teacherId,
  required DateTime selectedDate,
  required List<TeacherWorkHour> fallback,
}) async {
  try {
    final hours = await TeacherWorkHoursScheduleRepository().fetchForDate(
      teacherId: teacherId,
      onDate: selectedDate,
    );
    return hours
        .map(
          (hour) => TeacherWorkHour(
            teacherId: teacherId,
            weekday: hour.weekday,
            startTime: hour.startTime,
            endTime: hour.endTime,
          ),
        )
        .toList();
  } catch (_) {
    return fallback;
  }
}

Future<TimeOfDay?> _showSlotSheet({
  required BuildContext context,
  required List<_LessonTimeSlot> slots,
  required DateTime selectedDate,
  required TimeOfDay initialTime,
  required int durationMinutes,
  String emptyMessage = '이 날짜에 등록된 근무시간이 없습니다.',
}) async {
  final morningSlots = slots
      .where((slot) => _minutes(slot.time) < 12 * 60)
      .toList();
  final afternoonSlots = slots
      .where((slot) => _minutes(slot.time) >= 12 * 60)
      .toList();

  final directController = TextEditingController(
    text: _formatTime(initialTime),
  );
  var showDirectInput = false;
  String? directErrorText;

  final picked = await showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final keyboardInset =
              MediaQuery.viewInsetsOf(context).bottom;

          void submitDirectTime() {
            final parsed = _parseTimeInput(directController.text);
            if (parsed == null) {
              setSheetState(
                () => directErrorText =
                    '00:00 ~ 23:59 형식으로 입력해주세요.',
              );
              return;
            }

            final selectable = slots.any(
              (slot) =>
                  slot.available &&
                  _sameTime(slot.time, parsed),
            );
            if (!selectable) {
              setSheetState(
                () => directErrorText =
                    '선택 가능한 시간 중에서 입력해주세요.',
              );
              return;
            }

            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.of(sheetContext).pop(parsed);
          }

          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.sizeOf(context).height * 0.62,
                  ),
                  padding:
                      const EdgeInsets.fromLTRB(18, 10, 18, 16),
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
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(999),
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
                            color: primaryColor.withValues(
                              alpha: 0.055,
                            ),
                            borderRadius:
                                BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${selectedDate.month}월 '
                            '${selectedDate.day}일 · '
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
                                  padding:
                                      const EdgeInsets.symmetric(
                                    vertical: 22,
                                  ),
                                  child: Text(
                                    emptyMessage,
                                    textAlign: TextAlign.center,
                                    style:
                                        forestringTextStyle.copyWith(
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
                                color: Colors.black.withValues(
                                  alpha: 0.07,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '회색 시간은 기존 수업 또는 '
                                '개인 일정과 겹칩니다.',
                                style:
                                    forestringTextStyle.copyWith(
                                  color: Colors.black45,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      AnimatedSwitcher(
                        duration:
                            const Duration(milliseconds: 160),
                        child: showDirectInput
                            ? Container(
                                key: const ValueKey(
                                  'direct-time-input',
                                ),
                                padding:
                                    const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  8,
                                  8,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(
                                    alpha: 0.045,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller:
                                            directController,
                                        autofocus: true,
                                        keyboardType:
                                            TextInputType.datetime,
                                        textInputAction:
                                            TextInputAction.done,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .allow(
                                            RegExp(r'[0-9:]'),
                                          ),
                                          LengthLimitingTextInputFormatter(
                                            5,
                                          ),
                                        ],
                                        style: forestringTextStyle
                                            .copyWith(
                                          color: Colors.black87,
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight.w500,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText: '13:30',
                                          errorText:
                                              directErrorText,
                                          border:
                                              InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets
                                                  .symmetric(
                                            horizontal: 4,
                                            vertical: 10,
                                          ),
                                        ),
                                        onChanged: (_) {
                                          if (directErrorText !=
                                              null) {
                                            setSheetState(
                                              () =>
                                                  directErrorText =
                                                      null,
                                            );
                                          }
                                        },
                                        onSubmitted: (_) =>
                                            submitDirectTime(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: submitDirectTime,
                                      style:
                                          FilledButton.styleFrom(
                                        backgroundColor:
                                            primaryColor,
                                        foregroundColor:
                                            Colors.white,
                                        padding:
                                            const EdgeInsets
                                                .symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        shape:
                                            RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        '선택',
                                        style:
                                            forestringTextStyle
                                                .copyWith(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Align(
                                key: const ValueKey(
                                  'direct-time-button',
                                ),
                                alignment:
                                    Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () {
                                    setSheetState(
                                      () => showDirectInput = true,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.keyboard_outlined,
                                    size: 17,
                                  ),
                                  label: Text(
                                    '직접 입력',
                                    style:
                                        forestringTextStyle.copyWith(
                                      fontSize: 12,
                                      fontWeight:
                                          FontWeight.w500,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: primaryColor,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  directController.dispose();
  return picked;
}

class _TimeSlotSection extends StatelessWidget {
  const _TimeSlotSection({
    required this.title,
    required this.slots,
    required this.initialTime,
    required this.onSelected,
  });

  final String title;
  final List<_LessonTimeSlot> slots;
  final TimeOfDay initialTime;
  final ValueChanged<TimeOfDay> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(
            title,
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            mainAxisExtent: 40,
          ),
          itemCount: slots.length,
          itemBuilder: (context, index) {
            final slot = slots[index];
            final selected =
                _sameTime(slot.time, initialTime);

            return Material(
              color: selected
                  ? primaryColor
                  : slot.available
                      ? Colors.white
                      : Colors.black.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                onTap: slot.available
                    ? () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        onSelected(slot.time);
                      }
                    : null,
                borderRadius: BorderRadius.circular(11),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: selected
                          ? primaryColor
                          : slot.available
                              ? primaryColor.withValues(alpha: 0.16)
                              : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Text(
                    _formatTime(slot.time),
                    style: forestringTextStyle.copyWith(
                      color: selected
                          ? Colors.white
                          : slot.available
                              ? Colors.black87
                              : Colors.black26,
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TimeSheetCloseButton extends StatelessWidget {
  const _TimeSheetCloseButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: const Icon(
        Icons.close_rounded,
        color: primaryColor,
        size: 21,
      ),
    );
  }
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

TimeOfDay? _parseTimeInput(String raw) {
  final value = raw.trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
  if (match == null) return null;

  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

  return TimeOfDay(hour: hour, minute: minute);
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
