import 'package:flutter/material.dart';

import '../../../../core/theme/student_accent.dart';
import '../../domain/lesson.dart';

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
    final backgroundColor = _backgroundColor;

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: 3,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Text(
          name,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black,
            fontFamily: 'ELAND',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.05,
          ),
        ),
      ),
    );
  }

  Color get _backgroundColor =>
      accentColor ?? studentAccentColor(lesson.studentId);
}
