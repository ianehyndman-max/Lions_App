import 'package:flutter/foundation.dart';

/// Returns the API base URL depending on platform:
/// - Web: use the browser origin (e.g. http://localhost:8080 when running web dev).
/// - Mobile/Desktop: use the developer machine IP for local testing.
/// Change the mobileHost value when you deploy (e.g. https://api.example.com).
String getApiBase() {
  const useAWS = bool.fromEnvironment('USE_AWS', defaultValue: true);

  const awsHost = String.fromEnvironment(
    'API_AWS_HOST',
    defaultValue: 'https://api.thelionsapp.com',
  );
  const localMobileHost = String.fromEnvironment(
    'API_LOCAL_MOBILE_HOST',
    defaultValue: 'http://192.168.4.39:8080',
  );
  const localDevHost = String.fromEnvironment(
    'API_LOCAL_DEV_HOST',
    defaultValue: 'http://127.0.0.1:8080',
  );

  if (useAWS) {
    return awsHost;
  }

  if (kIsWeb) {
    return localDevHost;
  }

  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  if (isMobile) {
    return localMobileHost;
  }

  return localDevHost;
}

final String apiBase = getApiBase();
