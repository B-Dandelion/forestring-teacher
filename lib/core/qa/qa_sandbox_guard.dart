import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Hard runtime boundary for the local interactive QA sandbox.
///
/// The login button is already hidden outside debug QA builds, but this guard
/// also prevents accidental programmatic construction of the sandbox in a
/// release build or when MANAGER_QA_ENABLED is disabled.
abstract final class QaSandboxGuard {
  static bool get isEnabled =>
      !kReleaseMode && AppConfig.managerQaEnabled;

  static void ensureEnabled() {
    if (isEnabled) return;

    throw StateError(
      'QA Sandbox is disabled. '
      'Use a debug build with MANAGER_QA_ENABLED=true.',
    );
  }
}
