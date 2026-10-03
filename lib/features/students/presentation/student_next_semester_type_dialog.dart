import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../data/student_management_repository.dart';
import '../data/student_next_semester_type_repository.dart';
import 'widgets/regular_schedule_picker_widgets.dart';

Future<bool?> showStudentNextSemesterTypeDialog({
  required BuildContext context,
  required ManagedStudent student,
  StudentNextSemesterTypeRepository? repository,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => StudentNextSemesterTypePage(
        student: student,
        repository: repository,
      ),
    ),
  );
}

class StudentNextSemesterTypePage extends StatefulWidget {
  const StudentNextSemesterTypePage({
    super.key,
    required this.student,
    this.repository,
  });

  final ManagedStudent student;
  final StudentNextSemesterTypeRepository? repository;

  @override
  State<StudentNextSemesterTypePage> createState() =>
      _StudentNextSemesterTypePageState();
}

class _StudentNextSemesterTypePageState
    extends State<StudentNextSemesterTypePage> {
  late final StudentNextSemesterTypeRepository _repository;
  final _rightCountController = TextEditingController();

  NextSemesterStudentTypePlan? _plan;
  List<NextSemesterTeacherWorkWindow> _workHours = const [];
  final List<_NextRegularScheduleDraft> _regularSchedules = [];

  String _targetType = 'regular';
  int _flexDurationMinutes = 30;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? StudentNextSemesterTypeRepository();
    _load();
  }

  @override
  void dispose() {
    _rightCountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final plan = await _repository.fetchPlan(widget.student.id);
      if (!mounted) return;

      _targetType = plan.plannedStudentType;
      final count = plan.flexBaseRightCount ?? plan.defaultFlexBaseRightCount;
      _rightCountController.text = count.toString();
      _flexDurationMinutes =
          plan.flexDurationMinutes ?? plan.defaultFlexDurationMinutes;

      setState(() => _plan = plan);
      await _loadWorkHoursIfNeeded(plan);
    } on StudentNextSemesterTypeFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadWorkHoursIfNeeded(
    NextSemesterStudentTypePlan plan,
  ) async {
    if (plan.regularScheduleCount > 0 || plan.teacherId == null) {
      if (mounted) {
        setState(() => _workHours = const []);
      }
      return;
    }

    try {
      final workHours = await _repository.fetchTeacherWorkHours(
        teacherId: plan.teacherId!,
        onDate: plan.nextSemesterStartsOn,
      );
      if (!mounted) return;

      setState(() {
        _workHours = workHours;
        if (_regularSchedules.isEmpty && workHours.isNotEmpty) {
          final first = workHours.first;
          final availableMinutes = first.endMinutes - first.startMinutes;
          final duration = availableMinutes >= 30 ? 30 : 15;
          _regularSchedules.add(
            _NextRegularScheduleDraft(
              weekday: first.weekday,
              startMinutes: first.startMinutes,
              durationMinutes: duration,
            ),
          );
        }
      });
    } on StudentNextSemesterTypeFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    }
  }

  Future<void> _changeTarget(String value) async {
    if (_saving || value == _targetType) return;
    setState(() {
      _targetType = value;
      _errorMessage = null;
    });

    final plan = _plan;
    if (plan != null && value == 'regular') {
      await _loadWorkHoursIfNeeded(plan);
    }
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null || _saving || !plan.canChange) return;

    int? flexCount;
    if (_targetType == 'flex') {
      flexCount = int.tryParse(_rightCountController.text.trim());
      if (flexCount == null || flexCount <= 0) {
        setState(() => _errorMessage = '수업권 개수를 1개 이상 입력해주세요.');
        return;
      }
    }

    List<Map<String, dynamic>>? regularSchedules;
    if (_targetType == 'regular' && plan.regularScheduleCount == 0) {
      if (plan.teacherId == null || !plan.teacherAssignmentCoversSemester) {
        setState(() {
          _errorMessage = '다음 학기 전체 기간의 담당 선생님을 먼저 지정해주세요.';
        });
        return;
      }
      if (_regularSchedules.isEmpty) {
        setState(() => _errorMessage = '정규 수업 일정을 한 개 이상 추가해주세요.');
        return;
      }
      if (_regularSchedules.any((draft) => draft.startMinutes % 15 != 0)) {
        setState(() => _errorMessage = '정규 수업 시작 시간은 15분 단위로 선택해주세요.');
        return;
      }

      final signatures = <String>{};
      for (final draft in _regularSchedules) {
        if (!signatures.add(draft.signature)) {
          setState(() => _errorMessage = '같은 정규 수업 일정이 중복되어 있습니다.');
          return;
        }
      }

      regularSchedules = _regularSchedules
          .map((draft) => draft.toJson())
          .toList(growable: false);
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await _repository.save(
        studentId: widget.student.id,
        targetType: _targetType,
        flexBaseRightCount: flexCount,
        flexDurationMinutes:
            _targetType == 'flex' ? _flexDurationMinutes : null,
        regularSchedules: regularSchedules,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StudentNextSemesterTypeFailure catch (error) {
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
    final plan = _plan;

    return Scaffold(
      backgroundColor: primaryColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          '다음 학기 수강 형태',
          style: forestringTextStyle.copyWith(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: neutralIvory,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: primaryColor,
                  ),
                )
              : plan == null
                  ? ListView(
                      padding:
                          const EdgeInsets.fromLTRB(14, 16, 14, 24),
                      children: [_buildLoadFailure()],
                    )
                  : ListView(
                      padding:
                          const EdgeInsets.fromLTRB(14, 16, 14, 110),
                      children: [
                        _studentHeader(),
                        const SizedBox(height: 12),
                        _semesterCard(plan),
                        if (!plan.canChange) ...[
                          const SizedBox(height: 12),
                          _warningCard(
                            '다음 학기 시작 전이며 퇴원 일정과 겹치지 않을 때만 '
                            '수강 형태를 변경할 수 있습니다.',
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          _errorCard(_errorMessage!),
                        ],
                        const SizedBox(height: 12),
                        _settingsCard(plan),
                      ],
                    ),
        ),
      ),
      bottomNavigationBar: plan == null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                color: neutralIvory,
                padding:
                    const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: FilledButton(
                  onPressed:
                      _saving || !plan.canChange ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    _saving ? '저장 중...' : '다음 학기에 적용',
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

  Widget _studentHeader() {
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
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: primaryColor,
              size: 28,
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

  Widget _settingsCard(NextSemesterStudentTypePlan plan) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Text(
            '다음 학기 수강 형태',
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '현재 학기에는 영향이 없고 다음 학기 시작일부터 적용됩니다.',
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _typeChoiceCard(
                  value: 'regular',
                  icon: Icons.event_repeat_rounded,
                  title: '정규',
                  description: '정해진 일정',
                  enabled: plan.canChange,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _typeChoiceCard(
                  value: 'flex',
                  icon: Icons.confirmation_number_rounded,
                  title: '자율 예약',
                  description: '수업권 예약',
                  enabled: plan.canChange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_targetType == 'flex')
            _buildFlexSettings(plan)
          else
            _buildRegularSettings(plan),
        ],
      ),
    );
  }

  Widget _buildLoadFailure() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '다음 학기 수강 형태',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 23,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),
        _errorCard(_errorMessage ?? '정보를 불러오지 못했습니다.'),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _load,
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text(
            '다시 시도',
            style: TextStyle(color: Colors.white),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('닫기'),
        ),
      ],
    );
  }

  Widget _semesterCard(NextSemesterStudentTypePlan plan) {
    final dateFormat = DateFormat('yyyy.MM.dd');

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xffFFF6EC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xffB36A2E).withValues(alpha: 0.12),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xffF8E9D8),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Color(0xffB36A2E),
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.nextSemesterCode} 학기',
                  style: forestringTextStyle.copyWith(
                    color: const Color(0xff9B5A24),
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${dateFormat.format(plan.nextSemesterStartsOn)} ~ '
                  '${dateFormat.format(plan.nextSemesterEndsOn)}',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${plan.currentTypeLabel} → ${plan.plannedTypeLabel}',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChoiceCard({
    required String value,
    required IconData icon,
    required String title,
    required String description,
    required bool enabled,
  }) {
    final selected = _targetType == value;
    return Material(
      color: selected ? primaryColor.withValues(alpha: 0.07) : Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: !enabled || _saving ? null : () => _changeTarget(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? primaryColor
                  : primaryColor.withValues(alpha: 0.16),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? primaryColor
                      : primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  selected ? Icons.check_rounded : icon,
                  color: selected ? Colors.white : primaryColor,
                  size: 23,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black87,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
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
        ),
      ),
    );
  }

  Widget _buildFlexSettings(NextSemesterStudentTypePlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xff4B7892).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.confirmation_number_rounded,
                color: Color(0xff4B7892),
                size: 19,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              '자율 예약 설정',
              style: forestringTextStyle.copyWith(
                color: const Color(0xff4B7892),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _rightCountController,
                enabled: !_saving && plan.canChange,
                decoration:
                    _decoration('학기 수업권').copyWith(suffixText: '개'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 128,
              child: DropdownButtonFormField<int>(
                initialValue: _flexDurationMinutes,
                decoration: _decoration('수업 길이'),
                items: _durationItems(),
                onChanged: _saving || !plan.canChange
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(
                            () => _flexDurationMinutes = value,
                          );
                        }
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _infoCard(
          '다음 학기에는 정규 시간표 없이 수업권으로 예약합니다. '
          '수업권 개수와 수업 길이는 다음 학기 시작일부터 적용됩니다.',
        ),
      ],
    );
  }

  Widget _buildRegularSettings(NextSemesterStudentTypePlan plan) {
    if (plan.regularScheduleCount > 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('정규 수업 설정'),
          const SizedBox(height: 10),
          _infoCard(
            '등록된 정규 일정 ${plan.regularScheduleCount}개를 다음 학기에도 사용합니다. 자세한 일정은 정규 일정 관리에서 확인할 수 있습니다.',
          ),
        ],
      );
    }

    if (plan.teacherId == null || !plan.teacherAssignmentCoversSemester) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('정규 수업 설정'),
          const SizedBox(height: 10),
          _warningCard(
            '정규 학생으로 전환하려면 다음 학기 전체 기간의 담당 선생님이 먼저 지정되어 있어야 합니다. '
            '담당 선생님 변경에서 ${DateFormat('yyyy.MM.dd').format(plan.nextSemesterStartsOn)}부터 적용되도록 설정해주세요.',
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('정규 수업 설정'),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.person_rounded,
                color: primaryColor,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                plan.teacherName ?? '담당 선생님 확인 필요',
                style: forestringTextStyle.copyWith(
                  color: Colors.black87,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_workHours.isNotEmpty) ...[
          const SizedBox(height: 9),
          _infoCard('다음 학기 시작일 기준 근무시간\n${_workHoursLabel()}'),
        ],
        const SizedBox(height: 12),
        ...List.generate(
          _regularSchedules.length,
          (index) => _regularScheduleCard(index, plan),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            side: BorderSide(
              color: primaryColor.withValues(alpha: 0.20),
            ),
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          onPressed: _saving || !plan.canChange
              ? null
              : () {
                  final first = _workHours.isEmpty ? null : _workHours.first;
                  setState(() {
                    _regularSchedules.add(
                      _NextRegularScheduleDraft(
                        weekday: first?.weekday ?? 1,
                        startMinutes: first?.startMinutes ?? 600,
                        durationMinutes: 30,
                      ),
                    );
                  });
                },
          icon: const Icon(Icons.add_rounded),
          label: const Text('정규 수업 추가'),
        ),
      ],
    );
  }

  Widget _regularScheduleCard(
    int index,
    NextSemesterStudentTypePlan plan,
  ) {
    final draft = _regularSchedules[index];
    final timeOptions = _availableStartMinutesForDraft(draft);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.028),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '정규 수업 ${index + 1}',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_regularSchedules.length > 1)
                IconButton(
                  tooltip: '삭제',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving || !plan.canChange
                      ? null
                      : () => setState(
                            () => _regularSchedules.removeAt(index),
                          ),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          RegularWeekdaySelector(
            value: draft.weekday,
            enabled: !_saving && plan.canChange,
            onChanged: (value) {
              setState(() {
                draft.weekday = value;
                _ensureDraftTime(draft);
              });
            },
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: RegularTimeField(
                  value: timeOptions.contains(draft.startMinutes)
                      ? draft.startMinutes
                      : null,
                  enabled: !_saving &&
                      plan.canChange &&
                      timeOptions.isNotEmpty,
                  onTap: () async {
                    final selected = await showRegularTimePicker(
                      context: context,
                      options: timeOptions,
                      selectedMinutes: draft.startMinutes,
                    );
                    if (!mounted || selected == null) return;
                    setState(() => draft.startMinutes = selected);
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 128,
                child: DropdownButtonFormField<int>(
                  initialValue: draft.durationMinutes,
                  decoration: _decoration('수업 길이'),
                  items: _durationItems(),
                  onChanged: _saving || !plan.canChange
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            draft.durationMinutes = value;
                            _ensureDraftTime(draft);
                          });
                        },
                ),
              ),
            ],
          ),
          if (timeOptions.isEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '이 요일에는 선택한 수업 길이로 가능한 근무시간이 없습니다.',
                style: forestringTextStyle.copyWith(
                  color: Colors.redAccent,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<int> _availableStartMinutesForDraft(
    _NextRegularScheduleDraft draft,
  ) {
    final result = <int>{};
    for (final window in _workHours.where(
      (item) => item.weekday == draft.weekday,
    )) {
      var minute = ((window.startMinutes + 14) ~/ 15) * 15;
      while (minute + draft.durationMinutes <= window.endMinutes) {
        result.add(minute);
        minute += 15;
      }
    }
    final list = result.toList()..sort();
    return list;
  }

  void _ensureDraftTime(_NextRegularScheduleDraft draft) {
    final options = _availableStartMinutesForDraft(draft);
    if (options.isEmpty) return;
    if (!options.contains(draft.startMinutes)) {
      draft.startMinutes = options.first;
    }
  }

  List<DropdownMenuItem<int>> _durationItems() {
    return const [15, 30, 45, 60]
        .map(
          (minutes) => DropdownMenuItem(
            value: minutes,
            child: Text('$minutes분'),
          ),
        )
        .toList();
  }

  String _workHoursLabel() {
    return _workHours
        .map(
          (window) =>
              '${_weekdayLabel(window.weekday)} '
              '${regularFormatMinutes(window.startMinutes)}~${regularFormatMinutes(window.endMinutes)}',
        )
        .join(' · ');
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
      _ => '요일 확인 필요',
    };
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: forestringTextStyle.copyWith(
        color: primaryColor,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: forestringTextStyle.copyWith(
        color: Colors.black54,
        fontSize: 12,
      ),
      isDense: true,
      filled: true,
      fillColor: primaryColor.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
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
          color: primaryColor.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _infoCard(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withValues(alpha: 0.13)),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: Colors.black87,
          fontSize: 14,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _warningCard(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: forestringTextStyle.copyWith(
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.22)),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: Colors.redAccent,
          fontSize: 14,
          height: 1.45,
        ),
      ),
    );
  }
}

class _NextRegularScheduleDraft {
  _NextRegularScheduleDraft({
    required this.weekday,
    required this.startMinutes,
    required this.durationMinutes,
  });

  int weekday;
  int startMinutes;
  int durationMinutes;

  String get signature => '$weekday|$startMinutes|$durationMinutes';

  Map<String, dynamic> toJson() {
    final hour = (startMinutes ~/ 60).toString().padLeft(2, '0');
    final minute = (startMinutes % 60).toString().padLeft(2, '0');
    return {
      'weekday': weekday,
      'startTime': '$hour:$minute',
      'durationMinutes': durationMinutes,
    };
  }
}
