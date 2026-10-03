import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../data/teacher_repository.dart';

class TeacherAssignedStudentsPage extends StatefulWidget {
  const TeacherAssignedStudentsPage({
    super.key,
    required this.teacher,
    this.repository,
  });

  final ManagedTeacher teacher;
  final TeacherRepository? repository;

  @override
  State<TeacherAssignedStudentsPage> createState() =>
      _TeacherAssignedStudentsPageState();
}

class _TeacherAssignedStudentsPageState
    extends State<TeacherAssignedStudentsPage> {
  late final TeacherRepository _repository;
  final _searchController = TextEditingController();

  List<AssignedStudentSummary> _students = const [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? TeacherRepository();
    _searchController.addListener(_onSearchChanged);
    _loadStudents();
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

  Future<void> _loadStudents() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final students = await _repository.fetchAssignedStudents(
        widget.teacher.id,
      );
      if (!mounted) return;
      setState(() => _students = students);
    } on TeacherFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _students = const [];
        _errorMessage = error.message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AssignedStudentSummary> get _visibleStudents {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _students;
    return _students
        .where((student) => student.displayName.toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visibleStudents = _visibleStudents;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '담당 수강생',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _loadStudents,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStudents,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.teacher.displayName,
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.teacher.branchName} · 현재 담당 ${_students.length}명',
                style: forestringTextStyle.copyWith(
                  color: Colors.black54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '수강생 이름 검색',
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
              const SizedBox(height: 14),
              if (_errorMessage != null) ...[
                _errorCard(_errorMessage!),
                const SizedBox(height: 12),
              ],
              if (_loading && _students.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 70),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visibleStudents.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 70),
                  child: Center(
                    child: Text(
                      _students.isEmpty
                          ? '현재 담당 중인 수강생이 없습니다.'
                          : '검색 결과가 없습니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),
                )
              else ...[
                Text(
                  '${visibleStudents.length}명',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ...visibleStudents.map(_studentCard),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _studentCard(AssignedStudentSummary student) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: primaryColor.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person_outline,
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
                          student.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: forestringTextStyle.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _badge(
                        student.isFlex ? '자율' : '정규',
                        student.isFlex ? secondaryColor : primaryColor,
                      ),
                      if (!student.isActive) ...[
                        const SizedBox(width: 5),
                        _badge(student.statusLabel, Colors.black45),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  if (student.isFlex) ...[
                    Text(
                      _flexRightCountLabel(student.flexBaseRightCount),
                      style: forestringTextStyle.copyWith(
                        color: secondaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                  ] else ...[
                    Text(
                      _regularScheduleLabel(student.regularSchedules),
                      style: forestringTextStyle.copyWith(
                        color: secondaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    '담당 시작 ${DateFormat('yyyy.MM.dd').format(student.assignmentStartsOn)}',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _regularScheduleLabel(
    List<AssignedStudentRegularSchedule> schedules,
  ) {
    if (schedules.isEmpty) {
      return '정규 수업: 등록된 일정 없음';
    }

    final labels = schedules.map(
      (schedule) => '${_weekdayLabel(schedule.weekday)} '
          '${schedule.startTime} (${schedule.durationMinutes}분)',
    );
    return '정규 수업: ${labels.join(', ')}';
  }

  String _flexRightCountLabel(int? rightCount) {
    if (rightCount == null) {
      return '수업권 설정: 확인 필요';
    }
    return '수업권 설정: $rightCount개';
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
}
