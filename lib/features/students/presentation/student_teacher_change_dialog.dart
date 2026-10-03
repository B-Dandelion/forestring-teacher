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
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => StudentTeacherChangePage(
        student: student,
        repository: repository,
      ),
    ),
  );
}

class StudentTeacherChangePage extends StatefulWidget {
  const StudentTeacherChangePage({
    super.key,
    required this.student,
    this.repository,
  });

  final ManagedStudent student;
  final StudentTeacherManagementRepository? repository;

  @override
  State<StudentTeacherChangePage> createState() =>
      _StudentTeacherChangePageState();
}

class _StudentTeacherChangePageState
    extends State<StudentTeacherChangePage> {
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
        _errorMessage =
            '학생의 지점 정보가 없어 담당 선생님을 변경할 수 없습니다.';
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
    final selected = await showDatePicker(
      context: context,
      initialDate:
          _effectiveOn.isBefore(firstDate) ? firstDate : _effectiveOn,
      firstDate: firstDate,
      lastDate: DateTime(today.year + 3, 12, 31),
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

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: AppBar(
        backgroundColor: neutralIvory,
        foregroundColor: primaryColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          student.teacherId == null ? '담당 선생님 지정' : '담당 선생님 변경',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
          children: [
            _headerCard(student, currentTeacher),
            const SizedBox(height: 12),
            if (!canManage)
              _messageBox(
                '정규 학생의 기존 담당 선생님 배정이 없어 자동 변경할 수 없습니다. '
                '학생의 정규 일정 상태를 먼저 확인해주세요.',
                isError: true,
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: CircularProgressIndicator(
                    color: primaryColor,
                  ),
                ),
              )
            else ...[
              _sectionCard(
                title: '새 담당 선생님',
                child: DropdownButtonFormField<String>(
                  initialValue: _teacherId,
                  decoration: _decoration('선생님 선택'),
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
              ),
              const SizedBox(height: 12),
              _sectionCard(
                title: '변경 적용일',
                child: InkWell(
                  onTap: _saving ? null : _pickEffectiveDate,
                  borderRadius: BorderRadius.circular(13),
                  child: InputDecorator(
                    decoration: _decoration('적용일').copyWith(
                      suffixIcon:
                          const Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(
                      DateFormat('yyyy.MM.dd').format(_effectiveOn),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _messageBox(
                student.isRegular
                    ? '정규 학생은 선택한 날짜부터 기존 요일·시간·수업 길이를 유지한 채 담당 선생님이 변경됩니다.'
                    : '자율 예약 학생은 선택한 날짜부터 담당 선생님 배정이 변경됩니다.',
              ),
            ],
            if (_teachers.isEmpty && !_loading && canManage) ...[
              const SizedBox(height: 12),
              _messageBox('변경 가능한 다른 선생님이 없습니다.'),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _messageBox(_errorMessage!, isError: true),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: FilledButton(
            onPressed: _saving ||
                    _loading ||
                    !canManage ||
                    _teachers.isEmpty
                ? null
                : _save,
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _saving ? '변경 중...' : '담당 선생님 변경',
              style: forestringTextStyle.copyWith(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCard(
    ManagedStudent student,
    String currentTeacher,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            student.displayName,
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 22,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${student.branchName} · 현재 담당 $currentTeacher',
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: primaryColor.withValues(alpha: 0.035),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _messageBox(String message, {bool isError = false}) {
    final color = isError ? Colors.redAccent : primaryColor;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: isError ? Colors.redAccent : Colors.black87,
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}
