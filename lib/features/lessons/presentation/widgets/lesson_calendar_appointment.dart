import 'package:flutter/material.dart';

import '../../domain/lesson.dart';
import '../lesson_visual_style.dart';

class LessonCalendarAppointment extends StatelessWidget {
  const LessonCalendarAppointment({
    super.key,
    required this.lesson,
    this.accentColor,
  });

  final Lesson lesson;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final name = lesson.studentName ?? '학생';
    final statusColor = lessonStatusAccentColor(lesson);
    final backgroundColor = accentColor == null
        ? lessonStatusSurfaceColor(lesson)
        : Color.lerp(accentColor, Colors.white, 0.30)!;

    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(4, 2, 3, 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(
            color: statusColor,
            width: 3,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black87,
              fontFamily: 'ELAND',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            lessonStatusShortLabel(lesson),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: statusColor,
              fontFamily: 'ELAND',
              fontSize: 8,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
