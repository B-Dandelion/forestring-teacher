import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../data/student_management_repository.dart';
import '../data/student_regular_schedule_repository.dart';
import 'widgets/regular_schedule_picker_widgets.dart';

class StudentRegularSchedulePage extends StatefulWidget {
  const StudentRegularSchedulePage({
    super.key,
    required this.student,
    this.repository,
  });

  final ManagedStudent student;
  final StudentRegularScheduleRepository? repository;

  @override
  State<StudentRegularSchedulePage> createState() =>
      _StudentRegularSchedulePageState();
}

class _StudentRegularSchedulePageState
    extends State<StudentRegularSchedulePage> {
  late final StudentRegularScheduleRepository _repository;

  List<ManagedRegularSchedule> _schedules = const [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? StudentRegularScheduleRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final schedules = await _repository.fetchSchedules(widget.student.id);
      if (!mounted) return;
      setState(() => _schedules = schedules);
    } on StudentRegularScheduleFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _schedules = const [];
        _errorMessage = error.message;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _edit(ManagedRegularSchedule schedule) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _RegularScheduleEditPage(
          student: widget.student,
          schedule: schedule,
          repository: _repository,
        ),
      ),
    );

    if (!mounted || changed != true) return;
    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('정규 일정이 변경되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _add() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _RegularScheduleAddPage(
          student: widget.student,
          repository: _repository,
        ),
      ),
    );

    if (!mounted || changed != true) return;
    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('정규 일정이 추가되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _end(ManagedRegularSchedule schedule) async {
    DateTime initialDate;
    try {
      final semesters = await _repository.fetchUpcomingSemesters(
        widget.student.branchId,
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      initialDate = semesters.isEmpty ? today : semesters.first.startsOn;
    } on StudentRegularScheduleFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return;
    }

    if (!mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(today) ? today : initialDate,
      firstDate: today,
      lastDate: DateTime(today.year + 3, 12, 31),
      helpText: '정규 일정 종료 적용일',
      cancelText: '취소',
      confirmText: '선택',
    );

    if (picked == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('정규 일정 종료'),
        content: Text(
          '${schedule.weekdayLabel} ${schedule.timeLabel} 일정을 '
          '${DateFormat('yyyy.MM.dd').format(picked)}부터 종료할까요?\n\n'
          '적용일 이후 아직 개별 변경되지 않은 예정 수업만 정리되며, '
          '과거 수업과 취소·재예약 이력은 그대로 유지됩니다.',
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
              foregroundColor: Colors.white,
            ),
            child: const Text('종료'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() => _loading = true);
    try {
      final result = await _repository.endSchedule(
        scheduleSlotId: schedule.slotId,
        effectiveOn: picked,
      );
      await _load();
      if (!mounted) return;

      final canceledCount =
          (result['canceledLessonCount'] as num?)?.toInt() ?? 0;
      final suffix = canceledCount > 0
          ? ' 예정 수업 $canceledCount개도 함께 정리했습니다.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('정규 일정 종료를 저장했습니다.$suffix'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on StudentRegularScheduleFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: AppBar(
        backgroundColor: neutralIvory,
        foregroundColor: primaryColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          '정규 일정 관리',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 19,
            fontWeight: FontWeight.w500,
          ),
        ),
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
            padding: const EdgeInsets.all(16),
            children: [
              _studentHeader(),
              const SizedBox(height: 16),
              if (_errorMessage != null) ...[
                _messageBox(_errorMessage!, isError: true),
                const SizedBox(height: 12),
              ],
              if (_loading && _schedules.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 70),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_schedules.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 50),
                  child: Center(
                    child: Text(
                      '현재 관리할 정규 일정이 없습니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '정규 수업 ${_schedules.length}개',
                        style: forestringTextStyle.copyWith(
                          color: primaryColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _loading ? null : _add,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('추가'),
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...List.generate(
                  _schedules.length,
                  (index) => _scheduleCard(index, _schedules[index]),
                ),
              ],
              if (!_loading && _schedules.isEmpty) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('정규 수업 추가'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _messageBox(
                '정규 수업을 추가하거나 요일·시간·수업 길이를 변경할 수 있습니다. '
                '일정 종료 시 과거 수업과 기존 변경 이력은 유지됩니다.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _studentHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryColor.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.student.displayName,
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 21,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${widget.student.branchName} · '
            '${widget.student.teacherName ?? '담당 선생님 미배정'}',
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleCard(
    int index,
    ManagedRegularSchedule schedule,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _loading ? null : () => _edit(schedule),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.calendar_today_outlined,
                    color: primaryColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${schedule.weekdayLabel} · '
                        '${schedule.timeLabel} · '
                        '${schedule.durationMinutes}분',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          Text(
                            schedule.teacherName,
                            style: forestringTextStyle.copyWith(
                              color: Colors.black45,
                              fontSize: 10.5,
                            ),
                          ),
                          if (schedule.hasFutureVersion)
                            _statusChip(
                              '변경 예정',
                              secondaryColor,
                            ),
                          if (schedule.slotStartsOn.isAfter(today))
                            _statusChip(
                              '시작 예정',
                              secondaryColor,
                            ),
                          if (schedule.slotEndsOn != null &&
                              !schedule.slotEndsOn!.isBefore(today))
                            _statusChip(
                              '종료 예정',
                              Colors.orange.shade800,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '더보기',
                  onSelected: (value) {
                    if (value == 'end') {
                      _end(schedule);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'end',
                      child: Text('정규 일정 종료'),
                    ),
                  ],
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: primaryColor,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: primaryColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(color: color, fontSize: 11),
      ),
    );
  }

  Widget _messageBox(String message, {bool isError = false}) {
    final color = isError ? Colors.redAccent : primaryColor;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
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

class _RegularScheduleAddPage extends StatefulWidget {
  const _RegularScheduleAddPage({
    required this.student,
    required this.repository,
  });

  final ManagedStudent student;
  final StudentRegularScheduleRepository repository;

  @override
  State<_RegularScheduleAddPage> createState() =>
      _RegularScheduleAddPageState();
}

class _RegularScheduleAddPageState extends State<_RegularScheduleAddPage> {
  List<RegularScheduleSemesterOption> _semesters = const [];
  RegularScheduleSemesterOption? _semester;
  RegularScheduleTeacher? _teacher;
  List<TeacherWorkWindow> _workHours = const [];

  int _weekday = 1;
  int _durationMinutes = 30;
  int? _startMinutes;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final semesters = await widget.repository.fetchUpcomingSemesters(
        widget.student.branchId,
        includeCurrent: true,
      );
      if (semesters.isEmpty) {
        throw const StudentRegularScheduleFailure(
          '추가할 수 있는 적용 학기 정보가 없습니다.',
        );
      }

      if (!mounted) return;
      setState(() {
        _semesters = semesters;
        _semester = semesters.first;
      });
      await _loadTeacherContext();
    } on StudentRegularScheduleFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    }
  }

  Future<void> _loadTeacherContext({bool keepCurrentTime = false}) async {
    final semester = _semester;
    if (semester == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final teacher = await widget.repository.fetchTeacherAtDate(
        studentId: widget.student.id,
        date: semester.effectiveOnFor(DateTime.now()),
      );
      final workHours =
          await widget.repository.fetchTeacherWorkHours(teacher.id);

      if (!mounted) return;
      setState(() {
        _teacher = teacher;
        _workHours = workHours;
        _loading = false;
      });
      _ensureValidStart(keepCurrent: keepCurrentTime);
    } on StudentRegularScheduleFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _teacher = null;
        _workHours = const [];
        _loading = false;
        _errorMessage = error.message;
      });
    }
  }

  List<int> get _availableStartMinutes {
    final result = <int>{};
    for (final window in _workHours.where((item) => item.weekday == _weekday)) {
      var minute = ((window.startMinutes + 14) ~/ 15) * 15;
      while (minute + _durationMinutes <= window.endMinutes) {
        result.add(minute);
        minute += 15;
      }
    }
    final list = result.toList()..sort();
    return list;
  }

  void _ensureValidStart({bool keepCurrent = false}) {
    if (!mounted) return;
    final options = _availableStartMinutes;
    final current = _startMinutes;
    setState(() {
      if (options.isEmpty) {
        _startMinutes = null;
      } else if (keepCurrent && current != null && options.contains(current)) {
        _startMinutes = current;
      } else if (current == null || !options.contains(current)) {
        _startMinutes = options.first;
      }
    });
  }

  Future<void> _save() async {
    final semester = _semester;
    final teacher = _teacher;
    final startMinutes = _startMinutes;
    if (semester == null || teacher == null || startMinutes == null) {
      setState(() {
        _errorMessage = '선택한 조건으로 추가할 수 있는 정규 시간이 없습니다.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await widget.repository.addSchedule(
        studentId: widget.student.id,
        teacherId: teacher.id,
        weekday: _weekday,
        startMinutes: startMinutes,
        durationMinutes: _durationMinutes,
        effectiveOn: semester.effectiveOnFor(DateTime.now()),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StudentRegularScheduleFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeOptions = _availableStartMinutes;
    const durationOptions = [15, 30, 45, 60];

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: AppBar(
        backgroundColor: neutralIvory,
        foregroundColor: primaryColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          '정규 수업 추가',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
          children: [
            _addStudentHeader(),
            const SizedBox(height: 12),
            _addSectionCard(
              icon: Icons.calendar_month_rounded,
              title: '적용 학기',
              subtitle: '새 정규 수업을 어느 학기부터 적용할지 선택합니다.',
              child: DropdownButtonFormField<String>(
                initialValue: _semester?.id,
                decoration: _addInputDecoration('학기 선택'),
                items: _semesters
                    .map(
                      (semester) => DropdownMenuItem(
                        value: semester.id,
                        child: Text(
                          semester.isInProgressOn(DateTime.now())
                              ? '${semester.code} · 진행 중'
                              : '${semester.code} · '
                                  '${DateFormat('yyyy.MM.dd').format(semester.startsOn)}부터',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving || _loading
                    ? null
                    : (value) async {
                        if (value == null) return;
                        final selected = _semesters.firstWhere(
                          (item) => item.id == value,
                        );
                        setState(() => _semester = selected);
                        await _loadTeacherContext(
                          keepCurrentTime: true,
                        );
                      },
              ),
            ),
            const SizedBox(height: 12),
            _addSectionCard(
              icon: Icons.event_repeat_rounded,
              title: '수업 일정',
              subtitle: '담당 선생님의 근무시간 안에서 가능한 일정만 선택됩니다.',
              child: Column(
                children: [
                  RegularWeekdaySelector(
                    value: _weekday,
                    enabled: !_saving && !_loading,
                    onChanged: (value) {
                      setState(() => _weekday = value);
                      _ensureValidStart();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: RegularTimeField(
                          value: _startMinutes,
                          enabled: !_saving &&
                              !_loading &&
                              timeOptions.isNotEmpty,
                          onTap: () async {
                            final selected =
                                await showRegularTimePicker(
                              context: context,
                              options: timeOptions,
                              selectedMinutes: _startMinutes,
                            );
                            if (!mounted || selected == null) return;
                            setState(() => _startMinutes = selected);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 128,
                        child: DropdownButtonFormField<int>(
                          initialValue: _durationMinutes,
                          decoration:
                              _addInputDecoration('수업 길이'),
                          items: durationOptions
                              .map(
                                (minutes) => DropdownMenuItem(
                                  value: minutes,
                                  child: Text('$minutes분'),
                                ),
                              )
                              .toList(),
                          onChanged: _saving || _loading
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(
                                    () => _durationMinutes = value,
                                  );
                                  _ensureValidStart(
                                    keepCurrent: true,
                                  );
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _addSectionCard(
              icon: Icons.person_rounded,
              title: '담당 선생님',
              child: _loading
                  ? const LinearProgressIndicator(
                      color: primaryColor,
                    )
                  : Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(
                              alpha: 0.08,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: primaryColor,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _teacher?.displayName ?? '확인 불가',
                            style: forestringTextStyle.copyWith(
                              color: Colors.black87,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (!_loading && timeOptions.isEmpty) ...[
              const SizedBox(height: 12),
              _addMessageBox(
                '선택한 요일에는 담당 선생님의 근무시간이 없거나, '
                '선택한 수업 길이를 배치할 수 없습니다.',
                isError: true,
              ),
            ],
            const SizedBox(height: 12),
            _addMessageBox(
              '진행 중인 학기는 오늘 이후의 남은 회차만 생성합니다. '
              '미래 학기는 학기 시작일부터 새 정규 일정이 적용됩니다.',
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              _addMessageBox(_errorMessage!, isError: true),
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
                    _semester == null ||
                    _teacher == null ||
                    _startMinutes == null
                ? null
                : _save,
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Text(
              _saving ? '추가 중...' : '정규 수업 추가',
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

  Widget _addStudentHeader() {
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: primaryColor,
              size: 27,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.student.displayName,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.student.branchName,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _addSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: primaryColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  InputDecoration _addInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: forestringTextStyle.copyWith(
        color: Colors.black54,
        fontSize: 13,
      ),
      filled: true,
      fillColor: primaryColor.withValues(alpha: 0.045),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(
          color: primaryColor.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _addMessageBox(String message, {bool isError = false}) {
    final color = isError ? Colors.redAccent : primaryColor;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
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

class _RegularScheduleEditPage extends StatefulWidget {
  const _RegularScheduleEditPage({
    required this.student,
    required this.schedule,
    required this.repository,
  });

  final ManagedStudent student;
  final ManagedRegularSchedule schedule;
  final StudentRegularScheduleRepository repository;

  @override
  State<_RegularScheduleEditPage> createState() =>
      _RegularScheduleEditPageState();
}

class _RegularScheduleEditPageState extends State<_RegularScheduleEditPage> {
  late int _weekday;
  late int _durationMinutes;
  int? _startMinutes;
  late DateTime _effectiveOn;

  RegularScheduleTeacher? _teacher;
  List<TeacherWorkWindow> _workHours = const [];
  bool _loadingContext = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstApplicable = widget.schedule.slotStartsOn.isAfter(today)
        ? widget.schedule.slotStartsOn
        : today;
    _effectiveOn = firstApplicable;
    _weekday = widget.schedule.weekday;
    _durationMinutes = widget.schedule.durationMinutes;
    _startMinutes = widget.schedule.startMinutes;
    _loadTeacherContext(keepCurrentTime: true);
  }

  Future<void> _loadTeacherContext({bool keepCurrentTime = false}) async {
    setState(() {
      _loadingContext = true;
      _errorMessage = null;
    });

    try {
      final teacher = await widget.repository.fetchTeacherAtDate(
        studentId: widget.student.id,
        date: _effectiveOn,
      );
      final workHours = await widget.repository.fetchTeacherWorkHours(teacher.id);

      if (!mounted) return;
      setState(() {
        _teacher = teacher;
        _workHours = workHours;
        _loadingContext = false;
      });

      _ensureValidStart(keepCurrent: keepCurrentTime);
    } on StudentRegularScheduleFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _teacher = null;
        _workHours = const [];
        _loadingContext = false;
        _errorMessage = error.message;
      });
    }
  }

  List<int> get _availableStartMinutes {
    final result = <int>{};
    for (final window in _workHours.where((item) => item.weekday == _weekday)) {
      var minute = ((window.startMinutes + 14) ~/ 15) * 15;
      while (minute + _durationMinutes <= window.endMinutes) {
        result.add(minute);
        minute += 15;
      }
    }
    final list = result.toList()..sort();
    return list;
  }

  void _ensureValidStart({bool keepCurrent = false}) {
    if (!mounted) return;
    final options = _availableStartMinutes;
    final current = _startMinutes;
    setState(() {
      if (options.isEmpty) {
        _startMinutes = null;
      } else if (keepCurrent && current != null && options.contains(current)) {
        _startMinutes = current;
      } else if (current == null || !options.contains(current)) {
        _startMinutes = options.first;
      }
    });
  }

  Future<void> _save() async {
    final teacher = _teacher;
    final startMinutes = _startMinutes;
    if (teacher == null || startMinutes == null) {
      setState(() => _errorMessage = '선택한 조건으로 사용할 수 있는 정규 시간이 없습니다.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.repository.changeSchedule(
        scheduleSlotId: widget.schedule.slotId,
        teacherId: teacher.id,
        weekday: _weekday,
        startMinutes: startMinutes,
        durationMinutes: _durationMinutes,
        effectiveOn: _effectiveOn,
      );

      final changed = result['changed'] == true;
      if (!mounted) return;
      if (!changed) {
        setState(() {
          _saving = false;
          _errorMessage = '현재 정규 일정과 동일합니다. 변경할 내용을 선택해주세요.';
        });
        return;
      }

      Navigator.of(context).pop(true);
    } on StudentRegularScheduleFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeOptions = _availableStartMinutes;
    final durationOptions =
        <int>{15, 30, 45, 60, widget.schedule.durationMinutes}
            .where((value) => value <= 60)
            .toList()
          ..sort();

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: AppBar(
        backgroundColor: neutralIvory,
        foregroundColor: primaryColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          '정규 일정 변경',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
          children: [
            _editStudentHeader(),
            const SizedBox(height: 12),
            _editSectionCard(
              icon: Icons.history_rounded,
              title: '현재 일정',
              child: _scheduleSummary(
                weekday: widget.schedule.weekdayLabel,
                time: widget.schedule.timeLabel,
                duration: widget.schedule.durationMinutes,
              ),
            ),
            const SizedBox(height: 12),
            _editSectionCard(
              icon: Icons.edit_calendar_rounded,
              title: '변경할 일정',
              subtitle: '담당 선생님의 근무시간 안에서 가능한 시간만 표시됩니다.',
              child: Column(
                children: [
                  RegularWeekdaySelector(
                    value: _weekday,
                    enabled: !_saving && !_loadingContext,
                    onChanged: (value) {
                      setState(() => _weekday = value);
                      _ensureValidStart();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: RegularTimeField(
                          value: _startMinutes,
                          enabled: !_saving &&
                              !_loadingContext &&
                              timeOptions.isNotEmpty,
                          onTap: () async {
                            final selected =
                                await showRegularTimePicker(
                              context: context,
                              options: timeOptions,
                              selectedMinutes: _startMinutes,
                            );
                            if (!mounted || selected == null) return;
                            setState(() => _startMinutes = selected);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 128,
                        child: DropdownButtonFormField<int>(
                          initialValue:
                              durationOptions.contains(_durationMinutes)
                                  ? _durationMinutes
                                  : null,
                          decoration:
                              _editInputDecoration('수업 길이'),
                          items: durationOptions
                              .map(
                                (minutes) => DropdownMenuItem(
                                  value: minutes,
                                  child: Text('$minutes분'),
                                ),
                              )
                              .toList(),
                          onChanged: _saving || _loadingContext
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(
                                    () => _durationMinutes = value,
                                  );
                                  _ensureValidStart(
                                    keepCurrent: true,
                                  );
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _editSectionCard(
              icon: Icons.date_range_rounded,
              title: '적용할 주',
              subtitle: '선택한 주의 수업부터 변경된 정규 일정이 적용됩니다.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _weekOptions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final week = _weekOptions[index];
                        final selected = _sameDay(
                          week,
                          _startOfWeek(_effectiveOn),
                        );
                        final weekEnd =
                            week.add(const Duration(days: 6));
                        return ChoiceChip(
                          selected: selected,
                          showCheckmark: false,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                          label: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(
                                '${DateFormat('M/d').format(week)} 주',
                                style: forestringTextStyle.copyWith(
                                  color: selected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '~ ${DateFormat('M/d').format(weekEnd)}',
                                style: forestringTextStyle.copyWith(
                                  color: selected
                                      ? Colors.white70
                                      : Colors.black45,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          selectedColor: primaryColor,
                          backgroundColor:
                              primaryColor.withValues(alpha: 0.025),
                          side: BorderSide(
                            color: selected
                                ? primaryColor
                                : primaryColor.withValues(
                                    alpha: 0.14,
                                  ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                          onSelected: _saving
                              ? null
                              : (_) async {
                                  if (selected) return;
                                  final now = DateTime.now();
                                  final today = DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                  );
                                  setState(
                                    () => _effectiveOn =
                                        week.isBefore(today)
                                            ? today
                                            : week,
                                  );
                                  await _loadTeacherContext(
                                    keepCurrentTime: true,
                                  );
                                },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${DateFormat('M월 d일').format(_startOfWeek(_effectiveOn))}이 '
                          '포함된 주부터 적용됩니다.',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _editSectionCard(
              icon: Icons.person_rounded,
              title: '담당 선생님',
              child: _loadingContext
                  ? const LinearProgressIndicator(
                      color: primaryColor,
                    )
                  : Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(
                              alpha: 0.08,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: primaryColor,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _teacher?.displayName ?? '확인 불가',
                            style: forestringTextStyle.copyWith(
                              color: Colors.black87,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (!_loadingContext && timeOptions.isEmpty) ...[
              const SizedBox(height: 12),
              _editMessageBox(
                '선택한 요일에는 담당 선생님의 근무시간이 없거나, '
                '선택한 수업 길이를 배치할 수 없습니다.',
                isError: true,
              ),
            ],
            const SizedBox(height: 12),
            _editMessageBox(
              '적용 주 이후의 예정 수업은 새 일정에 맞춰 자동으로 조정됩니다. '
              '이미 개별 변경하거나 취소한 수업은 그대로 유지됩니다.',
            ),
            if (widget.schedule.hasFutureVersion &&
                widget.schedule.nextVersionDate != null) ...[
              const SizedBox(height: 10),
              _editMessageBox(
                '${DateFormat('yyyy.MM.dd').format(widget.schedule.nextVersionDate!)}부터 '
                '적용될 다른 정규 일정 변경이 이미 예정되어 있습니다.',
                isError: true,
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              _editMessageBox(_errorMessage!, isError: true),
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
                    _loadingContext ||
                    _teacher == null ||
                    _startMinutes == null
                ? null
                : _save,
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Text(
              _saving ? '변경 중...' : '정규 일정 변경',
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

  Widget _editStudentHeader() {
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: primaryColor,
              size: 27,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.student.displayName,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '현재 ${widget.schedule.weekdayLabel} · '
                  '${widget.schedule.timeLabel} · '
                  '${widget.schedule.durationMinutes}분',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleSummary({
    required String weekday,
    required String time,
    required int duration,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.event_repeat_rounded,
            color: primaryColor,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$weekday · $time · $duration분',
              style: forestringTextStyle.copyWith(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _editInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: forestringTextStyle.copyWith(
        color: Colors.black54,
        fontSize: 13,
      ),
      filled: true,
      fillColor: primaryColor.withValues(alpha: 0.045),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(
          color: primaryColor.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  List<DateTime> get _weekOptions {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = widget.schedule.slotStartsOn.isAfter(today)
        ? widget.schedule.slotStartsOn
        : today;
    final firstWeek = _startOfWeek(firstDate);

    final defaultLast = firstWeek.add(const Duration(days: 7 * 11));
    final slotEnd = widget.schedule.slotEndsOn;
    final lastDate =
        slotEnd != null && slotEnd.isBefore(defaultLast)
            ? slotEnd
            : defaultLast;
    final lastWeek = _startOfWeek(lastDate);

    final result = <DateTime>[];
    var cursor = firstWeek;
    while (!cursor.isAfter(lastWeek) && result.length < 12) {
      result.add(cursor);
      cursor = cursor.add(const Duration(days: 7));
    }
    return result;
  }

  DateTime _startOfWeek(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    return date.subtract(
      Duration(days: date.weekday - DateTime.monday),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  Widget _editSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: primaryColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _editMessageBox(String message, {bool isError = false}) {
    final color = isError ? Colors.redAccent : primaryColor;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
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
