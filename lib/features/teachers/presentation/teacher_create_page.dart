import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../../core/widgets/registration_form.dart';
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

  String get _selectedBranchName {
    final id = _branchId;
    if (id == null) return '지점 미선택';
    for (final branch in _branches) {
      if (branch.id == id) return branch.name;
    }
    return '지점 미선택';
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
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 118),
                    children: [
                      RegistrationContextCard(
                        icon: Icons.co_present_rounded,
                        title: '새 선생님 계정',
                        subtitle: _selectedBranchName,
                        detail: '계정 정보와 기본 근무시간을 함께 등록합니다.',
                        surfaceColor: const Color(0xffEEF1F8),
                        iconColor: const Color(0xff5E6F9B),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        _errorCard(_errorMessage!),
                      ],
                      if (_branches.isEmpty) ...[
                        const SizedBox(height: 10),
                        _emptyBranches(),
                      ],
                      const SizedBox(height: 20),
                      const RegistrationSectionHeader(
                        title: '계정 정보',
                        subtitle: '지점, 이름, 로그인 PIN을 설정합니다.',
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
                              onChanged: _saving || widget.profile.isManager
                                  ? null
                                  : (value) =>
                                      setState(() => _branchId = value),
                              validator: (value) =>
                                  value == null ? '지점을 선택해주세요.' : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _nameController,
                              decoration: registrationInputDecoration(
                                '선생님 이름',
                                icon: Icons.person_outline_rounded,
                              ),
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
                              decoration: _pinDecoration(
                                'PIN (4자리 숫자)',
                              ),
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              obscureText: !_showPin,
                              maxLength: 4,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              validator: (value) => value == null ||
                                      !RegExp(r'^\d{4}$').hasMatch(value)
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
                                if (value == null ||
                                    !RegExp(r'^\d{4}$').hasMatch(value)) {
                                  return 'PIN을 한 번 더 입력해주세요.';
                                }
                                if (value != _pinController.text) {
                                  return 'PIN이 일치하지 않습니다.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const RegistrationSectionHeader(
                        title: '근무시간',
                        subtitle: '요일별 근무시간을 15분 단위로 설정합니다.',
                      ),
                      const SizedBox(height: 9),
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
              label: '선생님 등록',
              loading: _saving,
              icon: Icons.person_add_alt_1_rounded,
              onPressed:
                  _saving || _branches.isEmpty ? null : _submit,
            ),
    );
  }

  Widget _emptyBranches() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xffA87524),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '등록 가능한 활성 지점이 없습니다.',
              style: forestringTextStyle.copyWith(
                color: const Color(0xffA87524),
                fontSize: 10.5,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadBranches,
            child: const Text('다시 불러오기'),
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

}
