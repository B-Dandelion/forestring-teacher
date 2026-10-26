import 'package:flutter_test/flutter_test.dart';
import 'package:forestring_teacher_2/core/qa/qa_sandbox_repositories.dart';
import 'package:forestring_teacher_2/core/qa/qa_sandbox_store.dart';
import 'package:forestring_teacher_2/features/lessons/domain/lesson.dart';
import 'package:forestring_teacher_2/features/students/data/student_management_repository.dart';
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late QaSandboxStore store;
  setUp(() {
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) => throw StateError('QA must stay offline')),
    );
    store = QaSandboxStore.forTesting();
  });
  tearDown(() async {
    store.dispose();
    await client.dispose();
  });

  test('QA 과거 수업권 조회는 운영 DB를 호출하지 않고 마감 학기를 구분한다', () async {
    final student = store.students.firstWhere((student) => student.isActive);
    final semester = store.semesters.firstWhere((semester) => semester.isPast);
    final repository = QaLessonRepository(store, client: client);
    final availability = await repository.fetchMakeupLessonRightAvailability(
      studentId: student.id,
      semesterId: semester.id,
      branchId: student.branchId!,
      durationMinutes: 30,
    );
    expect(availability.availableCount, greaterThanOrEqualTo(0));
    expect(availability.canDeductPast, isFalse);
    expect(
        await repository.fetchAvailableLessonRightCount(
          studentId: student.id,
          semesterId: semester.id,
          branchId: 'other-branch',
          durationMinutes: 30,
        ),
        0);
  });

  test('QA 소급 퇴원은 충돌이 없으면 즉시 확정된다', () async {
    final student = store.students.firstWhere((student) => student.isActive);
    store.lessons = [];
    final past = DateTime.now().subtract(const Duration(days: 3));
    final result = await QaStudentManagementRepository(store, client: client)
        .scheduleWithdrawal(studentId: student.id, withdrawalDate: past);
    expect(result.finalized, isTrue);
    expect(store.studentById(student.id)!.isActive, isFalse);
  });

  test('QA 소급 퇴원은 과거 취소 수업과 충돌하면 상태와 기록을 유지한다', () async {
    final student = store.students.firstWhere((student) => student.isActive);
    final lessonAt = DateTime.now().subtract(const Duration(days: 1));
    final lesson = Lesson(
      id: 'past-canceled',
      studentId: student.id,
      teacherId: 'teacher',
      startsAt: lessonAt,
      endsAt: lessonAt.add(const Duration(minutes: 30)),
      durationMinutes: 30,
      type: LessonType.makeup,
      status: LessonStatus.canceled,
    );
    store.lessons = [lesson];
    await expectLater(
      QaStudentManagementRepository(store, client: client).scheduleWithdrawal(
        studentId: student.id,
        withdrawalDate: lessonAt.subtract(const Duration(days: 1)),
      ),
      throwsA(isA<StudentManagementFailure>()),
    );
    expect(store.studentById(student.id), same(student));
    expect(store.lessons.single, same(lesson));
  });
}
