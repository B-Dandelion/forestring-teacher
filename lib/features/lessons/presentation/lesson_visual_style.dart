import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../domain/lesson.dart';

const Color regularLessonColor = primaryColor;
const Color flexLessonColor = Color(0xff4B7892);
const Color makeupLessonColor = Color(0xff7768A7);
const Color staffChangedLessonColor = Color(0xff9B678A);
const Color studentRebookedLessonColor = Color(0xff3F7F83);
const Color canceledLessonColor = Color(0xffC75D63);

Color classicLessonColor(Lesson lesson) {
  if (lesson.type == LessonType.makeup) {
    return secondaryColor;
  }
  if (lesson.isRescheduled) {
    return const Color(0xff4F7E67);
  }
  return primaryColor;
}

Color lessonStatusAccentColor(Lesson lesson) {
  if (lesson.isCanceled) {
    return canceledLessonColor;
  }
  if (lesson.isStudentRebooked) {
    return studentRebookedLessonColor;
  }
  if (lesson.isStaffChanged) {
    return staffChangedLessonColor;
  }
  if (lesson.type == LessonType.makeup) {
    return makeupLessonColor;
  }
  if (lesson.type == LessonType.flex) {
    return flexLessonColor;
  }
  return regularLessonColor;
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
