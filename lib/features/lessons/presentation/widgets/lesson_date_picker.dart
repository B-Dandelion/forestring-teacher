import 'package:flutter/material.dart';

import '../../../../core/theme/forestring_theme.dart';

Future<DateTime?> showLessonDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final minimum = _dateOnly(firstDate ?? DateTime(2024, 1, 1));
  final maximum = _dateOnly(lastDate ?? DateTime(2035, 12, 31));
  final initial = _clampDate(_dateOnly(initialDate), minimum, maximum);

  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    builder: (sheetContext) {
      var selectedDate = initial;
      var visibleMonth = DateTime(initial.year, initial.month);

      return StatefulBuilder(
        builder: (context, setState) {
          final previousMonth = DateTime(
            visibleMonth.year,
            visibleMonth.month - 1,
          );
          final nextMonth = DateTime(
            visibleMonth.year,
            visibleMonth.month + 1,
          );
          final canGoPrevious = !_monthEnd(previousMonth).isBefore(minimum);
          final canGoNext = !nextMonth.isAfter(
            DateTime(maximum.year, maximum.month),
          );

          void changeMonth(int delta) {
            final target = DateTime(
              visibleMonth.year,
              visibleMonth.month + delta,
            );
            setState(() => visibleMonth = target);
          }

          void goToday() {
            final today = _dateOnly(DateTime.now());
            if (today.isBefore(minimum) || today.isAfter(maximum)) return;
            setState(() {
              selectedDate = today;
              visibleMonth = DateTime(today.year, today.month);
            });
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Container(
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
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '날짜 선택',
                            style: forestringTextStyle.copyWith(
                              color: primaryColor,
                              fontSize: 21,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        _SheetIconButton(
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        children: [
                          _SheetIconButton(
                            icon: Icons.chevron_left_rounded,
                            onPressed:
                                canGoPrevious ? () => changeMonth(-1) : null,
                          ),
                          Expanded(
                            child: Text(
                              '${visibleMonth.year}년 ${visibleMonth.month}월',
                              textAlign: TextAlign.center,
                              style: forestringTextStyle.copyWith(
                                color: Colors.black87,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          _SheetIconButton(
                            icon: Icons.chevron_right_rounded,
                            onPressed: canGoNext ? () => changeMonth(1) : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _WeekdayHeader(),
                    const SizedBox(height: 4),
                    _MonthGrid(
                      visibleMonth: visibleMonth,
                      selectedDate: selectedDate,
                      minimum: minimum,
                      maximum: maximum,
                      onSelected: (value) {
                        setState(() => selectedDate = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton(
                          onPressed: goToday,
                          style: TextButton.styleFrom(
                            foregroundColor: primaryColor,
                          ),
                          child: Text(
                            '오늘',
                            style: forestringTextStyle.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black54,
                          ),
                          child: Text(
                            '취소',
                            style: forestringTextStyle.copyWith(
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(selectedDate),
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: Text(
                            '선택',
                            style: forestringTextStyle.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    const labels = ['월', '화', '수', '목', '금', '토', '일'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: forestringTextStyle.copyWith(
                color: Colors.black45,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.selectedDate,
    required this.minimum,
    required this.maximum,
    required this.onSelected,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime minimum;
  final DateTime maximum;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month,
      1,
    );
    final firstGridDate = firstOfMonth.subtract(
      Duration(days: firstOfMonth.weekday - DateTime.monday),
    );
    final today = _dateOnly(DateTime.now());

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: 42,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: 38,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemBuilder: (context, index) {
        final date = firstGridDate.add(Duration(days: index));
        final inCurrentMonth = date.month == visibleMonth.month;
        final enabled = !date.isBefore(minimum) && !date.isAfter(maximum);
        final selected = _sameDate(date, selectedDate);
        final isToday = _sameDate(date, today);

        return Material(
          color: selected ? primaryColor : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: enabled ? () => onSelected(date) : null,
            customBorder: const CircleBorder(),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: isToday && !selected
                    ? Border.all(
                        color: primaryColor.withValues(alpha: 0.65),
                      )
                    : null,
              ),
              child: Text(
                '${date.day}',
                style: forestringTextStyle.copyWith(
                  color: !enabled
                      ? Colors.black.withValues(alpha: 0.16)
                      : selected
                          ? Colors.white
                          : inCurrentMonth
                              ? Colors.black87
                              : Colors.black26,
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetIconButton extends StatelessWidget {
  const _SheetIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        color: onPressed == null
            ? Colors.black26
            : primaryColor,
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _monthEnd(DateTime value) =>
    DateTime(value.year, value.month + 1, 0);

DateTime _clampDate(
  DateTime value,
  DateTime minimum,
  DateTime maximum,
) {
  if (value.isBefore(minimum)) return minimum;
  if (value.isAfter(maximum)) return maximum;
  return value;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
