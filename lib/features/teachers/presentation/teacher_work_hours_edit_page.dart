import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../data/teacher_repository.dart';
import '../data/teacher_work_hours_schedule_repository.dart';
import 'teacher_work_hours_editor.dart';

class TeacherWorkHoursEditPage extends StatefulWidget {
  const TeacherWorkHoursEditPage({
    super.key,
    required this.teacher,
    this.title = '근무시간 변경',
    this.allowEmpty = true,
    this.repository,
  });

  final ManagedTeacher teacher;
  final String title;
  final bool allowEmpty;
  final TeacherWorkHoursScheduleRepository? repository;

  @override
  State<TeacherWorkHoursEditPage> createState() =>
      _TeacherWorkHoursEditPageState();
}

class _TeacherWorkHoursEditPageState extends State<TeacherWorkHoursEditPage> {
  late final TeacherWorkHoursScheduleRepository _repository;

  late List<TeacherWorkHourDraft> _workHours;
  late List<ManagedTeacherWorkHour> _loadedWorkHours;
  late DateTime _effectiveOn;
  bool _loadingHours = false;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? TeacherWorkHoursScheduleRepository();
    final now = DateTime.now();
    _effectiveOn = DateTime(now.year, now.month, now.day);
    _loadedWorkHours = List.of(widget.teacher.workHours);
    _workHours = _draftsFromManaged(_loadedWorkHours);
  }

  Future<void> _pickEffectiveOn() async {
    if (_saving || _loadingHours) return;

    if (!_draftMatchesLoaded()) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('작성 중인 변경사항'),
          content: const Text(
            '적용 시작일을 바꾸면 아직 저장하지 않은 근무시간 변경사항이 사라집니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('계속 수정'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('날짜 변경'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveOn.isBefore(today) ? today : _effectiveOn,
      firstDate: today,
      lastDate: DateTime(today.year + 3, 12, 31),
      helpText: '근무시간 적용 시작일',
      cancelText: '취소',
      confirmText: '선택',
    );

    if (picked == null || !mounted) return;
    final normalized = DateTime(picked.year, picked.month, picked.day);
    if (_sameDate(normalized, _effectiveOn)) return;

    setState(() {
      _loadingHours = true;
      _errorMessage = null;
    });

    try {
      final hours = await _repository.fetchForDate(
        teacherId: widget.teacher.id,
        onDate: normalized,
      );
      if (!mounted) return;
      setState(() {
        _effectiveOn = normalized;
        _loadedWorkHours = List.of(hours);
        _workHours = _draftsFromManaged(hours);
      });
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _loadingHours = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _loadingHours) return;

    final validationMessage = validateTeacherWorkHours(
      _workHours,
      allowEmpty: widget.allowEmpty,
    );
    if (validationMessage != null) {
      setState(() => _errorMessage = validationMessage);
      return;
    }

    if (widget.allowEmpty &&
        _workHours.isEmpty &&
        _loadedWorkHours.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('근무시간 전체 삭제'),
          content: Text(
            '${_formatDate(_effectiveOn)}부터 등록된 근무시간을 모두 없애면 '
            '해당 날짜 이후 새로운 수업 예약 가능 시간이 없어집니다. '
            '이미 등록된 수업은 유지됩니다. 계속하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('전체 삭제'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final changed = await _repository.replace(
        teacherId: widget.teacher.id,
        effectiveOn: _effectiveOn,
        workHours: _workHours
            .map((workHour) => workHour.toInput())
            .toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context).pop(changed);
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _saving || _loadingHours;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(title: widget.title),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.teacher.displayName,
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.teacher.branchName,
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 18),
            _effectiveDateCard(disabled),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '선택한 적용 시작일부터 새 근무시간이 예약 가능 시간 계산에 사용됩니다. '
                '그 이전 날짜의 근무시간과 이미 등록된 수업은 유지됩니다.',
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 13,
                ),
              ),
            ),
            if (_loadingHours) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _errorCard(_errorMessage!),
            ],
            const SizedBox(height: 16),
            TeacherWorkHoursEditor(
              values: _workHours,
              enabled: !disabled,
              allowEmpty: widget.allowEmpty,
              onChanged: (values) {
                setState(() {
                  _workHours = values;
                  _errorMessage = null;
                });
              },
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: disabled ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_saving ? '저장 중...' : '근무시간 저장'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _effectiveDateCard(bool disabled) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: disabled ? null : _pickEffectiveOn,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_outlined, color: primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '적용 시작일',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(_effectiveOn),
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
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

  List<TeacherWorkHourDraft> _draftsFromManaged(
    List<ManagedTeacherWorkHour> hours,
  ) {
    return hours
        .map(TeacherWorkHourDraft.fromManaged)
        .toList(growable: false);
  }

  bool _draftMatchesLoaded() {
    final draft = _workHours
        .map((item) => item.toInput())
        .map((item) => '${item.weekday}|${item.startTime}|${item.endTime}')
        .toList()
      ..sort();
    final loaded = _loadedWorkHours
        .map((item) => '${item.weekday}|${item.startTime}|${item.endTime}')
        .toList()
      ..sort();

    if (draft.length != loaded.length) return false;
    for (var index = 0; index < draft.length; index += 1) {
      if (draft[index] != loaded[index]) return false;
    }
    return true;
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDate(DateTime value) {
    return '${value.year}년 ${value.month}월 ${value.day}일';
  }
}
