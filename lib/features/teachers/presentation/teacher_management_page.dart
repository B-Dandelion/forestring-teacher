import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/teacher_repository.dart';
import '../data/teacher_work_hours_schedule_repository.dart';
import 'teacher_assigned_students_page.dart';
import 'teacher_blocked_periods_page.dart';
import 'teacher_create_page.dart';
import 'teacher_departure_page.dart';
import 'teacher_lesson_stats_page.dart';
import 'teacher_work_hours_edit_page.dart';

class TeacherManagementPage extends StatefulWidget {
  const TeacherManagementPage({
    super.key,
    required this.profile,
    this.repository,
    this.branchRepository,
    this.workHoursRepository,
    this.isQaSandbox = false,
    this.embeddedInShell = false,
  });

  final CurrentProfile profile;
  final TeacherRepository? repository;
  final BranchRepository? branchRepository;
  final TeacherWorkHoursScheduleRepository? workHoursRepository;
  final bool isQaSandbox;
  final bool embeddedInShell;

  @override
  State<TeacherManagementPage> createState() =>
      _TeacherManagementPageState();
}

class _TeacherManagementPageState extends State<TeacherManagementPage> {
  static const _allBranches = '__all__';

  late final TeacherRepository _repository;
  late final BranchRepository _branchRepository;
  final _searchController = TextEditingController();

  List<AcademyBranch> _branches = const [];
  List<ManagedTeacher> _teachers = const [];

  String? _branchId;
  String _statusFilter = 'active';
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.isQaSandbox &&
        (widget.repository == null ||
            widget.branchRepository == null ||
            widget.workHoursRepository == null)) {
      throw StateError(
        'QA teacher management requires sandbox repositories.',
      );
    }
    _repository = widget.repository ?? TeacherRepository();
    _branchRepository =
        widget.branchRepository ?? BranchRepository();
    _searchController.addListener(_onSearchChanged);
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final branches = (await _branchRepository.fetchBranches())
          .where((branch) => branch.isActive)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final branchId = widget.profile.isManager ? widget.profile.branchId : null;

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _branchId = branchId;
      });

      await _loadTeachers();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadTeachers() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final teachers = await _repository.fetchTeachers(branchId: _branchId);
      if (!mounted) return;
      setState(() => _teachers = teachers);
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _teachers = const [];
        _errorMessage = error.message;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<ManagedTeacher> get _visibleTeachers {
    final query = _searchController.text.trim().toLowerCase();

    return _teachers.where((teacher) {
      if (_statusFilter == 'active' && !teacher.isActive) {
        return false;
      }
      if (_statusFilter == 'departed' && teacher.isActive) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }

      return teacher.displayName.toLowerCase().contains(query) ||
          teacher.branchName.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openRegistration() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TeacherCreatePage(
          profile: widget.profile,
          repository: widget.repository,
          branchRepository: widget.branchRepository,
        ),
      ),
    );

    if (created == true && mounted) {
      await _loadTeachers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleTeachers = _visibleTeachers;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: widget.embeddedInShell
          ? null
          : ForestringAppBar(
              title: '선생님 관리',
              actions: [
                IconButton(
                  tooltip: '새로고침',
                  onPressed: _loading ? null : _loadTeachers,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
      floatingActionButton: widget.profile.isMaster || widget.profile.isManager
          ? FloatingActionButton.extended(
              heroTag: 'manager-teacher-registration-fab',
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              onPressed: _openRegistration,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(
                '선생님 등록',
                style: forestringTextStyle.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadTeachers,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              14,
              14,
              14,
              widget.profile.isMaster || widget.profile.isManager ? 100 : 28,
            ),
            children: [
              _buildFilters(),
              const SizedBox(height: 14),
              if (_errorMessage != null) ...[
                _errorCard(_errorMessage!),
                const SizedBox(height: 12),
              ],
              if (_loading && _teachers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visibleTeachers.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(
                    child: Text(
                      '조건에 맞는 선생님이 없습니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),
                )
              else ...[
                Text(
                  '${visibleTeachers.length}명',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ...visibleTeachers.map(_teacherCard),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '선생님 이름 검색',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (widget.profile.isMaster) ...[
          DropdownButtonFormField<String>(
            initialValue: _branchId ?? _allBranches,
            decoration: _filterDecoration('지점'),
            items: [
              const DropdownMenuItem(
                value: _allBranches,
                child: Text('전체 지점'),
              ),
              ..._branches.map(
                (branch) => DropdownMenuItem(
                  value: branch.id,
                  child: Text(branch.name),
                ),
              ),
            ],
            onChanged: _loading
                ? null
                : (value) async {
                    setState(() {
                      _branchId = value == _allBranches ? null : value;
                    });
                    await _loadTeachers();
                  },
          ),
          const SizedBox(height: 10),
        ],
        DropdownButtonFormField<String>(
          initialValue: _statusFilter,
          decoration: _filterDecoration('상태'),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('전체')),
            DropdownMenuItem(value: 'active', child: Text('재직')),
            DropdownMenuItem(value: 'departed', child: Text('퇴사')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _statusFilter = value);
            }
          },
        ),
      ],
    );
  }

  InputDecoration _filterDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.18)),
      ),
    );
  }

  Widget _teacherCard(ManagedTeacher teacher) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetails(teacher),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            teacher.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: forestringTextStyle.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusBadge(teacher),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      teacher.branchName,
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '담당 수강생 ${teacher.assignedStudentCount}명 · '
                      '${_workdaySummary(teacher.workHours)}',
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: secondaryColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(ManagedTeacher teacher) {
    final color = teacher.isActive
        ? (teacher.hasScheduledWithdrawal
            ? Colors.orange.shade700
            : primaryColor)
        : Colors.black45;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        teacher.statusLabel,
        style: forestringTextStyle.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _showDetails(ManagedTeacher teacher) async {
    var currentTeacher = teacher;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, setPageState) {
            Future<void> runAction(
              Future<void> Function(ManagedTeacher) action, {
              bool refreshTeacher = false,
            }) async {
              await action(currentTeacher);

              if (!refreshTeacher || !mounted || !pageContext.mounted) {
                return;
              }

              ManagedTeacher? refreshedTeacher;
              for (final item in _teachers) {
                if (item.id == currentTeacher.id) {
                  refreshedTeacher = item;
                  break;
                }
              }

              if (refreshedTeacher == null) {
                Navigator.of(pageContext).pop();
                return;
              }

              setPageState(() => currentTeacher = refreshedTeacher!);
            }

            return Scaffold(
              backgroundColor: neutralIvory,
              appBar: const ForestringAppBar(title: '선생님 관리'),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  children: [
                    Text(
                      currentTeacher.displayName,
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 23,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      currentTeacher.branchName,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '근무시간',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (currentTeacher.workHours.isEmpty)
                      _emptyWorkHours()
                    else
                      ...currentTeacher.workHours.map(_workHourRow),
                    const SizedBox(height: 18),
                    _detailActionSection(
                      title: '수업 정보',
                      actions: [
                        _detailActionButton(
                          icon: Icons.groups_2_outlined,
                          label:
                              '담당 수강생 ${currentTeacher.assignedStudentCount}명',
                          onPressed: () => runAction(
                            _showAssignedStudents,
                          ),
                        ),
                        _detailActionButton(
                          icon: Icons.bar_chart_outlined,
                          label: '학기별 수업 통계',
                          onPressed: () => runAction(
                            _showLessonStats,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _detailActionSection(
                      title: '일정 관리',
                      actions: [
                        _detailActionButton(
                          icon: Icons.event_busy_outlined,
                          label: '개인 일정 관리',
                          color: personalScheduleColor,
                          onPressed: () => runAction(
                            _showBlockedPeriods,
                          ),
                        ),
                        if (currentTeacher.isActive)
                          _detailActionButton(
                            icon: Icons.schedule_outlined,
                            label: '근무시간 변경',
                            onPressed: () => runAction(
                              _showWorkHoursEdit,
                              refreshTeacher: true,
                            ),
                          ),
                      ],
                    ),
                    if (currentTeacher.isActive) ...[
                      const SizedBox(height: 14),
                      _detailActionSection(
                        title: '계정 관리',
                        actions: [
                          _detailActionButton(
                            icon: Icons.drive_file_rename_outline,
                            label: '이름 수정',
                            onPressed: () => runAction(
                              _showNameEditDialog,
                              refreshTeacher: true,
                            ),
                          ),
                          _detailActionButton(
                            icon: Icons.lock_reset_outlined,
                            label: 'PIN 재설정',
                            onPressed: () => runAction(
                              _showPinResetDialog,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    _detailActionSection(
                      title: '재직 관리',
                      actions: [
                        _detailActionButton(
                          icon: currentTeacher.isActive
                              ? Icons.person_off_outlined
                              : Icons.badge_outlined,
                          label: currentTeacher.isActive
                              ? '퇴사 관리'
                              : '퇴사 정보',
                          color: Colors.red.shade700,
                          onPressed: () => runAction(
                            _showDeparture,
                            refreshTeacher: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    if (mounted) {
      await _loadTeachers();
    }
  }

  Widget _detailActionSection({
    required String title,
    required List<Widget> actions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: forestringTextStyle.copyWith(
            color: Colors.black54,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 7),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = actions.length == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - 8) / 2;

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: itemWidth,
                    height: 52,
                    child: action,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _detailActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color color = primaryColor,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
        textStyle: forestringTextStyle.copyWith(fontSize: 13),
      ),
    );
  }

  Future<void> _showNameEditDialog(ManagedTeacher teacher) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _TeacherNameEditDialog(
        teacher: teacher,
        repository: _repository,
      ),
    );

    if (!mounted || changed != true) return;
    await _loadTeachers();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이름이 변경되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showPinResetDialog(ManagedTeacher teacher) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _TeacherPinResetDialog(
        teacher: teacher,
        repository: _repository,
      ),
    );

    if (!mounted || changed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PIN이 변경되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showWorkHoursEdit(ManagedTeacher teacher) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TeacherWorkHoursEditPage(
          teacher: teacher,
          repository: widget.workHoursRepository,
        ),
      ),
    );

    if (!mounted || changed == null) return;

    if (changed) {
      await _loadTeachers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('근무시간이 변경되었습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('변경된 근무시간이 없습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showAssignedStudents(ManagedTeacher teacher) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TeacherAssignedStudentsPage(
          teacher: teacher,
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _showBlockedPeriods(ManagedTeacher teacher) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TeacherBlockedPeriodsPage(
          teacher: teacher,
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _showLessonStats(ManagedTeacher teacher) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TeacherLessonStatsPage(
          teacher: teacher,
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _showDeparture(ManagedTeacher teacher) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TeacherDeparturePage(
          teacher: teacher,
          repository: widget.repository,
        ),
      ),
    );

    if (!mounted) return;
    await _loadTeachers();
  }

  Widget _workHourRow(ManagedTeacherWorkHour workHour) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.13)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '${_weekdayLabel(workHour.weekday)}요일',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '${workHour.startTime} ~ ${workHour.endTime}',
            style: forestringTextStyle.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _emptyWorkHours() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.13)),
      ),
      child: Text(
        '등록된 근무시간이 없습니다.',
        style: forestringTextStyle.copyWith(color: Colors.black45),
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

  String _workdaySummary(List<ManagedTeacherWorkHour> workHours) {
    if (workHours.isEmpty) {
      return '근무시간 미등록';
    }

    final weekdays = workHours.map((item) => item.weekday).toSet().toList()
      ..sort();
    return '${weekdays.map(_weekdayLabel).join('·')} 근무';
  }

  String _weekdayLabel(int weekday) {
    return switch (weekday) {
      1 => '월',
      2 => '화',
      3 => '수',
      4 => '목',
      5 => '금',
      6 => '토',
      7 => '일',
      _ => '-',
    };
  }
}

class _TeacherNameEditDialog extends StatefulWidget {
  const _TeacherNameEditDialog({
    required this.teacher,
    required this.repository,
  });

  final ManagedTeacher teacher;
  final TeacherRepository repository;

  @override
  State<_TeacherNameEditDialog> createState() =>
      _TeacherNameEditDialogState();
}

class _TeacherNameEditDialogState extends State<_TeacherNameEditDialog> {
  late final TextEditingController _nameController;

  bool _saving = false;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.teacher.displayName);
    _nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _nameController.text.length,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final currentName = widget.teacher.displayName
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    if (name.isEmpty) {
      setState(() => _validationMessage = '이름을 입력해주세요.');
      return;
    }
    if (name.length > 100) {
      setState(() => _validationMessage = '이름은 100자 이하로 입력해주세요.');
      return;
    }
    if (name == currentName) {
      setState(() => _validationMessage = '현재 이름과 동일합니다.');
      return;
    }

    setState(() {
      _saving = true;
      _validationMessage = null;
    });

    try {
      await widget.repository.updateTeacherName(
        teacherId: widget.teacher.id,
        name: name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('선생님 이름 수정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '이름을 변경하면 선생님이 로그인할 때 사용하는 이름도 함께 변경됩니다.',
              style: forestringTextStyle.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              enabled: !_saving,
              autofocus: true,
              maxLength: 100,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_saving) _save();
              },
              decoration: const InputDecoration(
                labelText: '선생님 이름',
                border: OutlineInputBorder(),
              ),
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _validationMessage!,
                style: forestringTextStyle.copyWith(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ],
          ],
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
          child: Text(_saving ? '변경 중...' : '변경'),
        ),
      ],
    );
  }
}

class _TeacherPinResetDialog extends StatefulWidget {
  const _TeacherPinResetDialog({
    required this.teacher,
    required this.repository,
  });

  final ManagedTeacher teacher;
  final TeacherRepository repository;

  @override
  State<_TeacherPinResetDialog> createState() =>
      _TeacherPinResetDialogState();
}

class _TeacherPinResetDialogState extends State<_TeacherPinResetDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _saving = false;
  String? _validationMessage;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pinController.text.trim();
    final confirmPin = _confirmController.text.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _validationMessage = 'PIN은 4자리 숫자로 입력해주세요.');
      return;
    }
    if (pin != confirmPin) {
      setState(() => _validationMessage = 'PIN 확인 값이 일치하지 않습니다.');
      return;
    }

    setState(() {
      _saving = true;
      _validationMessage = null;
    });

    try {
      await widget.repository.resetTeacherPin(
        teacherId: widget.teacher.id,
        pin: pin,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PIN 재설정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.teacher.displayName} 선생님의 로그인 PIN을 변경합니다.',
              style: forestringTextStyle.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              enabled: !_saving,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(
                labelText: '새 PIN (4자리)',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmController,
              enabled: !_saving,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_saving) _save();
              },
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(
                labelText: '새 PIN 확인',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _validationMessage!,
                style: forestringTextStyle.copyWith(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ],
          ],
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
          child: Text(_saving ? '변경 중...' : '변경'),
        ),
      ],
    );
  }
}
