// Integration tests for /reports/*, /audit_logs, and /events/<id>/notify.
//
// IMPORTANT: three endpoints are broken against the schema shipped in
// migrations/create_schema.sql and return 500 on every call:
//   - /reports/volunteers       (selects members.first_name/last_name;
//                                the table only has `name`)
//   - /reports/club_comparison  (queries an `assignments` table and
//                                events.club_id/events.date, none of which exist)
//   - /audit_logs               (selects audit_log.changed_at; the column
//                                is `created_at`)
// Those tests pin the current 500 behavior — see gaps B18–B20 in
// regression_suite_plan.md. When the SQL is fixed they will fail loudly and
// should be replaced with real assertions.
//
// Email sending is exercised via dry_run (no SMTP) and a zero-recipient send;
// real SMTP delivery is deliberately out of scope for integration tests.

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

  group('GET /reports/events', () {
    test('requires an identity', () async {
      expect((await api.get('/reports/events')).statusCode, 401);
    });

    test('aggregates totals by type with date and club filters', () async {
      final bbqId = await createEventType(api, 'BBQ');
      final dinnerId = await createEventType(api, 'Dinner');
      await createEvent(api, eventTypeId: bbqId, date: '2026-06-01');
      await createEvent(api, eventTypeId: bbqId, date: '2026-06-15');
      await createEvent(api, eventTypeId: dinnerId, date: '2026-07-01');
      await createEvent(api,
          eventTypeId: bbqId,
          clubId: Fixtures.betaClubId,
          date: '2026-06-20');

      Future<Map<String, dynamic>> report(String query) async {
        final res = await api.get('/reports/events$query', as: Fixtures.adminId);
        expect(res.statusCode, 200, reason: res.body);
        return jsonDecode(res.body) as Map<String, dynamic>;
      }

      final all = await report('');
      expect(all['total_events'], 4);
      final byType = (all['by_type'] as List)
          .map((t) => '${t['event_type']}:${t['count']}');
      expect(byType, ['BBQ:3', 'Dinner:1']); // ordered by count desc

      final june = await report('?start_date=2026-06-01&end_date=2026-06-30');
      expect(june['total_events'], 3);

      final alphaOnly = await report('?club_id=${Fixtures.alphaClubId}');
      expect(alphaOnly['total_events'], 3);

      final narrow = await report(
          '?start_date=2026-06-10&end_date=2026-06-30&club_id=${Fixtures.alphaClubId}');
      expect(narrow['total_events'], 1);
    });
  });

  group('GET /reports/fill_rates', () {
    test('requires an identity', () async {
      expect((await api.get('/reports/fill_rates')).statusCode, 401);
    });

    test('computes overall and per-event fill rates', () async {
      final typeId = await createEventType(api, 'BBQ');
      final eventId = await createEvent(api,
          eventTypeId: typeId,
          date: '2026-06-01',
          roles: [
            {'role_name': 'Cook', 'time_in': '08:00', 'time_out': '12:00'},
            {'role_name': 'Server', 'time_in': '09:00', 'time_out': '13:00'},
          ]);
      final roleId = (await eventRoles(api, eventId)).first['role_id'];
      await api.post('/events/$eventId/volunteers',
          as: Fixtures.adminId,
          body: {'role_id': roleId, 'member_id': Fixtures.memberId});

      final res = await api.get('/reports/fill_rates', as: Fixtures.adminId);
      expect(res.statusCode, 200, reason: res.body);
      final report = jsonDecode(res.body) as Map<String, dynamic>;

      expect(report['total_roles'], 2);
      expect(report['filled_roles'], 1);
      expect(report['overall_fill_rate'], 0.5);

      final byEvent = (report['by_event'] as List).single;
      expect(byEvent['event_id'].toString(), eventId);
      expect(byEvent['event_type'], 'BBQ');
      expect(byEvent['total_roles'], 2);
      expect(byEvent['filled_roles'], 1);
      expect(byEvent['fill_rate'], 0.5);
    });

    test('an empty database yields a zero fill rate, not an error', () async {
      final res = await api.get('/reports/fill_rates', as: Fixtures.adminId);
      expect(res.statusCode, 200);
      expect(jsonDecode(res.body)['overall_fill_rate'], 0.0);
    });
  });

  group('broken report endpoints (pinned current behavior)', () {
    // BUG / gap B18: selects members.first_name/last_name which do not exist.
    test('/reports/volunteers currently fails with 500 (gap B18)', () async {
      expect((await api.get('/reports/volunteers')).statusCode, 401);

      final res = await api.get('/reports/volunteers', as: Fixtures.adminId);
      expect(res.statusCode, 500);
      expect(res.body, contains('first_name'));
    });

    // BUG / gap B19: queries a non-existent `assignments` table and wrong
    // event column names. Validation before the SQL still works.
    test('/reports/club_comparison currently fails with 500 (gap B19)',
        () async {
      expect((await api.get('/reports/club_comparison')).statusCode, 401);
      expect(
          (await api.get('/reports/club_comparison', as: Fixtures.adminId))
              .statusCode,
          403); // super only
      expect(
          (await api.get('/reports/club_comparison', as: Fixtures.superId))
              .statusCode,
          400); // dates required

      final res = await api.get(
          '/reports/club_comparison?start_date=2026-01-01&end_date=2026-12-31',
          as: Fixtures.superId);
      expect(res.statusCode, 500);
      expect(res.body, contains('assignments'));
    });
  });

  group('GET /audit_logs', () {
    test('requires a super identity', () async {
      expect((await api.get('/audit_logs')).statusCode, 401);
      for (final who in [Fixtures.memberId, Fixtures.adminId]) {
        expect((await api.get('/audit_logs', as: who)).statusCode, 403,
            reason: 'member $who must not read audit logs');
      }
    });

    // BUG / gap B20: selects audit_log.changed_at; the schema column is
    // created_at, so listing always fails.
    test('listing currently fails with 500 (gap B20)', () async {
      final res = await api.get('/audit_logs', as: Fixtures.superId);
      expect(res.statusCode, 500);
      expect(res.body, contains('changed_at'));
    });
  });

  group('POST /events/<id>/notify', () {
    late String typeId;
    late String eventId;

    setUp(() async {
      typeId = await createEventType(api, 'BBQ');
      eventId = await createEvent(api, eventTypeId: typeId, roles: [
        {'role_name': 'Cook', 'time_in': '08:00', 'time_out': '12:00'},
      ]);
    });

    test('returns 404 for a missing event', () async {
      final res = await api.post('/events/9999/notify',
          as: Fixtures.adminId, body: {'dry_run': true});
      expect(res.statusCode, 404);
    });

    test('dry run renders the new-event email for all club members',
        () async {
      final res = await api.post('/events/$eventId/notify',
          as: Fixtures.adminId, body: {'dry_run': true});
      expect(res.statusCode, 200);
      final preview = jsonDecode(res.body) as Map<String, dynamic>;

      expect(preview['subject'], contains('Alpha Club'));
      final bodyHtml = preview['body_html'] as String;
      expect(bodyHtml, contains('Cook'));
      expect(bodyHtml, contains('Test Hall'));
      expect(bodyHtml, contains('/events/$eventId/calendar.ics'));

      final recipients = (preview['recipients'] as String)
          .split(', ')
          .toSet();
      expect(recipients, {
        'sue@test.com',
        'alan@test.com',
        'mel@test.com',
        'carl@test.com',
      });
    });

    test('only_assigned dry run targets just assigned volunteers', () async {
      final roleId = (await eventRoles(api, eventId)).single['role_id'];
      await api.post('/events/$eventId/volunteers',
          as: Fixtures.adminId,
          body: {'role_id': roleId, 'member_id': Fixtures.memberId});

      final res = await api.post('/events/$eventId/notify',
          as: Fixtures.adminId,
          body: {'dry_run': true, 'only_assigned': true});
      final preview = jsonDecode(res.body) as Map<String, dynamic>;
      expect(preview['recipients'], 'mel@test.com');
    });

    test('subject and body overrides pass through unchanged', () async {
      final res = await api.post('/events/$eventId/notify',
          as: Fixtures.adminId,
          body: {
            'dry_run': true,
            'subject': 'Custom subject',
            'body_html': '<p>Custom body</p>',
          });
      final preview = jsonDecode(res.body) as Map<String, dynamic>;
      expect(preview['subject'], 'Custom subject');
      expect(preview['body_html'], '<p>Custom body</p>');
    });

    test('real send with no eligible recipients reports zero sent', () async {
      // A club with no members means no recipients and no SMTP attempt.
      await db.execute(
          "INSERT INTO lions_club (id, name) VALUES (3, 'Empty Club')");
      final emptyClubEvent = await createEvent(api,
          eventTypeId: typeId, clubId: 3, roles: [
        {'role_name': 'Cook', 'time_in': '08:00', 'time_out': '12:00'},
      ]);

      final res = await api.post('/events/$emptyClubEvent/notify',
          as: Fixtures.adminId, body: {});
      expect(res.statusCode, 200);
      expect(res.body, contains('0 recipients'));
    });

    test("an 'Other' event with no roles cannot be sent (400)", () async {
      final otherTypeId = await createEventType(api, 'Other');
      final otherEventId =
          await createEvent(api, eventTypeId: otherTypeId);

      final res = await api.post('/events/$otherEventId/notify',
          as: Fixtures.adminId, body: {});
      expect(res.statusCode, 400);
      expect(res.body, contains('No roles'));

      // But the dry-run preview still works.
      final dry = await api.post('/events/$otherEventId/notify',
          as: Fixtures.adminId, body: {'dry_run': true});
      expect(dry.statusCode, 200);
    });
  });
}
