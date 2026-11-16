// Integration test harness for lions_api.
//
// Starts the real API (bin/lions_api.dart) as a subprocess pointed at the
// disposable MySQL test database (see docker-compose.test.yml locally, or the
// MySQL service container in CI), and provides HTTP + database helpers.
//
// Defaults match docker-compose.test.yml and .github/workflows/ci.yml:
//   DB on 127.0.0.1:3307, root / lions_test, database lions_test.
// Override via TEST_DB_HOST / TEST_DB_PORT / TEST_DB_USER / TEST_DB_PASS /
// TEST_DB_NAME / TEST_API_PORT when needed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mysql_client/mysql_client.dart';

String _env(String name, String fallback) =>
    Platform.environment[name] ?? fallback;

final String testDbHost = _env('TEST_DB_HOST', '127.0.0.1');
final int testDbPort = int.parse(_env('TEST_DB_PORT', '3307'));
final String testDbUser = _env('TEST_DB_USER', 'root');
final String testDbPass = _env('TEST_DB_PASS', 'lions_test');
final String testDbName = _env('TEST_DB_NAME', 'lions_test');
final int testApiPort = int.parse(_env('TEST_API_PORT', '8099'));

/// Fixture member ids created by [seedFixtures].
class Fixtures {
  static const int alphaClubId = 1;
  static const int betaClubId = 2;

  static const int superId = 1; // Sue Super, Alpha Club, is_super
  static const int adminId = 2; // Alan Admin, Alpha Club, is_admin
  static const int memberId = 3; // Mel Member, Alpha Club, no flags
  static const int conferenceId = 4; // Carl Conference, Alpha Club, conf flag
  static const int betaMemberId = 5; // Betty Beta, Beta Club, no flags

  /// A member id that does not exist in the fixtures.
  static const int unknownId = 9999;
}

/// Runs the API server as a subprocess for the duration of a test file.
class TestServer {
  TestServer._(this._process);

  final Process _process;
  final List<String> _logBuffer = [];

  Uri get baseUri => Uri.parse('http://127.0.0.1:$testApiPort');

  static Future<TestServer> start() async {
    final process = await Process.start(
      'dart',
      ['run', 'bin/lions_api.dart'],
      environment: {
        ...Platform.environment,
        'DB_HOST': testDbHost,
        'DB_PORT': '$testDbPort',
        'DB_USER': testDbUser,
        'DB_PASS': testDbPass,
        'DB_NAME': testDbName,
        'PORT': '$testApiPort',
        'ATTACHMENT_PRESIGN_MODE': 'mock',
      },
    );

    final server = TestServer._(process);

    // Drain output so the process never blocks on a full pipe; keep a tail
    // for diagnostics. Set TEST_SERVER_LOGS=1 to stream it live.
    final echo = Platform.environment['TEST_SERVER_LOGS'] == '1';
    void consume(Stream<List<int>> stream) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        server._logBuffer.add(line);
        if (server._logBuffer.length > 200) server._logBuffer.removeAt(0);
        if (echo) stderr.writeln('[api] $line');
      });
    }

    consume(process.stdout);
    consume(process.stderr);

    await server._waitUntilReady();
    return server;
  }

  Future<void> _waitUntilReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final res = await http
            .get(baseUri.replace(path: '/clubs'))
            .timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) return;
      } catch (_) {
        // Not up yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    stop();
    throw StateError(
        'API server did not become ready. Last output:\n${_logBuffer.join('\n')}');
  }

  String get recentLogs => _logBuffer.join('\n');

  void stop() {
    _process.kill();
  }
}

/// HTTP client that talks to the test server, optionally authenticated via
/// the x-member-id header (the API's current identity mechanism).
class TestApi {
  TestApi(this.server);

  final TestServer server;

  Map<String, String> _headers(int? as) => {
        'Content-Type': 'application/json',
        if (as != null) 'x-member-id': '$as',
      };

  Uri _uri(String path) {
    final parts = path.split('?');
    return server.baseUri.replace(
      path: parts.first,
      query: parts.length > 1 ? parts[1] : null,
    );
  }

  Future<http.Response> get(String path, {int? as}) =>
      http.get(_uri(path), headers: _headers(as));

  Future<http.Response> post(String path, {int? as, Object? body}) =>
      http.post(_uri(path),
          headers: _headers(as), body: body == null ? null : jsonEncode(body));

  Future<http.Response> put(String path, {int? as, Object? body}) =>
      http.put(_uri(path),
          headers: _headers(as), body: body == null ? null : jsonEncode(body));

  Future<http.Response> delete(String path, {int? as}) =>
      http.delete(_uri(path), headers: _headers(as));
}

/// Opens a direct database connection for seeding and verification.
Future<MySQLConnection> connectTestDb() async {
  final conn = await MySQLConnection.createConnection(
    host: testDbHost,
    port: testDbPort,
    userName: testDbUser,
    password: testDbPass,
    databaseName: testDbName,
  );
  await conn.connect();
  return conn;
}

const _allTables = [
  'audit_log',
  'conference_section_attachments',
  'conference_sections',
  'conference_ideas',
  'conference_content',
  'event_volunteers',
  'roles',
  'events',
  'event_types',
  'dinner_meal_options',
  'members',
  'lions_club',
];

/// Truncates every table so each test starts from a blank, deterministic DB.
Future<void> resetDatabase(MySQLConnection conn) async {
  await conn.execute('SET FOREIGN_KEY_CHECKS = 0');
  for (final table in _allTables) {
    await conn.execute('TRUNCATE TABLE `$table`');
  }
  await conn.execute('SET FOREIGN_KEY_CHECKS = 1');
}

/// Seeds the standard fixture clubs and members (see [Fixtures]).
Future<void> seedFixtures(MySQLConnection conn) async {
  await conn.execute(
      "INSERT INTO lions_club (id, name) VALUES (1, 'Alpha Club'), (2, 'Beta Club')");
  await conn.execute('''
    INSERT INTO members
      (id, name, email, phone_number, lions_club_id,
       is_admin, is_super, is_conference_member)
    VALUES
      (1, 'Sue Super', 'sue@test.com', '0400000001', 1, 0, 1, 0),
      (2, 'Alan Admin', 'alan@test.com', '0400000002', 1, 1, 0, 0),
      (3, 'Mel Member', 'mel@test.com', '0400000003', 1, 0, 0, 0),
      (4, 'Carl Conference', 'carl@test.com', '0400000004', 1, 0, 0, 1),
      (5, 'Betty Beta', 'betty@test.com', '0400000005', 2, 0, 0, 0)
  ''');
}

/// Returns audit_log rows for an entity, newest first.
Future<List<Map<String, String?>>> auditRows(
  MySQLConnection conn, {
  required String entityType,
  String? action,
}) async {
  final result = await conn.execute(
    'SELECT entity_type, entity_id, action, changed_by_member_id, new_value '
    'FROM audit_log WHERE entity_type = :type '
    '${action == null ? '' : 'AND action = :action '}'
    'ORDER BY id DESC',
    {'type': entityType, if (action != null) 'action': action},
  );
  return result.rows.map((r) => r.assoc()).toList();
}
