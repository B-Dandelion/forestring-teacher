import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../../../core/theme/student_accent.dart';
import '../../domain/lesson.dart';
import '../lesson_visual_style.dart';

class LessonCard extends StatelessWidget {
  const LessonCard({
    super.key,
    required this.lesson,
    required this.personName,
    this.accentColor,
    this.onTap,
  });

  final Lesson lesson;
  final String personName;
  final Color? accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final start = DateFormat('HH:mm').format(lesson.startsAt);
    final end = DateFormat('HH:mm').format(lesson.endsAt);
    final badge = lesson.changeBadgeLabel;
    final badgeColor =
        lesson.isStudentRebooked ? secondaryColor : primaryColor;
    final resolvedAccentColor = lesson.isCanceled
        ? Colors.black38
        : accentColor ?? lessonStatusAccentColor(lesson);
    final accentTextColor = lesson.isCanceled
        ? Colors.black45
        : studentAccentForeground(resolvedAccentColor);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: lesson.isCanceled
                ? const Color(0xffF4F5F4)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: lesson.isCanceled
                  ? Colors.black12
                  : primaryColor.withValues(alpha: 0.10),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: resolvedAccentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 58,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                start,
                                style: forestringTextStyle.copyWith(
                                  color: accentTextColor,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w500,
                                  decoration: lesson.isCanceled
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                end,
                                style: forestringTextStyle.copyWith(
                                  color: Colors.black38,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 42,
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      personName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: forestringTextStyle.copyWith(
                                        color: Colors.black87,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        decoration: lesson.isCanceled
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                  if (lesson.isCanceled) ...[
                                    const SizedBox(width: 8),
                                    _statusBadge(
                                      '취소',
                                      Colors.redAccent,
                                    ),
                                  ] else if (badge != null) ...[
                                    const SizedBox(width: 8),
                                    _statusBadge(
                                      badge,
                                      badgeColor,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                lesson.displayTypeLabel,
                                style: forestringTextStyle.copyWith(
                                  color: Colors.black45,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
