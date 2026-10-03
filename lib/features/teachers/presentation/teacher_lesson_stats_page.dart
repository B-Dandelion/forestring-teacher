import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../data/teacher_repository.dart';

class TeacherLessonStatsPage extends StatefulWidget {
  const TeacherLessonStatsPage({
    super.key,
    required this.teacher,
    this.repository,
  });

  final ManagedTeacher teacher;
  final TeacherRepository? repository;

  @override
  State<TeacherLessonStatsPage> createState() =>
      _TeacherLessonStatsPageState();
}

class _TeacherLessonStatsPageState extends State<TeacherLessonStatsPage> {
  late final TeacherRepository _repository;

  TeacherLessonStats? _stats;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? TeacherRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final stats = await _repository.fetchTeacherLessonStats(
        widget.teacher.id,
      );
      if (!mounted) return;
      setState(() => _stats = stats);
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '학기별 수업 통계',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            children: [
              Text(
                _teacherLabel(widget.teacher.displayName),
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 21,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '수업 종료 시각이 지났고 취소되지 않은 수업만 집계합니다.',
                  style: forestringTextStyle.copyWith(fontSize: 13),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorCard(message: _errorMessage!),
              ],
              if (_loading && stats == null)
                const Padding(
                  padding: EdgeInsets.only(top: 90),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (stats != null) ...[
                const SizedBox(height: 14),
                _OverallSummary(stats: stats),
                const SizedBox(height: 18),
                if (stats.semesters.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Text(
                      '조회할 학기 정보가 없습니다.',
                      textAlign: TextAlign.center,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  )
                else
                  ...[
                    Text(
                      '학기별 내역',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...stats.semesters.map(_SemesterStatsCard.new),
                  ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OverallSummary extends StatelessWidget {
  const _OverallSummary({required this.stats});

  final TeacherLessonStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '누적 집계 · '
            '${DateFormat('yyyy.MM.dd').format(stats.employmentStartsOn)}부터',
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _summaryValue(
                  '전체 수업',
                  '${stats.totalLessonCount}회',
                ),
              ),
              Container(
                width: 1,
                height: 38,
                color: Colors.black12,
              ),
              Expanded(
                child: _summaryValue(
                  '전체 시간',
                  _minutesText(stats.totalMinutes),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryValue(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: forestringTextStyle.copyWith(
            color: Colors.black54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _SemesterStatsCard extends StatelessWidget {
  const _SemesterStatsCard(this.stats);

  final TeacherSemesterLessonStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: stats.isCurrent
              ? primaryColor.withValues(alpha: 0.35)
              : Colors.black12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _semesterLabel(stats.code),
                    style: forestringTextStyle.copyWith(
                      color: primaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (stats.isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '현재 학기',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${DateFormat('yyyy.MM.dd').format(stats.startsOn)} ~ '
              '${DateFormat('yyyy.MM.dd').format(stats.endsOn)}',
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Text(
                  '총 ${stats.totalLessonCount}회',
                  style: forestringTextStyle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '· ${_minutesText(stats.totalMinutes)}',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            if (stats.durationGroups.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: neutralIvory,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '집계된 수업 없음',
                  textAlign: TextAlign.center,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black45,
                    fontSize: 13,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: stats.durationGroups
                    .map(
                      (group) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: secondaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${group.durationMinutes}분 수업 '
                          '${group.lessonCount}회',
                          style: forestringTextStyle.copyWith(
                            color: primaryColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(color: Colors.redAccent),
      ),
    );
  }
}

String _semesterLabel(String code) {
  final parts = code.split('-');
  if (parts.length != 2) return code;

  final month = int.tryParse(parts[1]);
  return month == null ? code : '${parts[0]}년 $month월 학기';
}

String _minutesText(int minutes) {
  if (minutes < 60) return '$minutes분';

  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours시간' : '$hours시간 $remainder분';
}

String _teacherLabel(String name) {
  final trimmed = name.trim();
  return trimmed.endsWith('선생님') ? trimmed : '$trimmed 선생님';
}
