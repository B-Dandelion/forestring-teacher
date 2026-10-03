import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../data/teacher_repository.dart';

class TeacherBlockedPeriodsPage extends StatefulWidget {
  const TeacherBlockedPeriodsPage({
    super.key,
    required this.teacher,
    this.repository,
  });

  final ManagedTeacher teacher;
  final TeacherRepository? repository;

  @override
  State<TeacherBlockedPeriodsPage> createState() =>
      _TeacherBlockedPeriodsPageState();
}

class _TeacherBlockedPeriodsPageState
    extends State<TeacherBlockedPeriodsPage> {
  late final TeacherRepository _repository;

  List<ManagedTeacherBlockedPeriod> _periods = const [];
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
      final periods = await _repository.fetchTeacherBlockedPeriods(
        widget.teacher.id,
      );
      if (!mounted) return;
      setState(() => _periods = periods);
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openEditor({
    ManagedTeacherBlockedPeriod? period,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BlockedPeriodEditorDialog(
        teacher: widget.teacher,
        repository: _repository,
        period: period,
      ),
    );

    if (!mounted || saved != true) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(period == null ? '개인 일정이 추가되었습니다.' : '개인 일정이 변경되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _delete(ManagedTeacherBlockedPeriod period) async {
    final isPast = !period.endsAt.isAfter(DateTime.now());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('개인 일정 삭제'),
        content: Text(
          '${_rangeText(period)}\n\n'
          '${isPast ? '지난 개인 일정 기록을 삭제합니다.' : '이 일정을 삭제하면 해당 시간이 다시 예약 가능해집니다.'}',
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
              backgroundColor: Colors.redAccent,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await _repository.deleteTeacherBlockedPeriod(period.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('개인 일정이 삭제되었습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = _periods
        .where((period) => period.endsAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = _periods
        .where((period) => !period.endsAt.isAfter(now))
        .toList()
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '개인 일정 관리',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: widget.teacher.isActive
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _openEditor,
              backgroundColor: personalScheduleColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.event_busy_outlined),
              label: Text(
                '일정 추가',
                style: forestringTextStyle.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            children: [
              Text(
                '${widget.teacher.displayName} 선생님',
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 21,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _SummaryCard(label: '전체', count: _periods.length),
                  const SizedBox(width: 8),
                  _SummaryCard(label: '예정', count: upcoming.length),
                  const SizedBox(width: 8),
                  _SummaryCard(label: '지난 일정', count: past.length),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: personalScheduleColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '개인 일정과 겹치는 시간은 학생이 예약할 수 없습니다. '
                  '이미 수업이 있는 시간에는 개인 일정을 등록할 수 없습니다.',
                  style: forestringTextStyle.copyWith(fontSize: 13),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorCard(message: _errorMessage!),
              ],
              if (_loading && _periods.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_periods.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Text(
                    '등록된 개인 일정이 없습니다.',
                    textAlign: TextAlign.center,
                    style: forestringTextStyle.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                )
              else ...[
                if (upcoming.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _sectionTitle('예정 및 진행 중'),
                  const SizedBox(height: 8),
                  ...upcoming.map(
                    (period) => _periodCard(period, isPast: false),
                  ),
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _sectionTitle('지난 일정'),
                  const SizedBox(height: 8),
                  ...past.map(
                    (period) => _periodCard(period, isPast: true),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: forestringTextStyle.copyWith(
        color: primaryColor,
        fontSize: 17,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _periodCard(
    ManagedTeacherBlockedPeriod period, {
    required bool isPast,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: personalScheduleColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: personalScheduleColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.event_busy_outlined,
                color: isPast ? Colors.black38 : personalScheduleColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _rangeText(period),
                    style: forestringTextStyle.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isPast ? Colors.black54 : Colors.black,
                    ),
                  ),
                  if (period.reason?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      period.reason!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '일정 메뉴',
              onSelected: (value) {
                if (value == 'edit') {
                  _openEditor(period: period);
                } else if (value == 'delete') {
                  _delete(period);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('수정')),
                PopupMenuItem(value: 'delete', child: Text('삭제')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedPeriodEditorDialog extends StatefulWidget {
  const _BlockedPeriodEditorDialog({
    required this.teacher,
    required this.repository,
    this.period,
  });

  final ManagedTeacher teacher;
  final TeacherRepository repository;
  final ManagedTeacherBlockedPeriod? period;

  @override
  State<_BlockedPeriodEditorDialog> createState() =>
      _BlockedPeriodEditorDialogState();
}

class _BlockedPeriodEditorDialogState
    extends State<_BlockedPeriodEditorDialog> {
  late DateTime _startsAt;
  late DateTime _endsAt;
  late final TextEditingController _reasonController;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final period = widget.period;
    if (period != null) {
      _startsAt = period.startsAt;
      _endsAt = period.endsAt;
    } else {
      _startsAt = _nextQuarterHour(DateTime.now());
      _endsAt = _startsAt.add(const Duration(hours: 1));
    }
    _reasonController = TextEditingController(text: period?.reason ?? '');
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startsAt : _endsAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (picked == null || !mounted) return;

    setState(() {
      final updated = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
      if (start) {
        final duration = _endsAt.difference(_startsAt);
        _startsAt = updated;
        if (!_endsAt.isAfter(_startsAt)) {
          _endsAt = _startsAt.add(
            duration.isNegative || duration == Duration.zero
                ? const Duration(hours: 1)
                : duration,
          );
        }
      } else {
        _endsAt = updated;
      }
      _errorMessage = null;
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _startsAt : _endsAt;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null || !mounted) return;

    final roundedMinutes = (picked.minute / 15).round() * 15;
    final updated = DateTime(current.year, current.month, current.day).add(
      Duration(hours: picked.hour, minutes: roundedMinutes),
    );

    setState(() {
      if (start) {
        _startsAt = updated;
        if (!_endsAt.isAfter(_startsAt)) {
          _endsAt = _startsAt.add(const Duration(hours: 1));
        }
      } else {
        _endsAt = updated;
      }
      _errorMessage = null;
    });
  }

  Future<void> _save() async {
    if (!_endsAt.isAfter(_startsAt)) {
      setState(() => _errorMessage = '종료시간은 시작시간보다 뒤여야 합니다.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await widget.repository.saveTeacherBlockedPeriod(
        teacherId: widget.teacher.id,
        startsAt: _startsAt,
        endsAt: _endsAt,
        reason: _reasonController.text,
        blockedPeriodId: widget.period?.id,
      );
      if (!mounted) return;
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
    return AlertDialog(
      title: Text(
        widget.period == null ? '개인 일정 추가' : '개인 일정 수정',
        style: forestringTextStyle.copyWith(
          color: primaryColor,
          fontSize: 21,
          fontWeight: FontWeight.w500,
        ),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.teacher.displayName} 선생님',
                style: forestringTextStyle.copyWith(
                  color: personalScheduleColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              _DateTimeRow(
                label: '시작',
                value: _startsAt,
                onDateTap: _saving ? null : () => _pickDate(start: true),
                onTimeTap: _saving ? null : () => _pickTime(start: true),
              ),
              const SizedBox(height: 10),
              _DateTimeRow(
                label: '종료',
                value: _endsAt,
                onDateTap: _saving ? null : () => _pickDate(start: false),
                onTimeTap: _saving ? null : () => _pickTime(start: false),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _reasonController,
                enabled: !_saving,
                maxLength: 200,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '사유 (선택)',
                  hintText: '예: 병원, 외부 일정',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: forestringTextStyle.copyWith(
                    color: Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
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
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: primaryColor),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('저장'),
        ),
      ],
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.value,
    required this.onDateTap,
    required this.onTimeTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback? onDateTap;
  final VoidCallback? onTimeTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDateTap,
            icon: const Icon(Icons.calendar_today_outlined, size: 17),
            label: Text(DateFormat('yyyy.MM.dd').format(value)),
          ),
        ),
        const SizedBox(width: 7),
        SizedBox(
          width: 105,
          child: OutlinedButton(
            onPressed: onTimeTap,
            child: Text(DateFormat('HH:mm').format(value)),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: personalScheduleColor.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: forestringTextStyle.copyWith(
                color: personalScheduleColor,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              label,
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 12,
              ),
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

DateTime _nextQuarterHour(DateTime value) {
  final discarded = DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
  );
  final remainder = discarded.minute % 15;
  return remainder == 0
      ? discarded.add(const Duration(minutes: 15))
      : discarded.add(Duration(minutes: 15 - remainder));
}

String _rangeText(ManagedTeacherBlockedPeriod period) {
  final sameDate = period.startsAt.year == period.endsAt.year &&
      period.startsAt.month == period.endsAt.month &&
      period.startsAt.day == period.endsAt.day;

  if (sameDate) {
    return '${DateFormat('yyyy.MM.dd').format(period.startsAt)}  '
        '${DateFormat('HH:mm').format(period.startsAt)}~'
        '${DateFormat('HH:mm').format(period.endsAt)}';
  }

  return '${DateFormat('yyyy.MM.dd HH:mm').format(period.startsAt)} ~ '
      '${DateFormat('yyyy.MM.dd HH:mm').format(period.endsAt)}';
}
