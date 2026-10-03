import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/theme/student_accent.dart';
import '../../../core/theme/student_accent_controller.dart';
import '../../auth/domain/current_profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../teachers/data/teacher_repository.dart';
import '../domain/lesson.dart';
import 'lesson_controller.dart';

class TeacherMyPage extends StatefulWidget {
  const TeacherMyPage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  State<TeacherMyPage> createState() => _TeacherMyPageState();
}

class _TeacherMyPageState extends State<TeacherMyPage> {
  final TeacherRepository _repository = TeacherRepository();
  final GlobalKey _studentSectionKey = GlobalKey();

  List<AssignedStudentSummary> _students = const [];
  bool _loadingStudents = true;
  String? _studentError;

  @override
  void initState() {
    super.initState();

    if (widget.profile.isReviewAccount) {
      _loadingStudents = false;
    } else {
      _loadStudents();
    }
  }

  Future<void> _loadStudents() async {
    setState(() {
      _loadingStudents = true;
      _studentError = null;
    });

    try {
      final students = await _repository.fetchAssignedStudents(
        widget.profile.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _students = students;
      });
    } on TeacherFailure catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _studentError = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingStudents = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    final controller = context.read<LessonController>();

    if (widget.profile.isReviewAccount) {
      await controller.reload();
      return;
    }

    await Future.wait([
      controller.reload(),
      _loadStudents(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final lessonController = context.watch<LessonController>();
    final accentController = context.watch<StudentAccentController>();
    final now = DateTime.now();

    final students = widget.profile.isReviewAccount
        ? _reviewStudents(lessonController)
        : _students;

    final activeStudents =
        students.where((student) => student.isActive).toList();
    final regularStudentCount =
        activeStudents.where((student) => !student.isFlex).length;

    final todayLessons = lessonController.lessonsOn(now);

    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - DateTime.monday));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    final thisWeekLessons = lessonController.visibleLessons.where(
      (lesson) =>
          !lesson.isCanceled &&
          !lesson.startsAt.isBefore(startOfWeek) &&
          lesson.startsAt.isBefore(endOfWeek),
    );

    final monthStart = DateTime(now.year, now.month);
    final nextMonthStart = DateTime(now.year, now.month + 1);

    final monthLessons = lessonController.visibleLessons
        .where(
          (lesson) =>
              !lesson.isCanceled &&
              !lesson.startsAt.isBefore(monthStart) &&
              lesson.startsAt.isBefore(nextMonthStart),
        )
        .toList();

    final completedMonthLessons =
        monthLessons.where((lesson) => !lesson.endsAt.isAfter(now)).length;
    final remainingMonthLessons =
        monthLessons.length - completedMonthLessons;
    final makeupMonthLessons =
        monthLessons.where((lesson) => lesson.type == LessonType.makeup).length;
    final changedMonthLessons =
        monthLessons.where((lesson) => lesson.isRescheduled).length;

    final upcomingLessons = lessonController.visibleLessons
        .where(
          (lesson) =>
              !lesson.isCanceled &&
              lesson.startsAt.isAfter(now),
        )
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    final allStudentIds = <String>{
      ...students.map((student) => student.id),
      ...lessonController.visibleLessons.map((lesson) => lesson.studentId),
    };

    final studentAccents = accentController.assignments(allStudentIds);

    return Scaffold(
      backgroundColor: const Color(0xffF6F8F4),
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        title: const Text(
          '마이페이지',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'ELAND',
            fontWeight: FontWeight.w500,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            children: [
              _profileCard(),
              const SizedBox(height: 14),
              _summaryGrid(
                todayCount: todayLessons.length,
                weekCount: thisWeekLessons.length,
                activeStudentCount: activeStudents.length,
                regularStudentCount: regularStudentCount,
              ),
              const SizedBox(height: 14),
              _monthReportCard(
                total: monthLessons.length,
                completed: completedMonthLessons,
                remaining: remainingMonthLessons,
                makeup: makeupMonthLessons,
                changed: changedMonthLessons,
              ),
              const SizedBox(height: 20),
              _sectionTitle(
                key: _studentSectionKey,
                title: '내 수강생',
                trailing: activeStudents.isEmpty
                    ? null
                    : '${activeStudents.length}명',
              ),
              const SizedBox(height: 10),
              if (_studentError != null) ...[
                _errorCard(_studentError!),
                const SizedBox(height: 10),
              ],
              if (_loadingStudents && !widget.profile.isReviewAccount)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 34),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (activeStudents.isEmpty)
                _emptyCard(
                  icon: Icons.people_outline_rounded,
                  message: '현재 담당 중인 수강생이 없습니다.',
                )
              else
                ...activeStudents.take(5).map(
                      (student) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _studentCard(
                          student,
                          lessonController,
                          studentAccents[student.id] ??
                              accentController.colorFor(student.id),
                        ),
                      ),
                    ),
              if (activeStudents.length > 5)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _showAllStudents(
                      activeStudents,
                      lessonController,
                    ),
                    icon: const Icon(Icons.people_alt_outlined, size: 18),
                    label: Text('전체 ${activeStudents.length}명 보기'),
                  ),
                ),
              const SizedBox(height: 10),
              _sectionTitle(
                title: '다가오는 수업',
                trailing: upcomingLessons.isEmpty
                    ? null
                    : '다음 ${upcomingLessons.length}개',
              ),
              const SizedBox(height: 10),
              if (upcomingLessons.isEmpty)
                _emptyCard(
                  icon: Icons.event_available_outlined,
                  message: '예정된 수업이 없습니다.',
                )
              else
                _upcomingLessonCard(
                  upcomingLessons.take(3).toList(),
                  studentAccents,
                ),
              const SizedBox(height: 20),
              _sectionTitle(title: '빠른 메뉴'),
              const SizedBox(height: 10),
              _quickActions(lessonController),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard() {
    final label = _teacherLabel(widget.profile.displayName);
    final initial = widget.profile.displayName.trim().isEmpty
        ? '선'
        : widget.profile.displayName.trim().substring(0, 1);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
            child: Text(
              initial,
              style: forestringTextStyle.copyWith(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: forestringTextStyle.copyWith(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '오늘도 좋은 수업 되세요.',
                  style: forestringTextStyle.copyWith(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid({
    required int todayCount,
    required int weekCount,
    required int activeStudentCount,
    required int regularStudentCount,
  }) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.85,
      children: [
        _metricCard(
          icon: Icons.today_rounded,
          value: '$todayCount',
          label: '오늘 수업',
        ),
        _metricCard(
          icon: Icons.date_range_rounded,
          value: '$weekCount',
          label: '이번 주 수업',
        ),
        _metricCard(
          icon: Icons.people_alt_rounded,
          value: '$activeStudentCount',
          label: '활성 수강생',
        ),
        _metricCard(
          icon: Icons.event_repeat_rounded,
          value: '$regularStudentCount',
          label: '정규 학생',
        ),
      ],
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xffE8F0E4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  label,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
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

  Widget _monthReportCard({
    required int total,
    required int completed,
    required int remaining,
    required int makeup,
    required int changed,
  }) {
    final progress = total == 0 ? 0.0 : completed / total;
    final percent = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이번 달 수업 리포트',
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 10,
                        backgroundColor: Colors.white,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          primaryColor,
                        ),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$percent%',
                          style: forestringTextStyle.copyWith(
                            color: primaryColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$completed / $total회',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black45,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    _reportRow('완료', completed, primaryColor),
                    const SizedBox(height: 9),
                    _reportRow(
                      '남은 수업',
                      remaining,
                      secondaryColor,
                    ),
                    const Divider(height: 20),
                    _reportRow(
                      '보강',
                      makeup,
                      const Color(0xff187FA8),
                    ),
                    const SizedBox(height: 7),
                    _reportRow(
                      '변경·재예약',
                      changed,
                      const Color(0xff8E4DB0),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '완료는 수업 종료 시각이 지난 취소되지 않은 수업을 기준으로 계산합니다.',
            style: forestringTextStyle.copyWith(
              color: Colors.black45,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportRow(String label, int value, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          '$value회',
          style: forestringTextStyle.copyWith(
            color: Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle({
    Key? key,
    required String title,
    String? trailing,
  }) {
    return Row(
      key: key,
      children: [
        Expanded(
          child: Text(
            title,
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _studentCard(
    AssignedStudentSummary student,
    LessonController lessonController,
    Color accentColor,
  ) {
    final nextLesson = _nextLessonFor(
      student.id,
      lessonController.visibleLessons,
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: () => _showStudentColorPicker(student),
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 13, 12, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  student.displayName.trim().isEmpty
                      ? '학'
                      : student.displayName.trim().substring(0, 1),
                  style: forestringTextStyle.copyWith(
                    color: studentAccentForeground(accentColor),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: forestringTextStyle.copyWith(
                              color: Colors.black87,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        _studentTypeBadge(student),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      student.isFlex
                          ? _flexLabel(student)
                          : _regularScheduleLabel(
                              student.regularSchedules,
                            ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: studentAccentForeground(accentColor),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (nextLesson != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '다음 수업 ${DateFormat('M.d (E) HH:mm', 'ko_KR').format(nextLesson.startsAt)}',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black45,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.palette_outlined,
                color: accentColor,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _studentTypeBadge(AssignedStudentSummary student) {
    final label = student.isFlex ? '자율' : '정규';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: primaryColor,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _upcomingLessonCard(
    List<Lesson> lessons,
    Map<String, Color> accents,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < lessons.length; i++) ...[
            _upcomingLessonRow(
              lessons[i],
              accents[lessons[i].studentId] ??
                  studentAccentColor(lessons[i].studentId),
            ),
            if (i != lessons.length - 1)
              Divider(
                height: 1,
                color: Colors.black.withValues(alpha: 0.06),
              ),
          ],
        ],
      ),
    );
  }

  Widget _upcomingLessonRow(Lesson lesson, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('M.d (E)', 'ko_KR').format(lesson.startsAt),
                  style: forestringTextStyle.copyWith(
                    color: Colors.black45,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('HH:mm').format(lesson.startsAt),
                  style: forestringTextStyle.copyWith(
                    color: studentAccentForeground(accentColor),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.studentName ?? '학생',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lesson.displayTypeLabel,
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

  Widget _quickActions(LessonController lessonController) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.18,
      children: [
        _quickAction(
          icon: Icons.people_alt_outlined,
          label: '수강생',
          onTap: _scrollToStudents,
        ),
        _quickAction(
          icon: Icons.history_rounded,
          label: '수업 이력',
          onTap: () => _showLessonHistory(lessonController),
        ),
        _quickAction(
          icon: Icons.settings_outlined,
          label: '설정',
          onTap: _showSettings,
        ),
      ],
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.circle,
                size: 0,
              ),
              Icon(
                icon,
                color: primaryColor,
                size: 24,
              ),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: forestringTextStyle.copyWith(
                  color: Colors.black54,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyCard({
    required IconData icon,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: primaryColor.withValues(alpha: 0.50),
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: forestringTextStyle.copyWith(
              color: Colors.black45,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
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

  Future<void> _showStudentColorPicker(
    AssignedStudentSummary student,
  ) async {
    final accentController = context.read<StudentAccentController>();
    final currentColor = accentController.colorFor(student.id);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${student.displayName} 학생 색상',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '이 선생님 계정의 현재 기기에서만 사용됩니다.',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black45,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final color in studentAccentPalette)
                      InkWell(
                        onTap: () async {
                          await accentController.setColor(
                            student.id,
                            color,
                          );
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: currentColor.toARGB32() ==
                                      color.toARGB32()
                                  ? Colors.black87
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: currentColor.toARGB32() ==
                                  color.toARGB32()
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Color(0xff21322A),
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await accentController.resetColor(student.id);
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('자동 색상으로 되돌리기'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAllStudents(
    List<AssignedStudentSummary> students,
    LessonController lessonController,
  ) async {
    final accentController = context.read<StudentAccentController>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xffF6F8F4),
      builder: (sheetContext) {
        return ChangeNotifierProvider.value(
          value: accentController,
          child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.55,
          maxChildSize: 0.94,
          builder: (context, scrollController) {
            return Consumer<StudentAccentController>(
              builder: (context, accentController, _) {
                final accents = accentController.assignments(
                  students.map((student) => student.id),
                );

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '내 수강생',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final student in students)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _studentCard(
                          student,
                          lessonController,
                          accents[student.id] ??
                              accentController.colorFor(student.id),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
        );
      },
    );
  }

  Future<void> _showLessonHistory(
    LessonController lessonController,
  ) async {
    final now = DateTime.now();
    final history = lessonController.visibleLessons
        .where(
          (lesson) =>
              !lesson.isCanceled &&
              lesson.endsAt.isBefore(now),
        )
        .toList()
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xffF6F8F4),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.76,
          minChildSize: 0.5,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '최근 수업 이력',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '현재 앱에 불러온 최근 일정 범위의 수업입니다.',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black45,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                if (history.isEmpty)
                  _emptyCard(
                    icon: Icons.history_rounded,
                    message: '표시할 최근 수업 이력이 없습니다.',
                  )
                else
                  for (final lesson in history.take(30))
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(
                              DateFormat('M.d HH:mm').format(
                                lesson.startsAt,
                              ),
                              style: forestringTextStyle.copyWith(
                                color: primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              lesson.studentName ?? '학생',
                              style: forestringTextStyle.copyWith(
                                color: Colors.black87,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            lesson.displayTypeLabel,
                            style: forestringTextStyle.copyWith(
                              color: Colors.black45,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showSettings() async {
    final accentController = context.read<StudentAccentController>();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.palette_outlined,
                    color: primaryColor,
                  ),
                  title: const Text('학생 색상 설정 초기화'),
                  subtitle: const Text('이 기기에 저장된 학생별 색상을 모두 지웁니다.'),
                  onTap: () async {
                    await accentController.resetAll();
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    '로그아웃',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await context.read<AuthController>().signOut();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scrollToStudents() {
    final target = _studentSectionKey.currentContext;

    if (target == null) {
      return;
    }

    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Lesson? _nextLessonFor(
    String studentId,
    List<Lesson> lessons,
  ) {
    final now = DateTime.now();

    final upcoming = lessons
        .where(
          (lesson) =>
              lesson.studentId == studentId &&
              !lesson.isCanceled &&
              lesson.startsAt.isAfter(now),
        )
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    return upcoming.isEmpty ? null : upcoming.first;
  }

  List<AssignedStudentSummary> _reviewStudents(
    LessonController controller,
  ) {
    final latestByStudent = <String, Lesson>{};

    for (final lesson in controller.visibleLessons) {
      latestByStudent.putIfAbsent(lesson.studentId, () => lesson);
    }

    return latestByStudent.values
        .map(
          (lesson) => AssignedStudentSummary(
            id: lesson.studentId,
            displayName: lesson.studentName ?? '학생',
            studentType:
                lesson.type == LessonType.flex ? 'flex' : 'regular',
            assignmentStartsOn: lesson.startsAt,
            isActive: true,
            regularSchedules: const [],
          ),
        )
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  String _regularScheduleLabel(
    List<AssignedStudentRegularSchedule> schedules,
  ) {
    if (schedules.isEmpty) {
      return '정규 일정 정보 없음';
    }

    return schedules.map((schedule) {
      final start = _parseTime(schedule.startTime);
      final end = start.add(
        Duration(minutes: schedule.durationMinutes),
      );

      return '매주 ${_weekdayLabel(schedule.weekday)} '
          '${DateFormat('HH:mm').format(start)} ~ '
          '${DateFormat('HH:mm').format(end)}';
    }).join(' · ');
  }

  String _flexLabel(AssignedStudentSummary student) {
    final count = student.flexBaseRightCount;

    return count == null
        ? '자율 예약 학생'
        : '자율 예약 학생 · 기본 수업권 $count개';
  }

  DateTime _parseTime(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute =
        parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return DateTime(2000, 1, 1, hour, minute);
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

  String _teacherLabel(String name) {
    final trimmed = name.trim();

    return trimmed.endsWith('선생님')
        ? trimmed
        : '$trimmed 선생님';
  }
}
