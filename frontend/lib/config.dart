class AppConfig {
  /// Configurable via: flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// Local development only: `--dart-define=TRIP_DEMO_TOKEN=...`.
  /// Never ship this in a deployed web build; it is readable by anyone. [S2-04]
  static const String tripDemoToken = String.fromEnvironment('TRIP_DEMO_TOKEN');

  static String get locationsEndpoint => '$apiBaseUrl/locations';
  static String get tripsEndpoint => '$apiBaseUrl/api/v1/trips';
}
