import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../../branches/domain/branch_closure.dart';
import '../data/semester_repository.dart';
import '../domain/managed_semester.dart';
import 'semester_default_closure_page.dart';

class SemesterDetailPage extends StatefulWidget {
  const SemesterDetailPage({
    super.key,
    required this.semesterId,
  });

  final String semesterId;

  @override
  State<SemesterDetailPage> createState() => _SemesterDetailPageState();
}

class _SemesterDetailPageState extends State<SemesterDetailPage> {
  final _repository = SemesterRepository();
  final _branchRepository = BranchRepository();

  List<ManagedSemester> _semesters = const [];
  List<AcademyBranch> _branches = const [];
  List<DefaultClosure> _defaultClosures = const [];
  Map<String, List<BranchClosure>> _closuresByBranch = const {};
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  ManagedSemester? get _semester {
    for (final semester in _semesters) {
      if (semester.id == widget.semesterId) return semester;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
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
      final results = await Future.wait([
        _repository.fetchSemesters(),
        _branchRepository.fetchBranches(),
      ]);

      final semesters = (results[0] as List<ManagedSemester>).toList()
        ..sort((a, b) => a.startsOn.compareTo(b.startsOn));
      final branches = (results[1] as List<AcademyBranch>).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      ManagedSemester? selected;
      for (final semester in semesters) {
        if (semester.id == widget.semesterId) {
          selected = semester;
          break;
        }
      }

      var defaultClosures = <DefaultClosure>[];
      if (selected != null) {
        defaultClosures = await _branchRepository.fetchDefaultClosuresForSemester(
          semesterId: selected.id,
        );
      }

      final closuresByBranch = <String, List<BranchClosure>>{};
      if (selected != null && branches.isNotEmpty) {
        final closureResults = await Future.wait(
          branches.map(
            (branch) => _branchRepository.fetchBranchClosuresInRange(
              branchId: branch.id,
              startsOn: selected!.effectiveStart(branch.id),
              endsOn: selected.effectiveEnd(branch.id),
            ),
          ),
        );

        for (var i = 0; i < branches.length; i++) {
          closuresByBranch[branches[i].id] = closureResults[i];
        }
      }

      if (!mounted) return;
      setState(() {
        _semesters = semesters;
        _branches = branches;
        _defaultClosures = defaultClosures;
        _closuresByBranch = closuresByBranch;
      });
    } on SemesterFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on BranchFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = '학기 정보를 불러오지 못했습니다.\n$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editCode() async {
    final semester = _semester;
    if (semester == null || _saving) return;

    var code = semester.code;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: Text(
          '학기 이름 수정',
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: TextFormField(
          initialValue: code,
          autofocus: true,
          maxLength: 50,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '학기 이름',
            hintText: '예: 2026-09',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => code = value,
          onFieldSubmitted: (value) {
            final normalized = value.trim();
            if (normalized.isNotEmpty) {
              Navigator.of(dialogContext).pop(normalized);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final normalized = code.trim();
              if (normalized.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('학기 이름을 입력해주세요.')),
                );
                return;
              }
              Navigator.of(dialogContext).pop(normalized);
            },
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (result == null || !mounted || result == semester.code) return;

    await _runSave(
      () => _repository.updateSemesterCode(
        semester: semester,
        code: result,
      ),
      successMessage: '학기 이름을 변경했습니다.',
    );
  }

  Future<void> _editGlobalRange() async {
    final semester = _semester;
    if (semester == null || _saving) return;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      initialDateRange: DateTimeRange(
        start: semester.startsOn,
        end: semester.endsOn,
      ),
      helpText: '기본 학기 기간 변경',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (picked == null || !mounted) return;

    final changes = _buildGlobalChanges(
      semesterId: semester.id,
      startsOn: _dateOnly(picked.start),
      endsOn: _dateOnly(picked.end),
    );
    if (changes == null) return;
    if (changes.isEmpty) {
      _showMessage('변경된 기간이 없습니다.');
      return;
    }

    final confirmed = await _confirmBoundaryChanges(
      title: '기본 학기 기간 변경',
      changes: changes,
    );
    if (confirmed != true || !mounted) return;

    await _runSave(
      () => _repository.applySemesterCalendarChanges(changes),
      successMessage: '기본 학기 기간을 변경했습니다.',
    );
  }

  Future<void> _openDefaultClosures(ManagedSemester semester) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SemesterDefaultClosurePage(semester: semester),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _editBranchRange(AcademyBranch branch) async {
    final semester = _semester;
    if (semester == null || _saving) return;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      initialDateRange: DateTimeRange(
        start: semester.effectiveStart(branch.id),
        end: semester.effectiveEnd(branch.id),
      ),
      helpText: '${branch.name} 학기 기간',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (picked == null || !mounted) return;

    final changes = _buildBranchChanges(
      branchId: branch.id,
      semesterId: semester.id,
      startsOn: _dateOnly(picked.start),
      endsOn: _dateOnly(picked.end),
    );
    if (changes == null) return;
    if (changes.isEmpty) {
      _showMessage('변경된 기간이 없습니다.');
      return;
    }

    final confirmed = await _confirmBoundaryChanges(
      title: '${branch.name} 기간 변경',
      changes: _branchPreviewChanges(changes),
    );
    if (confirmed != true || !mounted) return;

    await _runSave(
      () => _repository.applyBranchSemesterChanges(
        branchId: branch.id,
        changes: changes,
      ),
      successMessage: '${branch.name} 학기 기간을 변경했습니다.',
    );
  }

  Future<void> _resetBranchRange(AcademyBranch branch) async {
    final semester = _semester;
    if (semester == null || semester.overrideFor(branch.id) == null || _saving) {
      return;
    }

    final changes = _buildBranchChanges(
      branchId: branch.id,
      semesterId: semester.id,
      startsOn: semester.startsOn,
      endsOn: semester.endsOn,
    );
    if (changes == null || changes.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('기본 기간으로 복원'),
        content: Text(
          '${branch.name}의 별도 학기 기간을 해제하고 기본 학기 일정을 사용합니다.\n\n'
          '앞·뒤 학기의 지점별 경계도 필요한 경우 함께 정리됩니다.',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            child: const Text('복원'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runSave(
      () => _repository.applyBranchSemesterChanges(
        branchId: branch.id,
        changes: changes,
      ),
      successMessage: '${branch.name}이(가) 기본 학기 일정을 사용하도록 변경했습니다.',
    );
  }

  Future<void> _editClosure(
    AcademyBranch branch,
    BranchClosureKind kind, [
    BranchClosure? closure,
  ]) async {
    final semester = _semester;
    if (semester == null || _saving) return;

    final scopeStart = semester.effectiveStart(branch.id);
    final scopeEnd = semester.effectiveEnd(branch.id);
    final today = _dateOnly(DateTime.now());

    var start = closure?.startsOn ?? _defaultClosureStart(
      scopeStart: scopeStart,
      scopeEnd: scopeEnd,
      kind: kind,
      today: today,
    );
    var end = closure?.endsOn ??
        (kind == BranchClosureKind.instructionalBreak
            ? start.add(const Duration(days: 6))
            : start);
    var reason = closure?.reason ?? '';
    String? dialogError;

    final shouldSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final days = end.difference(start).inDays + 1;

          Future<void> chooseRange() async {
            final picked = await showDateRangePicker(
              context: dialogContext,
              firstDate: DateTime(2020),
              lastDate: DateTime(DateTime.now().year + 10, 12, 31),
              initialDateRange: DateTimeRange(start: start, end: end),
              helpText: kind == BranchClosureKind.instructionalBreak
                  ? '휴원 주간 선택'
                  : '휴원일 선택',
              cancelText: '취소',
              confirmText: '선택',
            );
            if (picked == null) return;

            setDialogState(() {
              start = _dateOnly(picked.start);
              end = _dateOnly(picked.end);
              dialogError = null;
            });
          }

          return AlertDialog(
            backgroundColor: neutralIvory,
            title: Text(
              closure == null
                  ? (kind == BranchClosureKind.instructionalBreak
                      ? '휴원 주간 추가'
                      : '휴원일 추가')
                  : (kind == BranchClosureKind.instructionalBreak
                      ? '휴원 주간 수정'
                      : '휴원일 수정'),
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 370,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${branch.name} · ${_semesterLabel(semester.code)}',
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '설정 가능 기간  ${_formatDate(scopeStart)} ~ ${_formatDate(scopeEnd)}',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: chooseRange,
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(
                        start == end
                            ? _formatDate(start)
                            : '${_formatDate(start)} ~ ${_formatDate(end)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kind == BranchClosureKind.instructionalBreak
                          ? '휴원 주간 · $days일'
                          : (days == 1 ? '하루 휴원' : '$days일 휴원'),
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      initialValue: reason,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: '사유 (선택)',
                        hintText: '예: 여름 휴원, 시설 점검',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => reason = value,
                    ),
                    if (kind == BranchClosureKind.instructionalBreak) ...[
                      const SizedBox(height: 2),
                      Text(
                        '휴원 주간은 7일 단위로 저장되며 정규 수업 생성에서 제외됩니다.',
                        style: forestringTextStyle.copyWith(
                          color: Colors.black45,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        dialogError!,
                        style: forestringTextStyle.copyWith(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  final days = end.difference(start).inDays + 1;
                  if (!_withinRange(start, end, scopeStart, scopeEnd)) {
                    setDialogState(() {
                      dialogError = '휴원 일정은 이 지점의 학기 기간 안에서 설정해주세요.';
                    });
                    return;
                  }
                  if (kind == BranchClosureKind.instructionalBreak &&
                      (days < 7 || days % 7 != 0)) {
                    setDialogState(() {
                      dialogError = '휴원 주간은 7일 단위로 선택해주세요.';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                },
                style: FilledButton.styleFrom(backgroundColor: primaryColor),
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );

    if (shouldSave != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _branchRepository.saveClosure(
        closureId: closure?.id,
        branchId: branch.id,
        semesterId:
            kind == BranchClosureKind.instructionalBreak ? semester.id : null,
        startsOn: start,
        endsOn: end,
        kind: kind,
        reason: reason,
      );
      await _load();
      if (!mounted) return;
      _showMessage(closure == null ? '휴원 일정을 추가했습니다.' : '휴원 일정을 수정했습니다.');
    } on BranchFailure catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteClosure(
    AcademyBranch branch,
    BranchClosure closure,
  ) async {
    if (_saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('휴원 일정 삭제'),
        content: Text(
          '${branch.name}\n${_closureRangeText(closure)}\n\n이 휴원 일정을 삭제할까요?',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _branchRepository.deleteClosure(closureId: closure.id);
      await _load();
      if (!mounted) return;
      _showMessage('휴원 일정을 삭제했습니다.');
    } on BranchFailure catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  DateTime _defaultClosureStart({
    required DateTime scopeStart,
    required DateTime scopeEnd,
    required BranchClosureKind kind,
    required DateTime today,
  }) {
    var start = today.isBefore(scopeStart) ? scopeStart : today;
    if (start.isAfter(scopeEnd)) start = scopeStart;

    if (kind == BranchClosureKind.instructionalBreak &&
        start.add(const Duration(days: 6)).isAfter(scopeEnd)) {
      final candidate = scopeEnd.subtract(const Duration(days: 6));
      start = candidate.isBefore(scopeStart) ? scopeStart : candidate;
    }
    return start;
  }

  List<SemesterCalendarChange>? _buildGlobalChanges({
    required String semesterId,
    required DateTime startsOn,
    required DateTime endsOn,
  }) {
    final index = _semesters.indexWhere((item) => item.id == semesterId);
    if (index < 0) return null;
    if (!_validRange(startsOn, endsOn)) {
      _showMessage('학기 기간은 4주 이상이며 7일 단위여야 합니다.');
      return null;
    }

    final selected = _semesters[index];
    final desired = <String, _Bounds>{
      selected.id: _Bounds(startsOn, endsOn),
    };

    if (startsOn != selected.startsOn && index > 0) {
      final previous = _semesters[index - 1];
      desired[previous.id] = _Bounds(
        previous.startsOn,
        startsOn.subtract(const Duration(days: 1)),
      );
    }
    if (endsOn != selected.endsOn && index < _semesters.length - 1) {
      final next = _semesters[index + 1];
      desired[next.id] = _Bounds(
        endsOn.add(const Duration(days: 1)),
        next.endsOn,
      );
    }

    if (!_validateDesiredBounds(desired, branch: false)) return null;

    final result = <SemesterCalendarChange>[];
    for (final semester in _semesters) {
      final bounds = desired[semester.id];
      if (bounds == null) continue;
      if (bounds.start == semester.startsOn && bounds.end == semester.endsOn) {
        continue;
      }
      result.add(
        SemesterCalendarChange(
          semesterId: semester.id,
          code: semester.code,
          startsOn: bounds.start,
          endsOn: bounds.end,
        ),
      );
    }
    return result;
  }

  List<BranchSemesterChange>? _buildBranchChanges({
    required String branchId,
    required String semesterId,
    required DateTime startsOn,
    required DateTime endsOn,
  }) {
    final index = _semesters.indexWhere((item) => item.id == semesterId);
    if (index < 0) return null;
    if (!_validRange(startsOn, endsOn)) {
      _showMessage('학기 기간은 4주 이상이며 7일 단위여야 합니다.');
      return null;
    }

    final selected = _semesters[index];
    final desired = <String, _Bounds>{
      selected.id: _Bounds(startsOn, endsOn),
    };

    final currentStart = selected.effectiveStart(branchId);
    final currentEnd = selected.effectiveEnd(branchId);
    if (startsOn != currentStart && index > 0) {
      final previous = _semesters[index - 1];
      desired[previous.id] = _Bounds(
        previous.effectiveStart(branchId),
        startsOn.subtract(const Duration(days: 1)),
      );
    }
    if (endsOn != currentEnd && index < _semesters.length - 1) {
      final next = _semesters[index + 1];
      desired[next.id] = _Bounds(
        endsOn.add(const Duration(days: 1)),
        next.effectiveEnd(branchId),
      );
    }

    if (!_validateDesiredBounds(desired, branch: true)) return null;

    final result = <BranchSemesterChange>[];
    for (final semester in _semesters) {
      final bounds = desired[semester.id];
      if (bounds == null) continue;

      final currentStartForBranch = semester.effectiveStart(branchId);
      final currentEndForBranch = semester.effectiveEnd(branchId);
      if (bounds.start == currentStartForBranch &&
          bounds.end == currentEndForBranch) {
        continue;
      }

      final equalsGlobal =
          bounds.start == semester.startsOn && bounds.end == semester.endsOn;
      final existingOverride = semester.overrideFor(branchId);
      if (equalsGlobal) {
        if (existingOverride != null) {
          result.add(BranchSemesterChange.delete(semester.id));
        }
      } else {
        result.add(
          BranchSemesterChange.upsert(
            semesterId: semester.id,
            startsOn: bounds.start,
            endsOn: bounds.end,
          ),
        );
      }
    }
    return result;
  }

  bool _validateDesiredBounds(
    Map<String, _Bounds> desired, {
    required bool branch,
  }) {
    for (final bounds in desired.values) {
      if (!_validRange(bounds.start, bounds.end)) {
        _showMessage(
          branch
              ? '이 경계로 변경하면 인접 학기가 4주 미만이거나 7일 단위가 아니게 됩니다. 지점별 학기 경계는 주 단위로 조정해주세요.'
              : '이 경계로 변경하면 인접 학기가 4주 미만이거나 7일 단위가 아니게 됩니다. 학기 경계는 주 단위로 조정해주세요.',
        );
        return false;
      }
    }
    return true;
  }

  List<SemesterCalendarChange> _branchPreviewChanges(
    List<BranchSemesterChange> changes,
  ) {
    return changes.map((change) {
      final semester = _semesters.firstWhere(
        (item) => item.id == change.semesterId,
      );
      return SemesterCalendarChange(
        semesterId: semester.id,
        code: semester.code,
        startsOn: change.delete ? semester.startsOn : change.startsOn!,
        endsOn: change.delete ? semester.endsOn : change.endsOn!,
      );
    }).toList();
  }

  Future<bool?> _confirmBoundaryChanges({
    required String title,
    required List<SemesterCalendarChange> changes,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: Text(
          title,
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  changes.length > 1
                      ? '학기 사이가 끊기지 않도록 인접 학기 경계도 함께 변경됩니다.'
                      : '선택한 학기 기간을 변경합니다.',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                ...changes.map(
                  (change) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _semesterLabel(change.code),
                          style: forestringTextStyle.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_formatDate(change.startsOn)} ~ ${_formatDate(change.endsOn)}',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '이미 수업이 생성된 학기 경계는 변경할 수 없습니다.',
                  style: forestringTextStyle.copyWith(
                    color: Colors.orange.shade800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
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
  }

  Future<void> _deleteSemester() async {
    final semester = _semester;
    if (semester == null || _saving || _semesters.last.id != semester.id) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('학기 삭제'),
        content: Text(
          '${_semesterLabel(semester.code)}을(를) 삭제합니다.\n\n'
          '수업, 휴원, 학생 학기 데이터 등이 연결되어 있으면 삭제되지 않습니다.',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _repository.deleteSemester(semester.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on SemesterFailure catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runSave(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await action();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      _showMessage(successMessage);
    } on SemesterFailure catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _validRange(DateTime start, DateTime end) {
    final days = end.difference(start).inDays + 1;
    return !end.isBefore(start) && days >= 28 && days % 7 == 0;
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
    final semester = _semester;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '학기 상세',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (_loading && semester == null)
              const Center(child: CircularProgressIndicator())
            else if (semester == null)
              Center(
                child: Text(
                  _errorMessage ?? '학기 정보를 찾을 수 없습니다.',
                  style: forestringTextStyle,
                ),
              )
            else
              RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 36),
                  children: [
                    _headerCard(semester),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _errorCard(_errorMessage!),
                    ],
                    const SizedBox(height: 24),
                    _sectionTitle('기본 학기 설정'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _settingActionButton(
                            icon: Icons.edit_outlined,
                            label: '학기 이름 수정',
                            onPressed: _saving ? null : _editCode,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _settingActionButton(
                            icon: Icons.calendar_month_outlined,
                            label: '기간 변경',
                            onPressed: _saving ? null : _editGlobalRange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '기간 변경 시 인접 학기 경계도 함께 조정됩니다.',
                            style: forestringTextStyle.copyWith(
                              color: Colors.black54,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('기본 휴원'),
                    const SizedBox(height: 5),
                    Text(
                      '모든 지점에 우선 적용되는 기본 휴원 일정입니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                    if (_defaultClosures.isNotEmpty) ...[
                      const SizedBox(height: 11),
                      ..._defaultClosures.map(_defaultClosureRow),
                    ] else ...[
                      const SizedBox(height: 11),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.035),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Text(
                          '등록된 기본 휴원 일정이 없습니다.',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black54,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _openDefaultClosures(semester),
                        icon: const Icon(Icons.event_busy_rounded, size: 23),
                        label: Text(
                          '기본 휴원 주간 · 휴원일 관리',
                          style: forestringTextStyle.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColor,
                          side: BorderSide(
                            color: primaryColor.withValues(alpha: 0.7),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('지점별 기간 · 휴원'),
                    const SizedBox(height: 5),
                    Text(
                      '지점별 학기 기간과 휴원 일정을 관리합니다.',
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 11),
                    ..._branches.map((branch) => _branchCard(semester, branch)),
                    if (_semesters.isNotEmpty &&
                        _semesters.last.id == semester.id) ...[
                      const SizedBox(height: 24),
                      _sectionTitle('학기 삭제'),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _deleteSemester,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('마지막 학기 삭제'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade700),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (_saving)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x22000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(ManagedSemester semester) {
    final statusColor = semester.isCurrent
        ? primaryColor
        : semester.isPast
            ? Colors.black45
            : Colors.blueGrey.shade700;
    final status = semester.isCurrent
        ? '현재 학기'
        : semester.isPast
            ? '종료된 학기'
            : '예정 학기';

    return Container(
      padding: const EdgeInsets.all(15),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xffFBF2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xff98651B),
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _semesterLabel(semester.code),
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: forestringTextStyle.copyWith(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_formatDate(semester.startsOn)} ~ ${_formatDate(semester.endsOn)}',
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${semester.weekCount}주',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '지점별 별도 기간 ${semester.branchOverrides.length}곳',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          backgroundColor: primaryColor.withValues(alpha: 0.04),
          side: BorderSide(
            color: primaryColor.withValues(alpha: 0.10),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: forestringTextStyle.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultClosureRow(DefaultClosure closure) {
    final isBreak = closure.kind == BranchClosureKind.instructionalBreak;
    final reason = closure.reason?.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryColor.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isBreak ? Icons.event_busy_rounded : Icons.event_busy_outlined,
              size: 22,
              color: primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _defaultClosureRangeText(closure),
                  style: forestringTextStyle.copyWith(
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: forestringTextStyle.copyWith(
                      color: primaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _branchCard(ManagedSemester semester, AcademyBranch branch) {
    final override = semester.overrideFor(branch.id);
    final start = semester.effectiveStart(branch.id);
    final end = semester.effectiveEnd(branch.id);
    final weeks = (end.difference(start).inDays + 1) ~/ 7;
    final closures = (_closuresByBranch[branch.id] ?? const <BranchClosure>[])
        .toList()
      ..sort((a, b) => a.startsOn.compareTo(b.startsOn));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: override == null
              ? primaryColor.withValues(alpha: 0.11)
              : primaryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xffEAF3E9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    size: 22,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    branch.name,
                    style: forestringTextStyle.copyWith(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    override == null ? '기본 기간' : '별도 기간',
                    style: forestringTextStyle.copyWith(
                      color: primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${_formatDate(start)} ~ ${_formatDate(end)}',
              style: forestringTextStyle.copyWith(
                color: Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '$weeks주',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _editBranchRange(branch),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: primaryColor,
                      side: BorderSide(
                        color: primaryColor.withValues(alpha: 0.65),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(override == null ? '별도 기간 설정' : '기간 변경'),
                  ),
                ),
                if (override != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : () => _resetBranchRange(branch),
                      child: const Text('기본값으로 복원'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 13),
            Divider(color: primaryColor.withValues(alpha: 0.1), height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '휴원 일정',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${closures.length}건',
                  style: forestringTextStyle.copyWith(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (closures.isEmpty)
              Text(
                '등록된 휴원 일정이 없습니다.',
                style: forestringTextStyle.copyWith(
                  color: Colors.black54,
                  fontSize: 13,
                ),
              )
            else
              ...closures.map((closure) => _closureRow(branch, closure)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _editClosure(
                                branch,
                                BranchClosureKind.instructionalBreak,
                              ),
                      icon: const Icon(Icons.calendar_view_week_outlined, size: 19),
                      label: const Text('휴원 주간'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _editClosure(
                                branch,
                                BranchClosureKind.ordinary,
                              ),
                      icon: const Icon(Icons.event_busy_outlined, size: 19),
                      label: const Text('휴원일'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _closureRow(AcademyBranch branch, BranchClosure closure) {
    final isBreak = closure.kind == BranchClosureKind.instructionalBreak;
    final reason = closure.reason?.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(11, 9, 4, 9),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isBreak
                ? Icons.calendar_view_week_outlined
                : Icons.event_busy_outlined,
            size: 19,
            color: primaryColor,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: InkWell(
              onTap: _saving
                  ? null
                  : () => _editClosure(branch, closure.kind, closure),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _closureRangeText(closure),
                    style: forestringTextStyle.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (reason != null && reason.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '휴원 일정 삭제',
            visualDensity: VisualDensity.compact,
            onPressed: _saving ? null : () => _deleteClosure(branch, closure),
            icon: const Icon(Icons.delete_outline, size: 19),
            color: Colors.red.shade600,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: forestringTextStyle.copyWith(
        color: Colors.black87,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(13),
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

class _Bounds {
  const _Bounds(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _withinRange(
  DateTime start,
  DateTime end,
  DateTime scopeStart,
  DateTime scopeEnd,
) {
  return !start.isBefore(scopeStart) && !end.isAfter(scopeEnd);
}

String _semesterLabel(String code) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(code.trim());
  if (match == null) return code;
  return '${match.group(1)}년 ${int.parse(match.group(2)!)}월 학기';
}

String _defaultClosureRangeText(DefaultClosure closure) {
  if (closure.startsOn == closure.endsOn) {
    return _formatDate(closure.startsOn);
  }
  return '${_formatDate(closure.startsOn)} ~ ${_formatDate(closure.endsOn)}';
}

String _closureRangeText(BranchClosure closure) {
  if (closure.startsOn == closure.endsOn) {
    return _formatDate(closure.startsOn);
  }
  return '${_formatDate(closure.startsOn)} ~ ${_formatDate(closure.endsOn)}';
}

String _formatDate(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year.$month.$day';
}
