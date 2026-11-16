// Shared builders that create entities through the real API, so fixtures in
// one endpoint group also exercise the create endpoints they depend on.

import 'dart:convert';

import 'package:test/test.dart';

import 'test_harness.dart';

/// yyyy-MM-dd for a date relative to today.
String isoDate(DateTime d) => d.toIso8601String().split('T').first;

String today({int addDays = 0}) =>
    isoDate(DateTime.now().add(Duration(days: addDays)));

Future<String> createEventType(TestApi api, String name) async {
  final res =
      await api.post('/event_types', as: Fixtures.superId, body: {'name': name});
  expect(res.statusCode, 200, reason: 'create event type failed: ${res.body}');
  return jsonDecode(res.body)['id'].toString();
}

Future<String> createRoleTemplate(
  TestApi api,
  String eventTypeId,
  String roleName, {
  String timeIn = '',
  String timeOut = '',
}) async {
  final res = await api.post('/event_types/$eventTypeId/role_templates',
      as: Fixtures.superId,
      body: {'role_name': roleName, 'time_in': timeIn, 'time_out': timeOut});
  expect(res.statusCode, 200, reason: 'create template failed: ${res.body}');
  return jsonDecode(res.body)['id'].toString();
}

Future<String> createEvent(
  TestApi api, {
  required String eventTypeId,
  int clubId = Fixtures.alphaClubId,
  String? date,
  String location = 'Test Hall',
  String notes = '',
  List<Map<String, dynamic>>? roles,
  int? as = Fixtures.adminId,
}) async {
  final res = await api.post('/events', as: as, body: {
    'event_type_id': eventTypeId,
    'lions_club_id': clubId,
    'event_date': date ?? today(addDays: 1),
    'location': location,
    'notes': notes,
    if (roles != null) 'roles': roles,
  });
  expect(res.statusCode, 200, reason: 'create event failed: ${res.body}');
  return jsonDecode(res.body)['event_id'].toString();
}

/// Role list from GET /events/<id> as `[{role_id, role_name, ...}]`.
Future<List<Map<String, dynamic>>> eventRoles(TestApi api, String eventId,
    {int? as = Fixtures.superId}) async {
  final res = await api.get('/events/$eventId', as: as);
  expect(res.statusCode, 200, reason: 'event details failed: ${res.body}');
  return (jsonDecode(res.body)['roles'] as List)
      .cast<Map<String, dynamic>>();
}
