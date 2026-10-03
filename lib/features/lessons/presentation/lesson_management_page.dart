import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../../semesters/data/semester_repository.dart';
import '../../semesters/domain/managed_semester.dart';
import '../data/lesson_repository.dart';
import '../domain/lesson.dart';
import 'lesson_controller.dart';
import 'makeup_lesson_create_page.dart';
import 'widgets/lesson_action_dialog.dart';
import 'widgets/lesson_semester_picker.dart';
import 'widgets/student_search_picker.dart';
import 'widgets/student_style_lesson_calendar.dart';

class LessonManagementPage extends StatefulWidget {
  const LessonManagementPage({
    super.key,
    required this.profile,
    required this.controller,
    this.initialBranchId,
    this.initialStudentId,
    this.repository,
    this.semesterRepository,
    this.branchRepository,
    this.isQaSandbox = false,
    this.embeddedInShell = false,
  });

  final CurrentProfile profile;
  final LessonController controller;
  final String? initialBranchId;
  final String? initialStudentId;
  final LessonRepository? repository;
  final SemesterRepository? semesterRepository;
  final BranchRepository? branchRepository;
  final bool isQaSandbox;
  final bool embeddedInShell;

  @override
  State<LessonManagementPage> createState() => _LessonManagementPageState();
}

class _LessonManagementPageState extends State<LessonManagementPage> {
  late final LessonRepository _repository;
  late final SemesterRepository _semesterRepository;
  late final BranchRepository _branchRepository;

  List<Lesson> _lessons = const [];
  List<VisibleStudent> _students = const [];
  List<VisibleTeacher> _teachers = const [];
  List<ManagedSemester> _semesters = const [];
  List<AcademyBranch> _branches = const [];

  String? _selectedSemesterId;
  String? _selectedBranchId;
  String? _selectedStudentId;
  String _statusFilter = 'all';
  String _viewMode = 'list';
  bool _loading = true;
  String? _errorMessage;

  bool get _isMaster => widget.profile.isMaster;

  ManagedSemester? get _selectedSemester {
    final id = _selectedSemesterId;
    if (id == null) return null;
    for (final semester in _semesters) {
      if (semester.id == id) return semester;
    }
    return null;
  }

  List<VisibleStudent> get _filterStudents {
    final branchId = _selectedBranchId;
    return _students
        .where(
          (student) => branchId == null || student.branchId == branchId,
        )
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  List<Lesson> get _visibleLessons {
    final result = _lessons.where((lesson) {
      if (_selectedBranchId != null && lesson.branchId != _selectedBranchId) {
        return false;
      }
      if (_selectedStudentId != null &&
          lesson.studentId != _selectedStudentId) {
        return false;
      }
      if (!_matchesCategory(lesson)) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return result;
  }

  bool _matchesCategory(Lesson lesson) {
    return switch (_statusFilter) {
      'base' => !lesson.isCanceled &&
          !lesson.isRescheduled &&
          lesson.type != LessonType.makeup &&
          lesson.type != LessonType.flex,
      'changed' => !lesson.isCanceled && lesson.isStaffChanged,
      'canceled' => lesson.isCanceled,
      'special' => !lesson.isCanceled &&
          (lesson.type == LessonType.makeup ||
              lesson.type == LessonType.flex ||
              lesson.isStudentRebooked),
      _ => true,
    };
  }

  String? get _safeSemesterValue {
    final value = _selectedSemesterId;
    if (value == null) return null;
    return _semesters.any((item) => item.id == value) ? value : null;
  }

  String? get _safeBranchValue {
    final selected = _selectedBranchId;
    final exists =
        selected != null && _branches.any((branch) => branch.id == selected);

    if (_isMaster) return exists ? selected : '__all__';
    return exists ? selected : null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.isQaSandbox &&
        (widget.repository == null ||
            widget.semesterRepository == null ||
            widget.branchRepository == null)) {
      throw StateError(
        'QA lesson management requires sandbox repositories.',
      );
    }
    _repository = widget.repository ?? LessonRepository();
    _semesterRepository =
        widget.semesterRepository ?? SemesterRepository();
    _branchRepository =
        widget.branchRepository ?? BranchRepository();
    _selectedBranchId = widget.profile.isManager
        ? widget.profile.branchId
        : widget.initialBranchId;
    _selectedStudentId = widget.initialStudentId;
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _semesterRepository.fetchSemesters(),
        _repository.fetchVisibleStudents(),
        _repository.fetchVisibleTeachers(),
        _branchRepository.fetchBranches(),
      ]);

      final semesters = _uniqueById<ManagedSemester>(
        results[0] as List<ManagedSemester>,
        (item) => item.id,
      )..sort((a, b) => b.startsOn.compareTo(a.startsOn));

      final students = _uniqueById<VisibleStudent>(
        results[1] as List<VisibleStudent>,
        (item) => item.id,
      )..sort((a, b) => a.displayName.compareTo(b.displayName));

      final teachers = _uniqueById<VisibleTeacher>(
        results[2] as List<VisibleTeacher>,
        (item) => item.id,
      )..sort((a, b) => a.displayName.compareTo(b.displayName));

      var branches = _uniqueById<AcademyBranch>(
        results[3] as List<AcademyBranch>,
        (item) => item.id,
      )..sort((a, b) => a.name.compareTo(b.name));

      if (widget.profile.isManager) {
        branches = branches
            .where((branch) => branch.id == widget.profile.branchId)
            .toList();
      }

      var semesterId = _selectedSemesterId;
      if (semesterId == null ||
          !semesters.any((semester) => semester.id == semesterId)) {
        semesterId = _defaultSemesterId(semesters);
      }

      var branchId = widget.profile.isManager
          ? widget.profile.branchId
          : _selectedBranchId;
      if (branchId != null &&
          !branches.any((branch) => branch.id == branchId)) {
        branchId = null;
      }

      var studentId = _selectedStudentId;
      if (studentId != null &&
          !students.any(
            (student) =>
                student.id == studentId &&
                (branchId == null || student.branchId == branchId),
          )) {
        studentId = null;
      }

      if (!mounted) return;
      setState(() {
        _semesters = semesters;
        _students = students;
        _teachers = teachers;
        _branches = branches;
        _selectedSemesterId = semesterId;
        _selectedBranchId = branchId;
        _selectedStudentId = studentId;
      });

      await _loadLessons(setLoading: false);
    } on LessonFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } on SemesterFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } on BranchFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = '수업 관리 정보를 불러오지 못했습니다.\n$error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLessons({bool setLoading = true}) async {
    final semester = _selectedSemester;
    if (semester == null) {
      if (mounted) setState(() => _lessons = const []);
      return;
    }

    if (setLoading && mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final range = _queryRange(semester);
      final rows = await _repository.fetchVisibleLessons(
        from: range.$1,
        to: range.$2,
      );
      final lessons = rows
          .where((lesson) => _belongsToSemester(lesson, semester))
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

      if (mounted) setState(() => _lessons = lessons);
    } on LessonFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (setLoading && mounted) setState(() => _loading = false);
    }
  }

  String? _defaultSemesterId(List<ManagedSemester> semesters) {
    if (semesters.isEmpty) return null;
    for (final semester in semesters) {
      if (semester.isCurrent) return semester.id;
    }

    final upcoming = semesters.where((semester) => semester.isUpcoming).toList()
      ..sort((a, b) => a.startsOn.compareTo(b.startsOn));
    if (upcoming.isNotEmpty) return upcoming.first.id;
    return semesters.first.id;
  }

  (DateTime, DateTime) _queryRange(ManagedSemester semester) {
    var start = semester.startsOn;
    var end = semester.endsOn;
    for (final override in semester.branchOverrides) {
      if (override.startsOn.isBefore(start)) start = override.startsOn;
      if (override.endsOn.isAfter(end)) end = override.endsOn;
    }
    return (
      DateTime(start.year, start.month, start.day),
      DateTime(end.year, end.month, end.day).add(const Duration(days: 1)),
    );
  }

  bool _belongsToSemester(Lesson lesson, ManagedSemester semester) {
    final branchId = lesson.branchId;
    if (branchId == null) return false;
    final day = _dateOnly(lesson.startsAt);
    final start = semester.effectiveStart(branchId);
    final end = semester.effectiveEnd(branchId);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  Future<void> _changeSemester(String? id) async {
    if (id == null || id == _selectedSemesterId) return;
    setState(() => _selectedSemesterId = id);
    await _loadLessons();
  }

  void _changeBranch(String? value) {
    if (value == null) return;
    final branchId = value == '__all__' ? null : value;
    setState(() {
      _selectedBranchId = branchId;
      if (_selectedStudentId != null &&
          !_filterStudents.any((student) => student.id == _selectedStudentId)) {
        _selectedStudentId = null;
      }
      if (_selectedStudentId == null && _viewMode == 'calendar') {
        _viewMode = 'list';
      }
    });
  }

  Future<void> _openLesson(Lesson lesson) async {
    await showLessonActionDialog(
      context: context,
      lesson: lesson,
      controller: widget.controller,
    );
    if (mounted) await _loadLessons();
  }

  Future<void> _openMakeup() async {
    final semester = _selectedSemester;
    if (semester == null) {
      _message('학기를 먼저 선택해주세요.');
      return;
    }
    if (semester.isPast) {
      _message('지난 학기에는 새 추가 수업을 등록할 수 없습니다.');
      return;
    }

    final activeBranches =
        _branches.where((branch) => branch.isActive).toList();
    if (activeBranches.isEmpty) {
      _message('추가 수업을 등록할 운영 지점이 없습니다.');
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MakeupLessonCreatePage(
          profile: widget.profile,
          semester: semester,
          branches: activeBranches,
          students: _students,
          teachers: _teachers,
          initialBranchId: _selectedBranchId,
          initialStudentId: _selectedStudentId,
          initialDate: _initialMakeupDate(semester),
          repository: _repository,
        ),
      ),
    );

    if (result == true && mounted) {
      await widget.controller.reload();
      await _loadLessons();
      if (mounted) _message('추가 수업을 등록했습니다.');
    }
  }

  DateTime _initialMakeupDate(ManagedSemester semester) {
    final branchId = _selectedBranchId;
    final start = branchId == null
        ? semester.startsOn
        : semester.effectiveStart(branchId);
    final end =
        branchId == null ? semester.endsOn : semester.effectiveEnd(branchId);
    final tomorrow = _dateOnly(DateTime.now().add(const Duration(days: 1)));
    if (tomorrow.isBefore(start)) return start;
    if (tomorrow.isAfter(end)) return end;
    return tomorrow;
  }

  void _changeView(Set<String> values) {
    final next = values.first;
    if (next == 'calendar' && _selectedStudentId == null) {
      _message('학생을 선택하면 학생별 캘린더를 볼 수 있습니다.');
      return;
    }
    setState(() => _viewMode = next);
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lessons = _visibleLessons;
    final semester = _selectedSemester;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: widget.embeddedInShell
          ? null
          : ForestringAppBar(
              title: '수업 관리',
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
        onPressed: _loading ? null : _openMakeup,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(
          '추가 수업 등록',
          style: forestringTextStyle.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: _filterPanel(lessons.length),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: _errorCard(_errorMessage!),
              ),
            Expanded(
              child: _loading && _semesters.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _viewMode == 'calendar'
                      ? _calendar(lessons, semester)
                      : _lessonList(lessons),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterPanel(int count) {
    final students = _filterStudents;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '수업 $count건',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'list',
                    icon: Icon(Icons.view_list_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: 'calendar',
                    icon: Icon(Icons.calendar_month_outlined, size: 17),
                  ),
                ],
                selected: {_viewMode},
                showSelectedIcon: false,
                onSelectionChanged: _changeView,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: LessonSemesterPicker(
                  semesters: _semesters,
                  selectedSemesterId: _safeSemesterValue,
                  enabled: !_loading,
                  onChanged: (value) => _changeSemester(value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _safeBranchValue,
                  decoration: _decoration('지점'),
                  items: [
                    if (_isMaster)
                      const DropdownMenuItem<String>(
                        value: '__all__',
                        child: Text('전체 지점'),
                      ),
                    ..._branches.map(
                      (branch) => DropdownMenuItem<String>(
                        value: branch.id,
                        child: Text(
                          branch.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: _isMaster && !_loading ? _changeBranch : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StudentSearchPickerField(
                  students: students,
                  selectedStudentId: _selectedStudentId,
                  includeAllOption: true,
                  enabled: !_loading,
                  onChanged: (value) {
                    setState(() {
                      _selectedStudentId = value;
                      if (value == null && _viewMode == 'calendar') {
                        _viewMode = 'list';
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _statusFilter,
                  decoration: _decoration('구분'),
                  items: const [
                    DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('전체'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'base',
                      child: Text('기본 수업'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'changed',
                      child: Text('일정 변경'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'canceled',
                      child: Text('취소'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'special',
                      child: Text('보강·예약'),
                    ),
                  ],
                  onChanged: _loading
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _statusFilter = value);
                          }
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lessonList(List<Lesson> lessons) {
    if (lessons.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 80),
          children: [
            Text(
              '조건에 맞는 수업이 없습니다.',
              textAlign: TextAlign.center,
              style: forestringTextStyle.copyWith(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
        itemCount: lessons.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, index) => _lessonCard(lessons[index]),
      ),
    );
  }

  Widget _lessonCard(Lesson lesson) {
    final start = DateFormat('HH:mm').format(lesson.startsAt);
    final end = DateFormat('HH:mm').format(lesson.endsAt);
    final teacherName = lesson.teacherName ?? '담당자 확인 필요';
    final branchName = _branchName(lesson.branchId);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => _openLesson(lesson),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: lesson.isCanceled
                  ? Colors.black12
                  : primaryColor.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: lesson.isCanceled
                      ? Colors.black12
                      : primaryColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${lesson.startsAt.month}월',
                      style: forestringTextStyle.copyWith(fontSize: 11),
                    ),
                    Text(
                      '${lesson.startsAt.day}',
                      style: forestringTextStyle.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lesson.studentName ?? '학생 확인 필요',
                            overflow: TextOverflow.ellipsis,
                            style: forestringTextStyle.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              decoration: lesson.isCanceled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        _typeBadge(lesson),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$start ~ $end · $teacherName',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    if (_isMaster) ...[
                      const SizedBox(height: 2),
                      Text(
                        branchName,
                        style: forestringTextStyle.copyWith(
                          color: Colors.black45,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (lesson.isCanceled)
                Text(
                  '취소',
                  style: forestringTextStyle.copyWith(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeBadge(Lesson lesson) {
    final label = switch (lesson.type) {
      LessonType.makeup => '추가',
      LessonType.flex => lesson.changeBadgeLabel ?? '자율',
      LessonType.regular => lesson.changeBadgeLabel ?? '정규',
    };
    final color =
        lesson.type == LessonType.makeup ? secondaryColor : primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
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

  Widget _calendar(List<Lesson> lessons, ManagedSemester? semester) {
    if (_selectedStudentId == null) {
      return Center(
        child: Text(
          '학생을 선택하면 수업 캘린더를 볼 수 있습니다.',
          style: forestringTextStyle.copyWith(color: Colors.black54),
        ),
      );
    }
    if (semester == null) return const SizedBox.shrink();

    final range = _queryRange(semester);
    return StudentStyleLessonCalendar(
      key: ValueKey('${semester.id}-$_selectedStudentId'),
      lessons: lessons,
      firstDay: range.$1,
      lastDay: range.$2.subtract(const Duration(days: 1)),
      lessonBuilder: _lessonCard,
    );
  }

  String _branchName(String? branchId) {
    if (branchId == null) return '지점 미지정';
    for (final branch in _branches) {
      if (branch.id == branchId) return branch.name;
    }
    return '지점 확인 필요';
  }

  Widget _errorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
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

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: neutralIvory,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 11,
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.18)),
      ),
    );
  }
}

List<T> _uniqueById<T>(Iterable<T> items, String Function(T item) idOf) {
  final result = <String, T>{};
  for (final item in items) {
    result[idOf(item)] = item;
  }
  return result.values.toList();
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
