import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';

Future<bool> showLessonActivityDetailSheet({
  required BuildContext context,
  required Lesson lesson,
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
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.76,
              ),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              decoration: const BoxDecoration(
                color: neutralIvory,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: FutureBuilder<_LessonActivityData>(
                future: _loadLessonActivity(lesson),
                builder: (context, snapshot) {
                  final loading =
                      snapshot.connectionState == ConnectionState.waiting;
                  final data =
                      snapshot.data ?? const _LessonActivityData(events: []);

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
                              _sheetTitle(lesson),
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
                      Text(
                        '처리 이력',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (data.events.isEmpty)
                        _emptyActivityCard(data)
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: data.events.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) =>
                                _activityCard(data.events[index]),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
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

Widget _emptyActivityCard(_LessonActivityData data) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: primaryColor.withValues(alpha: 0.12),
      ),
    ),
    child: Text(
      data.loadFailed ? '처리 이력을 불러오지 못했습니다.' : '이력이 저장되지 않은 수업입니다.',
      textAlign: TextAlign.center,
      style: forestringTextStyle.copyWith(
        color: Colors.black54,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

Widget _activityCard(_LessonActivity event) {
  final color = switch (event.eventType) {
    'LESSON_CANCELED' => Colors.redAccent,
    'LESSON_MANUALLY_UPDATED' => secondaryColor,
    'LESSON_RIGHT_BOOKED' => primaryColor,
    'MAKEUP_LESSON_CREATED' => secondaryColor,
    _ => primaryColor,
  };

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: color.withValues(alpha: 0.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _eventLabel(event),
                style: forestringTextStyle.copyWith(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              DateFormat('yyyy.MM.dd HH:mm').format(event.createdAt),
              style: forestringTextStyle.copyWith(
                color: Colors.black45,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          event.actorLabel,
          style: forestringTextStyle.copyWith(
            color: Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        _finalDescription(event),
      ],
    ),
  );
}

Widget _finalDescription(_LessonActivity event) {
  final description = _eventDescription(event);
  if (description == null || description.isEmpty) {
    return const SizedBox.shrink();
  }
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      description,
      style: forestringTextStyle.copyWith(
        color: Colors.black54,
        fontSize: 12,
      ),
    ),
  );
}

String _eventLabel(_LessonActivity event) {
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
      return event.details['regularRebooking'] == true ||
              event.details['reusedLesson'] == true
          ? '재예약'
          : '수업권 예약';
    case 'MAKEUP_LESSON_CREATED':
      return '보강 등록';
    default:
      return '처리';
  }
}

String? _eventDescription(_LessonActivity event) {
  switch (event.eventType) {
    case 'LESSON_ORIGINAL_SCHEDULE':
      final originalStart = _parseDate(event.details['startsAt']);
      final originalEnd = _parseDate(event.details['endsAt']);
      if (originalStart == null) return null;
      return originalEnd == null
          ? DateFormat('M월 d일 HH:mm').format(originalStart)
          : '${DateFormat('M월 d일 HH:mm').format(originalStart)} ~ '
              '${DateFormat('HH:mm').format(originalEnd)}';
    case 'LESSON_CANCELED':
      final canceledStart = _parseDate(event.details['startsAt']);
      final canceledEnd = _parseDate(event.details['endsAt']);
      final reason = event.details['reason']?.toString().trim();
      final schedule = canceledStart == null
          ? null
          : canceledEnd == null
              ? DateFormat('M월 d일 HH:mm').format(canceledStart)
              : '${DateFormat('M월 d일 HH:mm').format(canceledStart)} ~ '
                  '${DateFormat('HH:mm').format(canceledEnd)}';
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
    case 'MAKEUP_LESSON_CREATED':
      final start = _parseDate(event.details['startsAt']);
      final end = _parseDate(event.details['endsAt']);
      if (start == null) return null;
      return end == null
          ? DateFormat('M월 d일 HH:mm').format(start)
          : '${DateFormat('M월 d일 HH:mm').format(start)} ~ '
              '${DateFormat('HH:mm').format(end)}';
    default:
      return null;
  }
}

String _sheetTitle(Lesson lesson) {
  if (lesson.isCanceled) return '취소 내역';
  if (lesson.isStudentRebooked) return '재예약 내역';
  if (lesson.isStaffChanged) return '변경 내역';
  if (lesson.type == LessonType.makeup) return '보강 내역';
  if (lesson.type == LessonType.flex) return '예약 내역';
  return '수업 내역';
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

Future<_LessonActivityData> _loadLessonActivity(Lesson lesson) async {
  try {
    final client = Supabase.instance.client;
    final rightId = lesson.lessonRightId;

    if (rightId != null && rightId.isNotEmpty) {
      final rawRows = await client.rpc(
        'get_student_lesson_activity',
        params: {
          'p_student_id': lesson.studentId,
          'p_right_id': rightId,
        },
      );

      final events = (rawRows as List).map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        final actorId = row['actor_id']?.toString();
        final actor = _Actor(
          name: row['actor_name']?.toString(),
          role: row['actor_role']?.toString(),
        );
        return _LessonActivity(
          eventType: row['event_type']?.toString() ?? '',
          createdAt: DateTime.parse(row['event_at'].toString()).toLocal(),
          actorLabel: _actorLabel(
            actorId: actorId,
            actor: actor,
            lesson: lesson,
          ),
          details: _asMap(row['details']),
        );
      }).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      return _LessonActivityData(events: events);
    }

    final rawRows = await client
        .from('audit_events')
        .select('event_type, actor_id, details, created_at')
        .eq('subject_profile_id', lesson.studentId)
        .inFilter('event_type', const [
      'LESSON_CANCELED',
      'LESSON_MANUALLY_UPDATED',
      'LESSON_RIGHT_BOOKED',
      'MAKEUP_LESSON_CREATED',
    ]).order('created_at');

    final rows = (rawRows as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((row) {
      final details = _asMap(row['details']);
      return details['lessonId']?.toString() == lesson.id;
    }).toList();

    final actorIds = rows
        .map((row) => row['actor_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final actors = <String, _Actor>{};
    if (actorIds.isNotEmpty) {
      final profileRows = await client
          .from('profiles')
          .select('id, display_name, role')
          .inFilter('id', actorIds.toList());
      for (final raw in profileRows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        actors[id] = _Actor(
          name: row['display_name']?.toString(),
          role: row['role']?.toString(),
        );
      }
    }

    final events = rows.map((row) {
      final actorId = row['actor_id']?.toString();
      final actor = actorId == null ? null : actors[actorId];
      return _LessonActivity(
        eventType: row['event_type']?.toString() ?? '',
        createdAt: DateTime.parse(row['created_at'].toString()).toLocal(),
        actorLabel: _actorLabel(
          actorId: actorId,
          actor: actor,
          lesson: lesson,
        ),
        details: _asMap(row['details']),
      );
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return _LessonActivityData(events: events);
  } catch (_) {
    return const _LessonActivityData(
      events: [],
      loadFailed: true,
    );
  }
}

String _actorLabel({
  required String? actorId,
  required _Actor? actor,
  required Lesson lesson,
}) {
  if (actorId != null && actorId == lesson.studentId) {
    return '${lesson.studentName ?? actor?.name ?? '학생'} · 수강생';
  }

  final roleLabel = switch (actor?.role) {
    'master' => '전체 관리자',
    'manager' => '지점장',
    'teacher' => '선생님',
    'student' => '수강생',
    _ => '사용자',
  };
  final name = actor?.name?.trim();
  if (name == null || name.isEmpty) return '확인되지 않음';
  return '$name · $roleLabel';
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

class _LessonActivityData {
  const _LessonActivityData({
    required this.events,
    this.loadFailed = false,
  });

  final List<_LessonActivity> events;
  final bool loadFailed;
}

class _LessonActivity {
  const _LessonActivity({
    required this.eventType,
    required this.createdAt,
    required this.actorLabel,
    required this.details,
  });

  final String eventType;
  final DateTime createdAt;
  final String actorLabel;
  final Map<String, dynamic> details;
}

class _Actor {
  const _Actor({
    required this.name,
    required this.role,
  });

  final String? name;
  final String? role;
}
