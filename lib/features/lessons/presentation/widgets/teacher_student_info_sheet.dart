import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../../teachers/data/teacher_repository.dart';

Future<void> showTeacherStudentInfoSheet({
  required BuildContext context,
  required AssignedStudentSummary student,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.displayName,
                          style: forestringTextStyle.copyWith(
                            color: Colors.black87,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${student.typeLabel} · ${student.statusLabel}',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _InfoRow(
                label: '담당 시작',
                value: DateFormat('yyyy.MM.dd').format(
                  student.assignmentStartsOn,
                ),
              ),
              const SizedBox(height: 10),
              if (student.isFlex)
                _InfoRow(
                  label: '수강 형태',
                  value: student.flexBaseRightCount == null
                      ? '자율 예약'
                      : '자율 예약 · 기본 수업권 '
                          '${student.flexBaseRightCount}회',
                )
              else if (student.regularSchedules.isEmpty)
                const _InfoRow(
                  label: '정규 일정',
                  value: '현재 적용 중인 정규 일정이 없습니다.',
                )
              else ...[
                Text(
                  '정규 일정',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black45,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 7),
                for (final schedule in student.regularSchedules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ScheduleRow(schedule: schedule),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: forestringTextStyle.copyWith(
              color: Colors.black45,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.schedule,
  });

  final AssignedStudentRegularSchedule schedule;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xffF3F7F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${_weekdayLabel(schedule.weekday)} '
        '${schedule.startTime} · '
        '${schedule.durationMinutes}분',
        style: forestringTextStyle.copyWith(
          color: Colors.black87,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    1 => '월요일',
    2 => '화요일',
    3 => '수요일',
    4 => '목요일',
    5 => '금요일',
    6 => '토요일',
    7 => '일요일',
    _ => '요일 미정',
  };
}
