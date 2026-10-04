import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../../core/widgets/registration_form.dart';
import '../../../core/widgets/compact_selection_sheet.dart';
import 'widgets/regular_schedule_picker_widgets.dart';
import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/student_admin_repository.dart';

class StudentCreatePage extends StatefulWidget {
  const StudentCreatePage({
    super.key,
    required this.profile,
    this.branchRepository,
    this.repository,
  });

  final CurrentProfile profile;
  final BranchRepository? branchRepository;
  final StudentAdminRepository? repository;

  @override
  State<StudentCreatePage> createState() => _StudentCreatePageState();
}

class _StudentCreatePageState extends State<StudentCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _rightCountController = TextEditingController(text: '4');
  late final BranchRepository _branchRepository;
  late final StudentAdminRepository _repository;

  List<AcademyBranch> _branches = const [];
  List<StudentAdminTeacher> _teachers = const [];
  List<StudentSemesterOption> _semesters = const [];

  String? _branchId;
  String? _teacherId;
  String? _semesterId;
  String? _createdStudentId;
  _StudentCreateType _studentType = _StudentCreateType.regular;
  int _flexDurationMinutes = 30;
  List<StudentAdminWorkWindow> _teacherWorkHours = const [];
  bool _showPin = false;

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  final List<_ScheduleDraft> _schedules = [
    _ScheduleDraft(),
  ];

  bool get _isRegular => _studentType == _StudentCreateType.regular;

  @override
  void initState() {
    super.initState();
    _branchRepository =
        widget.branchRepository ?? BranchRepository();
    _repository = widget.repository ?? StudentAdminRepository();
    _loadInitialData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _rightCountController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final branches = (await _branchRepository.fetchBranches())
          .where((branch) => branch.isActive)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      String? branchId;
      if (widget.profile.isManager) {
        branchId = widget.profile.branchId;
      } else if (branches.isNotEmpty) {
        branchId = branches.first.id;
      }

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _branchId = branchId;
      });

      if (branchId != null) {
        await _loadBranchData(branchId);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadBranchData(String branchId) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _teacherId = null;
      _semesterId = null;
      _createdStudentId = null;
      _teacherWorkHours = const [];
    });

    try {
      final results = await Future.wait([
        _repository.fetchTeachers(branchId),
        _repository.fetchSemesters(branchId),
      ]);

      final teachers = results[0] as List<StudentAdminTeacher>;
      final semesters = results[1] as List<StudentSemesterOption>;

      if (!mounted) return;
      setState(() {
        _teachers = teachers;
        _semesters = semesters;
        _teacherId = teachers.isEmpty ? null : teachers.first.id;

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final current = semesters.where(
          (semester) =>
              !today.isBefore(semester.startsOn) &&
              !today.isAfter(semester.endsOn),
        );
        _semesterId = current.isNotEmpty
            ? current.first.id
            : (semesters.isEmpty ? null : semesters.first.id);
      });

      if (_teacherId != null) {
        await _loadTeacherWorkHours(_teacherId!);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _teachers = const [];
        _semesters = const [];
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }

    if (_isRegular &&
        _schedules.any((schedule) => schedule.startMinutes == null)) {
      setState(() {
        _errorMessage =
            '담당 선생님의 근무시간 안에서 정규 수업 시간을 선택해주세요.';
      });
      return;
    }

    final branchId = _branchId;
    final teacherId = _teacherId;
    final semesterId = _semesterId;
    final studentType = _studentType;
    final studentName = _nameController.text.trim();
    final flexRightCount = studentType == _StudentCreateType.flex
        ? int.parse(_rightCountController.text)
        : null;
    final schedules = _schedules
        .map((schedule) => schedule.toJson())
        .toList(growable: false);
    if (branchId == null || teacherId == null || semesterId == null) {
      setState(() {
        _errorMessage = '지점, 담당 선생님, 학기를 모두 선택해주세요.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      var studentId = _createdStudentId;
      if (studentId == null) {
        studentId = await _repository.createStudentAccount(
          name: _nameController.text,
          pin: _pinController.text,
          branchId: branchId,
          studentType: studentType.value,
        );
        if (mounted) {
          setState(() => _createdStudentId = studentId);
        }
      }

      final Map<String, dynamic> result;
      if (studentType == _StudentCreateType.regular) {
        result = await _repository.initializeRegularSemester(
          studentId: studentId,
          teacherId: teacherId,
          semesterId: semesterId,
          schedules: schedules,
        );
      } else {
        result = await _repository.initializeFlexSemester(
          studentId: studentId,
          teacherId: teacherId,
          semesterId: semesterId,
          baseRightCount: flexRightCount!,
          durationMinutes: _flexDurationMinutes,
        );
      }

      if (!mounted) return;
      await _showSuccess(
        result,
        studentType: studentType,
        studentName: studentName,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showSuccess(
    Map<String, dynamic> result, {
    required _StudentCreateType studentType,
    required String studentName,
  }) async {
    final String title;
    final String message;

    if (studentType == _StudentCreateType.regular) {
      final activation = result['activation'];
      final activationMap = activation is Map
          ? Map<String, dynamic>.from(activation)
          : const <String, dynamic>{};
      final slotCount = activationMap['slotCount'] ?? _schedules.length;
      final rightCount = activationMap['rightCount'] ?? '-';
      final lessonCount = activationMap['lessonCount'] ?? '-';

      title = '정규 학생 등록 완료';
      message = '$studentName 학생의 정규 일정이 생성되었습니다.\n\n'
          '정규 스케줄 $slotCount개\n'
          '수강권 $rightCount개\n'
          '수업 $lessonCount개';
    } else {
      final rightCount = result['baseRightCount'] ?? '-';
      final durationMinutes = result['durationMinutes'] ?? '-';

      title = '자율 예약 학생 등록 완료';
      message = '$studentName 학생의 자율 예약 설정이 완료되었습니다.\n\n'
          '수강권 $rightCount개\n'
          '수업 길이 $durationMinutes분\n'
          '담당 선생님의 예약 가능 시간에서 직접 예약할 수 있습니다.';
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String get _selectedBranchName {
    final id = _branchId;
    if (id == null) return '지점 미선택';
    for (final branch in _branches) {
      if (branch.id == id) return branch.name;
    }
    return '지점 미선택';
  }

  String get _selectedSemesterLabel {
    final id = _semesterId;
    if (id == null) return '시작 학기 미선택';
    for (final semester in _semesters) {
      if (semester.id == id) return semester.label;
    }
    return '시작 학기 미선택';
  }

  Future<void> _loadTeacherWorkHours(String teacherId) async {
    try {
      final hours = await _repository.fetchTeacherWorkHours(teacherId);
      if (!mounted || _teacherId != teacherId) return;
      setState(() => _teacherWorkHours = hours);
      for (final schedule in _schedules) {
        _ensureScheduleStart(schedule, keepCurrent: true);
      }
    } on StudentAdminFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _teacherWorkHours = const [];
        _errorMessage = error.message;
      });
    }
  }

  Future<void> _changeTeacher(String? teacherId) async {
    if (teacherId == null || teacherId == _teacherId) return;
    setState(() {
      _teacherId = teacherId;
      _teacherWorkHours = const [];
      _errorMessage = null;
    });
    await _loadTeacherWorkHours(teacherId);
  }

  List<int> _availableStartMinutes(_ScheduleDraft schedule) {
    final result = <int>{};
    for (final window in _teacherWorkHours.where(
      (item) => item.weekday == schedule.weekday,
    )) {
      var minute = ((window.startMinutes + 14) ~/ 15) * 15;
      while (minute + schedule.durationMinutes <= window.endMinutes) {
        result.add(minute);
        minute += 15;
      }
    }
    final list = result.toList()..sort();
    return list;
  }

  void _ensureScheduleStart(
    _ScheduleDraft schedule, {
    bool keepCurrent = false,
  }) {
    final options = _availableStartMinutes(schedule);
    final current = schedule.startMinutes;
    setState(() {
      if (options.isEmpty) {
        schedule.startMinutes = null;
      } else if (keepCurrent &&
          current != null &&
          options.contains(current)) {
        schedule.startMinutes = current;
      } else if (current == null || !options.contains(current)) {
        schedule.startMinutes = options.first;
      }
    });
  }

  Future<void> _pickSemester() async {
    final selected = await showCompactSelectionSheet<String>(
      context: context,
      title: '시작 학기 선택',
      selectedValue: _semesterId,
      options: _semesters
          .map(
            (semester) => CompactSelectionOption(
              value: semester.id,
              label: semester.label,
              subtitle:
                  '${semester.startsOn.year}.${semester.startsOn.month.toString().padLeft(2, '0')}.${semester.startsOn.day.toString().padLeft(2, '0')} ~ '
                  '${semester.endsOn.year}.${semester.endsOn.month.toString().padLeft(2, '0')}.${semester.endsOn.day.toString().padLeft(2, '0')}',
            ),
          )
          .toList(),
    );
    if (!mounted || selected == null || selected == _semesterId) return;
    setState(() => _semesterId = selected);
  }

  InputDecoration _pinDecoration(String label) {
    return registrationInputDecoration(
      label,
      icon: Icons.lock_outline_rounded,
    ).copyWith(
      suffixIcon: IconButton(
        tooltip: _showPin ? 'PIN 숨기기' : 'PIN 보기',
        onPressed: _saving
            ? null
            : () => setState(() => _showPin = !_showPin),
        icon: Icon(
          _showPin
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: const ForestringAppBar(title: '수강생 등록'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 118),
                    children: [
                      RegistrationContextCard(
                        icon: _isRegular
                            ? Icons.event_repeat_rounded
                            : Icons.touch_app_outlined,
                        title: _studentType.label,
                        subtitle:
                            '$_selectedBranchName · $_selectedSemesterLabel',
                        detail: _isRegular
                            ? '계정과 첫 학기 정규 일정을 함께 등록합니다.'
                            : '계정과 첫 학기 자율 예약 수업권을 함께 등록합니다.',
                        surfaceColor: _isRegular
                            ? const Color(0xffEAF3E9)
                            : const Color(0xffEEF4F7),
                        iconColor: _isRegular
                            ? primaryColor
                            : const Color(0xff4B7892),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        _errorCard(_errorMessage!),
                      ],
                      const SizedBox(height: 20),
                      const RegistrationSectionHeader(
                        title: '계정 정보',
                        subtitle: '이름과 로그인 PIN을 설정합니다.',
                      ),
                      const SizedBox(height: 9),
                      RegistrationFormCard(
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _branchId,
                              decoration: registrationInputDecoration(
                                widget.profile.isManager
                                    ? '지점 (변경 불가)'
                                    : '지점',
                                icon: Icons.storefront_outlined,
                              ),
                              items: _branches
                                  .map(
                                    (branch) => DropdownMenuItem(
                                      value: branch.id,
                                      child: Text(branch.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _saving ||
                                      widget.profile.isManager ||
                                      _createdStudentId != null
                                  ? null
                                  : (value) {
                                      if (value != null &&
                                          value != _branchId) {
                                        setState(() => _branchId = value);
                                        _loadBranchData(value);
                                      }
                                    },
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _nameController,
                              decoration: registrationInputDecoration(
                                '학생 이름',
                                icon: Icons.person_outline_rounded,
                              ),
                              enabled:
                                  !_saving && _createdStudentId == null,
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '학생 이름을 입력해주세요.'
                                      : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _pinController,
                              decoration: _pinDecoration('PIN (4자리 숫자)'),
                              enabled:
                                  !_saving && _createdStudentId == null,
                              keyboardType: TextInputType.number,
                              obscureText: !_showPin,
                              maxLength: 4,
                              textInputAction: TextInputAction.done,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              validator: (value) => value == null ||
                                      !RegExp(r'^\d{4}$').hasMatch(value)
                                  ? '4자리 숫자를 입력해주세요.'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const RegistrationSectionHeader(
                        title: '수강 설정',
                        subtitle: '수강 형태와 담당 선생님, 시작 학기를 선택합니다.',
                      ),
                      const SizedBox(height: 9),
                      RegistrationFormCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '수강 형태',
                              style: forestringTextStyle.copyWith(
                                color: Colors.black54,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _typeChoice(
                                    type: _StudentCreateType.regular,
                                    icon: Icons.event_repeat_rounded,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _typeChoice(
                                    type: _StudentCreateType.flex,
                                    icon: Icons.touch_app_outlined,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _teacherId,
                              decoration: registrationInputDecoration(
                                '담당 선생님',
                                icon: Icons.co_present_outlined,
                              ),
                              items: _teachers
                                  .map(
                                    (teacher) => DropdownMenuItem(
                                      value: teacher.id,
                                      child: Text(teacher.displayName),
                                    ),
                                  )
                                  .toList(),
                              onChanged:
                                  _saving ? null : _changeTeacher,
                            ),
                            const SizedBox(height: 10),
                            CompactSelectionField(
                              label: '시작 학기',
                              value: _selectedSemesterLabel,
                              icon: Icons.calendar_month_outlined,
                              enabled: !_saving && _semesters.isNotEmpty,
                              onTap: _pickSemester,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_isRegular) ...[
                        const RegistrationSectionHeader(
                          title: '정규 수업',
                          subtitle: '요일, 시작 시간, 수업 길이를 설정합니다.',
                        ),
                        const SizedBox(height: 9),
                        ...List.generate(
                          _schedules.length,
                          (index) => _scheduleCard(index),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () {
                                  final schedule = _ScheduleDraft();
                                  setState(() => _schedules.add(schedule));
                                  _ensureScheduleStart(schedule);
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryColor,
                            backgroundColor:
                                primaryColor.withValues(alpha: 0.035),
                            side: BorderSide(
                              color: primaryColor.withValues(alpha: 0.09),
                            ),
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('정규 수업 추가'),
                        ),
                      ] else ...[
                        const RegistrationSectionHeader(
                          title: '자율 예약',
                          subtitle: '첫 학기에 사용할 수업권을 설정합니다.',
                        ),
                        const SizedBox(height: 9),
                        RegistrationFormCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _infoCard(
                                '정규 시간표 없이 발급된 수업권으로 담당 선생님의 빈 시간에 직접 예약합니다.',
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _rightCountController,
                                decoration: registrationInputDecoration(
                                  '이번 학기 수업권 횟수',
                                  icon: Icons.confirmation_number_outlined,
                                ),
                                enabled: !_saving,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                validator: (value) {
                                  if (_isRegular) return null;
                                  final count =
                                      int.tryParse(value ?? '');
                                  return count == null || count <= 0
                                      ? '수업권 횟수를 1회 이상 입력해주세요.'
                                      : null;
                                },
                              ),
                              const SizedBox(height: 14),
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
                                      selected:
                                          _flexDurationMinutes == minutes,
                                      showCheckmark: false,
                                      onSelected: _saving
                                          ? null
                                          : (_) => setState(
                                                () =>
                                                    _flexDurationMinutes =
                                                        minutes,
                                              ),
                                      selectedColor: primaryColor
                                          .withValues(alpha: 0.11),
                                      backgroundColor: primaryColor
                                          .withValues(alpha: 0.035),
                                      side: BorderSide(
                                        color:
                                            _flexDurationMinutes == minutes
                                                ? primaryColor.withValues(
                                                    alpha: 0.28,
                                                  )
                                                : primaryColor.withValues(
                                                    alpha: 0.07,
                                                  ),
                                      ),
                                      labelStyle:
                                          forestringTextStyle.copyWith(
                                        color:
                                            _flexDurationMinutes == minutes
                                                ? primaryColor
                                                : Colors.black54,
                                        fontSize: 11.5,
                                        fontWeight:
                                            _flexDurationMinutes == minutes
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
                      ],
                    ],
                  ),
                  if (_saving)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x22000000),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : RegistrationBottomAction(
              label: _createdStudentId == null
                  ? '${_studentType.label} 등록'
                  : '${_studentType.label} 설정 다시 시도',
              loading: _saving,
              icon: Icons.person_add_alt_1_rounded,
              onPressed: _saving ? null : _submit,
            ),
    );
  }

  Widget _typeChoice({
    required _StudentCreateType type,
    required IconData icon,
  }) {
    final selected = _studentType == type;
    final enabled = !_saving && _createdStudentId == null;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: !enabled
            ? null
            : () {
                setState(() {
                  _studentType = type;
                  _errorMessage = null;
                });
              },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            color: selected
                ? primaryColor.withValues(alpha: 0.08)
                : neutralIvory.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? primaryColor.withValues(alpha: 0.24)
                  : primaryColor.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? primaryColor : Colors.black38,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: forestringTextStyle.copyWith(
                    color: selected ? primaryColor : Colors.black54,
                    fontSize: 11.5,
                    fontWeight:
                        selected ? FontWeight.w500 : FontWeight.w300,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scheduleCard(int index) {
    final schedule = _schedules[index];
    final timeOptions = _availableStartMinutes(schedule);
    const durationOptions = [15, 30, 45, 60];

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: RegistrationFormCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '정규 수업 ${index + 1}',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_schedules.length > 1)
                  IconButton(
                    tooltip: '삭제',
                    visualDensity: VisualDensity.compact,
                    onPressed: _saving
                        ? null
                        : () =>
                            setState(() => _schedules.removeAt(index)),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.black38,
                      size: 20,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            RegularWeekdaySelector(
              value: schedule.weekday,
              enabled: !_saving && _teacherWorkHours.isNotEmpty,
              onChanged: (value) {
                setState(() => schedule.weekday = value);
                _ensureScheduleStart(schedule);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: RegularTimeField(
                    value: schedule.startMinutes,
                    enabled: !_saving && timeOptions.isNotEmpty,
                    onTap: () async {
                      final selected = await showRegularTimePicker(
                        context: context,
                        options: timeOptions,
                        selectedMinutes: schedule.startMinutes,
                      );
                      if (!mounted || selected == null) return;
                      setState(() => schedule.startMinutes = selected);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 128,
                  child: DropdownButtonFormField<int>(
                    initialValue: schedule.durationMinutes,
                    decoration: registrationInputDecoration('수업 길이'),
                    items: durationOptions
                        .map(
                          (minutes) => DropdownMenuItem(
                            value: minutes,
                            child: Text('$minutes분'),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(
                              () => schedule.durationMinutes = value,
                            );
                            _ensureScheduleStart(
                              schedule,
                              keepCurrent: true,
                            );
                          },
                  ),
                ),
              ],
            ),
            if (_teacherId != null && timeOptions.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '선택한 요일에는 담당 선생님의 근무시간이 없거나 '
                '선택한 수업 길이를 배치할 수 없습니다.',
                style: forestringTextStyle.copyWith(
                  color: Colors.redAccent,
                  fontSize: 10.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String message) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: primaryColor,
            size: 18,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: forestringTextStyle.copyWith(
                color: Colors.black54,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Colors.redAccent,
            size: 17,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: forestringTextStyle.copyWith(
                color: Colors.redAccent,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

}

enum _StudentCreateType {
  regular,
  flex,
}

extension on _StudentCreateType {
  String get value {
    return switch (this) {
      _StudentCreateType.regular => 'regular',
      _StudentCreateType.flex => 'flex',
    };
  }

  String get label {
    return switch (this) {
      _StudentCreateType.regular => '정규 학생',
      _StudentCreateType.flex => '자율 예약 학생',
    };
  }
}

class _ScheduleDraft {
  _ScheduleDraft()
      : weekday = 1,
        startMinutes = null,
        durationMinutes = 30;

  int weekday;
  int? startMinutes;
  int durationMinutes;

  Map<String, dynamic> toJson() {
    final minutes = startMinutes!;
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return {
      'weekday': weekday,
      'startTime': '$hour:$minute',
      'durationMinutes': durationMinutes,
    };
  }
}
