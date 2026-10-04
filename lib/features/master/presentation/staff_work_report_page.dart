import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../../core/widgets/management_filters.dart';
import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../../semesters/data/semester_repository.dart';
import '../../semesters/domain/managed_semester.dart';
import '../data/staff_work_report_repository.dart';

class StaffWorkReportPage extends StatefulWidget {
  const StaffWorkReportPage({
    super.key,
    required this.profile,
    this.reportRepository,
    this.branchRepository,
    this.semesterRepository,
  });

  final CurrentProfile profile;
  final StaffWorkReportRepository? reportRepository;
  final BranchRepository? branchRepository;
  final SemesterRepository? semesterRepository;

  @override
  State<StaffWorkReportPage> createState() =>
      _StaffWorkReportPageState();
}

class _StaffWorkReportPageState extends State<StaffWorkReportPage> {
  late final StaffWorkReportRepository _reportRepository;
  late final BranchRepository _branchRepository;
  late final SemesterRepository _semesterRepository;

  List<AcademyBranch> _branches = const [];
  List<ManagedSemester> _semesters = const [];
  String? _selectedSemesterId;
  String? _selectedBranchId;
  StaffWorkReport? _report;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _reportRepository =
        widget.reportRepository ?? StaffWorkReportRepository();
    _branchRepository =
        widget.branchRepository ?? BranchRepository();
    _semesterRepository =
        widget.semesterRepository ?? SemesterRepository();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _branchRepository.fetchBranches(),
        _semesterRepository.fetchSemesters(),
      ]);

      final branches = results[0] as List<AcademyBranch>;
      final semesters = results[1] as List<ManagedSemester>
        ..sort((a, b) => b.startsOn.compareTo(a.startsOn));

      String? semesterId;
      for (final semester in semesters) {
        if (semester.isCurrent) {
          semesterId = semester.id;
          break;
        }
      }
      semesterId ??= semesters.isEmpty ? null : semesters.first.id;

      final branchId = widget.profile.isManager
          ? widget.profile.branchId
          : null;

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _semesters = semesters;
        _selectedSemesterId = semesterId;
        _selectedBranchId = branchId;
      });

      if (semesterId == null) {
        setState(() {
          _loading = false;
          _errorMessage = '조회할 학기가 없습니다.';
        });
        return;
      }

      await _loadReport();
    } on BranchFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } on SemesterFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '근무 리포트 초기 정보를 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _loadReport() async {
    final semesterId = _selectedSemesterId;
    if (semesterId == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final report = await _reportRepository.fetchReport(
        semesterId: semesterId,
        branchId: _selectedBranchId,
      );
      if (!mounted) return;
      setState(() => _report = report);
    } on StaffWorkReportFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _changeSemester(String value) async {
    if (value == _selectedSemesterId) return;
    setState(() => _selectedSemesterId = value);
    await _loadReport();
  }

  Future<void> _changeBranch(String value) async {
    final next = value == '__all__' ? null : value;
    if (next == _selectedBranchId) return;
    setState(() => _selectedBranchId = next);
    await _loadReport();
  }

  ManagedSemester? get _selectedSemester {
    final id = _selectedSemesterId;
    if (id == null) return null;
    for (final semester in _semesters) {
      if (semester.id == id) return semester;
    }
    return null;
  }

  String get _selectedBranchLabel {
    final id = _selectedBranchId;
    if (id == null) return '전체 지점';
    for (final branch in _branches) {
      if (branch.id == id) return branch.name;
    }
    return '전체 지점';
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '근무 리포트',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _loadReport,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReport,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            _scopeCard(),
            const SizedBox(height: 10),
            _filters(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              _errorCard(),
            ],
            if (_loading && report == null)
              const Padding(
                padding: EdgeInsets.only(top: 90),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (report != null) ...[
              const SizedBox(height: 18),
              _summary(report),
              const SizedBox(height: 20),
              _sectionTitle(
                '수업 길이 구성',
                '실제 종료된 미취소 수업 기준',
              ),
              const SizedBox(height: 9),
              _durationComposition(report),
              const SizedBox(height: 20),
              _sectionTitle(
                '지점별 근무시간',
                '지점별 학기 기간 설정을 반영합니다.',
              ),
              const SizedBox(height: 9),
              _branchComparison(report),
              const SizedBox(height: 20),
              _sectionTitle(
                '선생님별 근무 기록',
                '수업시간이 긴 순서로 표시합니다.',
              ),
              const SizedBox(height: 9),
              _staffComparison(report),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '마지막 계산 ${DateFormat('MM.dd HH:mm').format(report.calculatedAt)}',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black38,
                    fontSize: 9.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scopeCard() {
    final semester = _selectedSemester;
    final code = semester == null
        ? '학기 미선택'
        : _semesterLabel(semester.code);

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: const Color(0xffEAF3E9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.analytics_outlined,
              color: primaryColor,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '수업 종료 시각이 지났고 취소되지 않은 수업만 집계합니다.',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '표시된 시간은 출퇴근 시간이 아니라 수업 기록 기준 근무시간입니다.',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black38,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Row(
      children: [
        PopupMenuButton<String>(
          initialValue: _selectedSemesterId,
          enabled: !_loading && _semesters.isNotEmpty,
          onSelected: _changeSemester,
          itemBuilder: (context) => _semesters
              .map(
                (semester) => PopupMenuItem(
                  value: semester.id,
                  child: Text(_semesterLabel(semester.code)),
                ),
              )
              .toList(),
          child: ManagementFilterPillSurface(
            icon: Icons.calendar_month_outlined,
            label: _selectedSemester == null
                ? '학기'
                : _semesterLabel(_selectedSemester!.code),
          ),
        ),
        if (widget.profile.isMaster) ...[
          const SizedBox(width: 7),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                initialValue: _selectedBranchId ?? '__all__',
                enabled: !_loading,
                onSelected: _changeBranch,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: '__all__',
                    child: Text('전체 지점'),
                  ),
                  ..._branches.map(
                    (branch) => PopupMenuItem(
                      value: branch.id,
                      child: Text(branch.name),
                    ),
                  ),
                ],
                child: ManagementFilterPillSurface(
                  icon: Icons.storefront_outlined,
                  label: _selectedBranchLabel,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _summary(StaffWorkReport report) {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            icon: Icons.schedule_rounded,
            value: _minutesText(report.totalMinutes),
            label: '총 수업시간',
            background: const Color(0xffEAF3E9),
            iconColor: primaryColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            icon: Icons.event_available_outlined,
            value: '${report.totalLessonCount}회',
            label: '완료 수업',
            background: const Color(0xffFBF2E2),
            iconColor: const Color(0xff98651B),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            icon: Icons.co_present_outlined,
            value: '${report.staffCount}명',
            label: '수업 담당',
            background: const Color(0xffEEF1F8),
            iconColor: const Color(0xff5E6F9B),
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String value,
    required String label,
    required Color background,
    required Color iconColor,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.fromLTRB(10, 11, 10, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: forestringTextStyle.copyWith(
              color: Colors.black45,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _durationComposition(StaffWorkReport report) {
    final counts = <int, int>{};
    for (final staff in report.staff) {
      for (final group in staff.durationGroups) {
        counts[group.durationMinutes] =
            (counts[group.durationMinutes] ?? 0) + group.lessonCount;
      }
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (entries.isEmpty) {
      return _emptyCard('집계된 수업이 없습니다.');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: _surfaceDecoration(),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: entries
            .map(
              (entry) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.055),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  '${entry.key}분 · ${entry.value}회',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _branchComparison(StaffWorkReport report) {
    final rows = report.branches
        .where(
          (branch) =>
              branch.lessonCount > 0 ||
              report.branchId == branch.branchId,
        )
        .toList();

    if (rows.isEmpty) {
      return _emptyCard('집계된 지점 수업이 없습니다.');
    }

    final maxMinutes = rows.fold<int>(
      0,
      (max, row) => row.totalMinutes > max ? row.totalMinutes : max,
    );

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: _surfaceDecoration(),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            _comparisonRow(
              title: rows[index].branchName,
              subtitle:
                  '${rows[index].lessonCount}회 · ${rows[index].staffCount}명',
              valueText: _minutesText(rows[index].totalMinutes),
              ratio: maxMinutes == 0
                  ? 0
                  : rows[index].totalMinutes / maxMinutes,
              color: primaryColor,
            ),
            if (index != rows.length - 1)
              const SizedBox(height: 15),
          ],
        ],
      ),
    );
  }

  Widget _staffComparison(StaffWorkReport report) {
    if (report.staff.isEmpty) {
      return _emptyCard('집계된 선생님 수업이 없습니다.');
    }

    final maxMinutes = report.staff.fold<int>(
      0,
      (max, staff) =>
          staff.totalMinutes > max ? staff.totalMinutes : max,
    );

    return Column(
      children: [
        for (var index = 0; index < report.staff.length; index++) ...[
          _staffCard(
            report.staff[index],
            maxMinutes: maxMinutes,
          ),
          if (index != report.staff.length - 1)
            const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _staffCard(
    StaffWorkSummary staff, {
    required int maxMinutes,
  }) {
    final ratio =
        maxMinutes == 0 ? 0.0 : staff.totalMinutes / maxMinutes;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: _surfaceDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xffEEF1F8),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  staff.isManager
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline_rounded,
                  color: const Color(0xff5E6F9B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            staff.staffName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: forestringTextStyle.copyWith(
                              color: Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (staff.isManager) ...[
                          const SizedBox(width: 6),
                          _miniBadge('지점장'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      staff.branchName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black45,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _minutesText(staff.totalMinutes),
                    style: forestringTextStyle.copyWith(
                      color: primaryColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${staff.lessonCount}회',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black38,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _bar(ratio, primaryColor),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...staff.durationGroups.map(
                (group) => _detailChip(
                  '${group.durationMinutes}분 ${group.lessonCount}회',
                ),
              ),
              ...staff.typeGroups.map(
                (group) => _detailChip(
                  '${group.label} ${group.lessonCount}회',
                  muted: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _comparisonRow({
    required String title,
    required String subtitle,
    required String valueText,
    required double ratio,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: forestringTextStyle.copyWith(
                      color: Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: forestringTextStyle.copyWith(
                      color: Colors.black38,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              valueText,
              style: forestringTextStyle.copyWith(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        _bar(ratio, color),
      ],
    );
  }

  Widget _bar(double ratio, Color color) {
    final safeRatio = ratio.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 8,
        color: color.withValues(alpha: 0.08),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: safeRatio,
          child: Container(
            color: color.withValues(alpha: 0.58),
          ),
        ),
      ),
    );
  }

  Widget _detailChip(
    String label, {
    bool muted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: muted
            ? Colors.black.withValues(alpha: 0.035)
            : primaryColor.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: muted ? Colors.black54 : primaryColor,
          fontSize: 9.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _miniBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: const Color(0xff5E6F9B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: const Color(0xff5E6F9B),
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _sectionTitle(
    String title,
    String subtitle,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: forestringTextStyle.copyWith(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: forestringTextStyle.copyWith(
              color: Colors.black38,
              fontSize: 9.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: _surfaceDecoration(),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: forestringTextStyle.copyWith(
          color: Colors.black45,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _errorCard() {
    return InkWell(
      onTap: _loadReport,
      borderRadius: BorderRadius.circular(13),
      child: Container(
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
                _errorMessage!,
                style: forestringTextStyle.copyWith(
                  color: Colors.redAccent,
                  fontSize: 10.5,
                ),
              ),
            ),
            Text(
              '다시 시도',
              style: forestringTextStyle.copyWith(
                color: Colors.redAccent,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _surfaceDecoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(
        color: primaryColor.withValues(alpha: 0.07),
      ),
    );
  }
}

String _semesterLabel(String code) {
  final match =
      RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(code.trim());
  if (match == null) return code;
  return '${match.group(1)}년 ${int.parse(match.group(2)!)}월 학기';
}

String _minutesText(int minutes) {
  if (minutes < 60) return '$minutes분';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0
      ? '$hours시간'
      : '$hours시간 $remainder분';
}
