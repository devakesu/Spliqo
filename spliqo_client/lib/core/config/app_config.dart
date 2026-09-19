/// Application configuration loaded from compile-time environment variables
/// injected via `--dart-define` (e.g. through Infisical).
class AppConfig {
  const AppConfig({
    required this.appName,
    required this.appVersion,
    required this.appDomain,
    required this.backendUrl,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.sentryDsn,
    required this.environment,
  });

  final String appName;
  final String appVersion;
  final String appDomain;
  final String backendUrl;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String sentryDsn;
  final String environment;

  bool get isDevelopment =>
      environment == 'development' || environment == 'dev';
  bool get isProduction => environment == 'production' || environment == 'prod';

  // ---------------------------------------------------------------------------
  // Compile-time environment defines (--dart-define=KEY=VALUE)
  // ---------------------------------------------------------------------------
  static const String _appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'Spliqo',
  );

  static const String _appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0',
  );

  static const String _appDomain = String.fromEnvironment(
    'APP_DOMAIN',
    defaultValue: 'localhost:8000',
  );

  static const String _backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
  );

  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static const String _sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
  );

  static const String _environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  /// Current active configuration instance resolved from environment.
  static const AppConfig current = AppConfig(
    appName: _appName,
    appVersion: _appVersion,
    appDomain: _appDomain,
    backendUrl: _backendUrl,
    supabaseUrl: _supabaseUrl,
    supabaseAnonKey: _supabaseAnonKey,
    sentryDsn: _sentryDsn,
    environment: _environment,
  );
}
