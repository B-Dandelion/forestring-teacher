import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../../core/widgets/management_filters.dart';
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
              _buildFilters(visibleTeachers.length),
              const SizedBox(height: 12),
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
              else
                ...visibleTeachers.map(_teacherCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(int visibleCount) {
    final filters = <Widget>[
      if (widget.profile.isMaster) _branchFilterPill(),
      _statusFilterPill(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ManagementSearchField(
          controller: _searchController,
          hintText: '선생님 이름 또는 지점 검색',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0;
                        index < filters.length;
                        index++) ...[
                      if (index > 0) const SizedBox(width: 7),
                      filters[index],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$visibleCount명',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ],
    );
  }

  Widget _statusFilterPill() {
    final label = switch (_statusFilter) {
      'all' => '전체 상태',
      'departed' => '퇴사',
      _ => '재직',
    };

    return _filterPill(
      label: label,
      value: _statusFilter,
      items: const [
        ('active', '재직'),
        ('departed', '퇴사'),
        ('all', '전체 상태'),
      ],
      onSelected: (value) {
        setState(() => _statusFilter = value);
      },
    );
  }

  Widget _branchFilterPill() {
    return PopupMenuButton<String>(
      initialValue: _branchId ?? _allBranches,
      onSelected: _loading
          ? null
          : (value) async {
              setState(() {
                _branchId =
                    value == _allBranches ? null : value;
              });
              await _loadTeachers();
            },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _allBranches,
          child: Text('전체 지점'),
        ),
        for (final branch in _branches)
          PopupMenuItem(
            value: branch.id,
            child: Text(branch.name),
          ),
      ],
      child: ManagementFilterPillSurface(
        label: _selectedBranchLabel(),
        icon: Icons.location_on_outlined,
      ),
    );
  }

  String _selectedBranchLabel() {
    final selected = _branchId;
    if (selected == null) return '전체 지점';
    for (final branch in _branches) {
      if (branch.id == selected) return branch.name;
    }
    return '전체 지점';
  }

  Widget _filterPill({
    required String label,
    required String value,
    required List<(String, String)> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem(
            value: item.$1,
            child: Text(item.$2),
          ),
      ],
      child: ManagementFilterPillSurface(label: label),
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

              if (!refreshTeacher ||
                  !mounted ||
                  !pageContext.mounted) {
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

              setPageState(
                () => currentTeacher = refreshedTeacher!,
              );
            }

            return Scaffold(
              backgroundColor: primaryColor,
              appBar: AppBar(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                centerTitle: true,
                systemOverlayStyle: SystemUiOverlayStyle.light,
                title: Text(
                  currentTeacher.displayName,
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
                  child: ListView(
                    padding:
                        const EdgeInsets.fromLTRB(12, 14, 12, 34),
                    children: [
                      _teacherProfileHeader(currentTeacher),
                      const SizedBox(height: 12),
                      _teacherWorkHoursCard(
                        currentTeacher,
                        onEdit: currentTeacher.isActive
                            ? () => runAction(
                                  _showWorkHoursEdit,
                                  refreshTeacher: true,
                                )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _teacherNavigationCard(
                        backgroundColor:
                            const Color(0xffEFF8F5),
                        borderColor:
                            const Color(0xffDDEFE7),
                        children: [
                          _teacherDetailRow(
                            icon: Icons.groups_2_rounded,
                            title: '담당 수강생',
                            value:
                                '${currentTeacher.assignedStudentCount}명',
                            color: const Color(0xff166B56),
                            onTap: () => runAction(
                              _showAssignedStudents,
                            ),
                          ),
                          _teacherCardDivider(),
                          _teacherDetailRow(
                            icon: Icons.bar_chart_rounded,
                            title: '학기별 수업 통계',
                            subtitle: '학기별 수업 진행 현황을 확인합니다.',
                            color: const Color(0xff166B56),
                            onTap: () => runAction(
                              _showLessonStats,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _teacherNavigationCard(
                        backgroundColor:
                            const Color(0xffFFF6EC),
                        borderColor:
                            const Color(0xffF4E5D5),
                        children: [
                          _teacherDetailRow(
                            icon: Icons.event_busy_rounded,
                            title: '개인 일정 관리',
                            subtitle: '휴무와 개인 일정을 관리합니다.',
                            color: const Color(0xffB36A2E),
                            onTap: () => runAction(
                              _showBlockedPeriods,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      _teacherSectionLabel('선생님 정보'),
                      const SizedBox(height: 7),
                      _teacherNavigationCard(
                        children: [
                          _teacherDetailRow(
                            icon: Icons.edit_rounded,
                            title: '이름',
                            value: currentTeacher.displayName,
                            color: const Color(0xff2B7A58),
                            onTap: currentTeacher.isActive
                                ? () => runAction(
                                      _showNameEditDialog,
                                      refreshTeacher: true,
                                    )
                                : null,
                          ),
                          _teacherCardDivider(),
                          _teacherDetailRow(
                            icon: Icons.location_on_rounded,
                            title: '지점',
                            value: currentTeacher.branchName,
                            color: const Color(0xff4D78A8),
                          ),
                        ],
                      ),
                      if (currentTeacher.isActive) ...[
                        const SizedBox(height: 15),
                        _teacherSectionLabel('계정'),
                        const SizedBox(height: 7),
                        _teacherNavigationCard(
                          backgroundColor:
                              const Color(0xffF7F5FB),
                          borderColor:
                              const Color(0xffECE8F5),
                          children: [
                            _teacherDetailRow(
                              icon: Icons.lock_reset_rounded,
                              title: '로그인 PIN 재설정',
                              subtitle:
                                  '선생님 앱 로그인 PIN을 변경합니다.',
                              color: const Color(0xff6C5CA5),
                              onTap: () => runAction(
                                _showPinResetDialog,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      _teacherNavigationCard(
                        backgroundColor: const Color(0xffFFF5F3),
                        borderColor: const Color(0xffF6E0DB),
                        children: [
                          _teacherDetailRow(
                            icon: currentTeacher.isActive
                                ? Icons.person_off_rounded
                                : Icons.badge_rounded,
                            title: currentTeacher.isActive
                                ? '퇴사 관리'
                                : '퇴사 정보',
                            subtitle: currentTeacher.hasScheduledWithdrawal &&
                                    currentTeacher.withdrawalDate != null
                                ? '퇴사 예정일이 등록되어 있습니다.'
                                : currentTeacher.isActive
                                    ? '퇴사일 지정 및 퇴사 처리를 관리합니다.'
                                    : '퇴사 처리 정보를 확인합니다.',
                            color: Colors.redAccent,
                            onTap: () => runAction(
                              _showDeparture,
                              refreshTeacher: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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

  Widget _teacherProfileHeader(ManagedTeacher teacher) {
    final statusColor = !teacher.isActive
        ? Colors.black54
        : teacher.hasScheduledWithdrawal
            ? Colors.orange.shade800
            : primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.055),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -30,
            bottom: -34,
            child: Container(
              width: 126,
              height: 126,
              decoration: const BoxDecoration(
                color: Color(0xffEAF5ED),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 7,
            child: Icon(
              Icons.school_rounded,
              size: 65,
              color: primaryColor.withValues(alpha: 0.11),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.11),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.badge_rounded,
                    color: primaryColor,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment:
                            WrapCrossAlignment.center,
                        children: [
                          Text(
                            teacher.displayName,
                            style: forestringTextStyle.copyWith(
                              color: Colors.black87,
                              fontSize: 25,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius:
                                  BorderRadius.circular(999),
                            ),
                            child: Text(
                              teacher.statusLabel,
                              style:
                                  forestringTextStyle.copyWith(
                                color: statusColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 16,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              teacher.branchName,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  forestringTextStyle.copyWith(
                                color: Colors.black54,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.groups_2_rounded,
                            size: 16,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '담당 수강생 ${teacher.assignedStudentCount}명',
                            style: forestringTextStyle.copyWith(
                              color: Colors.black54,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teacherWorkHoursCard(
    ManagedTeacher teacher, {
    VoidCallback? onEdit,
  }) {
    final grouped = <int, List<ManagedTeacherWorkHour>>{};
    for (final hour in teacher.workHours) {
      grouped.putIfAbsent(hour.weekday, () => []).add(hour);
    }
    for (final hours in grouped.values) {
      hours.sort(
        (a, b) => a.startTime.compareTo(b.startTime),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
      decoration: BoxDecoration(
        color: const Color(0xffF1F8F3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.10),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '근무시간',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${grouped.length}일 근무',
                style: forestringTextStyle.copyWith(
                  color: Colors.black45,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          if (grouped.isEmpty)
            Text(
              '등록된 근무시간이 없습니다.',
              style: forestringTextStyle.copyWith(
                color: Colors.black45,
                fontSize: 12.5,
              ),
            )
          else
            ...grouped.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _weekdayLabel(entry.key),
                        style: forestringTextStyle.copyWith(
                          color: primaryColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          entry.value
                              .map(
                                (hour) =>
                                    '${hour.startTime}–${hour.endTime}',
                              )
                              .join('  ·  '),
                          style: forestringTextStyle.copyWith(
                            color: Colors.black87,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (onEdit != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onEdit,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(
                Icons.edit_calendar_rounded,
                size: 19,
              ),
              label: Text(
                '근무시간 변경',
                style: forestringTextStyle.copyWith(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _teacherNavigationCard({
    required List<Widget> children,
    Color backgroundColor = Colors.white,
    Color? borderColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor ??
              primaryColor.withValues(alpha: 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _teacherDetailRow({
    required IconData icon,
    required String title,
    String? subtitle,
    String? value,
    VoidCallback? onTap,
    Color color = primaryColor,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 11,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: forestringTextStyle.copyWith(
                    color: color == primaryColor
                        ? Colors.black87
                        : color,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: forestringTextStyle.copyWith(
                      color: Colors.black45,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: forestringTextStyle.copyWith(
                  color: Colors.black54,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          const SizedBox(width: 5),
          if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              color: color.withValues(alpha: 0.70),
              size: 20,
            )
          else
            const SizedBox(width: 20),
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }

  Widget _teacherSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: primaryColor,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _teacherCardDivider() {
    return Divider(
      height: 1,
      indent: 59,
      color: primaryColor.withValues(alpha: 0.06),
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
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TeacherPinResetPage(
          teacher: teacher,
          repository: _repository,
        ),
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

class _TeacherPinResetPage extends StatefulWidget {
  const _TeacherPinResetPage({
    required this.teacher,
    required this.repository,
  });

  final ManagedTeacher teacher;
  final TeacherRepository repository;

  @override
  State<_TeacherPinResetPage> createState() =>
      _TeacherPinResetPageState();
}

class _TeacherPinResetPageState extends State<_TeacherPinResetPage> {
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
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _validationMessage = 'PIN은 4자리 숫자로 입력해주세요.');
      return;
    }
    if (pin != _confirmController.text.trim()) {
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
    return _TeacherEditScaffold(
      title: '로그인 PIN 재설정',
      saving: _saving,
      actionLabel: 'PIN 저장',
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TeacherEditHeader(
            teacher: widget.teacher,
            description: '선생님 앱 로그인에 사용할 새로운 4자리 PIN을 설정합니다.',
          ),
          const SizedBox(height: 12),
          _TeacherEditCard(
            child: Column(
              children: [
                TextField(
                  controller: _pinController,
                  enabled: !_saving,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: _teacherEditDecoration('새 PIN').copyWith(
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _confirmController,
                  enabled: !_saving,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration:
                      _teacherEditDecoration('새 PIN 확인').copyWith(
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          if (_validationMessage != null) ...[
            const SizedBox(height: 10),
            _TeacherEditMessage(
              message: _validationMessage!,
              isError: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _TeacherEditScaffold extends StatelessWidget {
  const _TeacherEditScaffold({
    required this.title,
    required this.child,
    required this.saving,
    required this.actionLabel,
    required this.onSave,
  });

  final String title;
  final Widget child;
  final bool saving;
  final String actionLabel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: AppBar(
        backgroundColor: neutralIvory,
        foregroundColor: primaryColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          title,
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 19,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
          children: [child],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: FilledButton(
            onPressed: saving ? null : onSave,
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              saving ? '저장 중...' : actionLabel,
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
}

class _TeacherEditHeader extends StatelessWidget {
  const _TeacherEditHeader({
    required this.teacher,
    required this.description,
  });

  final ManagedTeacher teacher;
  final String description;

  @override
  Widget build(BuildContext context) {
    return _TeacherEditCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            teacher.displayName,
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 22,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${teacher.branchName} · ${teacher.statusLabel}',
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherEditCard extends StatelessWidget {
  const _TeacherEditCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TeacherEditMessage extends StatelessWidget {
  const _TeacherEditMessage({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.redAccent : primaryColor;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: isError ? Colors.redAccent : Colors.black87,
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }
}

InputDecoration _teacherEditDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: primaryColor.withValues(alpha: 0.035),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide.none,
    ),
  );
}
