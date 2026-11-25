import 'package:flutter/foundation.dart';

/// API base URL per environment: `--dart-define=API_BASE_URL=https://budget.example.com/api/v1`.
/// Default: same origin on web (backend serves the web build), localhost for desktop development.
class Env {
  static const _defined = String.fromEnvironment('API_BASE_URL');
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'demo',
  );
  static const defaultTenant = String.fromEnvironment(
    'DEFAULT_TENANT',
    defaultValue: 'DEMO',
  );

  /// GitHub Pages demo: the backend runs inside the browser (web/backend), no server needed.
  static const inBrowserBackend = bool.fromEnvironment('IN_BROWSER_BACKEND');

  static String get apiBaseUrl {
    if (inBrowserBackend) return 'https://demo.local/api/v1';
    if (_defined.isNotEmpty) return _defined;
    if (kIsWeb) return '${Uri.base.origin}/api/v1';
    return 'http://localhost:8000/api/v1';
  }
}
