import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../data/student_management_repository.dart';
import '../data/student_regular_schedule_repository.dart';

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
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
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
    const durationOptions = [15, 30, 45, 60, 75, 90];

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: const ForestringAppBar(title: '정규 수업 추가'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
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
              '진행 중인 학기는 오늘부터, 미래 학기는 학기 시작일부터 적용됩니다.',
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _semester?.id,
              decoration: const InputDecoration(
                labelText: '적용 학기',
                border: OutlineInputBorder(),
              ),
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
                      await _loadTeacherContext(keepCurrentTime: true);
                    },
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '담당 선생님',
                border: OutlineInputBorder(),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      child: LinearProgressIndicator(),
                    )
                  : Text(_teacher?.displayName ?? '확인 불가'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _weekday,
              decoration: const InputDecoration(
                labelText: '요일',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('월요일')),
                DropdownMenuItem(value: 2, child: Text('화요일')),
                DropdownMenuItem(value: 3, child: Text('수요일')),
                DropdownMenuItem(value: 4, child: Text('목요일')),
                DropdownMenuItem(value: 5, child: Text('금요일')),
                DropdownMenuItem(value: 6, child: Text('토요일')),
                DropdownMenuItem(value: 7, child: Text('일요일')),
              ],
              onChanged: _saving || _loading
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _weekday = value);
                      _ensureValidStart();
                    },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _durationMinutes,
              decoration: const InputDecoration(
                labelText: '수업 길이',
                border: OutlineInputBorder(),
              ),
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
                      setState(() => _durationMinutes = value);
                      _ensureValidStart(keepCurrent: true);
                    },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _startMinutes != null &&
                      timeOptions.contains(_startMinutes)
                  ? _startMinutes
                  : null,
              decoration: const InputDecoration(
                labelText: '시작 시간',
                border: OutlineInputBorder(),
              ),
              items: timeOptions
                  .map(
                    (minutes) => DropdownMenuItem(
                      value: minutes,
                      child: Text(_formatMinutes(minutes)),
                    ),
                  )
                  .toList(),
              onChanged: _saving || _loading || timeOptions.isEmpty
                  ? null
                  : (value) => setState(() => _startMinutes = value),
            ),
            if (!_loading && timeOptions.isEmpty) ...[
              const SizedBox(height: 8),
              _addMessageBox(
                '선택한 요일에는 담당 선생님의 근무시간이 없거나, '
                '선택한 수업 길이를 배치할 수 없습니다.',
                isError: true,
              ),
            ],
            const SizedBox(height: 14),
            _addMessageBox(
              '진행 중인 학기는 이미 지난 수업을 만들지 않고 남은 회차만 생성합니다. '
              '다음 학기부터는 기존 정규 일정 기준으로 수업권 4개와 예정 수업이 생성됩니다.',
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              _addMessageBox(_errorMessage!, isError: true),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ||
                      _loading ||
                      _semester == null ||
                      _teacher == null ||
                      _startMinutes == null
                  ? null
                  : _save,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_saving ? '추가 중...' : '정규 수업 추가'),
            ),
          ],
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

  String _formatMinutes(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
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
      appBar: const ForestringAppBar(title: '정규 일정 변경'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
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
              '현재 ${widget.schedule.weekdayLabel} '
              '${widget.schedule.timeLabel} · ${widget.schedule.durationMinutes}분',
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 18),
            _editSectionCard(
              title: '현재 일정',
              child: Text(
                '${widget.schedule.weekdayLabel} · '
                '${widget.schedule.timeLabel} · '
                '${widget.schedule.durationMinutes}분',
                style: forestringTextStyle.copyWith(
                  color: Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _editSectionCard(
              title: '변경할 일정',
              child: Column(
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _weekday,
                    decoration: const InputDecoration(
                      labelText: '요일',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('월요일')),
                      DropdownMenuItem(value: 2, child: Text('화요일')),
                      DropdownMenuItem(value: 3, child: Text('수요일')),
                      DropdownMenuItem(value: 4, child: Text('목요일')),
                      DropdownMenuItem(value: 5, child: Text('금요일')),
                      DropdownMenuItem(value: 6, child: Text('토요일')),
                      DropdownMenuItem(value: 7, child: Text('일요일')),
                    ],
                    onChanged: _saving || _loadingContext
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _weekday = value);
                            _ensureValidStart();
                          },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue:
                        durationOptions.contains(_durationMinutes)
                            ? _durationMinutes
                            : null,
                    decoration: const InputDecoration(
                      labelText: '수업 길이',
                      border: OutlineInputBorder(),
                    ),
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
                            setState(() => _durationMinutes = value);
                            _ensureValidStart(keepCurrent: true);
                          },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: _startMinutes != null &&
                            timeOptions.contains(_startMinutes)
                        ? _startMinutes
                        : null,
                    decoration: const InputDecoration(
                      labelText: '시작 시간',
                      border: OutlineInputBorder(),
                    ),
                    items: timeOptions
                        .map(
                          (minutes) => DropdownMenuItem(
                            value: minutes,
                            child: Text(_formatMinutes(minutes)),
                          ),
                        )
                        .toList(),
                    onChanged: _saving ||
                            _loadingContext ||
                            timeOptions.isEmpty
                        ? null
                        : (value) =>
                            setState(() => _startMinutes = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _editSectionCard(
              title: '적용할 주차',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 58,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _weekOptions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 7),
                      itemBuilder: (context, index) {
                        final week = _weekOptions[index];
                        final selected =
                            _sameDay(
                              week,
                              _startOfWeek(_effectiveOn),
                            );
                        return ChoiceChip(
                          selected: selected,
                          showCheckmark: false,
                          label: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('M/d').format(week),
                                style:
                                    forestringTextStyle.copyWith(
                                  color: selected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${index + 1}주차',
                                style:
                                    forestringTextStyle.copyWith(
                                  color: selected
                                      ? Colors.white70
                                      : Colors.black45,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                          selectedColor: primaryColor,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: selected
                                ? primaryColor
                                : primaryColor.withValues(
                                    alpha: 0.12,
                                  ),
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
                  const SizedBox(height: 8),
                  Text(
                    '${DateFormat('M월 d일').format(_effectiveOn)}이 '
                    '포함된 주부터 새 일정이 적용됩니다.',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _editSectionCard(
              title: '적용 주차 담당 선생님',
              child: _loadingContext
                  ? const LinearProgressIndicator()
                  : Text(
                      _teacher?.displayName ?? '확인 불가',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            if (!_loadingContext && timeOptions.isEmpty) ...[
              const SizedBox(height: 8),
              _editMessageBox(
                '선택한 요일에는 담당 선생님의 근무시간이 없거나, '
                '선택한 수업 길이를 배치할 수 없습니다.',
                isError: true,
              ),
            ],
            const SizedBox(height: 14),
            _editMessageBox(
              '정규 수업의 요일·시간을 변경할 때는 기존 시간표 수업을 먼저 취소하지 마세요. '
              '정규 일정만 변경하면 적용일 이후의 예정 수업이 새 일정에 맞춰 자동으로 조정됩니다. '
              '이미 개별 변경하거나 취소한 수업은 그대로 유지됩니다.',
            ),
            if (widget.schedule.hasFutureVersion &&
                widget.schedule.nextVersionDate != null) ...[
              const SizedBox(height: 10),
              _editMessageBox(
                '${DateFormat('yyyy.MM.dd').format(widget.schedule.nextVersionDate!)}부터 '
                '적용될 다른 정규 일정 변경이 이미 예정되어 있습니다. '
                '적용일에 따라 서버에서 중복 변경을 막을 수 있습니다.',
                isError: true,
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              _editMessageBox(_errorMessage!, isError: true),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ||
                      _loadingContext ||
                      _teacher == null ||
                      _startMinutes == null
                  ? null
                  : _save,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_saving ? '변경 중...' : '정규 일정 변경'),
            ),
          ],
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
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 9),
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

  String _formatMinutes(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
