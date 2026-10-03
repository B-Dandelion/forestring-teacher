import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../domain/lesson.dart';

Color lessonStatusAccentColor(Lesson lesson) {
  if (lesson.isCanceled) {
    return Colors.redAccent;
  }
  if (lesson.isStudentRebooked) {
    return const Color(0xff4B7892);
  }
  if (lesson.isStaffChanged) {
    return const Color(0xffA87524);
  }
  if (lesson.type == LessonType.makeup) {
    return const Color(0xffB36A2E);
  }
  if (lesson.type == LessonType.flex) {
    return const Color(0xff5C8692);
  }
  return primaryColor;
}

Color lessonStatusSurfaceColor(Lesson lesson) {
  return Color.lerp(
    lessonStatusAccentColor(lesson),
    Colors.white,
    0.82,
  )!;
}

String lessonStatusShortLabel(Lesson lesson) {
  if (lesson.isCanceled) return '취소';
  if (lesson.isStudentRebooked) return '재예약';
  if (lesson.isStaffChanged) return '변경';
  return switch (lesson.type) {
    LessonType.makeup => '보강',
    LessonType.flex => '자율',
    LessonType.regular => '정규',
  };
}
