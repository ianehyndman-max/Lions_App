// Integration tests for the events lifecycle: create (custom roles and
// template copy), list/filter visibility, details, update, delete,
// volunteer assignment, per-event roles, and the ICS calendar download.
//
// Tests marked "gap B17" pin down currently-unauthenticated writes so that
// adding auth is a visible, deliberate change (see regression_suite_plan.md).

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

  group('POST /events', () {
    test('rejects empty body and missing required fields', () async {
      expect((await api.post('/events', as: Fixtures.adminId)).statusCode, 400);

      final typeId = await createEventType(api, 'BBQ');
      final missing = await api.post('/events',
          as: Fixtures.adminId,
          body: {'event_type_id': typeId, 'lions_club_id': 1});
      expect(missing.statusCode, 400); // no event_date
    });

    test('creates an event with custom roles and writes an audit row',
        () async {
      final typeId = await createEventType(api, 'BBQ');
      final eventId = await createEvent(api, eventTypeId: typeId, roles: [
        {'role_name': 'Cook', 'time_in': '08:00', 'time_out': '12:00'},
        {'role_name': 'Server', 'time_in': '09:00', 'time_out': '13:00'},
        {'role_name': '', 'time_in': '09:00', 'time_out': '13:00'}, // skipped
      ]);

      final roles = await eventRoles(api, eventId);
      expect(roles.map((r) => r['role_name']), ['Cook', 'Server']);
      expect(roles.every((r) => r['member_id'] == null), isTrue);

      final audits = await auditRows(db, entityType: 'event', action: 'CREATE');
      expect(audits, hasLength(1));
      expect(audits.first['entity_id'], eventId);
    });

    test('copies role templates when no roles are provided', () async {
      final typeId = await createEventType(api, 'Dinner Meeting');
      await createRoleTemplate(api, typeId, 'Greeter',
          timeIn: '18:00', timeOut: '19:00');
      await createRoleTemplate(api, typeId, 'Treasurer',
          timeIn: '17:30', timeOut: '21:00');

      final eventId = await createEvent(api, eventTypeId: typeId);

      final roles = await eventRoles(api, eventId);
      // Ordered by time_in: Treasurer 17:30 before Greeter 18:00.
      expect(roles.map((r) => r['role_name']), ['Treasurer', 'Greeter']);

      // Templates themselves are untouched (still listed for the type).
      final templates = jsonDecode(
              (await api.get('/event_types/$typeId/role_templates')).body)
          as List;
      expect(templates, hasLength(2));
    });

    test('creates no roles when the type has no templates', () async {
      final typeId = await createEventType(api, 'Plain');
      final eventId = await createEvent(api, eventTypeId: typeId);
      expect(await eventRoles(api, eventId), isEmpty);
    });

    // Regression guard for gap B17: event creation requires NO identity.
    // When auth is added, update this to expect 401.
    test('currently allows unauthenticated creation (gap B17)', () async {
      final typeId = await createEventType(api, 'BBQ');
      final eventId = await createEvent(api, eventTypeId: typeId, as: null);
      expect(int.parse(eventId), greaterThan(0));
    });
  });

  group('GET /events', () {
    test('super sees upcoming events from all clubs; members only their club',
        () async {
      final typeId = await createEventType(api, 'BBQ');
      await createEvent(api,
          eventTypeId: typeId, clubId: Fixtures.alphaClubId, location: 'Alpha');
      await createEvent(api,
          eventTypeId: typeId, clubId: Fixtures.betaClubId, location: 'Beta');

      final asSuper =
          jsonDecode((await api.get('/events', as: Fixtures.superId)).body)
              as List;
      expect(asSuper.map((e) => e['location']).toSet(), {'Alpha', 'Beta'});

      final asBetaMember =
          jsonDecode((await api.get('/events', as: Fixtures.betaMemberId)).body)
              as List;
      expect(asBetaMember.map((e) => e['location']), ['Beta']);
    });

    test('hides past events from the list but not from the calendar',
        () async {
      final typeId = await createEventType(api, 'BBQ');
      await createEvent(api,
          eventTypeId: typeId, date: today(addDays: -5), location: 'Past');
      await createEvent(api,
          eventTypeId: typeId, date: today(addDays: 1), location: 'Future');

      final list =
          jsonDecode((await api.get('/events', as: Fixtures.superId)).body)
              as List;
      expect(list.map((e) => e['location']), ['Future']);

      final calendar = jsonDecode(
              (await api.get('/events/calendar', as: Fixtures.superId)).body)
          as List;
      expect(calendar.map((e) => e['location']).toSet(), {'Past', 'Future'});
    });

    test('filters by type and date range', () async {
      final bbqId = await createEventType(api, 'BBQ');
      final dinnerId = await createEventType(api, 'Dinner');
      await createEvent(api,
          eventTypeId: bbqId, date: today(addDays: 3), location: 'SoonBBQ');
      await createEvent(api,
          eventTypeId: dinnerId, date: today(addDays: 3), location: 'SoonDinner');
      await createEvent(api,
          eventTypeId: bbqId, date: today(addDays: 20), location: 'LaterBBQ');
      await createEvent(api,
          eventTypeId: bbqId, date: today(addDays: 40), location: 'FarBBQ');

      Future<List<dynamic>> fetch(String query) async =>
          jsonDecode((await api.get('/events$query', as: Fixtures.superId)).body)
              as List;

      expect((await fetch('?type_id=$bbqId')).map((e) => e['location']),
          ['SoonBBQ', 'LaterBBQ', 'FarBBQ']);

      expect((await fetch('?date_range=week')).map((e) => e['location']).toSet(),
          {'SoonBBQ', 'SoonDinner'});

      expect(
          (await fetch('?date_range=month')).map((e) => e['location']).toSet(),
          {'SoonBBQ', 'SoonDinner', 'LaterBBQ'});
    });
  });

  group('GET /events/<id>', () {
    test('returns 404 for a missing event', () async {
      expect((await api.get('/events/9999', as: Fixtures.superId)).statusCode,
          404);
    });

    test('returns event details with club and type names', () async {
      final typeId = await createEventType(api, 'BBQ');
      final date = today(addDays: 2);
      final eventId = await createEvent(api,
          eventTypeId: typeId,
          date: date,
          location: 'Park',
          notes: 'Bring tongs');

      final body = jsonDecode(
              (await api.get('/events/$eventId', as: Fixtures.superId)).body)
          as Map<String, dynamic>;
      final event = body['event'] as Map<String, dynamic>;
      expect(event['event_type'], 'BBQ');
      expect(event['club_name'], 'Alpha Club');
      expect(event['location'], 'Park');
      expect(event['notes'], 'Bring tongs');
      expect(event['date'].toString(), startsWith(date));
    });
  });

  group('PUT /events/<id>', () {
    test('requires an admin or super identity', () async {
      final typeId = await createEventType(api, 'BBQ');
      final eventId = await createEvent(api, eventTypeId: typeId);
      final body = {
        'event_type_id': typeId,
        'lions_club_id': 1,
        'event_date': today(addDays: 5),
      };

      expect((await api.put('/events/$eventId', body: body)).statusCode, 401);
      expect(
          (await api.put('/events/$eventId', as: Fixtures.memberId, body: body))
              .statusCode,
          403);
    });

    test('admin updates event fields and an audit row is written', () async {
      final typeId = await createEventType(api, 'BBQ');
      final eventId = await createEvent(api, eventTypeId: typeId);

      final newDate = today(addDays: 9);
      final res = await api.put('/events/$eventId', as: Fixtures.adminId, body: {
        'event_type_id': typeId,
        'lions_club_id': 1,
        'event_date': newDate,
        'location': 'New Hall',
        'notes': 'Updated',
      });
      expect(res.statusCode, 200);
      expect(jsonDecode(res.body)['success'], true);

      final event = jsonDecode(
              (await api.get('/events/$eventId', as: Fixtures.superId)).body)[
          'event'] as Map<String, dynamic>;
      expect(event['location'], 'New Hall');
      expect(event['date'].toString(), startsWith(newDate));

      final audits = await auditRows(db, entityType: 'event', action: 'UPDATE');
      expect(audits, hasLength(1));
    });

    test('rejects missing required fields', () async {
      final typeId = await createEventType(api, 'BBQ');
      final eventId = await createEvent(api, eventTypeId: typeId);

      final res = await api.put('/events/$eventId',
          as: Fixtures.adminId, body: {'location': 'Only location'});
      expect(res.statusCode, 400);
    });
  });

  group('DELETE /events/<id>', () {
    test('rejects an invalid id', () async {
      expect((await api.delete('/events/abc', as: Fixtures.adminId)).statusCode,
          400);
    });

    test('deletes the event with its roles and volunteer assignments',
        () async {
      final typeId = await createEventType(api, 'BBQ');
      final eventId = await createEvent(api, eventTypeId: typeId, roles: [
        {'role_name': 'Cook', 'time_in': '08:00', 'time_out': '12:00'},
      ]);
      final roleId = (await eventRoles(api, eventId)).single['role_id'];
      await api.post('/events/$eventId/volunteers',
          as: Fixtures.adminId,
          body: {'role_id': roleId, 'member_id': Fixtures.memberId});

      final res = await api.delete('/events/$eventId', as: Fixtures.adminId);
      expect(res.statusCode, 204);
      expect((await api.get('/events/$eventId', as: Fixtures.superId))
          .statusCode, 404);

      // Related rows are gone.
      final roleCount = await db.execute(
          'SELECT COUNT(*) AS c FROM roles WHERE event_id = :id',
          {'id': eventId});
      expect(roleCount.rows.first.assoc()['c'], '0');
      final volCount = await db.execute(
          'SELECT COUNT(*) AS c FROM event_volunteers WHERE event_id = :id',
          {'id': eventId});
      expect(volCount.rows.first.assoc()['c'], '0');
    });

    // Regression guard for gap B17: deletion requires NO identity.
    // When auth is added, update this to expect 401.
    test('currently allows unauthenticated deletion (gap B17)', () async {
      final typeId = await createEventType(api, 'BBQ');
      final eventId = await createEvent(api, eventTypeId: typeId);
      expect((await api.delete('/events/$eventId')).statusCode, 204);
    });
  });

  group('volunteer assignment', () {
    late String eventId;
    late String roleId;

    setUp(() async {
      final typeId = await createEventType(api, 'BBQ');
      eventId = await createEvent(api, eventTypeId: typeId, roles: [
        {'role_name': 'Cook', 'time_in': '08:00', 'time_out': '12:00'},
      ]);
      roleId = (await eventRoles(api, eventId)).single['role_id'].toString();
    });

    test('requires role_id and a valid member_id', () async {
      expect(
          (await api.post('/events/$eventId/volunteers',
                  as: Fixtures.adminId, body: {'member_id': 3}))
              .statusCode,
          400);
      expect(
          (await api.post('/events/$eventId/volunteers',
                  as: Fixtures.adminId,
                  body: {'role_id': roleId, 'member_id': 'abc'}))
              .statusCode,
          400);
    });

    test('assigns a member with a meal choice, then reassigns', () async {
      final res = await api.post('/events/$eventId/volunteers',
          as: Fixtures.adminId,
          body: {
            'role_id': roleId,
            'member_id': Fixtures.memberId,
            'meal_choice': 'Chicken',
          });
      expect(res.statusCode, 200);

      var role = (await eventRoles(api, eventId)).single;
      expect(role['volunteer_name'], 'Mel Member');
      expect(role['meal_choice'], 'Chicken');

      // Reassigning the same role replaces the volunteer (one per role).
      await api.post('/events/$eventId/volunteers', as: Fixtures.adminId, body: {
        'role_id': roleId,
        'member_id': Fixtures.conferenceId,
      });
      role = (await eventRoles(api, eventId)).single;
      expect(role['volunteer_name'], 'Carl Conference');

      final count = await db.execute(
          'SELECT COUNT(*) AS c FROM event_volunteers WHERE event_id = :id',
          {'id': eventId});
      expect(count.rows.first.assoc()['c'], '1');
    });

    test('clears the assignment for null-like member_id values', () async {
      for (final clearValue in [null, 'Clear Assignment', '0', 'unassigned']) {
        await api.post('/events/$eventId/volunteers', as: Fixtures.adminId, body: {
          'role_id': roleId,
          'member_id': Fixtures.memberId,
        });

        final res = await api.post('/events/$eventId/volunteers',
            as: Fixtures.adminId,
            body: {'role_id': roleId, 'member_id': clearValue});
        expect(res.statusCode, 200, reason: 'clear with $clearValue');

        final role = (await eventRoles(api, eventId)).single;
        expect(role['member_id'], isNull, reason: 'clear with $clearValue');
      }
    });

    test('DELETE unassigns the volunteer', () async {
      await api.post('/events/$eventId/volunteers', as: Fixtures.adminId, body: {
        'role_id': roleId,
        'member_id': Fixtures.memberId,
      });

      final res = await api.delete('/events/$eventId/volunteers/$roleId',
          as: Fixtures.adminId);
      expect(res.statusCode, 204);
      expect((await eventRoles(api, eventId)).single['member_id'], isNull);
    });
  });

  group('per-event roles', () {
    late String eventId;

    setUp(() async {
      final typeId = await createEventType(api, 'BBQ');
      eventId = await createEvent(api, eventTypeId: typeId);
    });

    test('POST /events/<id>/roles requires admin and a role name', () async {
      final body = {'role_name': 'Helper', 'time_in': '10:00', 'time_out': '14:00'};
      expect(
          (await api.post('/events/$eventId/roles', body: body)).statusCode,
          401);
      expect(
          (await api.post('/events/$eventId/roles',
                  as: Fixtures.memberId, body: body))
              .statusCode,
          403);
      expect(
          (await api.post('/events/$eventId/roles',
                  as: Fixtures.adminId, body: {'role_name': ''}))
              .statusCode,
          400);

      final res = await api.post('/events/$eventId/roles',
          as: Fixtures.adminId, body: body);
      expect(res.statusCode, 200);
      expect((await eventRoles(api, eventId)).single['role_name'], 'Helper');
    });

    test('PUT /roles/<id> updates a role; DELETE removes it with assignments',
        () async {
      await api.post('/events/$eventId/roles',
          as: Fixtures.adminId,
          body: {'role_name': 'Helper', 'time_in': '10:00', 'time_out': '14:00'});
      final roleId =
          (await eventRoles(api, eventId)).single['role_id'].toString();

      expect(
          (await api.put('/roles/$roleId', body: {'role_name': 'X'}))
              .statusCode,
          401);
      expect(
          (await api.put('/roles/$roleId',
                  as: Fixtures.memberId, body: {'role_name': 'X'}))
              .statusCode,
          403);

      final updated = await api.put('/roles/$roleId', as: Fixtures.adminId, body: {
        'role_name': 'Head Helper',
        'time_in': '09:00',
        'time_out': '15:00',
      });
      expect(updated.statusCode, 200);
      final role = (await eventRoles(api, eventId)).single;
      expect(role['role_name'], 'Head Helper');
      expect(role['time_in'], '09:00');

      // Assign, then delete the role: the assignment must go too.
      await api.post('/events/$eventId/volunteers', as: Fixtures.adminId, body: {
        'role_id': roleId,
        'member_id': Fixtures.memberId,
      });
      expect((await api.delete('/roles/$roleId', as: Fixtures.adminId))
          .statusCode, 204);
      expect(await eventRoles(api, eventId), isEmpty);

      final volCount = await db.execute(
          'SELECT COUNT(*) AS c FROM event_volunteers WHERE role_id = :id',
          {'id': roleId});
      expect(volCount.rows.first.assoc()['c'], '0');
    });
  });

  group('GET /events/<id>/calendar.ics', () {
    test('returns 404 for a missing event', () async {
      expect((await api.get('/events/9999/calendar.ics')).statusCode, 404);
    });

    test('produces a valid all-day VEVENT with escaped text', () async {
      final typeId = await createEventType(api, 'BBQ');
      final date = today(addDays: 3);
      final eventId = await createEvent(api,
          eventTypeId: typeId,
          date: date,
          location: 'Hall, Main St',
          notes: 'Line one\nLine two');

      final res = await api.get('/events/$eventId/calendar.ics');
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('text/calendar'));

      final ics = res.body;
      final compactDate = date.replaceAll('-', '');
      expect(ics, contains('BEGIN:VCALENDAR'));
      expect(ics, contains('UID:event-$eventId@thelionsapp.com'));
      expect(ics, contains('DTSTART;VALUE=DATE:$compactDate'));
      expect(ics, contains('SUMMARY:BBQ'));
      // Commas and newlines are escaped per RFC 5545.
      expect(ics, contains('LOCATION:Hall\\, Main St'));
      expect(ics, contains('DESCRIPTION:Line one\\nLine two'));
      expect(ics, contains('END:VCALENDAR'));
    });
  });
}
