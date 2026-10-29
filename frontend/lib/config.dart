class AppConfig {
  /// Configurable via: flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// Supplied at build time with `--dart-define=TRIP_DEMO_TOKEN=...`.
  /// Deployed web bundles are public, so treat this token as exposed. [S2-04]
  static const String tripDemoToken = String.fromEnvironment('TRIP_DEMO_TOKEN');

  /// Public Supabase Auth configuration for this environment, supplied with
  /// `--dart-define`. Only the project URL and publishable/anon key belong
  /// here; service-role keys must never be compiled into the app. [S3-16]
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Optional override for where confirmation emails return, e.g.
  /// `--dart-define=AUTH_REDIRECT_URL=https://staging.lagaw.pages.dev`.
  /// Must be on the Supabase project's redirect allow-list.
  static const String authRedirectUrl = String.fromEnvironment(
    'AUTH_REDIRECT_URL',
  );

  static bool get authEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String get locationsEndpoint => '$apiBaseUrl/locations';
  static String get tripsEndpoint => '$apiBaseUrl/api/v1/trips';
  static String get preferenceExtractEndpoint =>
      '$apiBaseUrl/api/v1/preferences/extract';
}
