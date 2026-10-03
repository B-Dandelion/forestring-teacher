import 'package:flutter/material.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';
import '../lesson_controller.dart';
import 'lesson_activity_detail_sheet.dart';
import 'lesson_time_slot_picker.dart';

Future<void> showLessonActionDialog({
  required BuildContext context,
  required Lesson lesson,
  required LessonController controller,
}) async {
  if (lesson.isCanceled) {
    await showLessonActivityDetailSheet(
      context: context,
      lesson: lesson,
    );
    return;
  }

  final hostContext = context;
  var selectedDate = DateTime(
    lesson.startsAt.year,
    lesson.startsAt.month,
    lesson.startsAt.day,
  );
  var selectedTime = TimeOfDay.fromDateTime(lesson.startsAt);
  var selectedDuration = lesson.durationMinutes;
  var isSaving = false;

  final durations = <int>{15, 30, 45, 60, 75, 90, selectedDuration}
      .where((value) => value > 0 && value <= 720)
      .toList()
    ..sort();

  await showDialog<void>(
    context: hostContext,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogBodyContext, setState) {
          final hasChanges =
              !_sameDate(selectedDate, lesson.startsAt) ||
              selectedTime.hour != lesson.startsAt.hour ||
              selectedTime.minute != lesson.startsAt.minute ||
              selectedDuration != lesson.durationMinutes;

          Future<void> editDate() async {
            if (isSaving) return;
            final picked = await showDatePicker(
              context: dialogBodyContext,
              initialDate: selectedDate,
              firstDate: DateTime(2024, 1, 1),
              lastDate: DateTime(2035, 12, 31),
            );
            if (picked != null) {
              setState(() => selectedDate = picked);
            }
          }

          Future<void> editTime() async {
            if (isSaving) return;
            final picked = await showLessonTimeSlotPicker(
              context: dialogBodyContext,
              lesson: lesson,
              controller: controller,
              selectedDate: selectedDate,
              initialTime: selectedTime,
              durationMinutes: selectedDuration,
            );
            if (picked != null) {
              setState(() => selectedTime = picked);
            }
          }

          Future<void> cancelLesson() async {
            if (isSaving) return;

            final confirmed = await _confirmCancel(
              dialogBodyContext,
              lesson,
            );
            if (!confirmed || !dialogBodyContext.mounted) {
              return;
            }

            setState(() => isSaving = true);
            final ok = await controller.cancelLesson(
              lesson,
              reason: '앱에서 수업 취소',
            );

            if (!dialogBodyContext.mounted) {
              return;
            }

            if (ok) {
              Navigator.of(dialogContext).pop();
              if (hostContext.mounted) {
                _showMessage(hostContext, '수업이 취소되었습니다.');
              }
              return;
            }

            setState(() => isSaving = false);
            if (hostContext.mounted) {
              _showMessage(
                hostContext,
                controller.errorMessage ?? '수업을 취소하지 못했습니다.',
              );
            }
          }

          Future<void> saveChanges() async {
            if (isSaving || !hasChanges) return;

            final startsAt = DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
              selectedTime.hour,
              selectedTime.minute,
            );

            setState(() => isSaving = true);

            var result = await controller.updateLessonOnce(
              lesson: lesson,
              startsAt: startsAt,
              durationMinutes: selectedDuration,
              reason: '앱에서 수업 1회 수정',
            );

            if (!dialogBodyContext.mounted) {
              return;
            }

            if (result == null) {
              setState(() => isSaving = false);
              if (hostContext.mounted) {
                _showMessage(
                  hostContext,
                  controller.errorMessage ?? '일정을 변경하지 못했습니다.',
                );
              }
              return;
            }

            if (result.requiresConfirmation) {
              final confirmWarnings = await _confirmWarnings(
                dialogBodyContext,
                result.warningCodes,
              );

              if (!confirmWarnings || !dialogBodyContext.mounted) {
                setState(() => isSaving = false);
                return;
              }

              result = await controller.updateLessonOnce(
                lesson: lesson,
                startsAt: startsAt,
                durationMinutes: selectedDuration,
                confirmWarnings: true,
                reason: '앱에서 수업 1회 수정',
              );
            }

            if (!dialogBodyContext.mounted) {
              return;
            }

            if (result == null || result.requiresConfirmation) {
              setState(() => isSaving = false);
              if (hostContext.mounted) {
                _showMessage(
                  hostContext,
                  controller.errorMessage ?? '일정을 변경하지 못했습니다.',
                );
              }
              return;
            }

            Navigator.of(dialogContext).pop();
            if (hostContext.mounted) {
              _showMessage(
                hostContext,
                result.changed
                    ? '일정이 변경되었습니다.'
                    : '변경된 내용이 없습니다.',
              );
            }
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  color: const Color(0xffFCFDF9),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.07),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lesson.studentName ?? '학생',
                                  style: forestringTextStyle.copyWith(
                                    color: primaryColor,
                                    fontSize: 27,
                                    fontWeight: FontWeight.w500,
                                    height: 1.05,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _LessonBadge(
                                      label: lesson.type.label,
                                    ),
                                    if (lesson.changeBadgeLabel != null)
                                      _LessonBadge(
                                        label: lesson.changeBadgeLabel!,
                                        emphasized: true,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline_rounded,
                                      size: 18,
                                      color: Colors.black.withValues(
                                        alpha: 0.58,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        lesson.teacherName == null
                                            ? '담당 선생님 확인 필요'
                                            : '${lesson.teacherName} 선생님',
                                        overflow: TextOverflow.ellipsis,
                                        style: forestringTextStyle.copyWith(
                                          color: Colors.black87,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _RoundCloseButton(
                            onPressed: isSaving
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _ScheduleValueCard(
                              label: '날짜',
                              value: _formatLessonDate(selectedDate),
                              icon: Icons.calendar_today_outlined,
                              onTap: isSaving ? null : editDate,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ScheduleValueCard(
                              label: '시간',
                              value: _formatLessonTime(selectedTime),
                              icon: Icons.access_time_rounded,
                              onTap: isSaving ? null : editTime,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '수업 길이',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black54,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final duration in durations)
                            _DurationChoice(
                              duration: duration,
                              selected: selectedDuration == duration,
                              enabled: !isSaving,
                              onSelected: () {
                                setState(
                                  () => selectedDuration = duration,
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: OutlinedButton.icon(
                              onPressed: isSaving ? null : cancelLesson,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('수업 취소'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: BorderSide(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.24,
                                  ),
                                ),
                                backgroundColor: Colors.redAccent.withValues(
                                  alpha: 0.055,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            flex: 6,
                            child: FilledButton.icon(
                              onPressed: isSaving || !hasChanges
                                  ? null
                                  : saveChanges,
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.edit_calendar_outlined,
                                      size: 18,
                                    ),
                              label: Text(
                                isSaving ? '변경 중...' : '일정 변경',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: primaryColor,
                                disabledBackgroundColor:
                                    primaryColor.withValues(alpha: 0.16),
                                disabledForegroundColor:
                                    Colors.black.withValues(alpha: 0.34),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),
                        ],
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
}

class _LessonBadge extends StatelessWidget {
  const _LessonBadge({
    required this.label,
    this.emphasized = false,
  });

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final foreground =
        emphasized ? const Color(0xff946E16) : primaryColor;
    final background = emphasized
        ? const Color(0xffF4EBCF)
        : primaryColor.withValues(alpha: 0.075);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _RoundCloseButton extends StatelessWidget {
  const _RoundCloseButton({
    required this.onPressed,
  });

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primaryColor.withValues(alpha: 0.055),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            Icons.close_rounded,
            size: 21,
            color: primaryColor,
          ),
        ),
      ),
    );
  }
}

class _ScheduleValueCard extends StatelessWidget {
  const _ScheduleValueCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primaryColor.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.075),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: forestringTextStyle.copyWith(
                          color: Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationChoice extends StatelessWidget {
  const _DurationChoice({
    required this.duration,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final int duration;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? primaryColor : const Color(0xffF0F2ED),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: enabled ? onSelected : null,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 9,
          ),
          child: Text(
            '$duration분',
            style: forestringTextStyle.copyWith(
              color: selected ? Colors.white : Colors.black54,
              fontSize: 12,
              fontWeight:
                  selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

String _formatLessonDate(DateTime value) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  final weekday = weekdays[value.weekday - 1];
  return '${value.month}월 ${value.day}일 ($weekday)';
}

String _formatLessonTime(TimeOfDay value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

Future<bool> _confirmCancel(
  BuildContext context,
  Lesson lesson,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('수업 취소'),
          content: Text(
            '${lesson.studentName ?? '학생'} 학생의 '
            '${_formatLessonDate(lesson.startsAt)} '
            '${_formatLessonTime(TimeOfDay.fromDateTime(lesson.startsAt))} '
            '수업을 취소하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('아니요'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                '취소하기',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> _confirmWarnings(
  BuildContext context,
  List<String> warningCodes,
) async {
  final messages = warningCodes.map((code) {
    return switch (code) {
      'FORESTRING_OUTSIDE_WORK_HOURS' => '선생님 근무시간 밖입니다.',
      'FORESTRING_OVERLAPS_BLOCKED_PERIOD' => '예약 불가 시간과 겹칩니다.',
      'FORESTRING_NONSTANDARD_DURATION' => '권장 수업 길이(15/30/60분)가 아닙니다.',
      _ => code,
    };
  }).join('\n');

  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('확인이 필요합니다'),
          content: Text('$messages\n\n그래도 변경하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('돌아가기'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('변경하기'),
            ),
          ],
        ),
      ) ??
      false;
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
