import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../../core/qa/qa_sandbox_repositories.dart';
import '../../../core/qa/qa_sandbox_store.dart';
import '../../../core/theme/forestring_theme.dart';
import '../../../core/theme/student_accent_controller.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../branches/presentation/branch_management_page.dart';
import '../../managers/presentation/manager_management_page.dart';
import '../../semesters/presentation/semester_management_page.dart';
import '../../students/presentation/student_management_page.dart';
import '../../teachers/presentation/teacher_management_page.dart';
import '../domain/lesson.dart';
import 'lesson_controller.dart';
import 'lesson_management_page.dart';
import 'lesson_visual_style.dart';
import 'widgets/blocked_period_calendar_appointment.dart';
import 'widgets/blocked_period_info_dialog.dart';
import 'widgets/lesson_action_dialog.dart';
import 'widgets/lesson_calendar_appointment.dart';

class MasterSchedulePage extends StatelessWidget {
  const MasterSchedulePage({
    super.key,
    required this.profile,
    this.isQaSandbox = false,
    this.onQaExit,
    this.embeddedInShell = false,
  });

  final CurrentProfile profile;
  final bool isQaSandbox;
  final VoidCallback? onQaExit;
  final bool embeddedInShell;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LessonController>();
    final accentController = context.watch<StudentAccentController>();
    final studentAccents = accentController.isEnabled
        ? accentController.assignments(
            controller.visibleLessons.map((lesson) => lesson.studentId),
          )
        : const <String, Color>{};
    final qaStore =
        isQaSandbox ? context.read<QaSandboxStore>() : null;
    final selectedBranchId = controller.selectedBranchId;
    final selectedTeacherId = controller.selectedTeacherId;

    Future<void> resetQaSandbox() async {
      if (!isQaSandbox || qaStore == null) return;

      Navigator.of(context).pop();

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('QA 데이터 초기화'),
          content: const Text(
            '현재 QA 세션에서 변경한 수업, 수강생, 선생님 데이터를 '
            '모두 초기 상태로 되돌립니다.\n\n'
            '운영 데이터에는 영향을 주지 않습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
              ),
              child: const Text('초기화'),
            ),
          ],
        ),
      );

      if (!context.mounted || confirmed != true) return;

      qaStore.reset();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QA 데이터가 초기 상태로 복구되었습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final meetings = <Object>[
      ...controller.visibleLessons
          .where((lesson) => !lesson.isCanceled)
          .map(
            (lesson) => _MasterMeeting(
              lesson,
              studentAccents[lesson.studentId],
            ),
          ),
      ...controller.visibleBlockedPeriods.map(
        (period) => _MasterBlockedMeeting(period),
      ),
    ];

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: embeddedInShell
          ? null
          : ForestringAppBar(
              actions: [
                IconButton(
                  tooltip: '새로고침',
                  onPressed:
                      controller.isLoading ? null : controller.reload,
                  icon: controller.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
      drawer: embeddedInShell
          ? null
          : ForestringDrawer(
        displayName: profile.displayName,
        nameSuffix: profile.isManager ? '지점장님' : '선생님',
        roleLabel: isQaSandbox
            ? 'QA Sandbox · 로컬 데이터'
            : profile.isMaster
                ? '전체 관리자'
                : '환영합니다',
        showHeart: profile.isMaster,
        items: [
          ForestringDrawerItem(
            icon: Icons.home,
            label: '메인 페이지',
            onTap: () => Navigator.of(context).pop(),
          ),
          ForestringDrawerItem(
            icon: accentController.isEnabled
                ? Icons.palette_rounded
                : Icons.palette_outlined,
            label: accentController.isEnabled
                ? '학생별 색상 끄기'
                : '학생별 색상 켜기',
            onTap: () async {
              Navigator.of(context).pop();
              await accentController.setEnabled(
                !accentController.isEnabled,
              );
            },
          ),
          ForestringDrawerItem(
            icon: Icons.calendar_month_outlined,
            label: '수업 관리',
            onTap: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.push(
                MaterialPageRoute(
                  builder: (_) => LessonManagementPage(
                    profile: profile,
                    controller: controller,
                    initialBranchId: controller.selectedBranchId,
                    repository: qaStore == null
                        ? null
                        : QaLessonRepository(qaStore),
                    semesterRepository: qaStore == null
                        ? null
                        : QaSemesterRepository(qaStore),
                    branchRepository: qaStore == null
                        ? null
                        : QaBranchRepository(qaStore),
                    isQaSandbox: isQaSandbox,
                  ),
                ),
              );
            },
          ),
          ForestringDrawerItem(
            icon: Icons.people_alt_outlined,
            label: '수강생 관리',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StudentManagementPage(
                    profile: profile,
                    repository: qaStore == null
                        ? null
                        : QaStudentManagementRepository(qaStore),
                    branchRepository: qaStore == null
                        ? null
                        : QaBranchRepository(qaStore),
                    lessonRepository: qaStore == null
                        ? null
                        : QaLessonRepository(qaStore),
                    adminRepository: qaStore == null
                        ? null
                        : QaStudentAdminRepository(qaStore),
                    nextSemesterRepository: qaStore == null
                        ? null
                        : QaStudentNextSemesterTypeRepository(
                            qaStore,
                          ),
                    regularScheduleRepository: qaStore == null
                        ? null
                        : QaStudentRegularScheduleRepository(
                            qaStore,
                          ),
                    teacherManagementRepository: qaStore == null
                        ? null
                        : QaStudentTeacherManagementRepository(
                            qaStore,
                          ),
                    isQaSandbox: isQaSandbox,
                  ),
                ),
              );
            },
          ),
          ForestringDrawerItem(
            icon: Icons.co_present_outlined,
            label: '선생님 관리',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TeacherManagementPage(
                    profile: profile,
                    repository: qaStore == null
                        ? null
                        : QaTeacherRepository(qaStore),
                    branchRepository: qaStore == null
                        ? null
                        : QaBranchRepository(qaStore),
                    workHoursRepository: qaStore == null
                        ? null
                        : QaTeacherWorkHoursScheduleRepository(
                            qaStore,
                          ),
                    isQaSandbox: isQaSandbox,
                  ),
                ),
              );
            },
          ),
          if (isQaSandbox)
            ForestringDrawerItem(
              icon: Icons.restart_alt_rounded,
              label: 'QA 데이터 초기화',
              onTap: resetQaSandbox,
            ),
          if (!isQaSandbox) ...[
            if (profile.isMaster)
              ForestringDrawerItem(
                icon: Icons.admin_panel_settings_outlined,
                label: '지점장 관리',
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ManagerManagementPage(),
                    ),
                  );
                },
              ),
            if (profile.isMaster)
              ForestringDrawerItem(
                icon: Icons.storefront_outlined,
                label: '지점 관리',
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BranchManagementPage(
                        profile: profile,
                      ),
                    ),
                  );
                },
              ),
            if (profile.isMaster)
              ForestringDrawerItem(
                icon: Icons.event_note_outlined,
                label: '학기 관리',
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const SemesterManagementPage(),
                    ),
                  );
                },
              ),
          ],
        ],
        onLogout: () async {
          Navigator.of(context).pop();

          if (isQaSandbox) {
            onQaExit?.call();
            return;
          }

          await context.read<AuthController>().signOut();
        },
      ),
      body: embeddedInShell
          ? _ManagerScheduleBody(controller: controller)
          : SafeArea(
              child: RefreshIndicator(
          onRefresh: controller.reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(10),
            children: [
              if (controller.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    controller.errorMessage!,
                    style: forestringTextStyle.copyWith(
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedBranchId,
                      decoration: _selectorDecoration('지점 선택'),
                      items: controller.branches
                          .map(
                            (branch) => DropdownMenuItem<String>(
                              value: branch.id,
                              child: Text(
                                branch.name,
                                overflow: TextOverflow.ellipsis,
                                style: forestringTextStyle.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: profile.isManager
                          ? null
                          : (value) {
                              if (value != null) {
                                controller.selectBranch(value);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedTeacherId,
                      decoration: _selectorDecoration('선생님 선택'),
                      items: controller.branchTeachers
                          .map(
                            (teacher) => DropdownMenuItem<String>(
                              value: teacher.id,
                              child: Text(
                                teacher.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: forestringTextStyle.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          controller.selectTeacher(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: MediaQuery.of(context).size.height -
                    (embeddedInShell ? 250 : 180),
                child: controller.isLoading && controller.lessons.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : selectedTeacherId == null
                        ? Center(
                            child: Text(
                              selectedBranchId == null
                                  ? '등록된 지점이 없습니다.'
                                  : '선택한 지점에 선생님이 없습니다.',
                              style: forestringTextStyle,
                            ),
                          )
                        : SfCalendar(
                            minDate: DateTime(
                              DateTime.now().year,
                              DateTime.now().month - 2,
                              1,
                            ),
                            maxDate: DateTime(
                              DateTime.now().year,
                              DateTime.now().month + 4,
                              0,
                            ),
                            timeZone: 'Korea Standard Time',
                            view: CalendarView.week,
                            cellBorderColor: Colors.black12,
                            todayHighlightColor: primaryColor,
                            showNavigationArrow: true,
                            cellEndPadding: 0,
                            dataSource: _MasterDataSource(meetings),
                            appointmentBuilder: (context, details) {
                              if (details.appointments.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              final meeting = details.appointments.first;
                              if (meeting is! _MasterMeeting) {
                                if (meeting is _MasterBlockedMeeting) {
                                  return BlockedPeriodCalendarAppointment(
                                    period: meeting.period,
                                  );
                                }
                                return const SizedBox.shrink();
                              }

                              return LessonCalendarAppointment(
                                lesson: meeting.lesson,
                                accentColor: meeting.studentAccentColor,
                              );
                            },
                            specialRegions: _timeRegions(
                              controller.workHoursFor(
                                selectedTeacherId,
                              ),
                            ),
                            viewHeaderHeight: 50,
                            headerDateFormat: 'M월',
                            headerStyle: const CalendarHeaderStyle(
                              backgroundColor: Colors.transparent,
                              textAlign: TextAlign.center,
                              textStyle: TextStyle(
                                color: primaryColor,
                                fontFamily: 'ELAND',
                                fontWeight: FontWeight.w500,
                                fontSize: 20,
                              ),
                            ),
                            viewHeaderStyle: const ViewHeaderStyle(
                              dateTextStyle: TextStyle(
                                color: Colors.black,
                                fontFamily: 'ELAND',
                                fontWeight: FontWeight.w500,
                              ),
                              dayTextStyle: TextStyle(
                                color: Colors.black,
                                fontFamily: 'OpenSans',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            timeSlotViewSettings:
                                const TimeSlotViewSettings(
                              dayFormat: 'EEE',
                              timeTextStyle: TextStyle(
                                fontFamily: 'OpenSans',
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                                fontSize: 11,
                              ),
                              timeInterval: Duration(minutes: 15),
                              timeIntervalHeight: 36,
                              timeFormat: 'H:mm',
                              startHour: 7,
                              endHour: 23,
                            ),
                            onTap: (details) {
                              final appointments = details.appointments;
                              if (appointments == null ||
                                  appointments.isEmpty) {
                                return;
                              }

                              final meeting = appointments.first;
                              if (meeting is _MasterBlockedMeeting) {
                                showBlockedPeriodInfoDialog(
                                  context: context,
                                  period: meeting.period,
                                );
                                return;
                              }

                              if (meeting is! _MasterMeeting) {
                                return;
                              }

                              showLessonActionDialog(
                                context: context,
                                lesson: meeting.lesson,
                                controller:
                                    context.read<LessonController>(),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _selectorDecoration(String label) {
    return InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: forestringTextStyle.copyWith(
        color: primaryColor,
        fontSize: 12,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 12,
      ),
      border: const OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: primaryColor.withValues(alpha: 0.35),
        ),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  List<TimeRegion> _timeRegions(
    List<TeacherWorkHour> workHours,
  ) {
    return workHours.map((workHour) {
      final startParts = workHour.startTime.split(':');
      final endParts = workHour.endTime.split(':');

      return TimeRegion(
        startTime: DateTime(
          2024,
          1,
          1,
          int.parse(startParts[0]),
          int.parse(startParts[1]),
        ),
        endTime: DateTime(
          2024,
          1,
          1,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
        ),
        recurrenceRule:
            'FREQ=WEEKLY;BYDAY=${_weekdayCode(workHour.weekday)}',
        color: primaryColor.withValues(alpha: 0.12),
      );
    }).toList();
  }

  String _weekdayCode(int weekday) {
    return switch (weekday) {
      1 => 'MO',
      2 => 'TU',
      3 => 'WE',
      4 => 'TH',
      5 => 'FR',
      6 => 'SA',
      7 => 'SU',
      _ => 'MO',
    };
  }
}


class _ManagerScheduleBody extends StatefulWidget {
  const _ManagerScheduleBody({
    required this.controller,
  });

  final LessonController controller;

  @override
  State<_ManagerScheduleBody> createState() =>
      _ManagerScheduleBodyState();
}

class _ManagerScheduleBodyState extends State<_ManagerScheduleBody> {
  late final CalendarController _calendarController;
  late DateTime _visibleWeekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleWeekStart = _startOfWeek(now);
    _calendarController = CalendarController()
      ..displayDate = now;
  }

  @override
  void dispose() {
    _calendarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final accentController = context.watch<StudentAccentController>();
    final studentAccents = accentController.isEnabled
        ? accentController.assignments(
            controller.visibleLessons.map((lesson) => lesson.studentId),
          )
        : const <String, Color>{};
    final selectedTeacherId = controller.selectedTeacherId;
    final branchName = _selectedBranchName(controller);

    final meetings = <Object>[
      ...controller.visibleLessons
          .where((lesson) => !lesson.isCanceled)
          .map(
            (lesson) => _MasterMeeting(
              lesson,
              studentAccents[lesson.studentId],
            ),
          ),
      ...controller.visibleBlockedPeriods.map(
        (period) => _MasterBlockedMeeting(period),
      ),
    ];

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 6, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: primaryColor,
                  size: 18,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    branchName,
                    overflow: TextOverflow.ellipsis,
                    style: forestringTextStyle.copyWith(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '새로고침',
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      controller.isLoading ? null : controller.reload,
                  icon: controller.isLoading
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primaryColor,
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: primaryColor,
                          size: 20,
                        ),
                ),
              ],
            ),
          ),
          if (controller.errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  controller.errorMessage!,
                  style: forestringTextStyle.copyWith(
                    color: Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                _teacherChip(
                  label: '전체',
                  selected: selectedTeacherId == null,
                  onSelected: (_) => controller.selectAllTeachers(),
                ),
                const SizedBox(width: 8),
                ...controller.branchTeachers.expand(
                  (teacher) => [
                    _teacherChip(
                      label: teacher.displayName,
                      selected: selectedTeacherId == teacher.id,
                      onSelected: (_) =>
                          controller.selectTeacher(teacher.id),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _weekNavigator(),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(0, 0, 0, 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.07),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: controller.isLoading &&
                      controller.lessons.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : controller.branchTeachers.isEmpty
                      ? Center(
                          child: Text(
                            '등록된 선생님이 없습니다.',
                            style: forestringTextStyle.copyWith(
                              color: Colors.black54,
                            ),
                          ),
                        )
                      : SfCalendar(
                          controller: _calendarController,
                          view: CalendarView.week,
                          firstDayOfWeek: DateTime.monday,
                          initialDisplayDate: DateTime.now(),
                          minDate: DateTime(
                            DateTime.now().year,
                            DateTime.now().month - 2,
                            1,
                          ),
                          maxDate: DateTime(
                            DateTime.now().year,
                            DateTime.now().month + 4,
                            0,
                          ),
                          timeZone: 'Korea Standard Time',
                          headerHeight: 0,
                          showNavigationArrow: false,
                          cellBorderColor:
                              Colors.black.withValues(alpha: 0.055),
                          todayHighlightColor: primaryColor,
                          cellEndPadding: 0,
                          dataSource: _MasterDataSource(meetings),
                          appointmentBuilder: (context, details) {
                            if (details.appointments.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            final meeting =
                                details.appointments.first;
                            if (meeting is _MasterBlockedMeeting) {
                              return _ManagerBlockedAppointment(
                                period: meeting.period,
                              );
                            }
                            if (meeting is! _MasterMeeting) {
                              return const SizedBox.shrink();
                            }

                            return _ManagerLessonAppointment(
                              lesson: meeting.lesson,
                              studentAccentColor:
                                  meeting.studentAccentColor,
                            );
                          },
                          specialRegions: selectedTeacherId == null
                              ? const <TimeRegion>[]
                              : _timeRegions(
                                  controller.workHoursFor(
                                    selectedTeacherId,
                                  ),
                                ),
                          viewHeaderHeight: 45,
                          viewHeaderStyle: const ViewHeaderStyle(
                            dateTextStyle: TextStyle(
                              color: Colors.black87,
                              fontFamily: 'ELAND',
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                            dayTextStyle: TextStyle(
                              color: Colors.black54,
                              fontFamily: 'ELAND',
                              fontWeight: FontWeight.w300,
                              fontSize: 9,
                            ),
                          ),
                          timeSlotViewSettings:
                              const TimeSlotViewSettings(
                            dayFormat: 'EEE',
                            timeTextStyle: TextStyle(
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w400,
                              color: Colors.black45,
                              fontSize: 9,
                            ),
                            timeInterval: Duration(minutes: 30),
                            timeIntervalHeight: 38,
                            timeFormat: 'H:mm',
                            startHour: 7,
                            endHour: 23,
                            timeRulerSize: 36,
                          ),
                          onViewChanged: _onViewChanged,
                          onTap: (details) {
                            final appointments =
                                details.appointments;
                            if (appointments == null ||
                                appointments.isEmpty) {
                              return;
                            }

                            final meeting = appointments.first;
                            if (meeting is _MasterBlockedMeeting) {
                              showBlockedPeriodInfoDialog(
                                context: context,
                                period: meeting.period,
                              );
                              return;
                            }
                            if (meeting is! _MasterMeeting) {
                              return;
                            }

                            showLessonActionDialog(
                              context: context,
                              lesson: meeting.lesson,
                              controller: controller,
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teacherChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: onSelected,
      selectedColor: primaryColor,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected
            ? primaryColor
            : primaryColor.withValues(alpha: 0.12),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      labelStyle: forestringTextStyle.copyWith(
        color: selected ? Colors.white : Colors.black87,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w500 : FontWeight.w300,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: const VisualDensity(vertical: -1),
    );
  }

  Widget _weekNavigator() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '이전 주',
            visualDensity: VisualDensity.compact,
            onPressed: () => _moveWeek(-1),
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: primaryColor,
            ),
          ),
          Expanded(
            child: Text(
              _weekLabel(_visibleWeekStart),
              textAlign: TextAlign.center,
              style: forestringTextStyle.copyWith(
                color: Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: '다음 주',
            visualDensity: VisualDensity.compact,
            onPressed: () => _moveWeek(1),
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: primaryColor,
            ),
          ),
          Container(
            width: 1,
            height: 22,
            color: primaryColor.withValues(alpha: 0.08),
          ),
          TextButton(
            onPressed: _goToday,
            style: TextButton.styleFrom(
              foregroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 11),
            ),
            child: Text(
              '오늘',
              style: forestringTextStyle.copyWith(
                color: primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _moveWeek(int delta) {
    final target =
        _visibleWeekStart.add(Duration(days: delta * 7));
    setState(() => _visibleWeekStart = target);
    _calendarController.displayDate =
        target.add(const Duration(days: 3));
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() => _visibleWeekStart = _startOfWeek(now));
    _calendarController.displayDate = now;
  }

  void _onViewChanged(ViewChangedDetails details) {
    if (details.visibleDates.isEmpty) return;

    final next = _startOfWeek(details.visibleDates.first);
    if (_sameDay(next, _visibleWeekStart)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _sameDay(next, _visibleWeekStart)) {
        return;
      }
      setState(() => _visibleWeekStart = next);
    });
  }

  String _selectedBranchName(LessonController controller) {
    final branchId = controller.selectedBranchId;
    for (final branch in controller.branches) {
      if (branch.id == branchId) return branch.name;
    }
    return '지점 정보 확인 필요';
  }

  String _weekLabel(DateTime start) {
    final end = start.add(const Duration(days: 6));
    if (start.year == end.year && start.month == end.month) {
      return '${start.month}월 ${start.day}일 - '
          '${end.month}월 ${end.day}일';
    }
    return '${start.month}월 ${start.day}일 - '
        '${end.month}월 ${end.day}일';
  }

  List<TimeRegion> _timeRegions(
    List<TeacherWorkHour> workHours,
  ) {
    return workHours.map((workHour) {
      final startParts = workHour.startTime.split(':');
      final endParts = workHour.endTime.split(':');

      return TimeRegion(
        startTime: DateTime(
          2024,
          1,
          1,
          int.parse(startParts[0]),
          int.parse(startParts[1]),
        ),
        endTime: DateTime(
          2024,
          1,
          1,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
        ),
        recurrenceRule:
            'FREQ=WEEKLY;BYDAY=${_weekdayCode(workHour.weekday)}',
        color: primaryColor.withValues(alpha: 0.055),
      );
    }).toList();
  }

  String _weekdayCode(int weekday) {
    return switch (weekday) {
      1 => 'MO',
      2 => 'TU',
      3 => 'WE',
      4 => 'TH',
      5 => 'FR',
      6 => 'SA',
      7 => 'SU',
      _ => 'MO',
    };
  }

  DateTime _startOfWeek(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(
      Duration(days: day.weekday - DateTime.monday),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;
}

class _ManagerLessonAppointment extends StatelessWidget {
  const _ManagerLessonAppointment({
    required this.lesson,
    this.studentAccentColor,
  });

  final Lesson lesson;
  final Color? studentAccentColor;

  @override
  Widget build(BuildContext context) {
    final palette = _palette();
    final label = switch (lesson.type) {
      LessonType.makeup => '보강',
      LessonType.flex => lesson.isRescheduled ? '변경' : '자율',
      LessonType.regular => lesson.isRescheduled ? '변경' : '정규',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 3, 2),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(7),
        border: Border(
          left: BorderSide(
            color: palette.$2,
            width: 3,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lesson.studentName ?? '학생',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: forestringTextStyle.copyWith(
              color: Colors.black87,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: forestringTextStyle.copyWith(
              color: Colors.black54,
              fontSize: 7.5,
              fontWeight: FontWeight.w400,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _palette() {
    final statusColor = lessonStatusAccentColor(lesson);
    final studentColor = studentAccentColor;
    if (studentColor != null) {
      return (
        Color.lerp(studentColor, Colors.white, 0.34)!,
        statusColor,
      );
    }
    return (
      lessonStatusSurfaceColor(lesson),
      statusColor,
    );
  }
}

class _ManagerBlockedAppointment extends StatelessWidget {
  const _ManagerBlockedAppointment({
    required this.period,
  });

  final TeacherBlockedPeriod period;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(4, 2, 3, 2),
      decoration: BoxDecoration(
        color: const Color(0xffE8E9E7),
        borderRadius: BorderRadius.circular(7),
        border: const Border(
          left: BorderSide(
            color: Color(0xff8B918D),
            width: 3,
          ),
        ),
      ),
      child: Text(
        period.displayLabel,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: forestringTextStyle.copyWith(
          color: Colors.black54,
          fontSize: 8,
          fontWeight: FontWeight.w500,
          height: 1.05,
        ),
      ),
    );
  }
}

class _MasterMeeting {
  const _MasterMeeting(
    this.lesson,
    this.studentAccentColor,
  );

  final Lesson lesson;
  final Color? studentAccentColor;
}

class _MasterBlockedMeeting {
  const _MasterBlockedMeeting(this.period);

  final TeacherBlockedPeriod period;
}

class _MasterDataSource extends CalendarDataSource {
  _MasterDataSource(List<Object> source) {
    appointments = source;
  }

  Object _entry(int index) => appointments![index];

  @override
  DateTime getStartTime(int index) {
    final entry = _entry(index);
    return entry is _MasterMeeting
        ? entry.lesson.startsAt
        : (entry as _MasterBlockedMeeting).period.startsAt;
  }

  @override
  DateTime getEndTime(int index) {
    final entry = _entry(index);
    return entry is _MasterMeeting
        ? entry.lesson.endsAt
        : (entry as _MasterBlockedMeeting).period.endsAt;
  }

  @override
  String getSubject(int index) {
    final entry = _entry(index);
    return entry is _MasterMeeting
        ? (entry.lesson.studentName ?? '학생')
        : (entry as _MasterBlockedMeeting).period.displayLabel;
  }

  @override
  Color getColor(int index) {
    final entry = _entry(index);
    if (entry is _MasterBlockedMeeting) {
      return personalScheduleColor;
    }
    final meeting = entry as _MasterMeeting;
    final studentColor = meeting.studentAccentColor;
    return studentColor == null
        ? lessonStatusSurfaceColor(meeting.lesson)
        : Color.lerp(studentColor, Colors.white, 0.30)!;
  }
}
