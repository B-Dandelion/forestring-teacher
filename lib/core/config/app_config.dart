class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
  );

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static const managerQaEnabled = bool.fromEnvironment(
    'MANAGER_QA_ENABLED',
    defaultValue: false,
  );

  static void validate() {
    if (supabaseUrl.isEmpty) {
      throw StateError('SUPABASE_URL is not configured.');
    }

    if (supabasePublishableKey.isEmpty) {
      throw StateError(
        'SUPABASE_PUBLISHABLE_KEY is not configured.',
      );
    }
  }
}