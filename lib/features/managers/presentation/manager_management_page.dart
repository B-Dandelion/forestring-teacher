import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../../teachers/data/teacher_repository.dart';
import '../../teachers/presentation/teacher_assigned_students_page.dart';
import '../../teachers/presentation/teacher_blocked_periods_page.dart';
import '../../teachers/presentation/teacher_lesson_stats_page.dart';
import '../../teachers/presentation/teacher_work_hours_edit_page.dart';
import '../data/manager_repository.dart';
import 'manager_create_page.dart';
import 'manager_departure_page.dart';

class ManagerManagementPage extends StatefulWidget {
  const ManagerManagementPage({super.key});

  @override
  State<ManagerManagementPage> createState() =>
      _ManagerManagementPageState();
}

class _ManagerManagementPageState extends State<ManagerManagementPage> {
  static const _allBranches = '__all__';

  final _repository = ManagerRepository();
  final _branchRepository = BranchRepository();
  final _searchController = TextEditingController();

  List<ManagedManager> _managers = const [];
  List<AcademyBranch> _branches = const [];
  String _branchFilter = _allBranches;
  String _statusFilter = 'active';
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _repository.fetchManagers(),
        _branchRepository.fetchBranches(),
      ]);

      if (!mounted) return;

      final branches = (results[1] as List<AcademyBranch>).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _managers = results[0] as List<ManagedManager>;
        _branches = branches;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ManagerFailure
            ? error.message
            : '지점장 정보를 불러오지 못했습니다.\n$error';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ManagedManager> get _visibleManagers {
    final query = _searchController.text.trim().toLowerCase();

    return _managers.where((manager) {
      if (_branchFilter != _allBranches && manager.branchId != _branchFilter) {
        return false;
      }
      if (_statusFilter == 'active' && !manager.isActive) return false;
      if (_statusFilter == 'departed' && manager.isActive) return false;
      if (query.isEmpty) return true;

      return manager.displayName.toLowerCase().contains(query) ||
          manager.branchName.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const ManagerCreatePage(),
      ),
    );

    if (created != true || !mounted) return;

    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('지점장을 등록했습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openDetails(ManagedManager manager) async {
    var currentManager = manager;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, setPageState) {
            Future<void> runAction(
              Future<void> Function(ManagedManager) action, {
              bool refreshManager = false,
            }) async {
              await action(currentManager);

              if (!refreshManager || !mounted || !pageContext.mounted) {
                return;
              }

              ManagedManager? refreshedManager;
              for (final item in _managers) {
                if (item.id == currentManager.id) {
                  refreshedManager = item;
                  break;
                }
              }

              if (refreshedManager == null) {
                Navigator.of(pageContext).pop();
                return;
              }

              setPageState(() => currentManager = refreshedManager!);
            }

            return Scaffold(
              backgroundColor: neutralIvory,
              appBar: const ForestringAppBar(title: '지점장 관리'),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  children: [
                    Text(
                      currentManager.displayName,
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 23,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      currentManager.branchName,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                    if (currentManager.teachesLessons) ...[
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
                      ...currentManager.workHours.map(_workHourRow),
                      const SizedBox(height: 18),
                      _detailActionSection(
                        title: '수업 정보',
                        actions: [
                          _detailActionButton(
                            icon: Icons.groups_2_outlined,
                            label:
                                '담당 수강생 ${currentManager.assignedStudentCount}명',
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
                          if (currentManager.isActive)
                            _detailActionButton(
                              icon: Icons.schedule_outlined,
                              label: '근무시간 변경',
                              onPressed: () => runAction(
                                _showWorkHoursEdit,
                                refreshManager: true,
                              ),
                            ),
                        ],
                      ),
                    ] else if (currentManager.isActive) ...[
                      const SizedBox(height: 20),
                      _detailActionSection(
                        title: '수업 정보',
                        actions: [
                          _detailActionButton(
                            icon: Icons.add_business_outlined,
                            label: '수업 정보 등록',
                            onPressed: () => runAction(
                              _showTeachingRegistration,
                              refreshManager: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '근무시간을 등록하면 담당 수강생과 수업 일정 관리 기능을 사용할 수 있습니다.',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (currentManager.isActive) ...[
                      const SizedBox(height: 14),
                      _detailActionSection(
                        title: '계정 관리',
                        actions: [
                          _detailActionButton(
                            icon: Icons.drive_file_rename_outline,
                            label: '이름 수정',
                            onPressed: () => runAction(
                              _showNameEditDialog,
                              refreshManager: true,
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
                      const SizedBox(height: 14),
                      _detailActionSection(
                        title: '지점 관리',
                        actions: [
                          _detailActionButton(
                            icon: Icons.store_mall_directory_outlined,
                            label: '담당 지점 변경',
                            onPressed: currentManager.hasScheduledWithdrawal
                                ? null
                                : () => runAction(
                                      _showBranchChangeDialog,
                                      refreshManager: true,
                                    ),
                          ),
                        ],
                      ),
                      if (currentManager.hasScheduledWithdrawal) ...[
                        const SizedBox(height: 8),
                        Text(
                          '퇴사 예정인 지점장은 담당 지점을 변경할 수 없습니다.',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black45,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 14),
                    _detailActionSection(
                      title: '재직 관리',
                      actions: [
                        _detailActionButton(
                          icon: currentManager.isActive
                              ? Icons.person_off_outlined
                              : Icons.badge_outlined,
                          label: currentManager.isActive
                              ? '퇴사 관리'
                              : '퇴사 정보',
                          color: Colors.red.shade700,
                          onPressed: () => runAction(
                            _showDeparture,
                            refreshManager: true,
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

    if (mounted) await _load();
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
    required VoidCallback? onPressed,
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
        disabledForegroundColor: Colors.black38,
        side: BorderSide(
          color: onPressed == null ? Colors.black26 : color,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
        textStyle: forestringTextStyle.copyWith(fontSize: 13),
      ),
    );
  }

  ManagedTeacher _asManagedTeacher(ManagedManager manager) {
    return ManagedTeacher(
      id: manager.id,
      displayName: manager.displayName,
      branchId: manager.branchId.isEmpty ? null : manager.branchId,
      branchName: manager.branchName,
      profileIsActive: manager.isActive,
      workHours: manager.workHours
          .map(
            (workHour) => ManagedTeacherWorkHour(
              weekday: workHour.weekday,
              startTime: workHour.startTime,
              endTime: workHour.endTime,
            ),
          )
          .toList(growable: false),
      assignedStudentCount: manager.assignedStudentCount,
      withdrawalDate: manager.withdrawalDate,
    );
  }

  Future<void> _showTeachingRegistration(ManagedManager manager) async {
    await _openWorkHoursEditor(
      manager,
      registration: true,
    );
  }

  Future<void> _showWorkHoursEdit(ManagedManager manager) async {
    await _openWorkHoursEditor(
      manager,
      registration: false,
    );
  }

  Future<void> _openWorkHoursEditor(
    ManagedManager manager, {
    required bool registration,
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TeacherWorkHoursEditPage(
          teacher: _asManagedTeacher(manager),
          title: registration ? '수업 정보 등록' : '근무시간 변경',
        ),
      ),
    );

    if (!mounted || changed == null) return;

    if (changed) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            registration ? '수업 정보를 등록했습니다.' : '근무시간이 변경되었습니다.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          registration ? '등록된 수업 정보가 없습니다.' : '변경된 근무시간이 없습니다.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showAssignedStudents(ManagedManager manager) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TeacherAssignedStudentsPage(
          teacher: _asManagedTeacher(manager),
        ),
      ),
    );
  }

  Future<void> _showBlockedPeriods(ManagedManager manager) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TeacherBlockedPeriodsPage(
          teacher: _asManagedTeacher(manager),
        ),
      ),
    );
  }

  Future<void> _showLessonStats(ManagedManager manager) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TeacherLessonStatsPage(
          teacher: _asManagedTeacher(manager),
        ),
      ),
    );
  }

  Future<void> _showNameEditDialog(ManagedManager manager) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _ManagerNameEditDialog(
        manager: manager,
        repository: _repository,
      ),
    );

    if (!mounted || changed != true) return;

    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이름이 변경되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showPinResetDialog(ManagedManager manager) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _ManagerPinResetDialog(
        manager: manager,
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

  Future<void> _showBranchChangeDialog(ManagedManager manager) async {
    final activeBranches = _branches.where((branch) => branch.isActive).toList();

    if (activeBranches.isEmpty) {
      _showMessage('변경할 수 있는 운영 지점이 없습니다.');
      return;
    }

    var selectedId = manager.branchId;
    if (!activeBranches.any((branch) => branch.id == selectedId)) {
      selectedId = activeBranches.first.id;
    }

    final branchId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('담당 지점 변경'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedId,
            decoration: const InputDecoration(
              labelText: '담당 지점',
              border: OutlineInputBorder(),
            ),
            items: activeBranches
                .map(
                  (branch) => DropdownMenuItem(
                    value: branch.id,
                    child: Text(branch.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setDialogState(() => selectedId = value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(selectedId),
              style: FilledButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('다음'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (branchId == null || branchId == manager.branchId) return;

    final targetBranch = activeBranches.firstWhere(
      (branch) => branch.id == branchId,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('담당 지점 변경'),
        content: Text(
          '${manager.displayName} 지점장의 담당 지점을\n'
          '${manager.branchName} → ${targetBranch.name}(으)로 변경할까요?\n\n'
          '직접 담당 중인 학생, 정규 일정 또는 예정 수업이 남아 있으면 변경되지 않습니다.',
          style: forestringTextStyle.copyWith(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            child: const Text('변경'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _repository.changeManagerBranch(
        managerId: manager.id,
        branchId: branchId,
      );
      if (!mounted) return;

      await _load();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('담당 지점을 변경했습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ManagerFailure catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    }
  }

  Future<void> _showDeparture(ManagedManager manager) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManagerDeparturePage(manager: manager),
      ),
    );

    if (!mounted) return;
    await _load();
  }

  Widget _workHourRow(ManagedManagerWorkHour workHour) {
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleManagers = _visibleManagers;
    final activeCount =
        _managers.where((manager) => manager.isActive).length;
    final teachingCount = _managers
        .where((manager) => manager.isActive && manager.teachesLessons)
        .length;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '지점장 관리',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        onPressed: _loading ? null : _openCreate,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(
          '지점장 등록',
          style: forestringTextStyle.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
            children: [
              _summaryCard(
                activeCount: activeCount,
                teachingCount: teachingCount,
              ),
              const SizedBox(height: 12),
              _buildFilters(visibleManagers.length),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                _errorCard(_errorMessage!),
              ],
              const SizedBox(height: 14),
              if (_loading && _managers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 72),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visibleManagers.isEmpty)
                _emptyCard()
              else
                ...visibleManagers.map(_managerCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard({
    required int activeCount,
    required int teachingCount,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xffEEF1F8),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.admin_panel_settings_outlined,
              color: Color(0xff5E6F9B),
              size: 23,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '지점장 운영 현황',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _loading
                      ? '지점장 정보를 불러오는 중입니다.'
                      : '재직 $activeCount명 · 수업 담당 $teachingCount명',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black45,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(int visibleCount) {
    var branchLabel = '전체 지점';
    if (_branchFilter != _allBranches) {
      for (final branch in _branches) {
        if (branch.id == _branchFilter) {
          branchLabel = branch.name;
          break;
        }
      }
    }
    final statusLabel = switch (_statusFilter) {
      'all' => '전체 상태',
      'departed' => '퇴사',
      _ => '재직',
    };

    return Column(
      children: [
        TextField(
          controller: _searchController,
          onTapOutside: (_) =>
              FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(
            hintText: '지점장 이름 또는 지점 검색',
            hintStyle: forestringTextStyle.copyWith(
              color: Colors.black38,
              fontSize: 12,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: primaryColor,
              size: 19,
            ),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                    ),
                  ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.94),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: primaryColor.withValues(alpha: 0.07),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: primaryColor.withValues(alpha: 0.07),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: primaryColor.withValues(alpha: 0.22),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            PopupMenuButton<String>(
              initialValue: _branchFilter,
              onSelected: (value) =>
                  setState(() => _branchFilter = value),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _allBranches,
                  child: Text('전체 지점'),
                ),
                ..._branches.map(
                  (branch) => PopupMenuItem(
                    value: branch.id,
                    child: Text(branch.name),
                  ),
                ),
              ],
              child: _ManagerFilterPill(
                icon: Icons.storefront_outlined,
                label: branchLabel,
              ),
            ),
            const SizedBox(width: 7),
            PopupMenuButton<String>(
              initialValue: _statusFilter,
              onSelected: (value) =>
                  setState(() => _statusFilter = value),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'all',
                  child: Text('전체 상태'),
                ),
                PopupMenuItem(
                  value: 'active',
                  child: Text('재직'),
                ),
                PopupMenuItem(
                  value: 'departed',
                  child: Text('퇴사'),
                ),
              ],
              child: _ManagerFilterPill(
                icon: Icons.badge_outlined,
                label: statusLabel,
              ),
            ),
            const Spacer(),
            Text(
              '$visibleCount명',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _managerCard(ManagedManager manager) {
    final statusColor = manager.isActive
        ? (manager.hasScheduledWithdrawal
            ? const Color(0xffA87524)
            : primaryColor)
        : Colors.black45;
    final surfaceColor = manager.isActive
        ? const Color(0xffEEF1F8)
        : const Color(0xffEFEFED);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: () => _openDetails(manager),
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.07),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.badge_outlined,
                    color: statusColor,
                    size: 23,
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
                              manager.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: forestringTextStyle.copyWith(
                                color: manager.isActive
                                    ? Colors.black87
                                    : Colors.black54,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          _statusBadge(manager),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.storefront_outlined,
                            color: Colors.black38,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              manager.branchName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: forestringTextStyle.copyWith(
                                color: Colors.black54,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        manager.teachesLessons
                            ? '담당 수강생 ${manager.assignedStudentCount}명 · '
                                '${_workdaySummary(manager.workHours)}'
                            : '수업 업무 미등록',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: forestringTextStyle.copyWith(
                          color: manager.teachesLessons
                              ? primaryColor
                              : Colors.black38,
                          fontSize: 10.5,
                          fontWeight: manager.teachesLessons
                              ? FontWeight.w500
                              : FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.black38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.admin_panel_settings_outlined,
            color: primaryColor.withValues(alpha: 0.35),
            size: 30,
          ),
          const SizedBox(height: 9),
          Text(
            '조건에 맞는 지점장이 없습니다.',
            style: forestringTextStyle.copyWith(
              color: Colors.black45,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(ManagedManager manager) {
    final color = manager.isActive
        ? (manager.hasScheduledWithdrawal
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
        manager.statusLabel,
        style: forestringTextStyle.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
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

  String _workdaySummary(List<ManagedManagerWorkHour> workHours) {
    if (workHours.isEmpty) return '근무시간 미등록';

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

class _ManagerFilterPill extends StatelessWidget {
  const _ManagerFilterPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: primaryColor, size: 15),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: forestringTextStyle.copyWith(
                color: Colors.black87,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 3),
          const Icon(
            Icons.expand_more_rounded,
            color: Colors.black38,
            size: 16,
          ),
        ],
      ),
    );
  }
}

class _ManagerNameEditDialog extends StatefulWidget {
  const _ManagerNameEditDialog({
    required this.manager,
    required this.repository,
  });

  final ManagedManager manager;
  final ManagerRepository repository;

  @override
  State<_ManagerNameEditDialog> createState() =>
      _ManagerNameEditDialogState();
}

class _ManagerNameEditDialogState extends State<_ManagerNameEditDialog> {
  late final TextEditingController _nameController;

  bool _saving = false;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.manager.displayName);
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
    final currentName = widget.manager.displayName
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
      await widget.repository.updateManagerName(
        managerId: widget.manager.id,
        name: name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ManagerFailure catch (error) {
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
      title: const Text('지점장 이름 수정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '이름을 변경하면 지점장이 로그인할 때 사용하는 이름도 함께 변경됩니다.',
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
                labelText: '지점장 이름',
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

class _ManagerPinResetDialog extends StatefulWidget {
  const _ManagerPinResetDialog({
    required this.manager,
    required this.repository,
  });

  final ManagedManager manager;
  final ManagerRepository repository;

  @override
  State<_ManagerPinResetDialog> createState() =>
      _ManagerPinResetDialogState();
}

class _ManagerPinResetDialogState extends State<_ManagerPinResetDialog> {
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
      await widget.repository.resetManagerPin(
        managerId: widget.manager.id,
        pin: pin,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ManagerFailure catch (error) {
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
              '${widget.manager.displayName} 지점장의 로그인 PIN을 변경합니다.',
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
