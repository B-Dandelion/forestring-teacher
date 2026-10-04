import 'package:flutter/material.dart';

import '../../../../core/theme/student_accent_controller.dart';
import '../../domain/lesson.dart';
import '../lesson_visual_style.dart';

class LessonCalendarAppointment extends StatelessWidget {
  const LessonCalendarAppointment({
    super.key,
    required this.lesson,
    required this.displayMode,
    this.accentColor,
  });

  final Lesson lesson;
  final ScheduleDisplayMode displayMode;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final name = lesson.studentName ?? '학생';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 28;

        return switch (displayMode) {
          ScheduleDisplayMode.classic => _classic(
              name: name,
              compact: compact,
            ),
          ScheduleDisplayMode.status => _status(
              name: name,
              compact: compact,
            ),
          ScheduleDisplayMode.student => _student(
              name: name,
              compact: compact,
            ),
        };
      },
    );
  }

  Widget _classic({
    required String name,
    required bool compact,
  }) {
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: 3,
        vertical: compact ? 0 : 2,
      ),
      decoration: BoxDecoration(
        color: classicLessonColor(lesson),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        name,
        maxLines: compact ? 1 : 2,
        softWrap: !compact,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontFamily: 'ELAND',
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w500,
          height: 1.02,
        ),
      ),
    );
  }

  Widget _status({
    required String name,
    required bool compact,
  }) {
    final statusColor = lessonStatusAccentColor(lesson);

    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.fromLTRB(
        4,
        compact ? 0 : 2,
        3,
        compact ? 0 : 2,
      ),
      decoration: BoxDecoration(
        color: lessonStatusSurfaceColor(lesson),
        borderRadius: BorderRadius.circular(4),
        border: Border(
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
  }

  Widget _student({
    required String name,
    required bool compact,
  }) {
    final color = accentColor ?? const Color(0xff77C99A);

    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: 3,
        vertical: compact ? 0 : 2,
      ),
      decoration: BoxDecoration(
        color: Color.lerp(color, Colors.white, 0.30)!,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        name,
        maxLines: compact ? 1 : 2,
        softWrap: !compact,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color.lerp(
            color,
            const Color(0xff21322A),
            0.55,
          ),
          fontFamily: 'ELAND',
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w500,
          height: 1.02,
        ),
      ),
    );
  }
}
