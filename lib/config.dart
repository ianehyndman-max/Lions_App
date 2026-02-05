import 'package:flutter/foundation.dart';

//const String apiBase = 'http://192.168.4.39:8080'; // replace if your laptop IP changes

/// Returns the API base URL depending on platform:
/// - Web: use the browser origin (e.g. http://localhost:8080 when running web dev).
/// - Mobile/Desktop: use the developer machine IP for local testing.
/// Change the mobileHost value when you deploy (e.g. https://api.example.com).
String getApiBase() {
  // Set to true for AWS, false for local development
  const useAWS = true;
  
  // const awsHost = 'http://54.79.125.34:8080';  // ✅ Direct to port 8080 (bypass NGINX)
  const awsHost = 'https://thelionsapp.com/api';
  const localMobileHost = 'http://192.168.4.39:8080';
  const localDevHost = 'http://127.0.0.1:8080';

  if (useAWS) {
    return awsHost;
  }

  if (kIsWeb) {
    return localDevHost;
  } else {
    return localMobileHost;
  }
}


final String apiBase = getApiBase();
