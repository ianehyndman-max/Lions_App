// Integration tests for /members and /clubs.
//
// Requires the test database (docker-compose.test.yml locally, MySQL service
// in CI). The real API server is started as a subprocess.
//
// Some tests deliberately pin down *insecure* current behavior (unauthenticated
// reads/writes) so that fixing it is a visible, intentional change — see gaps
// B2/B16 in regression_suite_plan.md.

import 'dart:convert';

import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';

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

  group('GET /clubs', () {
    test('lists clubs sorted by name', () async {
      final res = await api.get('/clubs');
      expect(res.statusCode, 200);

      final clubs = jsonDecode(res.body) as List;
      expect(clubs.map((c) => c['name']), ['Alpha Club', 'Beta Club']);
      expect(clubs.first['email_subdomain'], isNull);
    });
  });

  group('POST /clubs', () {
    test('requires authentication', () async {
      final res = await api.post('/clubs', body: {'name': 'New Club'});
      expect(res.statusCode, 401);
    });

    test('requires super (admin and plain members are forbidden)', () async {
      for (final who in [Fixtures.adminId, Fixtures.memberId]) {
        final res =
            await api.post('/clubs', as: who, body: {'name': 'New Club'});
        expect(res.statusCode, 403, reason: 'member $who should be forbidden');
      }
    });

    test('rejects a missing or blank name', () async {
      final blank = await api.post('/clubs',
          as: Fixtures.superId, body: {'name': '   '});
      expect(blank.statusCode, 400);

      final missing =
          await api.post('/clubs', as: Fixtures.superId, body: {});
      expect(missing.statusCode, 400);
    });

    test('super creates a club with email settings', () async {
      final res = await api.post('/clubs', as: Fixtures.superId, body: {
        'name': 'Gamma Club',
        'email_subdomain': 'gamma',
        'reply_to_email': 'reply@gamma.org',
        'from_name': 'Gamma Lions',
      });
      expect(res.statusCode, 200);

      final created = jsonDecode(res.body) as Map<String, dynamic>;
      expect(created['name'], 'Gamma Club');
      expect(created['email_subdomain'], 'gamma');

      final list =
          jsonDecode((await api.get('/clubs')).body) as List;
      final gamma = list.singleWhere((c) => c['name'] == 'Gamma Club');
      expect(gamma['reply_to_email'], 'reply@gamma.org');
      expect(gamma['from_name'], 'Gamma Lions');
    });
  });

  group('PUT /clubs/<id>', () {
    test('requires authentication and super access', () async {
      expect(
          (await api.put('/clubs/1', body: {'name': 'X'})).statusCode, 401);
      expect(
          (await api.put('/clubs/1', as: Fixtures.adminId, body: {'name': 'X'}))
              .statusCode,
          403);
    });

    test('rejects a blank name', () async {
      final res = await api.put('/clubs/1',
          as: Fixtures.superId, body: {'name': ''});
      expect(res.statusCode, 400);
    });

    test('super updates club fields', () async {
      final res = await api.put('/clubs/1', as: Fixtures.superId, body: {
        'name': 'Alpha Renamed',
        'email_subdomain': 'alpha',
      });
      expect(res.statusCode, 200);
      expect(jsonDecode(res.body)['success'], true);

      final list = jsonDecode((await api.get('/clubs')).body) as List;
      final renamed = list.singleWhere((c) => c['name'] == 'Alpha Renamed');
      expect(renamed['email_subdomain'], 'alpha');
    });
  });

  group('DELETE /clubs/<id>', () {
    test('requires authentication and super access', () async {
      expect((await api.delete('/clubs/2')).statusCode, 401);
      expect(
          (await api.delete('/clubs/2', as: Fixtures.adminId)).statusCode, 403);
    });

    test('super deletes a club and its members are detached, not deleted',
        () async {
      final res = await api.delete('/clubs/2', as: Fixtures.superId);
      expect(res.statusCode, 204);

      final clubs = jsonDecode((await api.get('/clubs')).body) as List;
      expect(clubs.map((c) => c['name']), ['Alpha Club']);

      // FK is ON DELETE SET NULL: Betty survives without a club.
      final betty = jsonDecode(
              (await api.get('/members/${Fixtures.betaMemberId}',
                      as: Fixtures.superId))
                  .body)
          as Map<String, dynamic>;
      expect(betty['lions_club_id'], isNull);
    });
  });

  group('GET /members', () {
    test('lists members with normalized integer flags and club name',
        () async {
      final res = await api.get('/members', as: Fixtures.superId);
      expect(res.statusCode, 200);

      final members = jsonDecode(res.body) as List;
      expect(members.length, 5);
      // Sorted by lowercased name.
      expect(members.first['name'], 'Alan Admin');

      final sue = members.singleWhere((m) => m['name'] == 'Sue Super');
      expect(sue['is_super'], 1);
      expect(sue['is_admin'], 0);
      expect(sue['club_name'], 'Alpha Club');
    });

    test('filters by club_id', () async {
      final res = await api.get('/members?club_id=2', as: Fixtures.superId);
      final members = jsonDecode(res.body) as List;
      expect(members.map((m) => m['name']), ['Betty Beta']);
    });

    // Regression guard for gap B2: this read currently requires NO identity
    // and exposes emails/phone numbers. When auth is added, this test MUST
    // be updated to expect 401 — that is the point of pinning it.
    test('currently allows unauthenticated listing (gap B2)', () async {
      final res = await api.get('/members');
      expect(res.statusCode, 200);
      expect((jsonDecode(res.body) as List).length, 5);
    });
  });

  group('POST /members', () {
    test('rejects an empty body or missing required fields', () async {
      expect((await api.post('/members', as: Fixtures.adminId)).statusCode,
          400);
      expect(
          (await api.post('/members',
                  as: Fixtures.adminId, body: {'name': 'No Club'}))
              .statusCode,
          400);
      expect(
          (await api.post('/members',
                  as: Fixtures.adminId, body: {'lions_club_id': 1}))
              .statusCode,
          400);
    });

    test('creates a member with defaults and writes an audit row', () async {
      final res = await api.post('/members', as: Fixtures.adminId, body: {
        'name': 'Nina New',
        'email': 'nina@test.com',
        'phone_number': '0400000099',
        'lions_club_id': 1,
      });
      expect(res.statusCode, 200);
      final newId = jsonDecode(res.body)['id'];

      final fetched = jsonDecode(
              (await api.get('/members/$newId', as: Fixtures.superId)).body)
          as Map<String, dynamic>;
      expect(fetched['name'], 'Nina New');
      expect(fetched['is_admin'], 0);
      expect(fetched['is_super'], 0);
      expect(fetched['is_conference_member'], 0);

      final audits =
          await auditRows(db, entityType: 'member', action: 'CREATE');
      expect(audits, hasLength(1));
      expect(audits.first['entity_id'], '$newId');
      expect(audits.first['changed_by_member_id'], '${Fixtures.adminId}');
    });

    test('honours is_admin/is_conference_member flags but cannot create super',
        () async {
      final res = await api.post('/members', as: Fixtures.superId, body: {
        'name': 'Flag Member',
        'lions_club_id': 1,
        'is_admin': '1',
        'is_conference_member': true,
        'is_super': 1, // not supported by the endpoint; must be ignored
      });
      final newId = jsonDecode(res.body)['id'];

      final fetched = jsonDecode(
              (await api.get('/members/$newId', as: Fixtures.superId)).body)
          as Map<String, dynamic>;
      expect(fetched['is_admin'], 1);
      expect(fetched['is_conference_member'], 1);
      expect(fetched['is_super'], 0);
    });

    // Regression guard for gap B16: creation currently requires NO identity.
    // When auth is added, update this to expect 401.
    test('currently allows unauthenticated creation (gap B16)', () async {
      final res = await api.post('/members', body: {
        'name': 'Ghost',
        'lions_club_id': 1,
      });
      expect(res.statusCode, 200);
    });
  });

  group('GET /members/<id>', () {
    test('rejects an invalid id', () async {
      final res = await api.get('/members/abc', as: Fixtures.superId);
      expect(res.statusCode, 400);
    });

    test('requires admin, super, or self', () async {
      // Unauthenticated and non-self plain member are forbidden.
      expect((await api.get('/members/${Fixtures.memberId}')).statusCode, 403);
      expect(
          (await api.get('/members/${Fixtures.superId}',
                  as: Fixtures.memberId))
              .statusCode,
          403);

      // Self, admin, and super are allowed.
      for (final who in [
        Fixtures.memberId,
        Fixtures.adminId,
        Fixtures.superId
      ]) {
        final res = await api.get('/members/${Fixtures.memberId}', as: who);
        expect(res.statusCode, 200, reason: 'member $who should see profile');
      }
    });

    test('returns 404 for a missing member', () async {
      final res =
          await api.get('/members/${Fixtures.unknownId}', as: Fixtures.superId);
      expect(res.statusCode, 404);
    });

    test('returns the full profile with integer flags', () async {
      final res =
          await api.get('/members/${Fixtures.conferenceId}', as: Fixtures.superId);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['name'], 'Carl Conference');
      expect(body['email'], 'carl@test.com');
      expect(body['phone_number'], '0400000004');
      expect(body['is_conference_member'], 1);
      expect(body['club_name'], 'Alpha Club');
    });
  });

  group('PUT /members/<id>', () {
    test('rejects an invalid id', () async {
      expect(
          (await api.put('/members/abc',
                  as: Fixtures.superId, body: {'name': 'X'}))
              .statusCode,
          400);
    });

    test('requires admin, super, or self', () async {
      expect(
          (await api.put('/members/${Fixtures.memberId}', body: {'name': 'X'}))
              .statusCode,
          403);
      expect(
          (await api.put('/members/${Fixtures.adminId}',
                  as: Fixtures.memberId, body: {'name': 'X'}))
              .statusCode,
          403);
    });

    test('self can update contact fields', () async {
      final res =
          await api.put('/members/${Fixtures.memberId}', as: Fixtures.memberId, body: {
        'name': 'Mel Updated',
        'email': 'mel2@test.com',
        'phone_number': '0400999999',
      });
      expect(res.statusCode, 200);

      final fetched = jsonDecode(
              (await api.get('/members/${Fixtures.memberId}',
                      as: Fixtures.memberId))
                  .body)
          as Map<String, dynamic>;
      expect(fetched['name'], 'Mel Updated');
      expect(fetched['email'], 'mel2@test.com');
      expect(fetched['phone_number'], '0400999999');
    });

    test('self cannot escalate own privileges', () async {
      // Flag-only update: nothing the member may change -> rejected.
      final flagsOnly = await api.put('/members/${Fixtures.memberId}',
          as: Fixtures.memberId, body: {'is_admin': 1});
      expect(flagsOnly.statusCode, 400);

      // Mixed update: allowed fields apply, privilege flags are ignored.
      final mixed = await api.put('/members/${Fixtures.memberId}',
          as: Fixtures.memberId,
          body: {'name': 'Mel Sneaky', 'is_admin': 1, 'lions_club_id': 2});
      expect(mixed.statusCode, 200);

      final fetched = jsonDecode(
              (await api.get('/members/${Fixtures.memberId}',
                      as: Fixtures.memberId))
                  .body)
          as Map<String, dynamic>;
      expect(fetched['name'], 'Mel Sneaky');
      expect(fetched['is_admin'], 0);
      // Note: the API serializes ids as strings (raw DB values).
      expect(fetched['lions_club_id'], '1');
    });

    test('admin can set is_admin and club, but not is_conference_member',
        () async {
      final res = await api.put('/members/${Fixtures.memberId}',
          as: Fixtures.adminId,
          body: {'is_admin': true, 'lions_club_id': 2});
      expect(res.statusCode, 200);

      final fetched = jsonDecode(
              (await api.get('/members/${Fixtures.memberId}',
                      as: Fixtures.adminId))
                  .body)
          as Map<String, dynamic>;
      expect(fetched['is_admin'], 1);
      // Note: the API serializes ids as strings (raw DB values).
      expect(fetched['lions_club_id'], '2');

      // Conference flag is super-only; a flag-only request from admin is a 400.
      final confOnly = await api.put('/members/${Fixtures.memberId}',
          as: Fixtures.adminId, body: {'is_conference_member': 1});
      expect(confOnly.statusCode, 400);
    });

    test('super can set is_conference_member', () async {
      final res = await api.put('/members/${Fixtures.memberId}',
          as: Fixtures.superId, body: {'is_conference_member': 1});
      expect(res.statusCode, 200);

      final fetched = jsonDecode(
              (await api.get('/members/${Fixtures.memberId}',
                      as: Fixtures.superId))
                  .body)
          as Map<String, dynamic>;
      expect(fetched['is_conference_member'], 1);
    });

    test('update writes an audit row', () async {
      await api.put('/members/${Fixtures.memberId}',
          as: Fixtures.superId, body: {'name': 'Audited'});

      final audits =
          await auditRows(db, entityType: 'member', action: 'UPDATE');
      expect(audits, hasLength(1));
      expect(audits.first['entity_id'], '${Fixtures.memberId}');
      expect(audits.first['changed_by_member_id'], '${Fixtures.superId}');
    });
  });

  group('DELETE /members/<id>', () {
    test('rejects an invalid id', () async {
      expect((await api.delete('/members/abc', as: Fixtures.superId))
          .statusCode, 400);
    });

    test('deletes a member and writes an audit row', () async {
      final res =
          await api.delete('/members/${Fixtures.betaMemberId}', as: Fixtures.superId);
      expect(res.statusCode, 204);

      expect(
          (await api.get('/members/${Fixtures.betaMemberId}',
                  as: Fixtures.superId))
              .statusCode,
          404);

      final audits =
          await auditRows(db, entityType: 'member', action: 'DELETE');
      expect(audits, hasLength(1));
      expect(audits.first['entity_id'], '${Fixtures.betaMemberId}');
    });

    // Regression guard for gap B16: deletion currently requires NO identity.
    // When auth is added, update this to expect 401.
    test('currently allows unauthenticated deletion (gap B16)', () async {
      final res = await api.delete('/members/${Fixtures.betaMemberId}');
      expect(res.statusCode, 204);
    });
  });
}
