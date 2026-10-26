import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forestring_teacher_2/features/auth/domain/current_profile.dart';
import 'package:forestring_teacher_2/features/branches/domain/academy_branch.dart';
import 'package:forestring_teacher_2/features/lessons/data/lesson_repository.dart';
import 'package:forestring_teacher_2/features/lessons/domain/lesson.dart';
import 'package:forestring_teacher_2/features/lessons/presentation/makeup_lesson_create_page.dart';
import 'package:forestring_teacher_2/features/semesters/domain/managed_semester.dart';
import 'package:forestring_teacher_2/features/students/data/student_management_repository.dart';
import 'package:forestring_teacher_2/features/students/presentation/student_withdrawal_dialog.dart';
// Supabase's existing HTTP dependency supplies its injectable test transport.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

class _InlineJsonIsolate implements YAJsonIsolate {
  @override
  String? get debugName => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<dynamic> decode(String source) async => jsonDecode(source);
  @override
  Future<String> encode(Object? value) async => jsonEncode(value);
}

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    isolate: _InlineJsonIsolate(),
    httpClient: MockClient((request) async {
      final response = await handler(request);
      return http.Response.bytes(response.bodyBytes, response.statusCode,
          headers: response.headers, request: request);
    }),
  );
}

http.Response _json(Object? body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('퇴원 날짜 및 서버 확정 결과', () {
    final now = DateTime(2026, 9, 15, 12);
    final today = DateTime(2026, 9, 15);
    final past = DateTime(2026, 9, 10);

    test('과거 퇴원은 날짜를 그대로 보내고 서버의 원자 확정 결과를 사용한다', () async {
      final requests = <http.Request>[];
      final client = _client((request) async {
        requests.add(request);
        return _json({
          'finalized': true,
          'withdrawalDate': '2026-09-10',
          'deletedLessonCount': 2,
          'revokedRightCount': 3,
        });
      });
      addTearDown(client.dispose);
      final result = await StudentManagementRepository(
        client: client,
        now: () => now,
      ).scheduleWithdrawal(studentId: 'student', withdrawalDate: past);

      expect(requests, hasLength(1));
      expect(
          requests.single.url.path, endsWith('/schedule_student_withdrawal'));
      expect(jsonDecode(requests.single.body), {
        'p_student_id': 'student',
        'p_withdrawal_date': '2026-09-10',
      });
      expect(result.finalized, isTrue);
      expect(result.withdrawalDate, past);
      expect(result.deletedLessonCount, 2);
      expect(result.revokedRightCount, 3);
    });

    test('오늘 퇴원은 기존 서버 응답이면 기존 확정 RPC를 호출한다', () async {
      final paths = <String>[];
      final client = _client((request) async {
        paths.add(request.url.path);
        return request.url.path.endsWith('/schedule_student_withdrawal')
            ? _json({'changed': true})
            : _json({'withdrawalDate': '2026-09-15'});
      });
      addTearDown(client.dispose);
      final result = await StudentManagementRepository(
        client: client,
        now: () => now,
      ).scheduleWithdrawal(studentId: 'student', withdrawalDate: today);

      expect(paths, [
        '/rest/v1/rpc/schedule_student_withdrawal',
        '/rest/v1/rpc/finalize_student_withdrawal',
      ]);
      expect(result.finalized, isTrue);
      expect(result.withdrawalDate, today);
    });

    test('미래 퇴원은 기존처럼 예약 결과만 반환한다', () async {
      final paths = <String>[];
      final client = _client((request) async {
        paths.add(request.url.path);
        return _json({'changed': true});
      });
      addTearDown(client.dispose);
      final result = await StudentManagementRepository(
        client: client,
        now: () => now,
      ).scheduleWithdrawal(
        studentId: 'student',
        withdrawalDate: DateTime(2026, 9, 20, 23),
      );

      expect(paths, hasLength(1));
      expect(result.finalized, isFalse);
      expect(result.withdrawalDate, DateTime(2026, 9, 20));
    });

    test('과거 퇴원은 구서버의 불완전 응답을 확정 RPC로 우회하지 않는다', () async {
      var calls = 0;
      final client = _client((request) async {
        calls++;
        return _json({'changed': true});
      });
      addTearDown(client.dispose);
      final repository =
          StudentManagementRepository(client: client, now: () => now);

      await expectLater(
        repository.scheduleWithdrawal(
            studentId: 'student', withdrawalDate: past),
        throwsA(isA<StudentManagementFailure>()),
      );
      expect(calls, 1);
    });

    test('역사 충돌 오류를 기록 삭제 없이 사용자에게 안내한다', () async {
      final client = _client((request) async => _json({
            'code': 'P0001',
            'message': 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT',
          }, status: 400));
      addTearDown(client.dispose);
      await expectLater(
        StudentManagementRepository(client: client, now: () => now)
            .scheduleWithdrawal(studentId: 'student', withdrawalDate: past),
        throwsA(isA<StudentManagementFailure>().having(
          (error) => error.message,
          'message',
          contains('기존 기록을 확인'),
        )),
      );
    });

    test('역사 충돌의 JSON details에서 양수인 항목별 건수를 안내한다', () async {
      final client = _client((request) async => _json({
            'code': 'P0001',
            'message': 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT',
            'details': jsonEncode({
              'lessonCount': 2,
              'assignmentCount': 1,
              'scheduleCount': 0,
              'completedSemesterCount': 3,
            }),
          }, status: 400));
      addTearDown(client.dispose);
      await expectLater(
        StudentManagementRepository(client: client, now: () => now)
            .scheduleWithdrawal(studentId: 'student', withdrawalDate: past),
        throwsA(isA<StudentManagementFailure>().having(
          (error) => error.message,
          'message',
          allOf(contains('수업·취소 기록 2건'), contains('담당 배정 1건'),
              contains('확정 학기 3건'), isNot(contains('정규 일정 0건'))),
        )),
      );
    });

    test('충돌 details가 JSON이 아니어도 기본 안내를 유지한다', () async {
      final client = _client((request) async => _json({
            'code': 'P0001',
            'message': 'FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT',
            'details': 'unsupported details',
          }, status: 400));
      addTearDown(client.dispose);
      await expectLater(
        StudentManagementRepository(client: client, now: () => now)
            .scheduleWithdrawal(studentId: 'student', withdrawalDate: past),
        throwsA(isA<StudentManagementFailure>().having(
          (error) => error.message,
          'message',
          allOf(contains('기존 기록을 확인'), isNot(contains('충돌 항목:'))),
        )),
      );
    });
  });

  group('과거 수업권 조회', () {
    for (final status in [
      'planned',
      'active',
      'completed',
      'withdrawn',
      null
    ]) {
      test('$status 계획의 차감 가능 여부와 학기·길이 조회 조건', () async {
        final requests = <http.Request>[];
        final client = _client((request) async {
          requests.add(request);
          return request.url.path.endsWith('/lesson_rights')
              ? _json([
                  {'id': 'right'}
                ])
              : _json(status == null ? [] : {'status': status});
        });
        addTearDown(client.dispose);
        final availability = await LessonRepository(client: client)
            .fetchMakeupLessonRightAvailability(
          studentId: 'student',
          semesterId: 'semester',
          branchId: 'branch',
          durationMinutes: 30,
        );

        expect(availability.availableCount, 1);
        expect(availability.canDeductPast,
            status == 'planned' || status == 'active');
        final rights =
            requests.singleWhere((r) => r.url.path.endsWith('/lesson_rights'));
        expect(rights.url.queryParameters['student_id'], 'eq.student');
        expect(rights.url.queryParameters['usable_semester_id'], 'eq.semester');
        expect(rights.url.queryParameters['duration_minutes'], 'eq.30');
        expect(rights.url.queryParameters['status'], 'eq.available');
        expect(rights.url.queryParameters['branch_id'], 'eq.branch');
        final plan = requests
            .singleWhere((r) => r.url.path.endsWith('/student_semester_plans'));
        expect(plan.url.queryParameters['semester_id'], 'eq.semester');
        expect(plan.url.queryParameters['branch_id'], 'eq.branch');
      });
    }
  });

  group('동시 학기 정산 안내', () {
    for (final isWithdrawal in [true, false]) {
      test('${isWithdrawal ? '퇴원' : '추가 수업'}은 정산 중 오류를 재시도로 안내한다', () async {
        final client = _client((request) async => _json({
              'code': 'P0001',
              'message': 'FORESTRING_STUDENT_SETTLEMENT_BUSY',
            }, status: 400));
        addTearDown(client.dispose);
        final Future<Object> operation = isWithdrawal
            ? StudentManagementRepository(client: client).scheduleWithdrawal(
                studentId: 'student', withdrawalDate: DateTime(2026, 9, 1))
            : LessonRepository(client: client).createMakeupLesson(
                studentId: 'student',
                teacherId: 'teacher',
                startsAt: DateTime(2026, 9, 1, 10),
                durationMinutes: 30);
        await expectLater(operation, throwsA(predicate<Object>((error) {
          final message = error is StudentManagementFailure
              ? error.message
              : error is LessonFailure
                  ? error.message
                  : '';
          return message.contains('학기 정산 또는 학생 정보 변경이 진행 중입니다') &&
              message.contains('잠시 후 다시 시도');
        })));
      });
    }
  });

  testWidgets('과거 날짜 추가수업은 마감학기 차감을 막고 수업권 없이 등록한다', (tester) async {
    final past = DateTime.now().subtract(const Duration(days: 40));
    final date = DateTime(past.year, past.month, past.day);
    final semester = ManagedSemester(
      id: 'semester',
      code: 'past',
      startsOn: date.subtract(const Duration(days: 10)),
      endsOn: date.add(const Duration(days: 10)),
      branchOverrides: const [],
    );
    final mutations = <Map<String, dynamic>>[];
    final client = _client((request) async {
      if (request.url.path.endsWith('/lesson_rights')) {
        return _json([
          {'id': 'right'}
        ]);
      }
      if (request.url.path.endsWith('/student_semester_plans')) {
        return _json({'status': 'completed'});
      }
      mutations.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      return _json({'changed': true, 'requiresConfirmation': false});
    });
    addTearDown(() => tester.runAsync(client.dispose));
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<bool>(MaterialPageRoute(
                      builder: (_) => _makeupPage(
                          semester, date, LessonRepository(client: client)),
                    ));
                  },
                  child: const Text('열기'),
                ),
              )),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(DateFormat('yyyy.MM.dd').format(date)));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(picker.firstDate, semester.startsOn);
    expect(picker.initialDate, date);
    Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byType(SwitchListTile), 250,
        scrollable: find.byType(Scrollable).first);
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.onChanged, isNull);
    expect(toggle.value, isFalse);
    expect(find.textContaining('학기 정산이 완료'), findsOneWidget);

    final submit = find.widgetWithText(FilledButton, '추가 수업 등록');
    await tester.scrollUntilVisible(submit, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(mutations, hasLength(1));
    expect(mutations.single['p_deduct_lesson_right'], isFalse);
    expect(DateTime.parse(mutations.single['p_starts_at'] as String).toLocal(),
        DateTime(date.year, date.month, date.day, 10));
  });

  testWidgets('과거 퇴원 날짜는 picker에서 유지되고 즉시처리로 안내한다', (tester) async {
    final now = DateTime.now();
    final past = DateTime(now.year, now.month, now.day - 1);
    final client = _client((request) async => _json(null));
    addTearDown(() => tester.runAsync(client.dispose));
    final repository = StudentManagementRepository(client: client);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () => showStudentWithdrawalDialog(
                  context: context,
                  student: ManagedStudent(
                    id: 'student',
                    displayName: '학생',
                    branchId: 'branch',
                    branchName: '지점',
                    studentType: 'regular',
                    status: 'active',
                    profileIsActive: true,
                    withdrawalDate: past,
                  ),
                  repository: repository,
                ),
                child: const Text('열기'),
              ))),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('즉시 처리'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '퇴원 처리'), findsOneWidget);
    await tester.tap(find.text(DateFormat('yyyy.MM.dd').format(past)));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(picker.firstDate.isBefore(past), isTrue);
    expect(picker.initialDate, past);
  });
}

MakeupLessonCreatePage _makeupPage(
    ManagedSemester semester, DateTime date, LessonRepository repository) {
  return MakeupLessonCreatePage(
    profile: const CurrentProfile(
        id: 'manager',
        displayName: '지점장',
        role: AppRole.manager,
        isActive: true,
        branchId: 'branch'),
    semester: semester,
    branches: const [AcademyBranch(id: 'branch', name: '지점', isActive: true)],
    students: const [
      VisibleStudent(
          id: 'student', displayName: '학생', isActive: true, branchId: 'branch')
    ],
    teachers: const [
      VisibleTeacher(id: 'teacher', displayName: '선생님', branchId: 'branch')
    ],
    initialStudentId: 'student',
    initialDate: date,
    repository: repository,
  );
}
