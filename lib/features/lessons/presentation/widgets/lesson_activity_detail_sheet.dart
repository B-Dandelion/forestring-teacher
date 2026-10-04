import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../data/lesson_repository.dart';
import '../../domain/lesson.dart';
import '../lesson_visual_style.dart';

Future<bool> showLessonActivityDetailSheet({
  required BuildContext context,
  required Lesson lesson,
  required LessonRepository repository,
  bool allowEdit = false,
}) async {
  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.42),
        builder: (sheetContext) {
          return SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
              ),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              decoration: const BoxDecoration(
                color: neutralIvory,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: FutureBuilder<List<LessonActivityRecord>>(
                future: repository.fetchLessonActivity(lesson: lesson),
                builder: (context, snapshot) {
                  final loading =
                      snapshot.connectionState == ConnectionState.waiting;
                  final events = snapshot.data ?? const <LessonActivityRecord>[];

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '수업 변동 내역',
                              style: forestringTextStyle.copyWith(
                                color: primaryColor,
                                fontSize: 21,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          _pill(_lessonBadge(lesson)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${lesson.studentName ?? '학생'} · ${lesson.displayTypeLabel}',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black87,
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${DateFormat('M월 d일 HH:mm').format(lesson.startsAt)} ~ '
                        '${DateFormat('HH:mm').format(lesson.endsAt)}'
                        '${lesson.teacherName == null ? '' : ' · ${lesson.teacherName} 선생님'}',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black54,
                          fontSize: 13,
                          decoration: lesson.isCanceled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 34),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (snapshot.hasError)
                        _emptyActivityCard('처리 이력을 불러오지 못했습니다.')
                      else if (events.isEmpty)
                        _emptyActivityCard('변동 이력이 없는 수업입니다.')
                      else
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: primaryColor.withValues(alpha: 0.07),
                              ),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: events.length,
                              itemBuilder: (_, index) => _activityTimelineItem(
                                lesson,
                                events[index],
                                isLast: index == events.length - 1,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      if (allowEdit)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('닫기'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('일정 변경'),
                              ),
                            ),
                          ],
                        )
                      else
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('확인'),
                        ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ) ??
      false;
}

Widget _emptyActivityCard(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: primaryColor.withValues(alpha: 0.08),
      ),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: forestringTextStyle.copyWith(
        color: Colors.black54,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

Widget _activityTimelineItem(
  Lesson lesson,
  LessonActivityRecord event, {
  required bool isLast,
}) {
  final color = _eventColor(event);
  final scheduleText = _eventDescription(event);
  final actorText = _actorLabel(event, lesson);
  final actionTime = DateFormat('M월 d일 HH:mm').format(event.eventAt);

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 22,
        child: Column(
          children: [
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 1,
                height: scheduleText == null ? 42 : 58,
                margin: const EdgeInsets.only(top: 3),
                color: Colors.black.withValues(alpha: 0.11),
              ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _eventLabel(event),
                style: forestringTextStyle.copyWith(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (scheduleText != null) ...[
                const SizedBox(height: 3),
                Text(
                  scheduleText,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 3),
              Text(
                '$actorText · $actionTime',
                style: forestringTextStyle.copyWith(
                  color: Colors.black38,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

Color _eventColor(LessonActivityRecord event) {
  return switch (event.eventType) {
    'LESSON_CANCELED' => canceledLessonColor,
    'LESSON_MANUALLY_UPDATED' => staffChangedLessonColor,
    'LESSON_RIGHT_BOOKED' =>
      _isRebooking(event) ? studentRebookedLessonColor : regularLessonColor,
    'MAKEUP_LESSON_CREATED' => makeupLessonColor,
    _ => regularLessonColor,
  };
}

String _eventLabel(LessonActivityRecord event) {
  switch (event.eventType) {
    case 'LESSON_ORIGINAL_SCHEDULE':
      return '원래 일정';
    case 'LESSON_CANCELED':
      return event.details['cancellationOrigin']?.toString() == 'student'
          ? '학생 취소'
          : '학원 취소';
    case 'LESSON_MANUALLY_UPDATED':
      return '일정 변경';
    case 'LESSON_RIGHT_BOOKED':
      return _isRebooking(event) ? '재예약' : '수업권 예약';
    case 'MAKEUP_LESSON_CREATED':
      return '보강 등록';
    default:
      return '처리';
  }
}

bool _isRebooking(LessonActivityRecord event) {
  return event.details['regularRebooking'] == true ||
      event.details['reusedLesson'] == true;
}

String? _eventDescription(LessonActivityRecord event) {
  switch (event.eventType) {
    case 'LESSON_ORIGINAL_SCHEDULE':
      return _scheduleText(
        _parseDate(event.details['startsAt']),
        _parseDate(event.details['endsAt']),
      );
    case 'LESSON_CANCELED':
      final schedule = _scheduleText(
        _parseDate(event.details['startsAt']),
        _parseDate(event.details['endsAt']),
      );
      final reason = event.details['reason']?.toString().trim();
      if (schedule == null) {
        return reason == null || reason.isEmpty ? null : reason;
      }
      return reason == null || reason.isEmpty
          ? schedule
          : '$schedule · $reason';
    case 'LESSON_MANUALLY_UPDATED':
      final before = _asMap(event.details['before']);
      final after = _asMap(event.details['after']);
      final beforeStart = _parseDate(before['startsAt']);
      final afterStart = _parseDate(after['startsAt']);
      final afterDuration = _asInt(after['durationMinutes']);
      if (beforeStart == null && afterStart == null) return null;
      final beforeText = beforeStart == null
          ? '기존 일정'
          : DateFormat('M월 d일 HH:mm').format(beforeStart);
      final afterText = afterStart == null
          ? '변경 일정'
          : DateFormat('M월 d일 HH:mm').format(afterStart);
      return '$beforeText → $afterText'
          '${afterDuration == null ? '' : ' · $afterDuration분'}';
    case 'LESSON_RIGHT_BOOKED':
      return _scheduleText(
        _parseDate(event.details['startsAt']),
        _parseDate(event.details['endsAt']),
      );
    case 'MAKEUP_LESSON_CREATED':
      final schedule = _scheduleText(
        _parseDate(event.details['startsAt']),
        _parseDate(event.details['endsAt']),
      );
      final reason = event.details['reason']?.toString().trim();
      if (schedule == null) {
        return reason == null || reason.isEmpty ? null : reason;
      }
      return reason == null || reason.isEmpty
          ? schedule
          : '$schedule · 메모: $reason';
    default:
      return null;
  }
}

String? _scheduleText(DateTime? start, DateTime? end) {
  if (start == null) return null;
  if (end == null) {
    return DateFormat('M월 d일 HH:mm').format(start);
  }
  return '${DateFormat('M월 d일 HH:mm').format(start)} ~ '
      '${DateFormat('HH:mm').format(end)}';
}

String _actorLabel(LessonActivityRecord event, Lesson lesson) {
  if (event.actorId != null && event.actorId == lesson.studentId) {
    return '${lesson.studentName ?? event.actorName ?? '학생'} · 수강생';
  }

  final roleLabel = switch (event.actorRole) {
    'master' => '전체 관리자',
    'manager' => '지점장',
    'teacher' => '선생님',
    'student' => '수강생',
    _ => '사용자',
  };
  final name = event.actorName?.trim();
  if (name == null || name.isEmpty) return '확인되지 않음';
  return '$name · $roleLabel';
}

String _lessonBadge(Lesson lesson) {
  if (lesson.isCanceled) return '취소';
  if (lesson.isStudentRebooked) return '재예약';
  if (lesson.isStaffChanged) return '변경';
  if (lesson.type == LessonType.makeup) return '보강';
  if (lesson.type == LessonType.flex) return '예약';
  return '수업';
}

Widget _pill(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: forestringTextStyle.copyWith(
        color: Colors.black54,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}
