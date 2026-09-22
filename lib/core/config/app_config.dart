class AppConfig {
  static const appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
  );

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isStaging => appEnv == 'staging';

  static void validate() {
    if (appEnv != 'production' && appEnv != 'staging') {
      throw StateError('APP_ENV must be production or staging.');
    }

    if (supabaseUrl.isEmpty) {
      throw StateError('SUPABASE_URL is not configured.');
    }

    if (supabasePublishableKey.isEmpty) {
      throw StateError(
        'SUPABASE_PUBLISHABLE_KEY is not configured.',
      );
    }

    if (isStaging) {
      final uri = Uri.tryParse(supabaseUrl);
      final allowedHosts = {
        '127.0.0.1',
        'localhost',
        '10.0.2.2',
      };

      if (uri == null ||
          uri.scheme != 'http' ||
          uri.port != 54321 ||
          !allowedHosts.contains(uri.host)) {
        throw StateError(
          'Staging must point to the local Supabase API on port 54321.',
        );
      }
    }
  }
}
