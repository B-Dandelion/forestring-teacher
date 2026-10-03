import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../data/student_management_repository.dart';

Future<StudentWithdrawalResult?> showStudentWithdrawalDialog({
  required BuildContext context,
  required ManagedStudent student,
  required StudentManagementRepository repository,
}) {
  return Navigator.of(context).push<StudentWithdrawalResult>(
    MaterialPageRoute(
      builder: (_) => StudentWithdrawalPage(
        student: student,
        repository: repository,
      ),
    ),
  );
}

class StudentWithdrawalPage extends StatefulWidget {
  const StudentWithdrawalPage({
    super.key,
    required this.student,
    required this.repository,
  });

  final ManagedStudent student;
  final StudentManagementRepository repository;

  @override
  State<StudentWithdrawalPage> createState() =>
      _StudentWithdrawalPageState();
}

class _StudentWithdrawalPageState
    extends State<StudentWithdrawalPage> {
  late DateTime _withdrawalDate;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _withdrawalDate = widget.student.withdrawalDate ??
        DateTime(now.year, now.month, now.day);
  }

  bool get _isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(
      _withdrawalDate.year,
      _withdrawalDate.month,
      _withdrawalDate.day,
    );
    return selected == today;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate:
          _withdrawalDate.isBefore(today) ? today : _withdrawalDate,
      firstDate: today,
      lastDate: DateTime(today.year + 3, 12, 31),
      helpText: '퇴원일 선택',
      cancelText: '취소',
      confirmText: '선택',
    );

    if (selected == null || !mounted) return;
    setState(() => _withdrawalDate = selected);
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.repository.scheduleWithdrawal(
        studentId: widget.student.id,
        withdrawalDate: _withdrawalDate,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText =
        DateFormat('yyyy.MM.dd').format(_withdrawalDate);

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: AppBar(
        backgroundColor: neutralIvory,
        foregroundColor: primaryColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.student.withdrawalDate == null
              ? '퇴원 관리'
              : '퇴원 예정일 변경',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 19,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.student.displayName,
                    style: forestringTextStyle.copyWith(
                      color: primaryColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.student.branchName,
                    style: forestringTextStyle.copyWith(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '퇴원 예정일',
                    style: forestringTextStyle.copyWith(
                      color: primaryColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _saving ? null : _pickDate,
                    borderRadius: BorderRadius.circular(13),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.035),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            color: primaryColor,
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              dateText,
                              style: forestringTextStyle.copyWith(
                                color: Colors.black87,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _messageBox(
              _isToday
                  ? '오늘을 선택하면 즉시 퇴원 처리됩니다. 오늘 이후 수업은 정리되고, 사용 가능한 수업권은 회수되며 학생 계정은 비활성화됩니다. 과거 수업 기록은 유지됩니다.'
                  : '$dateText부터 수업을 진행하지 않는 것으로 예약합니다. 저장 즉시 해당 날짜 이후 예정 수업이 정리됩니다. 퇴원일 전까지는 학생 계정이 유지되며 예약을 취소할 수 있습니다.',
            ),
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
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _saving
                  ? '처리 중...'
                  : _isToday
                      ? '오늘 퇴원'
                      : '퇴원 예약',
              style: forestringTextStyle.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
      ),
      child: child,
    );
  }

  Widget _messageBox(
    String message, {
    bool isError = false,
  }) {
    final color = isError ? Colors.redAccent : primaryColor;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: isError ? Colors.redAccent : Colors.black87,
          fontSize: 12,
          height: 1.45,
        ),
      ),
    );
  }
}
