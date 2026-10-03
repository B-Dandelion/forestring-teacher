import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../data/teacher_repository.dart';

class TeacherWorkHourDraft {
  const TeacherWorkHourDraft({
    this.weekday = 1,
    this.startTime = const TimeOfDay(hour: 9, minute: 0),
    this.endTime = const TimeOfDay(hour: 18, minute: 0),
  });

  final int weekday;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  factory TeacherWorkHourDraft.fromManaged(
    ManagedTeacherWorkHour workHour,
  ) {
    return TeacherWorkHourDraft(
      weekday: workHour.weekday,
      startTime: parseTeacherWorkTime(workHour.startTime),
      endTime: parseTeacherWorkTime(workHour.endTime),
    );
  }

  TeacherWorkHourDraft copyWith({
    int? weekday,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) {
    return TeacherWorkHourDraft(
      weekday: weekday ?? this.weekday,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  TeacherWorkHourInput toInput() {
    return TeacherWorkHourInput(
      weekday: weekday,
      startTime: formatTeacherWorkTime(startTime),
      endTime: formatTeacherWorkTime(endTime),
    );
  }
}

class TeacherWorkTimeRange {
  const TeacherWorkTimeRange({
    required this.startTime,
    required this.endTime,
  });

  final TimeOfDay startTime;
  final TimeOfDay endTime;
}

class TeacherWorkHoursEditor extends StatelessWidget {
  const TeacherWorkHoursEditor({
    super.key,
    required this.values,
    required this.onChanged,
    this.enabled = true,
    this.allowEmpty = false,
  });

  final List<TeacherWorkHourDraft> values;
  final ValueChanged<List<TeacherWorkHourDraft>> onChanged;
  final bool enabled;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var weekday = 1; weekday <= 7; weekday += 1) ...[
          _weekdayCard(context, weekday),
          if (weekday != 7) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _weekdayCard(BuildContext context, int weekday) {
    final entries = values
        .where((value) => value.weekday == weekday)
        .toList()
      ..sort(
        (a, b) => _minutes(a.startTime).compareTo(
          _minutes(b.startTime),
        ),
      );
    final working = entries.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      padding: EdgeInsets.fromLTRB(
        13,
        working ? 12 : 9,
        10,
        working ? 12 : 9,
      ),
      decoration: BoxDecoration(
        color: working
            ? Colors.white
            : primaryColor.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: working
              ? primaryColor.withValues(alpha: 0.10)
              : primaryColor.withValues(alpha: 0.055),
        ),
        boxShadow: working
            ? const [
                BoxShadow(
                  color: Color(0x07000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: working
                      ? primaryColor.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.035),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  teacherWeekdayLabel(weekday),
                  style: forestringTextStyle.copyWith(
                    color: working ? primaryColor : Colors.black45,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  working ? '근무' : '휴무',
                  style: forestringTextStyle.copyWith(
                    color: working ? Colors.black87 : Colors.black45,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Switch.adaptive(
                value: working,
                activeTrackColor: primaryColor,
                onChanged: !enabled
                    ? null
                    : (next) {
                        if (next) {
                          _enableWeekday(weekday);
                        } else {
                          _disableWeekday(weekday);
                        }
                      },
              ),
            ],
          ),
          if (working) ...[
            const SizedBox(height: 9),
            ...List.generate(
              entries.length,
              (index) => Padding(
                padding: EdgeInsets.only(
                  bottom: index == entries.length - 1 ? 0 : 7,
                ),
                child: _rangeRow(
                  context,
                  entries[index],
                  canDelete: entries.length > 1,
                ),
              ),
            ),
            if (_canAddRange(entries)) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: enabled
                      ? () => _addRange(weekday, entries)
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: primaryColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 18,
                  ),
                  label: Text(
                    '시간대 추가',
                    style: forestringTextStyle.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _rangeRow(
    BuildContext context,
    TeacherWorkHourDraft value, {
    required bool canDelete,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Expanded(
            child: _compactTimeButton(
              label: '시작',
              value: value.startTime,
              onTap: () => _editTimeRange(
                context,
                value,
                initialEditingStart: true,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 7),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 17,
              color: Colors.black38,
            ),
          ),
          Expanded(
            child: _compactTimeButton(
              label: '종료',
              value: value.endTime,
              onTap: () => _editTimeRange(
                context,
                value,
                initialEditingStart: false,
              ),
            ),
          ),
          if (canDelete) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: '시간대 삭제',
              visualDensity: VisualDensity.compact,
              onPressed: enabled ? () => _removeValue(value) : null,
              icon: const Icon(
                Icons.close_rounded,
                size: 19,
                color: Colors.black38,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _compactTimeButton({
    required String label,
    required TimeOfDay value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: forestringTextStyle.copyWith(
                  color: Colors.black45,
                  fontSize: 9.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                formatTeacherWorkTime(value),
                style: forestringTextStyle.copyWith(
                  color: enabled ? primaryColor : Colors.black38,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editTimeRange(
    BuildContext context,
    TeacherWorkHourDraft current, {
    required bool initialEditingStart,
  }) async {
    if (!enabled) return;

    final picked = await showTeacherWorkTimeRangePicker(
      context: context,
      initialStartTime: current.startTime,
      initialEndTime: current.endTime,
      initialEditingStart: initialEditingStart,
    );

    if (picked == null) return;

    _replaceValue(
      current,
      current.copyWith(
        startTime: picked.startTime,
        endTime: picked.endTime,
      ),
    );
  }

  void _enableWeekday(int weekday) {
    _emit([
      ...values,
      TeacherWorkHourDraft(weekday: weekday),
    ]);
  }

  void _disableWeekday(int weekday) {
    if (!allowEmpty &&
        values.where((value) => value.weekday != weekday).isEmpty) {
      return;
    }
    _emit(
      values
          .where((value) => value.weekday != weekday)
          .toList(),
    );
  }

  bool _canAddRange(List<TeacherWorkHourDraft> entries) {
    if (entries.isEmpty) return false;
    final latest = entries
        .map((entry) => _minutes(entry.endTime))
        .reduce((a, b) => a > b ? a : b);
    return latest < 23 * 60 + 45;
  }

  void _addRange(
    int weekday,
    List<TeacherWorkHourDraft> entries,
  ) {
    var startMinutes = 9 * 60;
    if (entries.isNotEmpty) {
      startMinutes = entries
          .map((entry) => _minutes(entry.endTime))
          .reduce((a, b) => a > b ? a : b);
    }
    startMinutes =
        ((startMinutes + 14) ~/ 15) * 15;
    if (startMinutes > 23 * 60) return;

    final proposedEnd = startMinutes + 60;
    final endMinutes = proposedEnd > 23 * 60 + 45
        ? 23 * 60 + 45
        : proposedEnd;

    _emit([
      ...values,
      TeacherWorkHourDraft(
        weekday: weekday,
        startTime: TimeOfDay(
          hour: startMinutes ~/ 60,
          minute: startMinutes % 60,
        ),
        endTime: TimeOfDay(
          hour: endMinutes ~/ 60,
          minute: endMinutes % 60,
        ),
      ),
    ]);
  }

  void _replaceValue(
    TeacherWorkHourDraft current,
    TeacherWorkHourDraft next,
  ) {
    final updated = List<TeacherWorkHourDraft>.of(values);
    final index = updated.indexOf(current);
    if (index < 0) return;
    updated[index] = next;
    _emit(updated);
  }

  void _removeValue(TeacherWorkHourDraft value) {
    final updated = List<TeacherWorkHourDraft>.of(values)
      ..remove(value);
    _emit(updated);
  }

  void _emit(List<TeacherWorkHourDraft> updated) {
    updated.sort((a, b) {
      final weekday = a.weekday.compareTo(b.weekday);
      if (weekday != 0) return weekday;
      return _minutes(a.startTime).compareTo(
        _minutes(b.startTime),
      );
    });
    onChanged(updated);
  }
}

Future<TeacherWorkTimeRange?> showTeacherWorkTimeRangePicker({
  required BuildContext context,
  required TimeOfDay initialStartTime,
  required TimeOfDay initialEndTime,
  bool initialEditingStart = true,
}) async {
  var startTime = _roundToQuarter(initialStartTime);
  var endTime = _roundToQuarter(initialEndTime);
  var editingStart = initialEditingStart;

  return showModalBottomSheet<TeacherWorkTimeRange>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedTime = editingStart ? startTime : endTime;
          final startMinutes = _minutes(startTime);
          final endMinutes = _minutes(endTime);
          final isValid = startMinutes < endMinutes;
          final durationMinutes = isValid ? endMinutes - startMinutes : 0;

          return SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              decoration: const BoxDecoration(
                color: neutralIvory,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '근무시간 설정',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _timeRangeTarget(
                          label: '시작',
                          value: startTime,
                          selected: editingStart,
                          onTap: () {
                            setSheetState(() => editingStart = true);
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.black45,
                        ),
                      ),
                      Expanded(
                        child: _timeRangeTarget(
                          label: '종료',
                          value: endTime,
                          selected: !editingStart,
                          onTap: () {
                            setSheetState(() => editingStart = false);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: isValid
                        ? Row(
                            key: const ValueKey('duration'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 16,
                                color: Colors.black45,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _durationLabel(durationMinutes),
                                style: forestringTextStyle.copyWith(
                                  color: Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            '종료시간은 시작시간보다 뒤여야 합니다.',
                            key: const ValueKey('error'),
                            style: forestringTextStyle.copyWith(
                              color: Colors.redAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 210,
                    child: CupertinoDatePicker(
                      key: ValueKey(editingStart),
                      mode: CupertinoDatePickerMode.time,
                      use24hFormat: true,
                      minuteInterval: 15,
                      backgroundColor: Colors.transparent,
                      initialDateTime: DateTime(
                        2000,
                        1,
                        1,
                        selectedTime.hour,
                        selectedTime.minute,
                      ),
                      onDateTimeChanged: (value) {
                        final next = TimeOfDay(
                          hour: value.hour,
                          minute: value.minute,
                        );
                        setSheetState(() {
                          if (editingStart) {
                            startTime = next;
                          } else {
                            endTime = next;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: !isValid
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop(
                                TeacherWorkTimeRange(
                                  startTime: startTime,
                                  endTime: endTime,
                                ),
                              );
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            primaryColor.withValues(alpha: 0.2),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('완료'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _timeRangeTarget({
  required String label,
  required TimeOfDay value,
  required bool selected,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? primaryColor.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? primaryColor
                : primaryColor.withValues(alpha: 0.16),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: forestringTextStyle.copyWith(
                color: selected ? primaryColor : Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatTeacherWorkTime(value),
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String? validateTeacherWorkHours(
  List<TeacherWorkHourDraft> values, {
  bool allowEmpty = false,
}) {
  if (values.isEmpty && !allowEmpty) {
    return '근무시간을 한 개 이상 등록해주세요.';
  }

  final byWeekday = <int, List<TeacherWorkHourDraft>>{};
  for (final value in values) {
    final start = _minutes(value.startTime);
    final end = _minutes(value.endTime);
    if (start >= end) {
      return '${teacherWeekdayLabel(value.weekday)}요일의 종료시간은 시작시간보다 뒤여야 합니다.';
    }
    byWeekday.putIfAbsent(value.weekday, () => []).add(value);
  }

  for (final entry in byWeekday.entries) {
    final ranges = List<TeacherWorkHourDraft>.of(entry.value)
      ..sort(
        (a, b) => _minutes(a.startTime).compareTo(_minutes(b.startTime)),
      );
    for (var index = 1; index < ranges.length; index += 1) {
      if (_minutes(ranges[index].startTime) <
          _minutes(ranges[index - 1].endTime)) {
        return '${teacherWeekdayLabel(entry.key)}요일에 서로 겹치는 근무시간이 있습니다.';
      }
    }
  }

  return null;
}

String formatTeacherWorkTime(TimeOfDay value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

TimeOfDay parseTeacherWorkTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) {
    return const TimeOfDay(hour: 9, minute: 0);
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return const TimeOfDay(hour: 9, minute: 0);
  }

  return TimeOfDay(hour: hour, minute: minute);
}

String teacherWeekdayLabel(int weekday) {
  return switch (weekday) {
    1 => '월',
    2 => '화',
    3 => '수',
    4 => '목',
    5 => '금',
    6 => '토',
    7 => '일',
    _ => '-',
  };
}

TimeOfDay _roundToQuarter(TimeOfDay value) {
  final roundedMinute = value.minute - (value.minute % 15);
  return TimeOfDay(hour: value.hour, minute: roundedMinute);
}

String _durationLabel(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '총 $remainder분';
  if (remainder == 0) return '총 $hours시간';
  return '총 $hours시간 $remainder분';
}

int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;