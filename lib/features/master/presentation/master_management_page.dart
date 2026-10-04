import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/theme/student_accent_controller.dart';
import '../../auth/domain/current_profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../../branches/presentation/branch_management_page.dart';
import '../../managers/data/manager_repository.dart';
import '../../managers/presentation/manager_management_page.dart';
import '../../semesters/data/semester_repository.dart';
import '../../semesters/domain/managed_semester.dart';
import '../../semesters/presentation/semester_management_page.dart';

class MasterManagementPage extends StatefulWidget {
  const MasterManagementPage({
    super.key,
    required this.profile,
    this.branchRepository,
    this.managerRepository,
    this.semesterRepository,
  });

  final CurrentProfile profile;
  final BranchRepository? branchRepository;
  final ManagerRepository? managerRepository;
  final SemesterRepository? semesterRepository;

  @override
  State<MasterManagementPage> createState() =>
      _MasterManagementPageState();
}

class _MasterManagementPageState extends State<MasterManagementPage> {
  late final BranchRepository _branchRepository;
  late final ManagerRepository _managerRepository;
  late final SemesterRepository _semesterRepository;

  List<AcademyBranch> _branches = const [];
  List<ManagedManager> _managers = const [];
  List<ManagedSemester> _semesters = const [];
  bool _loading = true;
  String? _overviewError;

  @override
  void initState() {
    super.initState();
    _branchRepository = widget.branchRepository ?? BranchRepository();
    _managerRepository = widget.managerRepository ?? ManagerRepository();
    _semesterRepository =
        widget.semesterRepository ?? SemesterRepository();
    _loadOverview();
  }

  Future<void> _loadOverview() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _overviewError = null;
      });
    }

    try {
      final results = await Future.wait([
        _branchRepository.fetchBranches(),
        _managerRepository.fetchManagers(),
        _semesterRepository.fetchSemesters(),
      ]);

      if (!mounted) return;

      setState(() {
        _branches = results[0] as List<AcademyBranch>;
        _managers = results[1] as List<ManagedManager>;
        _semesters = results[2] as List<ManagedSemester>;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _overviewError = '운영 현황을 불러오지 못했습니다.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int get _activeBranchCount =>
      _branches.where((branch) => branch.isActive).length;

  int get _activeManagerCount =>
      _managers.where((manager) => manager.isActive).length;

  ManagedSemester? get _currentSemester {
    for (final semester in _semesters) {
      if (semester.isCurrent) return semester;
    }
    return null;
  }

  String get _currentSemesterLabel {
    final semester = _currentSemester;
    if (semester == null) return '없음';

    final match =
        RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(semester.code.trim());
    if (match == null) return semester.code;

    return '${int.parse(match.group(2)!)}월';
  }

  Future<void> _openManagerManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const ManagerManagementPage(),
      ),
    );
    if (mounted) await _loadOverview();
  }

  Future<void> _openBranchManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BranchManagementPage(
          profile: widget.profile,
        ),
      ),
    );
    if (mounted) await _loadOverview();
  }

  Future<void> _openSemesterManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const SemesterManagementPage(),
      ),
    );
    if (mounted) await _loadOverview();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              '로그아웃',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            content: Text(
              '전체 관리자 계정에서 로그아웃하시겠습니까?',
              style: forestringTextStyle.copyWith(
                color: Colors.black87,
                fontSize: 14,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(true),
                child: Text(
                  '로그아웃',
                  style: forestringTextStyle.copyWith(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;
    await context.read<AuthController>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final accentController = context.watch<StudentAccentController>();

    return Scaffold(
      backgroundColor: neutralIvory,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadOverview,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 30),
            children: [
              _masterHero(),
              const SizedBox(height: 14),
              _overviewCard(),
              if (_overviewError != null) ...[
                const SizedBox(height: 8),
                _overviewErrorCard(),
              ],
              const SizedBox(height: 22),
              _sectionTitle(
                '운영 관리',
                subtitle: '학원 전체에 영향을 주는 설정입니다.',
              ),
              const SizedBox(height: 10),
              _managementGrid(),
              const SizedBox(height: 22),
              _sectionTitle(
                '화면 설정',
                subtitle: '이 계정에서 보이는 화면만 변경됩니다.',
              ),
              const SizedBox(height: 10),
              _settingsCard(accentController),
              const SizedBox(height: 22),
              _sectionTitle('계정'),
              const SizedBox(height: 10),
              _logoutCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _masterHero() {
    final name = widget.profile.displayName.trim();
    final displayName = name.isEmpty ? '관리자' : name;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            primaryColor,
            Color(0xff315E45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            top: -18,
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white.withValues(alpha: 0.07),
              size: 124,
            ),
          ),
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '전체 관리자',
                        style: forestringTextStyle.copyWith(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '$displayName님',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '포레스트링 전체 지점의 운영과 권한을 관리합니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.white70,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overviewCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '전체 운영 현황',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: primaryColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _metricCell(
                  icon: Icons.storefront_outlined,
                  label: '운영 지점',
                  value: _loading ? '—' : '$_activeBranchCount곳',
                  backgroundColor: const Color(0xffEDF5ED),
                  iconColor: const Color(0xff477253),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCell(
                  icon: Icons.badge_outlined,
                  label: '재직 지점장',
                  value: _loading ? '—' : '$_activeManagerCount명',
                  backgroundColor: const Color(0xffEEF1F8),
                  iconColor: const Color(0xff5E6F9B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCell(
                  icon: Icons.calendar_month_outlined,
                  label: '현재 학기',
                  value: _loading ? '—' : _currentSemesterLabel,
                  backgroundColor: const Color(0xffFBF3E3),
                  iconColor: const Color(0xff98651B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCell({
    required IconData icon,
    required String label,
    required String value,
    required Color backgroundColor,
    required Color iconColor,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.fromLTRB(10, 11, 10, 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 18,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: forestringTextStyle.copyWith(
              color: Colors.black45,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _managementGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _managementCard(
                icon: Icons.admin_panel_settings_outlined,
                title: '지점장',
                description: '계정 · 담당 지점 · 퇴사',
                value: _loading ? null : '$_activeManagerCount명 재직',
                backgroundColor: const Color(0xffEEF1F8),
                iconColor: const Color(0xff5E6F9B),
                onTap: _openManagerManagement,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _managementCard(
                icon: Icons.storefront_outlined,
                title: '지점',
                description: '지점 정보 · 운영 상태',
                value: _loading ? null : '$_activeBranchCount곳 운영',
                backgroundColor: const Color(0xffEAF3E9),
                iconColor: const Color(0xff477253),
                onTap: _openBranchManagement,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _managementCard(
          icon: Icons.event_note_outlined,
          title: '학기',
          description: '기본 기간 · 지점별 기간 · 휴원',
          value: _loading
              ? null
              : _currentSemester == null
                  ? '현재 학기 없음'
                  : '$_currentSemesterLabel 학기 운영 중',
          backgroundColor: const Color(0xffFBF2E2),
          iconColor: const Color(0xff98651B),
          onTap: _openSemesterManagement,
          wide: true,
        ),
      ],
    );
  }

  Widget _managementCard({
    required IconData icon,
    required String title,
    required String description,
    required String? value,
    required Color backgroundColor,
    required Color iconColor,
    required VoidCallback onTap,
    bool wide = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: EdgeInsets.fromLTRB(
            15,
            wide ? 15 : 16,
            13,
            wide ? 15 : 14,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: iconColor.withValues(alpha: 0.07),
            ),
          ),
          child: wide
              ? Row(
                  children: [
                    _managementIcon(icon, iconColor),
                    const SizedBox(width: 13),
                    Expanded(
                      child: _managementText(
                        title: title,
                        description: description,
                        value: value,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.black38,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _managementIcon(icon, iconColor),
                        const Spacer(),
                        const Icon(
                          Icons.arrow_outward_rounded,
                          color: Colors.black38,
                          size: 17,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _managementText(
                      title: title,
                      description: description,
                      value: value,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _managementIcon(IconData icon, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: color,
        size: 21,
      ),
    );
  }

  Widget _managementText({
    required String title,
    required String description,
    required String? value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: forestringTextStyle.copyWith(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: forestringTextStyle.copyWith(
            color: Colors.black45,
            fontSize: 10.5,
          ),
        ),
        if (value != null) ...[
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _settingsCard(StudentAccentController accentController) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 3,
        ),
        secondary: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xffE8F0E4),
            shape: BoxShape.circle,
          ),
          child: Icon(
            accentController.isEnabled
                ? Icons.palette_rounded
                : Icons.palette_outlined,
            color: primaryColor,
            size: 21,
          ),
        ),
        title: Text(
          '학생별 색상 구분',
          style: forestringTextStyle.copyWith(
            color: Colors.black87,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          accentController.isEnabled
              ? '학생별 색상을 사용 중입니다. 수업 상태 표시는 함께 유지됩니다.'
              : '수업 종류와 변경 상태를 기준으로 색상을 표시합니다.',
          style: forestringTextStyle.copyWith(
            color: Colors.black45,
            fontSize: 10.5,
            height: 1.35,
          ),
        ),
        value: accentController.isEnabled,
        activeThumbColor: primaryColor,
        onChanged: (value) => accentController.setEnabled(value),
      ),
    );
  }

  Widget _logoutCard() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _confirmLogout,
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xffFFF7F6),
          foregroundColor: Colors.redAccent,
          padding: const EdgeInsets.symmetric(vertical: 13),
          side: BorderSide(
            color: Colors.redAccent.withValues(alpha: 0.15),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(
          Icons.logout_rounded,
          size: 19,
        ),
        label: Text(
          '전체 관리자 계정 로그아웃',
          style: forestringTextStyle.copyWith(
            color: Colors.redAccent,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(
    String title, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: forestringTextStyle.copyWith(
                  color: Colors.black38,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _overviewErrorCard() {
    return InkWell(
      onTap: _loadOverview,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
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
                _overviewError!,
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
}
