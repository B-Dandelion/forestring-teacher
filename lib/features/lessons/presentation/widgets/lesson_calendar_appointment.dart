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
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(
        horizontal: 2,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          name,
          maxLines: 1,
          style: TextStyle(
            color: Colors.black,
            fontFamily: 'ELAND',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
      ),
    );
  }

  Color get _backgroundColor =>
      accentColor ?? studentAccentColor(lesson.studentId);
}
