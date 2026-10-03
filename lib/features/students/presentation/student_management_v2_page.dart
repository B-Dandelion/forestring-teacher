import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../../lessons/data/lesson_repository.dart';
import '../data/student_admin_repository.dart';
import '../data/student_management_repository.dart';
import '../data/student_next_semester_type_repository.dart';
import '../data/student_regular_schedule_repository.dart';
import '../data/student_teacher_management_repository.dart';
import 'student_create_page.dart';
import 'student_lesson_history_page.dart';
import 'student_next_semester_type_dialog.dart';
import 'student_regular_schedule_page.dart';
import 'student_teacher_change_dialog.dart';
import 'student_withdrawal_dialog.dart';

class StudentManagementV2Page extends StatefulWidget {
  const StudentManagementV2Page({
    super.key,
    required this.profile,
    this.repository,
    this.branchRepository,
    this.lessonRepository,
    this.adminRepository,
    this.nextSemesterRepository,
    this.regularScheduleRepository,
    this.teacherManagementRepository,
    this.embeddedInShell = false,
  });

  final CurrentProfile profile;
  final StudentManagementRepository? repository;
  final BranchRepository? branchRepository;
  final LessonRepository? lessonRepository;
  final StudentAdminRepository? adminRepository;
  final StudentNextSemesterTypeRepository? nextSemesterRepository;
  final StudentRegularScheduleRepository? regularScheduleRepository;
  final StudentTeacherManagementRepository? teacherManagementRepository;
  final bool embeddedInShell;

  @override
  State<StudentManagementV2Page> createState() =>
      _StudentManagementV2PageState();
}

class _StudentManagementV2PageState extends State<StudentManagementV2Page> {
  static const _allBranches = '__all__';
  static const _memoKeyPrefix = 'forestring.student.memo.v1.';

  late final StudentManagementRepository _repository;
  late final BranchRepository _branchRepository;
  final _searchController = TextEditingController();

  List<AcademyBranch> _branches = const [];
  List<ManagedStudent> _students = const [];
  final Map<String, String> _localMemos = {};
  SharedPreferences? _preferences;
  String? _branchId;
  String _typeFilter = 'all';
  String _statusFilter = 'active';
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? StudentManagementRepository();
    _branchRepository =
        widget.branchRepository ?? BranchRepository();
    _searchController.addListener(_onSearchChanged);
    _loadLocalMemos();
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
    if (mounted) setState(() {});
  }

  Future<void> _loadLocalMemos() async {
    final preferences = await SharedPreferences.getInstance();
    final memos = <String, String>{};

    for (final key in preferences.getKeys()) {
      if (!key.startsWith(_memoKeyPrefix)) continue;
      final value = preferences.getString(key)?.trim();
      if (value == null || value.isEmpty) continue;
      memos[key.substring(_memoKeyPrefix.length)] = value;
    }

    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _localMemos
        ..clear()
        ..addAll(memos);
    });
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
      final branchId =
          widget.profile.isManager ? widget.profile.branchId : null;

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _branchId = branchId;
      });
      await _loadStudents();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            '수강생 관리 화면을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStudents() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final students =
          await _repository.fetchStudents(branchId: _branchId);
      if (!mounted) return;
      setState(() => _students = students);
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _students = const [];
        _errorMessage = error.message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ManagedStudent> get _visibleStudents {
    final query = _searchController.text.trim().toLowerCase();
    return _students.where((student) {
      if (_typeFilter != 'all' &&
          student.studentType != _typeFilter) {
        return false;
      }
      if (_statusFilter == 'active' && !student.isActive) {
        return false;
      }
      if (_statusFilter == 'withdrawn' && student.isActive) {
        return false;
      }
      if (query.isEmpty) return true;
      return student.displayName.toLowerCase().contains(query) ||
          (student.teacherName ?? '').toLowerCase().contains(query) ||
          student.branchName.toLowerCase().contains(query) ||
          (_localMemos[student.id] ?? '')
              .toLowerCase()
              .contains(query);
    }).toList();
  }

  Future<void> _openRegistration() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentCreatePage(
          profile: widget.profile,
          branchRepository: widget.branchRepository,
          repository: widget.adminRepository,
        ),
      ),
    );
    if (mounted) await _loadStudents();
  }

  Future<void> _openStudent(ManagedStudent student) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StudentManagementDetailPage(
          profile: widget.profile,
          initialStudent: student,
          repository: widget.repository,
          branchRepository: widget.branchRepository,
          lessonRepository: widget.lessonRepository,
          nextSemesterRepository: widget.nextSemesterRepository,
          regularScheduleRepository: widget.regularScheduleRepository,
          teacherManagementRepository:
              widget.teacherManagementRepository,
        ),
      ),
    );
    if (mounted) await _loadStudents();
  }

  Future<void> _editLocalMemo(ManagedStudent student) async {
    final initial = _localMemos[student.id] ?? '';
    final next = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      requestFocus: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (_) => _StudentMemoSheet(
        studentName: student.displayName,
        initialValue: initial,
      ),
    );

    if (!mounted || next == null) return;

    final preferences =
        _preferences ?? await SharedPreferences.getInstance();
    final key = _memoKeyPrefix + student.id;

    if (next.isEmpty) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, next);
    }

    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      if (next.isEmpty) {
        _localMemos.remove(student.id);
      } else {
        _localMemos[student.id] = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleStudents = _visibleStudents;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: widget.embeddedInShell
          ? null
          : ForestringAppBar(
              title: '수강생 관리',
              actions: [
                IconButton(
                  tooltip: '새로고침',
                  onPressed: _loading ? null : _loadStudents,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: _openRegistration,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          '수강생 등록',
          style: forestringTextStyle.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadStudents,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 100),
            children: [
              _buildFilters(visibleStudents.length),
              const SizedBox(height: 12),
              if (_errorMessage != null) ...[
                _errorCard(_errorMessage!),
                const SizedBox(height: 12),
              ],
              if (_loading && _students.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (visibleStudents.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(
                    child: Text(
                      '조건에 맞는 수강생이 없습니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),
                )
              else
                ...visibleStudents.map(_studentCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(int visibleCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.07),
            ),
          ),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onTapOutside: (_) =>
                FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: '수강생 이름 또는 선생님 검색',
              hintStyle: forestringTextStyle.copyWith(
                color: Colors.black38,
                fontSize: 13,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: primaryColor,
                size: 21,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '검색어 지우기',
                      onPressed: _searchController.clear,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 19,
                      ),
                    ),
              filled: true,
              fillColor: Colors.transparent,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 13),
              border: InputBorder.none,
            ),
          ),
        ),
        if (widget.profile.isMaster) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _branchFilterPill(),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            _statusFilterPill(),
            const SizedBox(width: 7),
            _typeFilterPill(),
            const Spacer(),
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
      'withdrawn' => '퇴원',
      _ => '재원',
    };

    return _filterPill(
      label: label,
      value: _statusFilter,
      items: const [
        ('active', '재원'),
        ('withdrawn', '퇴원'),
        ('all', '전체 상태'),
      ],
      onSelected: (value) {
        setState(() => _statusFilter = value);
      },
    );
  }

  Widget _typeFilterPill() {
    final label = switch (_typeFilter) {
      'regular' => '정규',
      'flex' => '자율 예약',
      _ => '전체 형태',
    };

    return _filterPill(
      label: label,
      value: _typeFilter,
      items: const [
        ('all', '전체 형태'),
        ('regular', '정규'),
        ('flex', '자율 예약'),
      ],
      onSelected: (value) {
        setState(() => _typeFilter = value);
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
              await _loadStudents();
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
      child: _FilterPillSurface(
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
      child: _FilterPillSurface(label: label),
    );
  }

  Widget _studentCard(ManagedStudent student) {
    final memo = _localMemos[student.id]?.trim();
    final typeColor =
        student.isRegular ? primaryColor : const Color(0xff4B7892);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.065),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: () => _openStudent(student),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  13,
                  12,
                  9,
                  memo == null || memo.isEmpty ? 12 : 9,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 43,
                      height: 43,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.09),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        color: typeColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  student.displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      forestringTextStyle.copyWith(
                                    color: Colors.black87,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              _typeBadge(student),
                              if (!student.isActive ||
                                  student.hasScheduledWithdrawal) ...[
                                const SizedBox(width: 5),
                                _statusBadge(student),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          _infoLine(
                            Icons.person_rounded,
                            _teacherLine(student),
                            color: student.teacherName == null
                                ? Colors.black45
                                : Colors.black54,
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: primaryColor,
                        size: 21,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (memo != null && memo.isNotEmpty)
              InkWell(
                onTap: () => _editLocalMemo(student),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(67, 0, 30, 11),
                  child: _infoLine(
                    Icons.sticky_note_2_outlined,
                    memo,
                    color: secondaryColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _teacherLine(ManagedStudent student) {
    final teacher = student.teacherName == null
        ? '담당 선생님 미배정'
        : '${student.teacherName} 선생님';
    if (!widget.profile.isMaster) return teacher;
    return '$teacher · ${student.branchName}';
  }

  Widget _infoLine(
    IconData icon,
    String text, {
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: forestringTextStyle.copyWith(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w400,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  Widget _typeBadge(ManagedStudent student) {
    final color =
        student.isRegular ? primaryColor : const Color(0xff4B7892);
    final label = student.isRegular ? '정규' : '자율';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _statusBadge(ManagedStudent student) {
    final color = student.isActive
        ? Colors.orange.shade700
        : Colors.black45;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        student.statusLabel,
        style: forestringTextStyle.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(
          color: Colors.redAccent,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StudentMemoSheet extends StatefulWidget {
  const _StudentMemoSheet({
    required this.studentName,
    required this.initialValue,
  });

  final String studentName;
  final String initialValue;

  @override
  State<_StudentMemoSheet> createState() => _StudentMemoSheetState();
}

class _StudentMemoSheetState extends State<_StudentMemoSheet> {
  late final TextEditingController _controller;

  bool get _changed =>
      _controller.text.trim() != widget.initialValue.trim();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue)
      ..addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!_changed) return;
    final value = _controller.text.trim();
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            decoration: BoxDecoration(
              color: const Color(0xffFCFDF9),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.07),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.studentName} 메모',
                        style: forestringTextStyle.copyWith(
                          color: primaryColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _controller,
                  autofocus: false,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 120,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: '학생을 기억하기 위한 메모를 입력하세요.',
                    filled: true,
                    fillColor: primaryColor.withValues(alpha: 0.045),
                    helperText: '이 메모는 이 휴대폰에만 저장됩니다.',
                    helperStyle: forestringTextStyle.copyWith(
                      color: Colors.black45,
                      fontSize: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FilledButton(
                  onPressed: _changed ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        primaryColor.withValues(alpha: 0.13),
                    disabledForegroundColor:
                        Colors.black.withValues(alpha: 0.28),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    widget.initialValue.isEmpty ? '메모 저장' : '변경 저장',
                    style: forestringTextStyle.copyWith(
                      color: _changed
                          ? Colors.white
                          : Colors.black.withValues(alpha: 0.28),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterPillSurface extends StatelessWidget {
  const _FilterPillSurface({
    required this.label,
    this.icon,
  });

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: primaryColor),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: forestringTextStyle.copyWith(
              color: Colors.black.withValues(alpha: 0.72),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.expand_more_rounded,
            size: 17,
            color: primaryColor,
          ),
        ],
      ),
    );
  }
}

class StudentManagementDetailPage extends StatefulWidget {
  const StudentManagementDetailPage({
    super.key,
    required this.profile,
    required this.initialStudent,
    this.repository,
    this.branchRepository,
    this.lessonRepository,
    this.nextSemesterRepository,
    this.regularScheduleRepository,
    this.teacherManagementRepository,
  });

  final CurrentProfile profile;
  final ManagedStudent initialStudent;
  final StudentManagementRepository? repository;
  final BranchRepository? branchRepository;
  final LessonRepository? lessonRepository;
  final StudentNextSemesterTypeRepository? nextSemesterRepository;
  final StudentRegularScheduleRepository? regularScheduleRepository;
  final StudentTeacherManagementRepository? teacherManagementRepository;

  @override
  State<StudentManagementDetailPage> createState() =>
      _StudentManagementDetailPageState();
}

class _StudentManagementDetailPageState
    extends State<StudentManagementDetailPage> {
  late final StudentManagementRepository _repository;
  late final StudentNextSemesterTypeRepository
      _nextSemesterRepository;
  late final StudentRegularScheduleRepository
      _regularScheduleRepository;

  late ManagedStudent _student;
  NextSemesterStudentTypePlan? _nextPlan;
  List<ManagedRegularSchedule> _regularSchedules = const [];
  bool _regularSchedulesLoading = false;
  bool _refreshing = false;
  bool _nextPlanLoading = false;
  String? _nextPlanError;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? StudentManagementRepository();
    _nextSemesterRepository = widget.nextSemesterRepository ??
        StudentNextSemesterTypeRepository();
    _regularScheduleRepository = widget.regularScheduleRepository ??
        StudentRegularScheduleRepository();
    _student = widget.initialStudent;
    _loadNextPlan();
    _loadRegularSchedules();
  }

  Future<void> _refreshStudent() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final students = await _repository.fetchStudents(
        branchId: _student.branchId,
      );
      ManagedStudent? refreshed;
      for (final student in students) {
        if (student.id == _student.id) {
          refreshed = student;
          break;
        }
      }
      if (!mounted) return;
      if (refreshed == null) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _student = refreshed!);
      await Future.wait([
        _loadNextPlan(),
        _loadRegularSchedules(),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _loadNextPlan() async {
    if (!_student.isActive) {
      if (mounted) {
        setState(() {
          _nextPlan = null;
          _nextPlanError = null;
          _nextPlanLoading = false;
        });
      }
      return;
    }

    setState(() {
      _nextPlanLoading = true;
      _nextPlanError = null;
    });
    try {
      final plan = await _nextSemesterRepository.fetchPlan(_student.id);
      if (!mounted) return;
      setState(() => _nextPlan = plan);
    } on StudentNextSemesterTypeFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _nextPlan = null;
        _nextPlanError = error.message;
      });
    } finally {
      if (mounted) setState(() => _nextPlanLoading = false);
    }
  }

  Future<void> _loadRegularSchedules() async {
    if (!_student.isActive || !_student.isRegular) {
      if (mounted) {
        setState(() {
          _regularSchedules = const [];
          _regularSchedulesLoading = false;
        });
      }
      return;
    }

    setState(() => _regularSchedulesLoading = true);
    try {
      final schedules =
          await _regularScheduleRepository.fetchSchedules(_student.id);
      if (!mounted) return;
      setState(() => _regularSchedules = schedules);
    } on StudentRegularScheduleFailure {
      if (!mounted) return;
      setState(() => _regularSchedules = const []);
    } finally {
      if (mounted) {
        setState(() => _regularSchedulesLoading = false);
      }
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
        centerTitle: true,
        title: Text(
          _student.displayName,
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _refreshing ? null : _refreshStudent,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refreshStudent,
          color: primaryColor,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 34),
            children: [
              _profileHeader(),
              const SizedBox(height: 12),
              if (_student.isActive) ...[
                _currentSemesterCard(),
                const SizedBox(height: 12),
                _nextSemesterCard(),
                const SizedBox(height: 12),
              ],
              _navigationCard(
                children: [
                  _detailRow(
                    icon: Icons.receipt_long_outlined,
                    title: '수업 내역',
                    subtitle: '이번 학기 · 이전 학기 · 전체',
                    onTap: _openLessonHistory,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _sectionLabel('학생 정보'),
              const SizedBox(height: 7),
              _navigationCard(
                children: [
                  _detailRow(
                    icon: Icons.drive_file_rename_outline,
                    title: '이름',
                    value: _student.displayName,
                    onTap: _student.isActive ? _changeName : null,
                  ),
                  _cardDivider(),
                  _detailRow(
                    icon: Icons.badge_outlined,
                    title: '담당 선생님',
                    value: _student.teacherName == null
                        ? '미배정'
                        : '${_student.teacherName} 선생님',
                    onTap: _student.isActive ? _changeTeacher : null,
                  ),
                  _cardDivider(),
                  _detailRow(
                    icon: Icons.location_on_outlined,
                    title: '지점',
                    value: _student.branchName,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _sectionLabel('계정'),
              const SizedBox(height: 7),
              _navigationCard(
                children: [
                  _detailRow(
                    icon: Icons.lock_reset_outlined,
                    title: '로그인 PIN 재설정',
                    subtitle: '학생 앱 로그인 PIN을 변경합니다.',
                    onTap: _student.isActive ? _changePin : null,
                  ),
                ],
              ),
              if (_student.withdrawalDate != null) ...[
                const SizedBox(height: 12),
                _withdrawalNotice(),
              ],
              if (_student.isActive) ...[
                const SizedBox(height: 12),
                _navigationCard(
                  children: [
                    _detailRow(
                      icon: Icons.person_off_outlined,
                      title: _student.withdrawalIsDue
                          ? '퇴원 확정'
                          : _student.hasScheduledWithdrawal
                              ? '퇴원 관리'
                              : '퇴원 처리',
                      subtitle: _student.hasScheduledWithdrawal &&
                              _student.withdrawalDate != null
                          ? '${DateFormat('yyyy.MM.dd').format(_student.withdrawalDate!)} 예정'
                          : '퇴원일 지정 및 퇴원 처리를 관리합니다.',
                      color: Colors.redAccent,
                      onTap: _student.withdrawalIsDue
                          ? _finalizeWithdrawal
                          : _openWithdrawal,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileHeader() {
    final typeColor =
        _student.isRegular ? primaryColor : const Color(0xff4B7892);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              color: typeColor,
              size: 30,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _student.displayName,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black87,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    _smallBadge(
                      _student.isRegular ? '정규' : '자율 예약',
                      typeColor,
                    ),
                    if (!_student.isActive)
                      _smallBadge('퇴원', Colors.black54)
                    else if (_student.hasScheduledWithdrawal)
                      _smallBadge('퇴원 예정', Colors.orange.shade800),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  _student.branchName,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _student.teacherName == null
                      ? '담당 선생님 미배정'
                      : '${_student.teacherName} 선생님',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentSemesterCard() {
    if (_student.isRegular) {
      return _surfaceCard(
        title: '이번 학기 · 정규 수업',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_regularSchedulesLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primaryColor,
                  ),
                ),
              )
            else if (_regularSchedules.isEmpty)
              Text(
                '현재 적용 중인 정규 일정이 없습니다.',
                style: forestringTextStyle.copyWith(
                  color: Colors.black54,
                  fontSize: 12,
                ),
              )
            else
              ..._regularSchedules.map(_regularScheduleRow),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _openRegularSchedule,
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(
                  color: primaryColor.withValues(alpha: 0.25),
                ),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: Text(
                '정규 일정 관리',
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final rightCount = _student.flexBaseRightCount;
    final duration = _student.flexDurationMinutes;
    return _surfaceCard(
      title: '이번 학기 · 자율 예약',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _metricTile(
                  icon: Icons.confirmation_number_outlined,
                  label: '기본 수업권',
                  value: rightCount == null ? '확인 필요' : '$rightCount개',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricTile(
                  icon: Icons.schedule_outlined,
                  label: '수업 길이',
                  value: duration == null ? '확인 필요' : '$duration분',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _changeFlexRightCount,
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryColor,
              side: BorderSide(
                color: primaryColor.withValues(alpha: 0.25),
              ),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: Text(
              '수업권 관리',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _regularScheduleRow(ManagedRegularSchedule schedule) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            size: 17,
            color: primaryColor,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${schedule.weekdayLabel} · ${schedule.timeLabel} · '
              '${schedule.durationMinutes}분',
              style: forestringTextStyle.copyWith(
                color: Colors.black87,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (schedule.hasFutureVersion)
            _smallBadge('변경 예정', secondaryColor),
        ],
      ),
    );
  }

  Widget _nextSemesterCard() {
    final plan = _nextPlan;
    final subtitle = _nextPlanLoading
        ? '불러오는 중...'
        : plan == null
            ? (_nextPlanError ?? '다음 학기 정보 확인 필요')
            : '${plan.currentTypeLabel} → ${plan.plannedTypeLabel}';

    return _surfaceCard(
      title: '다음 학기',
      child: _detailRow(
        icon: Icons.event_available_outlined,
        title: plan == null
            ? '다음 학기 수강 형태'
            : '${plan.nextSemesterCode} 학기',
        subtitle: subtitle,
        value: plan?.plannedIsFlex == true
            ? '수업권 ${plan!.flexBaseRightCount ?? plan.defaultFlexBaseRightCount}개'
            : null,
        onTap: !_nextPlanLoading && plan?.canChange == true
            ? _changeNextSemesterType
            : null,
        compact: true,
      ),
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryColor, size: 19),
          const SizedBox(height: 8),
          Text(
            label,
            style: forestringTextStyle.copyWith(
              color: Colors.black45,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _surfaceCard({
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _navigationCard({
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String title,
    String? subtitle,
    String? value,
    VoidCallback? onTap,
    Color color = primaryColor,
    bool compact = false,
  }) {
    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 13,
        vertical: compact ? 8 : 11,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.075),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
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
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: forestringTextStyle.copyWith(
                  color: Colors.black54,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 5),
            Icon(
              Icons.chevron_right_rounded,
              color: color.withValues(alpha: 0.70),
              size: 20,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }

  Widget _sectionLabel(String label) {
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

  Widget _smallBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _cardDivider() {
    return Divider(
      height: 1,
      indent: 57,
      color: primaryColor.withValues(alpha: 0.06),
    );
  }

  Widget _withdrawalNotice() {
    final date = _student.withdrawalDate;
    if (date == null) return const SizedBox.shrink();

    final color =
        _student.isActive ? Colors.orange.shade800 : Colors.black54;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.event_busy_outlined, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_student.isActive ? '퇴원 예정' : '퇴원'} · '
              '${DateFormat('yyyy.MM.dd').format(date)}',
              style: forestringTextStyle.copyWith(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_student.isActive && _student.hasScheduledWithdrawal)
            TextButton(
              onPressed: _cancelWithdrawal,
              child: const Text('예약 취소'),
            ),
        ],
      ),
    );
  }

  Future<void> _openLessonHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentLessonHistoryPage(
          student: _student,
          profile: widget.profile,
          repository: widget.lessonRepository,
          branchRepository: widget.branchRepository,
        ),
      ),
    );
  }

  Future<void> _openRegularSchedule() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentRegularSchedulePage(
          student: _student,
          repository: widget.regularScheduleRepository,
        ),
      ),
    );
    if (mounted) await _refreshStudent();
  }

  Future<void> _changeTeacher() async {
    final changed = await showStudentTeacherChangeDialog(
      context: context,
      student: _student,
      repository: widget.teacherManagementRepository,
    );
    if (!mounted || changed != true) return;
    await _refreshStudent();
    if (!mounted) return;
    _showMessage('담당 선생님 변경이 저장되었습니다.');
  }

  Future<void> _changeNextSemesterType() async {
    final changed = await showStudentNextSemesterTypeDialog(
      context: context,
      student: _student,
      repository: _nextSemesterRepository,
    );
    if (!mounted || changed != true) return;
    await _refreshStudent();
    if (!mounted) return;
    _showMessage('다음 학기 수강 형태가 저장되었습니다.');
  }

  Future<void> _changeName() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _StudentNameEditPage(
          student: _student,
          repository: _repository,
        ),
      ),
    );
    if (!mounted || changed != true) return;
    await _refreshStudent();
    if (!mounted) return;
    _showMessage('이름이 변경되었습니다.');
  }

  Future<void> _changePin() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PinResetPage(
          student: _student,
          repository: _repository,
        ),
      ),
    );
    if (!mounted || changed != true) return;
    _showMessage('PIN이 변경되었습니다.');
  }

  Future<void> _changeFlexRightCount() async {
    final result = await Navigator.of(context)
        .push<FlexRightCountChangeResult>(
      MaterialPageRoute(
        builder: (_) => _FlexRightCountPage(
          student: _student,
          repository: _repository,
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _refreshStudent();
    if (!mounted) return;
    _showMessage(
      '수업권이 ${result.newBaseRightCount}개로 변경되었습니다. '
      '취소 가능 ${result.newCancellationLimit}회 · 이월 상한 ${result.newCarryoverCap}개',
    );
  }

  Future<void> _openWithdrawal() async {
    final result = await showStudentWithdrawalDialog(
      context: context,
      student: _student,
      repository: _repository,
    );
    if (!mounted || result == null) return;
    await _refreshStudent();
    if (!mounted) return;
    _showMessage(
      result.finalized
          ? '퇴원 처리가 완료되었습니다.'
          : '${DateFormat('yyyy.MM.dd').format(result.withdrawalDate)} 퇴원 예정으로 저장되었습니다. 퇴원일 이후 수업은 즉시 정리됩니다.',
    );
  }

  Future<void> _finalizeWithdrawal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('퇴원 확정'),
        content: Text(
          '${_student.displayName} 학생의 퇴원을 확정합니다.\n\n'
          '퇴원일 이후 수업은 이미 정리되어 있으며, 남은 사용 가능한 수강권을 회수하고 학생 계정을 비활성화합니다. 과거 수업 기록은 유지됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('퇴원 확정'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await _repository.finalizeWithdrawal(studentId: _student.id);
      if (!mounted) return;
      _showMessage('퇴원 처리가 완료되었습니다.');
      Navigator.of(context).pop();
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    }
  }

  Future<void> _cancelWithdrawal() async {
    final date = _student.withdrawalDate;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('퇴원 예약 취소'),
        content: Text(
          date == null
              ? '${_student.displayName} 학생의 퇴원 예약을 취소할까요?'
              : '${_student.displayName} 학생의 ${DateFormat('yyyy.MM.dd').format(date)} 퇴원 예약을 취소할까요?\n\n원래 수업 시간에 다른 예약이 생긴 경우 해당 수업은 자동 복구되지 않고 수업권으로 반환됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('아니요'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            child: const Text('예약 취소'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await _repository.cancelWithdrawal(studentId: _student.id);
      if (!mounted) return;
      await _refreshStudent();
      if (!mounted) return;
      _showMessage('퇴원 예약이 취소되었습니다. 복구 가능한 수업은 원래 일정으로 복구되었습니다.');
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _StudentNameEditPage extends StatefulWidget {
  const _StudentNameEditPage({
    required this.student,
    required this.repository,
  });

  final ManagedStudent student;
  final StudentManagementRepository repository;

  @override
  State<_StudentNameEditPage> createState() =>
      _StudentNameEditPageState();
}

class _StudentNameEditPageState extends State<_StudentNameEditPage> {
  late final TextEditingController _nameController;
  bool _saving = false;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.student.displayName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name =
        _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final current =
        widget.student.displayName.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (name.isEmpty) {
      setState(() => _validationMessage = '이름을 입력해주세요.');
      return;
    }
    if (name.length > 100) {
      setState(() => _validationMessage = '이름은 100자 이하로 입력해주세요.');
      return;
    }
    if (name == current) {
      setState(() => _validationMessage = '현재 이름과 동일합니다.');
      return;
    }

    setState(() {
      _saving = true;
      _validationMessage = null;
    });

    try {
      await widget.repository.updateStudentName(
        studentId: widget.student.id,
        name: name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _StudentEditScaffold(
      title: '학생 이름 수정',
      saving: _saving,
      actionLabel: '이름 변경',
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StudentEditHeader(
            student: widget.student,
            description:
                '이름을 변경하면 학생 앱 로그인에 사용하는 이름도 함께 변경됩니다.',
          ),
          const SizedBox(height: 12),
          _StudentEditCard(
            child: TextField(
              controller: _nameController,
              enabled: !_saving,
              maxLength: 100,
              onChanged: (_) {
                if (_validationMessage != null) {
                  setState(() => _validationMessage = null);
                } else {
                  setState(() {});
                }
              },
              decoration: _studentEditDecoration('학생 이름'),
            ),
          ),
          if (_validationMessage != null) ...[
            const SizedBox(height: 10),
            _StudentEditMessage(
              message: _validationMessage!,
              isError: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _PinResetPage extends StatefulWidget {
  const _PinResetPage({
    required this.student,
    required this.repository,
  });

  final ManagedStudent student;
  final StudentManagementRepository repository;

  @override
  State<_PinResetPage> createState() => _PinResetPageState();
}

class _PinResetPageState extends State<_PinResetPage> {
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
      await widget.repository.resetStudentPin(
        studentId: widget.student.id,
        pin: pin,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _StudentEditScaffold(
      title: '로그인 PIN 재설정',
      saving: _saving,
      actionLabel: 'PIN 저장',
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StudentEditHeader(
            student: widget.student,
            description: '학생 앱 로그인에 사용할 새로운 4자리 PIN을 설정합니다.',
          ),
          const SizedBox(height: 12),
          _StudentEditCard(
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
                  decoration: _studentEditDecoration('새 PIN').copyWith(
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
                      _studentEditDecoration('새 PIN 확인').copyWith(
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          if (_validationMessage != null) ...[
            const SizedBox(height: 10),
            _StudentEditMessage(
              message: _validationMessage!,
              isError: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _FlexRightCountPage extends StatefulWidget {
  const _FlexRightCountPage({
    required this.student,
    required this.repository,
  });

  final ManagedStudent student;
  final StudentManagementRepository repository;

  @override
  State<_FlexRightCountPage> createState() =>
      _FlexRightCountPageState();
}

class _FlexRightCountPageState extends State<_FlexRightCountPage> {
  late final TextEditingController _countController;
  bool _saving = false;
  String? _validationMessage;

  int? get _enteredCount =>
      int.tryParse(_countController.text.trim());

  @override
  void initState() {
    super.initState();
    _countController = TextEditingController(
      text: widget.student.flexBaseRightCount?.toString() ?? '',
    )..addListener(_changed);
  }

  @override
  void dispose() {
    _countController
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() => _validationMessage = null);
    }
  }

  Future<void> _save() async {
    final current = widget.student.flexBaseRightCount;
    final next = _enteredCount;

    if (current == null) {
      setState(
        () => _validationMessage =
            '현재 학기의 자율 수업권 설정을 찾지 못했습니다.',
      );
      return;
    }
    if (next == null || next <= 0) {
      setState(
        () => _validationMessage =
            '수업권 개수를 1개 이상 입력해주세요.',
      );
      return;
    }
    if (next == current) {
      setState(
        () => _validationMessage =
            '현재 수업권 개수와 동일합니다.',
      );
      return;
    }

    if (next < current) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (confirmContext) => AlertDialog(
          title: const Text('수업권 감액 확인'),
          content: Text(
            '${widget.student.displayName} 학생의 수업권을 '
            '$current개에서 $next개로 줄일까요?\n\n'
            '사용 가능한 수업권부터 회수되며, '
            '이미 사용한 취소 횟수는 유지됩니다.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(confirmContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(confirmContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text('감액'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }

    setState(() {
      _saving = true;
      _validationMessage = null;
    });

    try {
      final result =
          await widget.repository.changeFlexBaseRightCount(
        studentId: widget.student.id,
        newBaseRightCount: next,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on StudentManagementFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entered = _enteredCount;
    final cancellationLimit =
        entered == null ? null : (entered ~/ 4) * 2;
    final carryoverCap =
        entered == null ? null : entered ~/ 4;

    return _StudentEditScaffold(
      title: '자율 수업권 관리',
      saving: _saving,
      actionLabel: '수업권 변경',
      onSave: widget.student.flexBaseRightCount == null ? null : _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StudentEditHeader(
            student: widget.student,
            description:
                '현재 학기의 기본 수업권 개수를 변경합니다.',
          ),
          const SizedBox(height: 12),
          _StudentEditCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _countController,
                  enabled: !_saving &&
                      widget.student.flexBaseRightCount != null,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration:
                      _studentEditDecoration('수업권 개수').copyWith(
                    suffixText: '개',
                  ),
                ),
                if (entered != null && entered > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    '변경 후 취소 $cancellationLimit회 · '
                    '이월 $carryoverCap개',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_validationMessage != null) ...[
            const SizedBox(height: 10),
            _StudentEditMessage(
              message: _validationMessage!,
              isError: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _StudentEditScaffold extends StatelessWidget {
  const _StudentEditScaffold({
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

class _StudentEditHeader extends StatelessWidget {
  const _StudentEditHeader({
    required this.student,
    required this.description,
  });

  final ManagedStudent student;
  final String description;

  @override
  Widget build(BuildContext context) {
    return _StudentEditCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            student.displayName,
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 22,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${student.branchName} · ${student.typeLabel}',
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

class _StudentEditCard extends StatelessWidget {
  const _StudentEditCard({
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

class _StudentEditMessage extends StatelessWidget {
  const _StudentEditMessage({
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

InputDecoration _studentEditDecoration(String label) {
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
