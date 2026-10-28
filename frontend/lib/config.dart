class AppConfig {
  /// Configurable via: flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// Supplied at build time with `--dart-define=TRIP_DEMO_TOKEN=...`.
  /// Deployed web bundles are public, so treat this token as exposed. [S2-04]
  static const String tripDemoToken = String.fromEnvironment('TRIP_DEMO_TOKEN');

  static String get locationsEndpoint => '$apiBaseUrl/locations';
  static String get tripsEndpoint => '$apiBaseUrl/api/v1/trips';
  static String get preferenceExtractEndpoint =>
      '$apiBaseUrl/api/v1/preferences/extract';
}
