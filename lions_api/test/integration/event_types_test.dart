// Integration tests for /event_types, role templates, and
// /dinner_meal_options: CRUD, admin/super permission checks, validation,
// in-use protection, and template ordering.

import 'dart:convert';

import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';

import '../helpers/api_builders.dart';
import '../helpers/test_harness.dart';

void main() {
  late TestServer server;
  late TestApi api;
  late MySQLConnection db;

  setUpAll(() async {
    db = await connectTestDb();
    server = await TestServer.start();
    api = TestApi(server);
  });

  tearDownAll(() async {
    server.stop();
    await db.close();
  });

  setUp(() async {
    await resetDatabase(db);
    await seedFixtures(db);
  });

  group('event types CRUD', () {
    test('GET lists types sorted by name', () async {
      await createEventType(api, 'Zebra Walk');
      await createEventType(api, 'Auction');

      final types = jsonDecode((await api.get('/event_types')).body) as List;
      expect(types.map((t) => t['name']), ['Auction', 'Zebra Walk']);
    });

    test('POST requires admin/super and a non-blank name', () async {
      expect((await api.post('/event_types', body: {'name': 'X'})).statusCode,
          401);
      expect(
          (await api.post('/event_types',
                  as: Fixtures.memberId, body: {'name': 'X'}))
              .statusCode,
          403);
      expect(
          (await api.post('/event_types',
                  as: Fixtures.adminId, body: {'name': '  '}))
              .statusCode,
          400);

      final res = await api.post('/event_types',
          as: Fixtures.adminId, body: {'name': 'Sausage Sizzle'});
      expect(res.statusCode, 200);
      expect(jsonDecode(res.body)['name'], 'Sausage Sizzle');

      final audits =
          await auditRows(db, entityType: 'event_type', action: 'CREATE');
      expect(audits, hasLength(1));
    });

    test('PUT renames a type; 404 for a missing one', () async {
      final typeId = await createEventType(api, 'Old Name');

      expect(
          (await api.put('/event_types/$typeId', body: {'name': 'X'}))
              .statusCode,
          401);
      expect(
          (await api.put('/event_types/$typeId',
                  as: Fixtures.memberId, body: {'name': 'X'}))
              .statusCode,
          403);
      expect(
          (await api.put('/event_types/$typeId',
                  as: Fixtures.adminId, body: {'name': ''}))
              .statusCode,
          400);

      final res = await api.put('/event_types/$typeId',
          as: Fixtures.adminId, body: {'name': 'New Name'});
      expect(res.statusCode, 200);

      final types = jsonDecode((await api.get('/event_types')).body) as List;
      expect(types.single['name'], 'New Name');

      expect(
          (await api.put('/event_types/9999',
                  as: Fixtures.adminId, body: {'name': 'Ghost'}))
              .statusCode,
          404);
    });

    test('DELETE refuses while events use the type, then removes it with '
        'its templates', () async {
      final typeId = await createEventType(api, 'BBQ');
      await createRoleTemplate(api, typeId, 'Cook');
      final eventId = await createEvent(api, eventTypeId: typeId);

      expect((await api.delete('/event_types/$typeId')).statusCode, 401);
      expect(
          (await api.delete('/event_types/$typeId', as: Fixtures.memberId))
              .statusCode,
          403);

      final inUse =
          await api.delete('/event_types/$typeId', as: Fixtures.adminId);
      expect(inUse.statusCode, 400);
      expect(inUse.body, contains('in use'));

      await api.delete('/events/$eventId', as: Fixtures.adminId);

      final res =
          await api.delete('/event_types/$typeId', as: Fixtures.adminId);
      expect(res.statusCode, 204);
      expect(jsonDecode((await api.get('/event_types')).body), isEmpty);

      // Its role templates were removed with it.
      final templateCount = await db.execute(
          'SELECT COUNT(*) AS c FROM roles WHERE event_type_id = :id',
          {'id': typeId});
      expect(templateCount.rows.first.assoc()['c'], '0');
    });
  });

  group('role templates', () {
    late String typeId;

    setUp(() async {
      typeId = await createEventType(api, 'Dinner Meeting');
    });

    test('POST requires admin/super and a role name', () async {
      final body = {'role_name': 'Greeter'};
      expect(
          (await api.post('/event_types/$typeId/role_templates', body: body))
              .statusCode,
          401);
      expect(
          (await api.post('/event_types/$typeId/role_templates',
                  as: Fixtures.memberId, body: body))
              .statusCode,
          403);
      expect(
          (await api.post('/event_types/$typeId/role_templates',
                  as: Fixtures.adminId, body: {'role_name': ''}))
              .statusCode,
          400);
    });

    test('GET lists templates ordered by start time', () async {
      await createRoleTemplate(api, typeId, 'Late Shift',
          timeIn: '19:00', timeOut: '22:00');
      await createRoleTemplate(api, typeId, 'Early Shift',
          timeIn: '17:00', timeOut: '19:00');

      final templates = jsonDecode(
              (await api.get('/event_types/$typeId/role_templates')).body)
          as List;
      expect(templates.map((t) => t['role_name']), ['Early Shift', 'Late Shift']);
      expect(templates.first['time_in'], '17:00');
    });

    test('POST with an id updates an existing template', () async {
      final templateId = await createRoleTemplate(api, typeId, 'Greeter',
          timeIn: '18:00', timeOut: '19:00');

      final res = await api.post('/event_types/$typeId/role_templates',
          as: Fixtures.adminId,
          body: {
            'id': templateId,
            'role_name': 'Head Greeter',
            'time_in': '17:45',
            'time_out': '19:15',
          });
      expect(res.statusCode, 200);
      expect(jsonDecode(res.body)['success'], true);

      final templates = jsonDecode(
              (await api.get('/event_types/$typeId/role_templates')).body)
          as List;
      expect(templates.single['role_name'], 'Head Greeter');
      expect(templates.single['time_in'], '17:45');
    });

    test('DELETE removes a template but never an event role', () async {
      final templateId = await createRoleTemplate(api, typeId, 'Greeter');

      expect((await api.delete('/role_templates/$templateId')).statusCode, 401);
      expect(
          (await api.delete('/role_templates/$templateId',
                  as: Fixtures.memberId))
              .statusCode,
          403);

      expect(
          (await api.delete('/role_templates/$templateId',
                  as: Fixtures.adminId))
              .statusCode,
          204);
      expect(
          jsonDecode((await api.get('/event_types/$typeId/role_templates')).body),
          isEmpty);

      // An event-attached role is not deletable through the template route.
      final eventId = await createEvent(api, eventTypeId: typeId, roles: [
        {'role_name': 'Cook', 'time_in': '08:00', 'time_out': '12:00'},
      ]);
      final eventRoleId =
          (await eventRoles(api, eventId)).single['role_id'].toString();
      await api.delete('/role_templates/$eventRoleId', as: Fixtures.adminId);
      expect((await eventRoles(api, eventId)).single['role_name'], 'Cook');
    });
  });

  group('dinner meal options', () {
    test('GET returns options sorted by sort_order', () async {
      await api.post('/dinner_meal_options',
          as: Fixtures.adminId, body: {'name': 'Fish', 'sort_order': 2});
      await api.post('/dinner_meal_options',
          as: Fixtures.adminId, body: {'name': 'Chicken', 'sort_order': 1});

      final options =
          jsonDecode((await api.get('/dinner_meal_options')).body) as List;
      expect(options.map((o) => o['name']), ['Chicken', 'Fish']);
    });

    test('POST requires admin/super and a name', () async {
      expect(
          (await api.post('/dinner_meal_options', body: {'name': 'X'}))
              .statusCode,
          401);
      expect(
          (await api.post('/dinner_meal_options',
                  as: Fixtures.memberId, body: {'name': 'X'}))
              .statusCode,
          403);
      expect(
          (await api.post('/dinner_meal_options',
                  as: Fixtures.adminId, body: {'name': '  '}))
              .statusCode,
          400);
    });

    test('POST with an id updates; DELETE removes', () async {
      final createRes = await api.post('/dinner_meal_options',
          as: Fixtures.adminId, body: {'name': 'Chicken', 'sort_order': 1});
      final optionId = jsonDecode(createRes.body)['id'].toString();

      final updateRes = await api.post('/dinner_meal_options',
          as: Fixtures.adminId,
          body: {'id': optionId, 'name': 'Roast Chicken', 'sort_order': 5});
      expect(updateRes.statusCode, 200);
      expect(jsonDecode(updateRes.body)['success'], true);

      var options =
          jsonDecode((await api.get('/dinner_meal_options')).body) as List;
      expect(options.single['name'], 'Roast Chicken');

      expect((await api.delete('/dinner_meal_options/$optionId')).statusCode,
          401);
      expect(
          (await api.delete('/dinner_meal_options/$optionId',
                  as: Fixtures.memberId))
              .statusCode,
          403);
      expect(
          (await api.delete('/dinner_meal_options/$optionId',
                  as: Fixtures.adminId))
              .statusCode,
          204);

      options =
          jsonDecode((await api.get('/dinner_meal_options')).body) as List;
      expect(options, isEmpty);
    });
  });
}
