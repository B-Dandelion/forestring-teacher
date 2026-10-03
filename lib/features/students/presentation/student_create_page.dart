import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: const ForestringAppBar(title: '수강생 등록'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: forestringTextStyle.copyWith(
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _sectionTitle('계정 정보'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _branchId,
                    decoration: _decoration('지점'),
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
                            if (value != null && value != _branchId) {
                              setState(() => _branchId = value);
                              _loadBranchData(value);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<_StudentCreateType>(
                    initialValue: _studentType,
                    decoration: _decoration('수강 형태'),
                    items: _StudentCreateType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.label),
                          ),
                        )
                        .toList(),
                    onChanged: _saving || _createdStudentId != null
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _studentType = value;
                                _errorMessage = null;
                              });
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nameController,
                    decoration: _decoration('학생 이름'),
                    enabled: !_saving && _createdStudentId == null,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '학생 이름을 입력해주세요.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _pinController,
                    decoration: _decoration('PIN (4자리 숫자)'),
                    enabled: !_saving && _createdStudentId == null,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: (value) =>
                        value == null || !RegExp(r'^\d{4}$').hasMatch(value)
                            ? '4자리 숫자를 입력해주세요.'
                            : null,
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle(_isRegular ? '정규 수업 설정' : '자율 예약 설정'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _teacherId,
                    decoration: _decoration('담당 선생님'),
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
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _semesterId,
                    decoration: _decoration('시작 학기'),
                    items: _semesters
                        .map(
                          (semester) => DropdownMenuItem(
                            value: semester.id,
                            child: Text(semester.label),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _semesterId = value),
                  ),
                  if (_isRegular) ...[
                    const SizedBox(height: 14),
                    ...List.generate(
                      _schedules.length,
                      (index) => _scheduleCard(index),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(
                                () => _schedules.add(_ScheduleDraft()),
                              ),
                      icon: const Icon(Icons.add),
                      label: const Text('정규 수업 추가'),
                    ),
                  ] else ...[
                    const SizedBox(height: 14),
                    _infoCard(
                      '자율 예약 학생은 정규 시간표 없이, 발급된 수강권으로 담당 선생님의 빈 시간에 직접 예약합니다.',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _rightCountController,
                      decoration: _decoration('이번 학기 수강권 횟수'),
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      validator: (value) {
                        if (_isRegular) return null;
                        final count = int.tryParse(value ?? '');
                        return count == null || count <= 0
                            ? '수강권 횟수를 1회 이상 입력해주세요.'
                            : null;
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: _flexDurationMinutes,
                      decoration: _decoration('수업 길이'),
                      items: const [
                        DropdownMenuItem(value: 15, child: Text('15분')),
                        DropdownMenuItem(value: 30, child: Text('30분')),
                        DropdownMenuItem(value: 45, child: Text('45분')),
                        DropdownMenuItem(value: 60, child: Text('60분')),
                        DropdownMenuItem(value: 75, child: Text('75분')),
                        DropdownMenuItem(value: 90, child: Text('90분')),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _flexDurationMinutes = value);
                              }
                            },
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _saving
                          ? '등록 중...'
                          : _createdStudentId == null
                              ? '${_studentType.label} 등록'
                              : '${_studentType.label} 설정 다시 시도',
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _scheduleCard(int index) {
    final schedule = _schedules[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: primaryColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: schedule.weekday,
                    decoration: _decoration('요일'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('월요일')),
                      DropdownMenuItem(value: 2, child: Text('화요일')),
                      DropdownMenuItem(value: 3, child: Text('수요일')),
                      DropdownMenuItem(value: 4, child: Text('목요일')),
                      DropdownMenuItem(value: 5, child: Text('금요일')),
                      DropdownMenuItem(value: 6, child: Text('토요일')),
                      DropdownMenuItem(value: 7, child: Text('일요일')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => schedule.weekday = value);
                      }
                    },
                  ),
                ),
                if (_schedules.length > 1) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '삭제',
                    onPressed: _saving
                        ? null
                        : () => setState(() => _schedules.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: schedule.time,
                            );
                            if (picked != null && mounted) {
                              setState(() => schedule.time = picked);
                            }
                          },
                    icon: const Icon(Icons.access_time),
                    label: Text(
                      '${schedule.time.hour.toString().padLeft(2, '0')}:'
                      '${schedule.time.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: schedule.durationMinutes,
                    decoration: _decoration('수업 길이'),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15분')),
                      DropdownMenuItem(value: 30, child: Text('30분')),
                      DropdownMenuItem(value: 45, child: Text('45분')),
                      DropdownMenuItem(value: 60, child: Text('60분')),
                      DropdownMenuItem(value: 75, child: Text('75분')),
                      DropdownMenuItem(value: 90, child: Text('90분')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => schedule.durationMinutes = value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  Widget _infoCard(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: primaryColor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: forestringTextStyle.copyWith(
                color: Colors.black87,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      counterText: '',
      border: const OutlineInputBorder(),
      isDense: true,
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
        time = const TimeOfDay(hour: 10, minute: 0),
        durationMinutes = 30;

  int weekday;
  TimeOfDay time;
  int durationMinutes;

  Map<String, dynamic> toJson() {
    return {
      'weekday': weekday,
      'startTime':
          '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}',
      'durationMinutes': durationMinutes,
    };
  }
}
