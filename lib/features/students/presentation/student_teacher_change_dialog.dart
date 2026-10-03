import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../data/student_management_repository.dart';
import '../data/student_teacher_management_repository.dart';

Future<bool?> showStudentTeacherChangeDialog({
  required BuildContext context,
  required ManagedStudent student,
  StudentTeacherManagementRepository? repository,
}) {
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => _StudentTeacherChangeDialog(
      student: student,
      repository: repository,
    ),
  );
}

class _StudentTeacherChangeDialog extends StatefulWidget {
  const _StudentTeacherChangeDialog({
    required this.student,
    this.repository,
  });

  final ManagedStudent student;
  final StudentTeacherManagementRepository? repository;

  @override
  State<_StudentTeacherChangeDialog> createState() =>
      _StudentTeacherChangeDialogState();
}

class _StudentTeacherChangeDialogState
    extends State<_StudentTeacherChangeDialog> {
  late final StudentTeacherManagementRepository _repository;

  List<ManagedTeacherOption> _teachers = const [];
  String? _teacherId;
  late DateTime _effectiveOn;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? StudentTeacherManagementRepository();
    final now = DateTime.now();
    _effectiveOn = DateTime(now.year, now.month, now.day);
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    final branchId = widget.student.branchId;
    if (branchId == null) {
      setState(() {
        _loading = false;
        _errorMessage = '학생의 지점 정보가 없어 담당 선생님을 변경할 수 없습니다.';
      });
      return;
    }

    try {
      final teachers = await _repository.fetchBranchTeachers(branchId);
      final available = teachers
          .where((teacher) => teacher.id != widget.student.teacherId)
          .toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));

      if (!mounted) return;
      setState(() {
        _teachers = available;
        _loading = false;
        _teacherId = available.length == 1 ? available.first.id : null;
      });
    } on StudentTeacherManagementFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    }
  }

  Future<void> _pickEffectiveDate() async {
    final today = DateTime.now();
    final firstDate = DateTime(today.year, today.month, today.day);
    final lastDate = DateTime(today.year + 3, 12, 31);

    final selected = await showDatePicker(
      context: context,
      initialDate: _effectiveOn.isBefore(firstDate) ? firstDate : _effectiveOn,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: '변경 적용일 선택',
      cancelText: '취소',
      confirmText: '선택',
    );

    if (selected == null || !mounted) return;
    setState(() => _effectiveOn = selected);
  }

  Future<void> _save() async {
    final teacherId = _teacherId;
    if (teacherId == null) {
      setState(() => _errorMessage = '변경할 선생님을 선택해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await _repository.changeStudentTeacher(
        studentId: widget.student.id,
        teacherId: teacherId,
        effectiveOn: _effectiveOn,
        currentTeacherId: widget.student.teacherId,
        isFlex: widget.student.isFlex,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StudentTeacherManagementFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final currentTeacher = student.teacherName == null
        ? '미배정'
        : '${student.teacherName} 선생님';

    final canManage = student.teacherId != null || student.isFlex;

    return AlertDialog(
      title: Text(student.teacherId == null ? '담당 선생님 지정' : '담당 선생님 변경'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${student.displayName} · ${student.branchName}',
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '현재 담당: $currentTeacher',
                style: forestringTextStyle.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (!canManage)
                _messageBox(
                  '정규 학생의 기존 담당 선생님 배정이 없어 자동 변경할 수 없습니다.\n'
                  '학생의 정규 일정 상태를 먼저 확인해주세요.',
                  isError: true,
                )
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _teacherId,
                  decoration: const InputDecoration(
                    labelText: '새 담당 선생님',
                    border: OutlineInputBorder(),
                  ),
                  items: _teachers
                      .map(
                        (teacher) => DropdownMenuItem(
                          value: teacher.id,
                          child: Text(teacher.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _teacherId = value),
                ),
                if (_teachers.isEmpty) ...[
                  const SizedBox(height: 8),
                  _messageBox('변경 가능한 다른 선생님이 없습니다.'),
                ],
                const SizedBox(height: 12),
                InkWell(
                  onTap: _saving ? null : _pickEffectiveDate,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '변경 적용일',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(DateFormat('yyyy.MM.dd').format(_effectiveOn)),
                  ),
                ),
                const SizedBox(height: 12),
                _messageBox(
                  student.isRegular
                      ? '정규 학생은 변경일부터 기존 요일·시간·수업 길이를 유지한 채 담당 선생님이 변경됩니다. 새 선생님의 근무시간과 기존 수업 충돌 조건을 만족해야 합니다.'
                      : '자율 예약 학생은 선택한 날짜부터 담당 선생님 배정이 변경됩니다.',
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _messageBox(_errorMessage!, isError: true),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _saving || _loading || !canManage || _teachers.isEmpty
              ? null
              : _save,
          style: FilledButton.styleFrom(backgroundColor: primaryColor),
          child: Text(_saving ? '변경 중...' : '변경'),
        ),
      ],
    );
  }

  Widget _messageBox(String message, {bool isError = false}) {
    final color = isError ? Colors.redAccent : primaryColor;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: isError ? Colors.redAccent : Colors.black87,
          fontSize: 13,
        ),
      ),
    );
  }
}
