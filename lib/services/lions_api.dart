import 'package:web/web.dart' as web;
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Dynamically builds the backend URL based on current host
String getBackendUrl(String path) {
  final host = web.window.location.hostname;
  return 'http://$host:8080/$path';
}

/// Fetches members from the backend
Future<List<dynamic>> fetchMembers() async {
  final response = await http.get(Uri.parse(getBackendUrl('members')));
  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception('Failed to load members');
  }
}

/// Fetches events from the backend
Future<List<dynamic>> fetchEvents() async {
  final response = await http.get(Uri.parse(getBackendUrl('events')));
  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception('Failed to load events');
  }
}

// Add more functions here for calendar, clubs, roles, etc.
