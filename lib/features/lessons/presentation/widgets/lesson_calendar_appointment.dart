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
    final usesStudentColor = accentColor != null;
    final backgroundColor = usesStudentColor
        ? Color.lerp(accentColor, Colors.white, 0.30)!
        : lessonStatusSurfaceColor(lesson);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 28;

        return Container(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.fromLTRB(
            4,
            compact ? 0 : 2,
            3,
            compact ? 0 : 2,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(4),
            border: usesStudentColor
                ? null
                : Border(
                    left: BorderSide(
                      color: statusColor,
                      width: 3,
                    ),
                  ),
          ),
          child: compact
              ? Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontFamily: 'ELAND',
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                )
              : Column(
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
      },
    );
  }
}
