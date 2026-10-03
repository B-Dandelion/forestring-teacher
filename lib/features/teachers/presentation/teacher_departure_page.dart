import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../data/teacher_repository.dart';

class TeacherDeparturePage extends StatefulWidget {
  const TeacherDeparturePage({
    super.key,
    required this.teacher,
    this.repository,
  });

  final ManagedTeacher teacher;
  final TeacherRepository? repository;

  @override
  State<TeacherDeparturePage> createState() =>
      _TeacherDeparturePageState();
}

class _TeacherDeparturePageState extends State<TeacherDeparturePage> {
  late final TeacherRepository _repository;

  StaffDepartureState? _departure;
  DateTime? _selectedDate;
  bool _loading = false;
  bool _saving = false;
  String? _errorMessage;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isDue {
    final date = _departure?.withdrawalDate;
    return date != null && !date.isAfter(_today);
  }

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? TeacherRepository();
    _selectedDate = widget.teacher.withdrawalDate;
    if (widget.teacher.isActive && widget.teacher.withdrawalDate != null) {
      _loadDeparture();
    }
  }

  Future<void> _loadDeparture() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final departure = await _repository.fetchStaffDepartureState(
        widget.teacher.id,
      );
      if (!mounted) return;
      setState(() {
        _departure = departure;
        _selectedDate = departure.withdrawalDate;
      });
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _chooseDate() async {
    final initialDate = _selectedDate == null || _selectedDate!.isBefore(_today)
        ? _today
        : _selectedDate!;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _today,
      lastDate: DateTime(_today.year + 3, 12, 31),
      helpText: '퇴사 예정일 선택',
      cancelText: '취소',
      confirmText: '선택',
    );

    if (!mounted || selected == null) return;
    setState(() => _selectedDate = selected);
  }

  Future<void> _saveDeparture() async {
    final selectedDate = _selectedDate;
    final wasScheduled = _departure != null;
    if (selectedDate == null) {
      setState(() => _errorMessage = '퇴사 예정일을 선택해주세요.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_departure == null ? '퇴사 예약' : '퇴사 예정일 변경'),
        content: Text(
          '${DateFormat('yyyy년 M월 d일').format(selectedDate)}부터 '
          '${widget.teacher.displayName} 선생님은 근무하거나 로그인할 수 없습니다.\n\n'
          '이 날짜 전까지 담당 학생, 정규 일정과 예정 수업을 정리해야 합니다.',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            child: Text(_departure == null ? '예약' : '변경'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final departure = await _repository.scheduleStaffDeparture(
        staffId: widget.teacher.id,
        withdrawalDate: selectedDate,
      );
      if (!mounted) return;
      setState(() {
        _departure = departure;
        _selectedDate = departure.withdrawalDate;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasScheduled
                ? '퇴사 예정일이 저장되었습니다.'
                : '퇴사가 예약되었습니다.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _cancelDeparture() async {
    final date = _departure?.withdrawalDate;
    if (date == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('퇴사 예약 취소'),
        content: Text(
          '${DateFormat('yyyy년 M월 d일').format(date)}로 예약된 '
          '퇴사를 취소합니다.',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('예약 취소'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await _repository.cancelStaffDeparture(widget.teacher.id);
      if (!mounted) return;
      setState(() {
        _departure = null;
        _selectedDate = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('퇴사 예약이 취소되었습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _finalizeDeparture() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('퇴사 확정'),
        content: Text(
          '${widget.teacher.displayName} 선생님의 계정을 즉시 비활성화합니다. '
          '확정 후에는 이 화면에서 되돌릴 수 없습니다.',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('퇴사 확정'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await _repository.finalizeStaffDeparture(widget.teacher.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('퇴사가 확정되어 계정이 비활성화되었습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: widget.teacher.isActive ? '퇴사 관리' : '퇴사 정보',
        actions: [
          if (widget.teacher.isActive && _departure != null)
            IconButton(
              tooltip: '새로고침',
              onPressed: _loading || _saving ? null : _loadDeparture,
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListView(
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
            const SizedBox(height: 4),
            Text(
              widget.teacher.branchName,
              style: forestringTextStyle.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            _policyCard(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _errorCard(_errorMessage!),
            ],
            const SizedBox(height: 16),
            if (!widget.teacher.isActive)
              _departedCard()
            else if (_loading && _departure == null)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _dateSection(),
              if (_departure != null) ...[
                const SizedBox(height: 16),
                _blockerSection(_departure!),
              ],
              const SizedBox(height: 20),
              if (!_isDue)
                FilledButton(
                  onPressed: _saving || _selectedDate == null
                      ? null
                      : _saveDeparture,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    _saving
                        ? '처리 중...'
                        : _departure == null
                            ? '퇴사 예약'
                            : '퇴사 예정일 저장',
                  ),
                ),
              if (_departure != null && !_isDue) ...[
                const SizedBox(height: 9),
                OutlinedButton(
                  onPressed: _saving ? null : _cancelDeparture,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade700),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('퇴사 예약 취소'),
                ),
              ],
              if (_departure != null &&
                  _isDue &&
                  _departure!.canFinalize) ...[
                const SizedBox(height: 9),
                FilledButton(
                  onPressed: _saving ? null : _finalizeDeparture,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('지금 퇴사 확정'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _policyCard() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '퇴사 예정일은 선생님이 근무할 수 없는 첫날입니다. '
        '전날까지는 정상 근무하며, 예정일이 되면 정리 상태를 확인한 뒤 '
        '자동으로 계정이 비활성화됩니다.',
        style: forestringTextStyle.copyWith(fontSize: 13),
      ),
    );
  }

  Widget _departedCard() {
    final date = widget.teacher.withdrawalDate;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '퇴사 완료',
            style: forestringTextStyle.copyWith(
              color: Colors.red.shade700,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            date == null
                ? '퇴사일 정보가 없습니다.'
                : '${DateFormat('yyyy년 M월 d일').format(date)}부터 계정이 비활성화되었습니다.',
            style: forestringTextStyle,
          ),
        ],
      ),
    );
  }

  Widget _dateSection() {
    final date = _selectedDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _departure == null ? '퇴사 예정일' : '예약된 퇴사일',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saving || _isDue ? null : _chooseDate,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            date == null
                ? '날짜 선택'
                : DateFormat('yyyy년 M월 d일').format(date),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            side: const BorderSide(color: primaryColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (_isDue) ...[
          const SizedBox(height: 8),
          Text(
            '퇴사 예정일이 도래하여 날짜 변경과 예약 취소가 제한됩니다.',
            style: forestringTextStyle.copyWith(
              color: Colors.red.shade700,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _blockerSection(StaffDepartureState departure) {
    final color = departure.canFinalize
        ? primaryColor
        : Colors.orange.shade800;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            departure.canFinalize ? '퇴사 준비 완료' : '퇴사 전 정리 필요',
            style: forestringTextStyle.copyWith(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _countTile('담당 학생', departure.assignmentCount),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _countTile('정규 일정', departure.seriesCount),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _countTile(
                  '예정 수업',
                  departure.scheduledLessonCount,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            departure.canFinalize
                ? '정리할 항목이 없습니다. 예정일이 되면 자동으로 퇴사 처리됩니다.'
                : '퇴사 확정 전까지 담당 학생 변경, 정규 일정 종료와 예정 수업 변경·취소가 필요합니다.',
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _countTile(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: neutralIvory,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            '$count개',
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
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

String _teacherLabel(String name) {
  final trimmed = name.trim();
  return trimmed.endsWith('선생님') ? trimmed : '$trimmed 선생님';
}
