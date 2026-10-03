import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/teacher_repository.dart';
import 'teacher_work_hours_editor.dart';

class TeacherCreatePage extends StatefulWidget {
  const TeacherCreatePage({
    super.key,
    required this.profile,
    this.repository,
    this.branchRepository,
  });

  final CurrentProfile profile;
  final TeacherRepository? repository;
  final BranchRepository? branchRepository;

  @override
  State<TeacherCreatePage> createState() => _TeacherCreatePageState();
}

class _TeacherCreatePageState extends State<TeacherCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  late final TeacherRepository _repository;
  late final BranchRepository _branchRepository;

  List<AcademyBranch> _branches = const [];
  List<TeacherWorkHourDraft> _workHours = const [
    TeacherWorkHourDraft(),
  ];
  String? _branchId;
  bool _loading = true;
  bool _saving = false;
  bool _showPin = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? TeacherRepository();
    _branchRepository =
        widget.branchRepository ?? BranchRepository();
    _loadBranches();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      var branches = (await _branchRepository.fetchBranches())
          .where((branch) => branch.isActive)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (widget.profile.isManager) {
        final managerBranchId = widget.profile.branchId;
        branches = managerBranchId == null
            ? const []
            : branches
                .where((branch) => branch.id == managerBranchId)
                .toList(growable: false);
      }

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _branchId = branches.isEmpty ? null : branches.first.id;
      });
    } on BranchFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }

    final branchId = _branchId;
    if (branchId == null || branchId.isEmpty) {
      setState(() => _errorMessage = '지점을 선택해주세요.');
      return;
    }

    final workHourError = validateTeacherWorkHours(_workHours);
    if (workHourError != null) {
      setState(() => _errorMessage = workHourError);
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final teacher = await _repository.createTeacher(
        name: _nameController.text,
        pin: _pinController.text,
        branchId: branchId,
        workHours: _workHours
            .map((workHour) => workHour.toInput())
            .toList(growable: false),
      );

      if (!mounted) return;
      String? branchName;
      for (final branch in _branches) {
        if (branch.id == branchId) {
          branchName = branch.name;
          break;
        }
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('선생님 등록 완료'),
          content: Text(
            '${teacher.displayName} 선생님 계정이 등록되었습니다.\n\n'
            '지점: ${branchName ?? '-'}\n'
            '근무시간: ${_workHours.length}개',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
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
    if (!widget.profile.isMaster && !widget.profile.isManager) {
      return const Scaffold(
        backgroundColor: neutralIvory,
        appBar: ForestringAppBar(title: '선생님 등록'),
        body: Center(child: Text('관리자만 선생님을 등록할 수 있습니다.')),
      );
    }

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: const ForestringAppBar(title: '선생님 등록'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_errorMessage != null) ...[
                    _errorCard(_errorMessage!),
                    const SizedBox(height: 12),
                  ],
                  if (_branches.isEmpty) ...[
                    _emptyBranches(),
                    const SizedBox(height: 16),
                  ],
                  _sectionTitle('계정 정보'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _branchId,
                    decoration: _decoration(
                      widget.profile.isManager ? '지점 (변경 불가)' : '지점',
                    ),
                    items: _branches
                        .map(
                          (branch) => DropdownMenuItem(
                            value: branch.id,
                            child: Text(branch.name),
                          ),
                        )
                        .toList(),
                    onChanged: _saving || widget.profile.isManager
                        ? null
                        : (value) => setState(() => _branchId = value),
                    validator: (value) => value == null ? '지점을 선택해주세요.' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nameController,
                    decoration: _decoration('선생님 이름'),
                    enabled: !_saving,
                    maxLength: 100,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty) {
                        return '선생님 이름을 입력해주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _pinController,
                    decoration: _pinDecoration('PIN (4자리 숫자)'),
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    obscureText: !_showPin,
                    maxLength: 4,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    validator: (value) =>
                        value == null || !RegExp(r'^\d{4}$').hasMatch(value)
                            ? '4자리 숫자를 입력해주세요.'
                            : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _pinConfirmController,
                    decoration: _pinDecoration('PIN 확인'),
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    obscureText: !_showPin,
                    maxLength: 4,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    validator: (value) {
                      if (value == null || !RegExp(r'^\d{4}$').hasMatch(value)) {
                        return 'PIN을 한 번 더 입력해주세요.';
                      }
                      if (value != _pinController.text) {
                        return 'PIN이 일치하지 않습니다.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle('근무시간'),
                  const SizedBox(height: 6),
                  Text(
                    '요일별 근무시간을 15분 단위로 등록합니다.',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black54,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TeacherWorkHoursEditor(
                    values: _workHours,
                    enabled: !_saving,
                    onChanged: (values) {
                      setState(() {
                        _workHours = values;
                        _errorMessage = null;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed:
                        _saving || _branches.isEmpty ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_saving ? '등록 중...' : '선생님 등록'),
                  ),
                  const SizedBox(height: 20),
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

  Widget _emptyBranches() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '등록 가능한 활성 지점이 없습니다.',
            style: forestringTextStyle,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _loadBranches,
            child: const Text('지점 다시 불러오기'),
          ),
        ],
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

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      counterText: '',
      border: const OutlineInputBorder(),
      isDense: true,
    );
  }

  InputDecoration _pinDecoration(String label) {
    return _decoration(label).copyWith(
      suffixIcon: IconButton(
        tooltip: _showPin ? 'PIN 숨기기' : 'PIN 보기',
        onPressed: _saving
            ? null
            : () => setState(() => _showPin = !_showPin),
        icon: Icon(
          _showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    );
  }
}
