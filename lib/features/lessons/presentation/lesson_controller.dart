import 'package:flutter/foundation.dart';

import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/lesson_repository.dart';
import '../domain/lesson.dart';

class LessonController extends ChangeNotifier {
  LessonController(
    this._repository,
    this._profile, {
    BranchRepository? branchRepository,
  }) : _branchRepository = branchRepository ?? BranchRepository();

  static const _preferredMasterBranchName = '포레스트링 키즈';
  static const _preferredMasterTeacherName = '포링키즈';

  final LessonRepository _repository;
  final BranchRepository _branchRepository;
  final CurrentProfile _profile;

  bool _isLoading = false;
  String? _errorMessage;
  List<Lesson> _lessons = const [];
  List<TeacherBlockedPeriod> _blockedPeriods = const [];
  List<VisibleTeacher> _teachers = const [];
  List<AcademyBranch> _branches = const [];
  Map<String, List<TeacherWorkHour>> _workHours = const {};
  String? _selectedBranchId;
  String? _selectedTeacherId;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Lesson> get lessons => _lessons;
  List<TeacherBlockedPeriod> get blockedPeriods => _blockedPeriods;
  List<VisibleTeacher> get teachers => _teachers;
  List<AcademyBranch> get branches => _branches;
  Map<String, List<TeacherWorkHour>> get workHours => _workHours;
  String? get selectedBranchId => _selectedBranchId;
  String? get selectedTeacherId => _selectedTeacherId;

  bool get isMaster => _profile.role == AppRole.master;
  bool get isManager => _profile.role == AppRole.manager;
  bool get canManageLessons => isMaster || isManager;
  LessonRepository get repository => _repository;


  List<VisibleTeacher> get branchTeachers {
    if (!canManageLessons || _selectedBranchId == null) {
      return _teachers;
    }

    return _teachers
        .where((teacher) => teacher.branchId == _selectedBranchId)
        .toList();
  }

  List<Lesson> get visibleLessons {
    final teacherId = _selectedTeacherId;
    if (!canManageLessons || teacherId == null || teacherId.isEmpty) {
      return _lessons;
    }

    return _lessons
        .where((lesson) => lesson.teacherId == teacherId)
        .toList();
  }

  List<TeacherBlockedPeriod> get visibleBlockedPeriods {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return canManageLessons ? _blockedPeriods : const [];
    }

    return _blockedPeriods
        .where((period) => period.teacherId == teacherId)
        .toList();
  }

  Future<void> initialize() async {
    await reload();
  }

  Future<void> reload() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final from = DateTime(
        now.year,
        now.month - 2,
        1,
      );
      final to = DateTime(
        now.year,
        now.month + 4,
        1,
      );

      if (canManageLessons) {
        final results = await Future.wait<dynamic>([
          _repository.fetchVisibleLessons(
            from: from,
            to: to,
          ),
          _repository.fetchVisibleTeachers(),
          _repository.fetchVisibleWorkHours(),
          _branchRepository.fetchBranches(),
          _repository.fetchVisibleBlockedPeriods(
            from: from,
            to: to,
          ),
        ]);

        final loadedLessons = results[0] as List<Lesson>;
        final loadedTeachers = List<VisibleTeacher>.from(
          results[1] as List<VisibleTeacher>,
        );
        final loadedBranches = (results[3] as List<AcademyBranch>)
            .where((branch) => branch.isActive)
            .toList();

        if (isManager) {
          final branchId = _profile.branchId;
          if (branchId == null) {
            _lessons = const [];
            _teachers = const [];
            _branches = const [];
            _workHours = const {};
            _selectedBranchId = null;
            _selectedTeacherId = null;
            _errorMessage = '지점 정보가 없는 지점장 계정입니다.';
            return;
          }

          _lessons = loadedLessons
              .where((lesson) => lesson.branchId == branchId)
              .toList();
          _blockedPeriods = (results[4] as List<TeacherBlockedPeriod>)
              .where(
                (period) => loadedTeachers.any(
                  (teacher) =>
                      teacher.id == period.teacherId &&
                      teacher.branchId == branchId,
                ),
              )
              .toList();
          _teachers = loadedTeachers
              .where((teacher) => teacher.branchId == branchId)
              .toList();
          _branches = loadedBranches
              .where((branch) => branch.id == branchId)
              .toList();
        } else {
          _lessons = loadedLessons;
          _blockedPeriods = results[4] as List<TeacherBlockedPeriod>;
          _teachers = loadedTeachers;
          _branches = loadedBranches;
        }

        _teachers.sort(
          (a, b) => a.displayName.compareTo(b.displayName),
        );
        _branches.sort(
          (a, b) => a.name.compareTo(b.name),
        );

        _workHours = results[2] as Map<String, List<TeacherWorkHour>>;

        final branchStillExists = _selectedBranchId != null &&
            _branches.any((branch) => branch.id == _selectedBranchId);

        if (!branchStillExists) {
          _selectedBranchId = _initialBranchId();
        }

        _ensureTeacherSelectionForBranch();
      } else {
        final results = await Future.wait<dynamic>([
          _repository.fetchVisibleLessons(
            from: from,
            to: to,
            teacherId: _profile.id,
          ),
          _repository.fetchVisibleWorkHours(
            teacherId: _profile.id,
          ),
          _repository.fetchVisibleBlockedPeriods(
            from: from,
            to: to,
            teacherId: _profile.id,
          ),
        ]);

        _lessons = results[0] as List<Lesson>;
        _workHours = results[1] as Map<String, List<TeacherWorkHour>>;
        _blockedPeriods = results[2] as List<TeacherBlockedPeriod>;
        _teachers = [
          VisibleTeacher(
            id: _profile.id,
            displayName: _profile.displayName,
            branchId: _profile.branchId,
          ),
        ];
        _selectedBranchId = _profile.branchId;
        _selectedTeacherId = _profile.id;
      }
    } on LessonFailure catch (error) {
      _errorMessage = error.message;
    } on BranchFailure catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = '수업 정보를 불러오지 못했습니다.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String? _initialBranchId() {
    if (_branches.isEmpty) return null;
    if (!isMaster) return _branches.first.id;

    for (final branch in _branches) {
      if (branch.name == _preferredMasterBranchName) {
        return branch.id;
      }
    }
    return _branches.first.id;
  }

  void selectBranch(String branchId) {
    if (_selectedBranchId == branchId) {
      return;
    }

    if (isManager && branchId != _profile.branchId) {
      return;
    }

    _selectedBranchId = branchId;
    _selectedTeacherId = null;
    _ensureTeacherSelectionForBranch();
    notifyListeners();
  }

  void selectTeacher(String teacherId) {
    if (_selectedTeacherId == teacherId) {
      return;
    }

    if (canManageLessons &&
        !branchTeachers.any((teacher) => teacher.id == teacherId)) {
      return;
    }

    _selectedTeacherId = teacherId;
    notifyListeners();
  }

  void selectAllTeachers() {
    if (!canManageLessons || _selectedTeacherId == null) {
      return;
    }
    _selectedTeacherId = null;
    notifyListeners();
  }

  void _ensureTeacherSelectionForBranch() {
    final candidates = branchTeachers;

    final teacherStillVisible = _selectedTeacherId != null &&
        candidates.any((teacher) => teacher.id == _selectedTeacherId);

    if (teacherStillVisible) return;

    if (isManager) {
      _selectedTeacherId = null;
      return;
    }

    if (isMaster) {
      for (final teacher in candidates) {
        if (teacher.displayName == _preferredMasterTeacherName) {
          _selectedTeacherId = teacher.id;
          return;
        }
      }
    }

    _selectedTeacherId = candidates.isNotEmpty ? candidates.first.id : null;
  }

  List<Lesson> lessonsOn(DateTime date) {
    return visibleLessons.where((lesson) {
      if (lesson.isCanceled) {
        return false;
      }

      final local = lesson.startsAt;
      return local.year == date.year &&
          local.month == date.month &&
          local.day == date.day;
    }).toList();
  }

  List<TeacherBlockedPeriod> blockedPeriodsOn(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    return visibleBlockedPeriods.where((period) {
      return period.startsAt.isBefore(dayEnd) &&
          period.endsAt.isAfter(dayStart);
    }).toList();
  }

  List<TeacherWorkHour> workHoursFor(String teacherId) {
    return _workHours[teacherId] ?? const [];
  }

  Future<bool> cancelLesson(
    Lesson lesson, {
    String? reason,
  }) async {
    if (!canManageLessons) {
      _errorMessage = '일반 선생님은 수업을 조회만 할 수 있습니다.';
      notifyListeners();
      return false;
    }

    try {
      if (lesson.type == LessonType.makeup && lesson.lessonRightId == null) {
        await _repository.cancelStandaloneMakeupLesson(
          lessonId: lesson.id,
          reason: reason,
        );
      } else {
        await _repository.cancelLesson(
          lessonId: lesson.id,
          reason: reason,
        );
      }
      await reload();
      return true;
    } on LessonFailure catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    }
  }

  Future<LessonMutationResult?> updateLessonOnce({
    required Lesson lesson,
    required DateTime startsAt,
    required int durationMinutes,
    bool confirmWarnings = false,
    String? reason,
  }) async {
    if (!canManageLessons) {
      _errorMessage = '일반 선생님은 수업을 조회만 할 수 있습니다.';
      notifyListeners();
      return null;
    }

    try {
      final result = await _repository.updateLessonOnce(
        lessonId: lesson.id,
        startsAt: startsAt,
        durationMinutes: durationMinutes,
        confirmWarnings: confirmWarnings,
        reason: reason,
      );

      if (!result.requiresConfirmation) {
        await reload();
      }

      return result;
    } on LessonFailure catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return null;
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }
}
