import 'package:flutter/foundation.dart';

//const String apiBase = 'http://192.168.4.39:8080'; // replace if your laptop IP changes

/// Returns the API base URL depending on platform:
/// - Web: use the browser origin (e.g. http://localhost:8080 when running web dev).
/// - Mobile/Desktop: use the developer machine IP for local testing.
/// Change the mobileHost value when you deploy (e.g. https://api.example.com).
String getApiBase() {
  const mobileHost = 'http://192.168.4.39:8080';
  const devApiHost = 'http://127.0.0.1:8080';

  if (kIsWeb) {
    // Always use explicit dev API host for web dev so requests go to backend not the web server.
    return devApiHost;
  } else {
    return mobileHost;
  }
}


final String apiBase = getApiBase();
