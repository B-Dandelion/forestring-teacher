import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/presentation/auth_controller.dart';
import 'notification_navigation_coordinator.dart';

class NotificationForegroundHost extends StatefulWidget {
  const NotificationForegroundHost({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<NotificationForegroundHost> createState() =>
      _NotificationForegroundHostState();
}

class _NotificationForegroundHostState
    extends State<NotificationForegroundHost> {
  String? _lastPresentedNotificationId;

  @override
  Widget build(BuildContext context) {
    final coordinator =
        context.watch<NotificationNavigationCoordinator>();
    final auth = context.watch<AuthController>();
    final presentation = coordinator.foregroundPresentation;

    if (presentation != null &&
        presentation.intent.notificationId !=
            _lastPresentedNotificationId) {
      _lastPresentedNotificationId =
          presentation.intent.notificationId;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        final profile = auth.profile;
        if (profile == null ||
            profile.id !=
                presentation.intent.recipientProfileId) {
          coordinator.dismissForeground(
            presentation.intent.notificationId,
          );
          return;
        }

        final title =
            presentation.title?.trim().isNotEmpty == true
                ? presentation.title!.trim()
                : '포레스트링 알림';
        final body =
            presentation.body?.trim().isNotEmpty == true
                ? presentation.body!.trim()
                : '새로운 알림이 도착했습니다.';

        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();

        final controller = messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 7),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(body),
              ],
            ),
            action: SnackBarAction(
              label: '보기',
              onPressed: () {
                coordinator.openForegroundNotification(
                  presentation.intent.notificationId,
                );
              },
            ),
          ),
        );

        controller.closed.then((_) {
          if (!mounted) {
            return;
          }

          coordinator.dismissForeground(
            presentation.intent.notificationId,
          );
        });
      });
    }

    return widget.child;
  }
}
