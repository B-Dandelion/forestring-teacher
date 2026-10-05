import '../../features/auth/domain/current_profile.dart';
import 'notification_payload.dart';

enum NotificationDestinationKind {
  teacherWeek,
  teacherStudentDetail,
  managementWeek,
  managementStudentDetail,
}

class NotificationDestination {
  const NotificationDestination(this.kind);

  final NotificationDestinationKind kind;
}

class NotificationDestinationResolver {
  const NotificationDestinationResolver._();

  static NotificationDestination? resolve({
    required CurrentProfile profile,
    required NotificationNavigationIntent intent,
  }) {
    if (!profile.isActive || profile.isReviewAccount) {
      return null;
    }

    return switch (profile.role) {
      AppRole.teacher => _forTeacher(profile, intent),
      AppRole.manager => _forManager(profile, intent),
      AppRole.master => _forMaster(intent),
      AppRole.student => null,
    };
  }

  static NotificationDestination? _forTeacher(
    CurrentProfile profile,
    NotificationNavigationIntent intent,
  ) {
    if (intent.teacherId != profile.id) {
      return null;
    }

    return switch (intent.navigationKind) {
      NotificationNavigationKind.lessonWeek =>
        const NotificationDestination(
          NotificationDestinationKind.teacherWeek,
        ),
      NotificationNavigationKind.studentDetail =>
        const NotificationDestination(
          NotificationDestinationKind.teacherStudentDetail,
        ),
    };
  }

  static NotificationDestination? _forManager(
    CurrentProfile profile,
    NotificationNavigationIntent intent,
  ) {
    if (profile.branchId == null ||
        profile.branchId != intent.branchId) {
      return null;
    }

    return switch (intent.navigationKind) {
      NotificationNavigationKind.lessonWeek =>
        const NotificationDestination(
          NotificationDestinationKind.managementWeek,
        ),
      NotificationNavigationKind.studentDetail =>
        const NotificationDestination(
          NotificationDestinationKind.managementStudentDetail,
        ),
    };
  }

  static NotificationDestination _forMaster(
    NotificationNavigationIntent intent,
  ) {
    return switch (intent.navigationKind) {
      NotificationNavigationKind.lessonWeek =>
        const NotificationDestination(
          NotificationDestinationKind.managementWeek,
        ),
      NotificationNavigationKind.studentDetail =>
        const NotificationDestination(
          NotificationDestinationKind.managementStudentDetail,
        ),
    };
  }
}
