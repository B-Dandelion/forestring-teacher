import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../data/branch_repository.dart';
import '../domain/academy_branch.dart';
import '../domain/branch_closure.dart';
import 'branch_closure_page.dart';

class BranchDetailPage extends StatefulWidget {
  const BranchDetailPage({
    super.key,
    required this.branch,
  });

  final AcademyBranch branch;

  @override
  State<BranchDetailPage> createState() => _BranchDetailPageState();
}

class _BranchDetailPageState extends State<BranchDetailPage> {
  final _repository = BranchRepository();

  BranchManagementDetails? _details;
  List<String> _activeManagerNames = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _repository.fetchBranchDetails(
          branchId: widget.branch.id,
        ),
        _repository.fetchActiveManagerNames(
          branchId: widget.branch.id,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _details = results[0] as BranchManagementDetails;
        _activeManagerNames = results[1] as List<String>;
      });
    } on BranchFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rename() async {
    final details = _details;
    if (details == null || _isSaving) return;

    final controller = TextEditingController(text: details.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: Text(
          '지점명 변경',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          style: forestringTextStyle,
          decoration: const InputDecoration(
            labelText: '지점명',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.trim().isEmpty || name.trim() == details.name) {
      return;
    }

    await _runMutation(
      () => _repository.renameBranch(
        branchId: details.branchId,
        name: name,
      ),
      successMessage: '지점명을 변경했습니다.',
    );
  }

  Future<void> _openClosureManagement(BranchClosureKind kind) async {
    final details = _details;
    if (details == null || _isSaving) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BranchClosurePage(
          branchId: details.branchId,
          branchName: details.name,
          initialKind: kind,
        ),
      ),
    );
  }

  Future<void> _changeStatus() async {
    final details = _details;
    if (details == null || _isSaving) return;

    if (details.isActive && !details.canDeactivate) {
      return;
    }

    final willActivate = !details.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: Text(willActivate ? '지점 재활성화' : '지점 비활성화'),
        content: Text(
          willActivate
              ? '${details.name}을(를) 다시 운영 상태로 변경할까요?'
              : '${details.name}을(를) 비활성화할까요?\n\n'
                  '과거 수업과 관리 기록은 삭제되지 않습니다.',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(willActivate ? '재활성화' : '비활성화'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _runMutation(
      () => _repository.setBranchActive(
        branchId: details.branchId,
        isActive: willActivate,
      ),
      successMessage: willActivate
          ? '지점을 다시 활성화했습니다.'
          : '지점을 비활성화했습니다.',
    );
  }

  Future<void> _runMutation(
    Future<BranchManagementDetails> Function() mutation, {
    required String successMessage,
  }) async {
    setState(() => _isSaving = true);

    try {
      final result = await mutation();
      if (!mounted) return;

      setState(() => _details = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } on BranchFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '지점 상세',
        actions: [
          IconButton(
            onPressed: _isLoading || _isSaving ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _details == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _details == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: forestringTextStyle,
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }

    final details = _details!;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
            children: [
              _HeaderCard(details: details),
              const SizedBox(height: 22),
              _SectionTitle('활성 계정'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _CountCard(
                      label: '지점장',
                      count: details.activeManagerCount,
                      icon: Icons.admin_panel_settings_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CountCard(
                      label: '선생님',
                      count: details.activeTeacherCount,
                      icon: Icons.badge_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CountCard(
                      label: '수강생',
                      count: details.activeStudentCount,
                      icon: Icons.groups_outlined,
                    ),
                  ),
                ],
              ),
              if (_activeManagerNames.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _activeManagerNames
                      .map((name) => _ManagerNameCard(name: name))
                      .toList(),
                ),
              ],
              const SizedBox(height: 24),
              _SectionTitle('운영 중인 일정'),
              const SizedBox(height: 10),
              _OperationCard(details: details),
              const SizedBox(height: 24),
              _SectionTitle('휴원 관리'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _openClosureManagement(
                                BranchClosureKind.instructionalBreak,
                              ),
                      icon: const Icon(Icons.calendar_view_week_outlined),
                      label: const Text('휴원 주간'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        minimumSize: const Size.fromHeight(50),
                        side: BorderSide(color: primaryColor.withValues(alpha: 0.12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _openClosureManagement(
                                BranchClosureKind.ordinary,
                              ),
                      icon: const Icon(Icons.event_busy_outlined),
                      label: const Text('휴원일'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        minimumSize: const Size.fromHeight(50),
                        side: BorderSide(color: primaryColor.withValues(alpha: 0.12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: secondaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  details.isActive && !details.canDeactivate
                      ? '지점을 비활성화하려면 활성 계정과 담당 관계, 정규 일정, 남은 예약 수업을 먼저 정리해주세요.'
                      : '지점을 비활성화해도 과거 수업과 관리 기록은 그대로 유지됩니다.',
                  style: forestringTextStyle.copyWith(height: 1.45),
                ),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _rename,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('지점명 변경'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  minimumSize: const Size.fromHeight(54),
                  side: BorderSide(color: primaryColor.withValues(alpha: 0.12)),
                ),
              ),
              const SizedBox(height: 12),
              if (details.isActive)
                OutlinedButton.icon(
                  onPressed: details.canDeactivate && !_isSaving
                      ? _changeStatus
                      : null,
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('지점 비활성화'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    minimumSize: const Size.fromHeight(54),
                    side: BorderSide(
                      color: details.canDeactivate ? Colors.red : Colors.black26,
                    ),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _isSaving ? null : _changeStatus,
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('지점 재활성화'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
            ],
          ),
        ),
        if (_isSaving)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x22000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.details});

  final BranchManagementDetails details;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        details.isActive ? primaryColor : Colors.black45;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
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
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: details.isActive
                  ? const Color(0xffEAF3E9)
                  : const Color(0xffEFEFED),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.storefront_outlined,
              color: statusColor,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              details.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: forestringTextStyle.copyWith(
                color: Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              details.isActive ? '운영 중' : '비활성',
              style: forestringTextStyle.copyWith(
                color: statusColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: forestringTextStyle.copyWith(
        color: Colors.black87,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.label,
    required this.count,
    required this.icon,
  });

  final String label;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xffF6F8F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: primaryColor, size: 23),
          const SizedBox(height: 7),
          Text(
            '$count명',
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 19,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: forestringTextStyle.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

class _ManagerNameCard extends StatelessWidget {
  const _ManagerNameCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.person_outline,
            color: secondaryColor,
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(
            '$name 지점장',
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.details});

  final BranchManagementDetails details;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        children: [
          _row('담당 관계', details.openAssignmentCount),
          const Divider(height: 1),
          _row('정규 일정', details.activeSeriesCount),
          const Divider(height: 1),
          _row('남은 예약 수업', details.remainingLessonCount),
        ],
      ),
    );
  }

  Widget _row(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(child: Text(label, style: forestringTextStyle)),
          Text(
            '$count개',
            style: forestringTextStyle.copyWith(
              color: count == 0 ? primaryColor : Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
