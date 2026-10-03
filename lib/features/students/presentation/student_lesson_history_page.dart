import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../lessons/data/lesson_repository.dart';
import '../../lessons/domain/lesson.dart';
import '../../lessons/presentation/lesson_controller.dart';
import '../../lessons/presentation/widgets/lesson_action_dialog.dart';
import '../data/student_management_repository.dart';

enum _HistoryRange { upcoming, past, all }

class StudentLessonHistoryPage extends StatefulWidget {
  const StudentLessonHistoryPage({
    super.key,
    required this.student,
    this.profile,
    this.repository,
    this.branchRepository,
  });

  final ManagedStudent student;
  final CurrentProfile? profile;
  final LessonRepository? repository;
  final BranchRepository? branchRepository;

  @override
  State<StudentLessonHistoryPage> createState() =>
      _StudentLessonHistoryPageState();
}

class _StudentLessonHistoryPageState
    extends State<StudentLessonHistoryPage> {
  late final LessonRepository _repository;
  LessonController? _actionController;
  Future<void>? _actionControllerInitialization;
  List<Lesson> _lessons = const [];
  _HistoryRange _range = _HistoryRange.upcoming;
  bool _loading = true;
  bool _openingLesson = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? LessonRepository();
    final profile = widget.profile;
    if (profile != null) {
      _actionController = LessonController(
        _repository,
        profile,
        branchRepository: widget.branchRepository,
      );
      _actionControllerInitialization = _actionController!.initialize();
    }
    _load();
  }

  @override
  void dispose() {
    _actionController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final lessons = await _repository.fetchVisibleLessons(
        studentId: widget.student.id,
      );
      if (!mounted) return;
      setState(() => _lessons = lessons);
    } on LessonFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openLesson(Lesson lesson) async {
    final controller = _actionController;
    if (controller == null || _openingLesson) return;

    setState(() => _openingLesson = true);
    try {
      await _actionControllerInitialization;
      if (!mounted) return;

      await showLessonActionDialog(
        context: context,
        lesson: lesson,
        controller: controller,
      );
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _openingLesson = false);
    }
  }

  List<Lesson> get _visibleLessons {
    final now = DateTime.now();
    final filtered = _lessons.where((lesson) {
      return switch (_range) {
        _HistoryRange.upcoming => !lesson.endsAt.isBefore(now),
        _HistoryRange.past => lesson.endsAt.isBefore(now),
        _HistoryRange.all => true,
      };
    }).toList();

    filtered.sort((a, b) => _range == _HistoryRange.past
        ? b.startsAt.compareTo(a.startsAt)
        : a.startsAt.compareTo(b.startsAt));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final scheduledCount = _lessons.where((lesson) => !lesson.isCanceled).length;
    final canceledCount = _lessons.where((lesson) => lesson.isCanceled).length;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: AppBar(
        backgroundColor: neutralIvory,
        foregroundColor: primaryColor,
        title: Text(
          '수업 내역',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 21,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: primaryColor,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            _SummaryCard(
              student: widget.student,
              scheduledCount: scheduledCount,
              canceledCount: canceledCount,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.06),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x07000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: SegmentedButton<_HistoryRange>(
                segments: const [
                  ButtonSegment(
                    value: _HistoryRange.upcoming,
                    label: Text('예정'),
                  ),
                  ButtonSegment(
                    value: _HistoryRange.past,
                    label: Text('지난 수업'),
                  ),
                  ButtonSegment(
                    value: _HistoryRange.all,
                    label: Text('전체'),
                  ),
                ],
                selected: {_range},
                onSelectionChanged: (values) {
                  setState(() => _range = values.single);
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: primaryColor,
                  selectedForegroundColor: Colors.white,
                  foregroundColor: primaryColor,
                  side: BorderSide.none,
                  textStyle: forestringTextStyle.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(
                  child: CircularProgressIndicator(color: primaryColor),
                ),
              )
            else if (_errorMessage != null)
              _MessageCard(
                icon: Icons.error_outline,
                message: _errorMessage!,
                actionLabel: '다시 시도',
                onAction: _load,
              )
            else if (_visibleLessons.isEmpty)
              const _MessageCard(
                icon: Icons.event_busy_outlined,
                message: '해당하는 수업이 없습니다.',
              )
            else
              ..._buildGroupedLessons(_visibleLessons),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedLessons(List<Lesson> lessons) {
    final widgets = <Widget>[];
    DateTime? previousDay;

    for (final lesson in lessons) {
      final day = DateTime(
        lesson.startsAt.year,
        lesson.startsAt.month,
        lesson.startsAt.day,
      );
      if (previousDay == null ||
          previousDay.year != day.year ||
          previousDay.month != day.month ||
          previousDay.day != day.day) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 14));
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(day),
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
        previousDay = day;
      }
      widgets.add(
        _LessonHistoryCard(
          lesson: lesson,
          onTap: _actionController == null || _openingLesson
              ? null
              : () => _openLesson(lesson),
        ),
      );
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.student,
    required this.scheduledCount,
    required this.canceledCount,
  });

  final ManagedStudent student;
  final int scheduledCount;
  final int canceledCount;

  @override
  Widget build(BuildContext context) {
    final typeColor =
        student.isRegular ? primaryColor : const Color(0xff4B7892);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09000000),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              color: typeColor,
              size: 29,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        student.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: forestringTextStyle.copyWith(
                          color: Colors.black87,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        student.typeLabel,
                        style: forestringTextStyle.copyWith(
                          color: typeColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  student.branchName,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _CountBadge(
                      label: '수업',
                      count: scheduledCount,
                    ),
                    _CountBadge(
                      label: '취소',
                      count: canceledCount,
                      color: Colors.redAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    required this.count,
    this.color = primaryColor,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $count회',
        style: forestringTextStyle.copyWith(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _LessonHistoryCard extends StatelessWidget {
  const _LessonHistoryCard({
    required this.lesson,
    this.onTap,
  });

  final Lesson lesson;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final time = '${DateFormat('HH:mm').format(lesson.startsAt)} ~ '
        '${DateFormat('HH:mm').format(lesson.endsAt)}';
    final originalTime = lesson.occurrenceAt;
    final wasMoved = originalTime != null &&
        originalTime.toUtc() != lesson.startsAt.toUtc();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 13, 11, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: lesson.isCanceled
                  ? Colors.redAccent.withValues(alpha: 0.18)
                  : primaryColor.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (lesson.isCanceled
                          ? Colors.redAccent
                          : primaryColor)
                      .withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  lesson.isCanceled
                      ? Icons.event_busy_rounded
                      : Icons.event_available_rounded,
                  color: lesson.isCanceled
                      ? Colors.redAccent
                      : primaryColor,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            time,
                            style: forestringTextStyle.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              decoration: lesson.isCanceled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        _StatusBadge(lesson: lesson),
                        if (onTap != null) ...[
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.black38,
                            size: 19,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${lesson.displayTypeLabel} · ${lesson.durationMinutes}분',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      lesson.teacherName == null
                          ? '담당 선생님 정보 없음'
                          : '${lesson.teacherName} 선생님',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13.5,
                      ),
                    ),
                    if (wasMoved) ...[
                      const SizedBox(height: 6),
                      Text(
                        '변경 전 ${DateFormat('M.d (E) HH:mm', 'ko_KR').format(originalTime)}',
                        style: forestringTextStyle.copyWith(
                          color: secondaryColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (lesson.isCanceled &&
                        lesson.cancellationReason?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Text(
                        '취소 사유 · ${lesson.cancellationReason!.trim()}',
                        style: forestringTextStyle.copyWith(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final label = lesson.isCanceled
        ? '취소'
        : (lesson.changeBadgeLabel ?? lesson.type.label);
    final color = lesson.isCanceled ? Colors.redAccent : secondaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.black38, size: 34),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: forestringTextStyle.copyWith(color: Colors.black54),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
