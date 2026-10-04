import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../../core/widgets/registration_form.dart';
import '../../auth/domain/current_profile.dart';
import '../../branches/domain/academy_branch.dart';
import '../../semesters/domain/managed_semester.dart';
import '../data/lesson_repository.dart';
import '../domain/lesson.dart';
import 'widgets/lesson_time_slot_picker.dart';
import 'widgets/student_search_picker.dart';

class MakeupLessonCreatePage extends StatefulWidget {
  const MakeupLessonCreatePage({
    super.key,
    required this.profile,
    required this.semester,
    required this.branches,
    required this.students,
    required this.teachers,
    this.initialBranchId,
    this.initialStudentId,
    this.initialDate,
    this.repository,
  });

  final CurrentProfile profile;
  final ManagedSemester semester;
  final List<AcademyBranch> branches;
  final List<VisibleStudent> students;
  final List<VisibleTeacher> teachers;
  final String? initialBranchId;
  final String? initialStudentId;
  final DateTime? initialDate;
  final LessonRepository? repository;

  @override
  State<MakeupLessonCreatePage> createState() =>
      _MakeupLessonCreatePageState();
}

class _MakeupLessonCreatePageState extends State<MakeupLessonCreatePage> {
  late final LessonRepository _repository;

  String? _branchId;
  String? _studentId;
  String? _teacherId;
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  int _durationMinutes = 30;
  String _reason = '';
  bool _deductLessonRight = false;
  int? _availableRightCount;
  bool _loadingRightCount = false;
  int _rightLoadToken = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? LessonRepository();

    final requestedBranch = widget.profile.isManager
        ? widget.profile.branchId
        : widget.initialBranchId;
    if (requestedBranch != null &&
        widget.branches.any((branch) => branch.id == requestedBranch)) {
      _branchId = requestedBranch;
    } else if (widget.branches.isNotEmpty) {
      _branchId = widget.branches.first.id;
    }

    final requestedDate = _dateOnly(
      widget.initialDate ?? DateTime.now().add(const Duration(days: 1)),
    );
    _date = _clampToSemester(requestedDate);

    final requestedStudent = widget.initialStudentId;
    if (requestedStudent != null &&
        _availableStudents.any((student) => student.id == requestedStudent)) {
      _studentId = requestedStudent;
    }

    final teachers = _availableTeachers;
    if (teachers.length == 1) {
      _teacherId = teachers.first.id;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshAvailableRightCount();
    });
  }

  DateTime get _scopeStart {
    final branchId = _branchId;
    return branchId == null
        ? widget.semester.startsOn
        : widget.semester.effectiveStart(branchId);
  }

  DateTime get _scopeEnd {
    final branchId = _branchId;
    return branchId == null
        ? widget.semester.endsOn
        : widget.semester.effectiveEnd(branchId);
  }

  List<VisibleStudent> get _availableStudents {
    final branchId = _branchId;
    return widget.students
        .where(
          (student) =>
              student.isActive &&
              branchId != null &&
              student.branchId == branchId,
        )
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  List<VisibleTeacher> get _availableTeachers {
    final branchId = _branchId;
    return widget.teachers
        .where(
          (teacher) => branchId != null && teacher.branchId == branchId,
        )
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  AcademyBranch? get _selectedBranch {
    final id = _branchId;
    if (id == null) return null;
    for (final branch in widget.branches) {
      if (branch.id == id) return branch;
    }
    return null;
  }

  DateTime _clampToSemester(DateTime value) {
    final start = _scopeStart;
    final end = _scopeEnd;
    if (value.isBefore(start)) return start;
    if (value.isAfter(end)) return end;
    return value;
  }

  void _changeBranch(String? value) {
    if (value == null || value == _branchId) return;
    setState(() {
      _branchId = value;
      _date = _clampToSemester(_date);
      _studentId = null;
      _teacherId = null;
      _deductLessonRight = false;
      _availableRightCount = null;
      final teachers = _availableTeachers;
      if (teachers.length == 1) {
        _teacherId = teachers.first.id;
      }
    });
  }

  void _selectStudent(String? value) {
    setState(() {
      _studentId = value;
      _deductLessonRight = false;
      _availableRightCount = null;
    });
    _refreshAvailableRightCount();
  }

  Future<void> _refreshAvailableRightCount() async {
    final studentId = _studentId;
    final token = ++_rightLoadToken;

    if (studentId == null) {
      if (mounted) {
        setState(() {
          _availableRightCount = null;
          _loadingRightCount = false;
          _deductLessonRight = false;
        });
      }
      return;
    }

    setState(() => _loadingRightCount = true);
    try {
      final count = await _repository.fetchAvailableLessonRightCount(
        studentId: studentId,
        semesterId: widget.semester.id,
        durationMinutes: _durationMinutes,
      );
      if (!mounted || token != _rightLoadToken) return;
      setState(() {
        _availableRightCount = count;
        _loadingRightCount = false;
        if (count == 0) _deductLessonRight = false;
      });
    } on LessonFailure {
      if (!mounted || token != _rightLoadToken) return;
      setState(() {
        _availableRightCount = null;
        _loadingRightCount = false;
        _deductLessonRight = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final today = _dateOnly(DateTime.now());
    final firstDate = today.isAfter(_scopeStart) ? today : _scopeStart;
    if (firstDate.isAfter(_scopeEnd)) {
      _message('선택한 학기는 이미 종료되었습니다.');
      return;
    }

    final initialDate = _date.isBefore(firstDate) ? firstDate : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: _scopeEnd,
      helpText: '추가 수업 날짜',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (picked != null && mounted) {
      setState(() => _date = _dateOnly(picked));
    }
  }

  Future<void> _pickTime() async {
    final studentId = _studentId;
    final teacherId = _teacherId;
    if (studentId == null || teacherId == null) {
      _message('학생과 수업 담당자를 먼저 선택해주세요.');
      return;
    }

    final picked = await showMakeupLessonTimeSlotPicker(
      context: context,
      repository: _repository,
      teacherId: teacherId,
      studentId: studentId,
      selectedDate: _date,
      initialTime: _time,
      durationMinutes: _durationMinutes,
    );
    if (picked != null && mounted) {
      setState(() => _time = picked);
    }
  }

  Future<void> _submit() async {
    final branchId = _branchId;
    final studentId = _studentId;
    final teacherId = _teacherId;

    if (branchId == null) {
      _message('지점을 선택해주세요.');
      return;
    }
    if (studentId == null) {
      _message('학생을 선택해주세요.');
      return;
    }
    if (teacherId == null) {
      _message('선생님 또는 지점장을 선택해주세요.');
      return;
    }
    if (_date.isBefore(_scopeStart) || _date.isAfter(_scopeEnd)) {
      _message('선택한 학기 기간 안의 날짜를 선택해주세요.');
      return;
    }
    if (_deductLessonRight && (_availableRightCount ?? 0) <= 0) {
      _message('사용할 수 있는 $_durationMinutes분 수업권이 없습니다.');
      return;
    }

    final startsAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    if (!startsAt.isAfter(DateTime.now())) {
      _message('현재보다 이후 시간을 선택해주세요.');
      return;
    }

    setState(() => _saving = true);
    try {
      var result = await _repository.createMakeupLesson(
        studentId: studentId,
        teacherId: teacherId,
        startsAt: startsAt,
        durationMinutes: _durationMinutes,
        deductLessonRight: _deductLessonRight,
        reason: _reason,
      );

      if (!mounted) return;
      if (result.requiresConfirmation) {
        final confirmed = await _confirmWarnings(result.warningCodes);
        if (!confirmed || !mounted) return;

        result = await _repository.createMakeupLesson(
          studentId: studentId,
          teacherId: teacherId,
          startsAt: startsAt,
          durationMinutes: _durationMinutes,
          confirmWarnings: true,
          deductLessonRight: _deductLessonRight,
          reason: _reason,
        );
      }

      if (!mounted) return;
      if (result.changed) {
        Navigator.of(context).pop(true);
      } else {
        _message('추가 수업을 등록하지 못했습니다.');
      }
    } on LessonFailure catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmWarnings(List<String> warningCodes) async {
    final messages = warningCodes.map((code) {
      return switch (code) {
        'FORESTRING_OUTSIDE_WORK_HOURS' => '근무시간 밖의 수업입니다.',
        'FORESTRING_NONSTANDARD_DURATION' =>
          '권장 수업 길이(15/30/60분)가 아닙니다.',
        _ => code,
      };
    }).join('\n');

    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('확인이 필요합니다'),
            content: Text('$messages\n\n그래도 추가 수업을 등록하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('돌아가기'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(backgroundColor: primaryColor),
                child: const Text('등록'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String get _rightStatusText {
    if (_studentId == null) return '학생을 선택하면 사용 가능한 수업권을 확인합니다.';
    if (_loadingRightCount) return '사용 가능한 수업권을 확인하는 중입니다.';
    final count = _availableRightCount;
    if (count == null) return '수업권 정보를 확인하지 못했습니다.';
    return '$_durationMinutes분 수업권 $count회 사용 가능';
  }

  @override
  Widget build(BuildContext context) {
    final students = _availableStudents;
    final teachers = _availableTeachers;
    final branch = _selectedBranch;
    final canDeduct = !_saving &&
        !_loadingRightCount &&
        _studentId != null &&
        (_availableRightCount ?? 0) > 0;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: const ForestringAppBar(title: '추가 수업 등록'),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 118),
              children: [
                RegistrationContextCard(
                  icon: Icons.event_available_outlined,
                  title: _semesterLabel(widget.semester.code),
                  subtitle: '${DateFormat('yyyy.MM.dd').format(_scopeStart)} ~ '
                      '${DateFormat('yyyy.MM.dd').format(_scopeEnd)}',
                  detail: '휴원 · 개인 일정 · 기존 수업 충돌을 등록 전에 확인합니다.',
                ),
                const SizedBox(height: 20),
                const RegistrationSectionHeader(
                  title: '수업 대상',
                  subtitle: '지점과 학생, 담당자를 먼저 선택해주세요.',
                ),
                const SizedBox(height: 9),
                RegistrationFormCard(
                  child: Column(
                    children: [
                      if (widget.profile.isMaster)
                        DropdownButtonFormField<String>(
                          initialValue: _branchId,
                          decoration: registrationInputDecoration(
                            '지점',
                            icon: Icons.storefront_outlined,
                          ),
                          items: widget.branches
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item.id,
                                  child: Text(item.name),
                                ),
                              )
                              .toList(),
                          onChanged: _saving ? null : _changeBranch,
                        )
                      else
                        _FixedField(
                          label: '지점',
                          value: branch?.name ?? '지점 정보 없음',
                          icon: Icons.storefront_outlined,
                        ),
                      const SizedBox(height: 10),
                      StudentSearchPickerField(
                        students: students,
                        selectedStudentId: _studentId,
                        enabled: !_saving && students.isNotEmpty,
                        onChanged: _selectStudent,
                      ),
                      if (students.isEmpty) ...[
                        const SizedBox(height: 6),
                        _inlineMessage(
                          '선택한 지점에 재원 중인 학생이 없습니다.',
                        ),
                      ],
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue:
                            teachers.any((item) => item.id == _teacherId)
                                ? _teacherId
                                : null,
                        decoration: registrationInputDecoration(
                          '수업 담당자',
                          icon: Icons.co_present_outlined,
                        ),
                        items: teachers
                            .map(
                              (teacher) => DropdownMenuItem<String>(
                                value: teacher.id,
                                child: Text(teacher.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (value) =>
                                setState(() => _teacherId = value),
                      ),
                      if (teachers.isEmpty) ...[
                        const SizedBox(height: 6),
                        _inlineMessage(
                          '선택한 지점에 수업 가능한 담당자가 없습니다.',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const RegistrationSectionHeader(
                  title: '수업 일정',
                  subtitle: '학생과 담당자를 선택한 뒤 가능한 시간을 확인합니다.',
                ),
                const SizedBox(height: 9),
                RegistrationFormCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _scheduleButton(
                              icon: Icons.calendar_today_outlined,
                              label: DateFormat('yyyy.MM.dd').format(_date),
                              onPressed: _saving ? null : _pickDate,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _scheduleButton(
                              icon: Icons.schedule_outlined,
                              label: _formatTime(_time),
                              onPressed: _saving ? null : _pickTime,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Text(
                        '수업 길이',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final minutes
                              in const [15, 30, 45, 60])
                            ChoiceChip(
                              label: Text('$minutes분'),
                              selected: _durationMinutes == minutes,
                              showCheckmark: false,
                              onSelected: _saving
                                  ? null
                                  : (_) {
                                      if (_durationMinutes == minutes) {
                                        return;
                                      }
                                      setState(() {
                                        _durationMinutes = minutes;
                                        _deductLessonRight = false;
                                      });
                                      _refreshAvailableRightCount();
                                    },
                              selectedColor:
                                  primaryColor.withValues(alpha: 0.11),
                              backgroundColor:
                                  primaryColor.withValues(alpha: 0.035),
                              side: BorderSide(
                                color: _durationMinutes == minutes
                                    ? primaryColor.withValues(alpha: 0.28)
                                    : primaryColor.withValues(alpha: 0.07),
                              ),
                              labelStyle: forestringTextStyle.copyWith(
                                color: _durationMinutes == minutes
                                    ? primaryColor
                                    : Colors.black54,
                                fontSize: 11.5,
                                fontWeight: _durationMinutes == minutes
                                    ? FontWeight.w500
                                    : FontWeight.w300,
                              ),
                              visualDensity:
                                  const VisualDensity(vertical: -1),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const RegistrationSectionHeader(
                  title: '수업권',
                  subtitle: '필요한 경우 같은 길이의 수업권 1회를 사용합니다.',
                ),
                const SizedBox(height: 9),
                Material(
                  color: Colors.white.withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.07),
                      ),
                    ),
                    child: SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 3,
                    ),
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xffE8F0E4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.confirmation_number_outlined,
                        color: primaryColor,
                        size: 20,
                      ),
                    ),
                    value: _deductLessonRight,
                    onChanged: canDeduct
                        ? (value) =>
                            setState(() => _deductLessonRight = value)
                        : null,
                    activeThumbColor: primaryColor,
                    title: Text(
                      '수업권 1회 사용',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      _rightStatusText,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black45,
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
                const SizedBox(height: 20),
                const RegistrationSectionHeader(
                  title: '메모',
                  subtitle: '선택 사항입니다.',
                ),
                const SizedBox(height: 9),
                RegistrationFormCard(
                  child: TextFormField(
                    enabled: !_saving,
                    maxLength: 100,
                    minLines: 2,
                    maxLines: 3,
                    decoration: registrationInputDecoration('메모 (선택)').copyWith(
                      alignLabelWithHint: true,
                      counterText: '',
                    ),
                    onChanged: (value) => _reason = value,
                  ),
                ),
              ],
            ),
            if (_saving)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x22000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: RegistrationBottomAction(
        label: '추가 수업 등록',
        loading: _saving,
        icon: Icons.add_task_outlined,
        onPressed: _saving ? null : _submit,
      ),
    );
  }

  Widget _inlineMessage(String message) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: Colors.black45,
          fontSize: 10.5,
        ),
      ),
    );
  }

  Widget _scheduleButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        backgroundColor: primaryColor.withValues(alpha: 0.035),
        side: BorderSide(
          color: primaryColor.withValues(alpha: 0.09),
        ),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: forestringTextStyle.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _FixedField extends StatelessWidget {
  const _FixedField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: neutralIvory.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: primaryColor,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black45,
                    fontSize: 9.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 13,
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
}
String _semesterLabel(String code) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(code.trim());
  if (match == null) return code;
  return '${match.group(1)}년 ${int.parse(match.group(2)!)}월';
}

String _formatTime(TimeOfDay value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
