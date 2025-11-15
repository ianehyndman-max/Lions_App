import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path/path.dart' as p;

// ---------------- Diagnostics ----------------
void debugDbDiagnostics({
  required String dbHost,
  required int dbPort,
  required String dbUser,
  String? dbName,
  String? dbPassword,
}) {
  final scriptPath = Platform.script.toFilePath();
  final scriptDir = p.dirname(scriptPath);
  stderr.writeln('DEBUG: Starting DB diagnostics');
  stderr.writeln('DEBUG: current working directory: ${Directory.current.path}');
  stderr.writeln('DEBUG: script directory: $scriptDir');
  stderr.writeln('DEBUG: resolved DB config -> host=$dbHost port=$dbPort user=$dbUser db=${dbName ?? "<none>"}');
  stderr.writeln('DEBUG: DB password present=${(dbPassword ?? '').isNotEmpty} (hidden)');
  stderr.writeln('DEBUG: env DB_HOST=${Platform.environment['DB_HOST']}');
  stderr.writeln('DEBUG: env DB_PORT=${Platform.environment['DB_PORT']}');
  stderr.writeln('DEBUG: env DB_USER=${Platform.environment['DB_USER']}');
  stderr.writeln('DEBUG: env DB_NAME=${Platform.environment['DB_NAME']}');

  Socket.connect(dbHost, dbPort, timeout: const Duration(seconds: 3)).then((s) {
    stderr.writeln('DEBUG: TCP connect to $dbHost:$dbPort succeeded');
    s.destroy();
  }).catchError((e) {
    stderr.writeln('DEBUG: TCP connect to $dbHost:$dbPort FAILED -> $e');
  });
}

// ---------------- Config (env first) ----------------
String _envOr(String key, String fallback) => Platform.environment[key] ?? fallback;
final _dbHost = _envOr('DB_HOST', '127.0.0.1');
final _dbPort = int.tryParse(Platform.environment['DB_PORT'] ?? '') ?? 3306;
final _dbUser = _envOr('DB_USER', 'root');
final _dbPass = _envOr('DB_PASS', 'IanMySql1*.*');
final _dbName = _envOr('DB_NAME', 'lions');

final _smtpUser = Platform.environment['SMTP_USER'] ?? '';
final _smtpPass = Platform.environment['SMTP_PASS'] ?? '';

// ---------------- DB connect ----------------
Future<MySQLConnection> _connect() async {
  debugDbDiagnostics(dbHost: _dbHost, dbPort: _dbPort, dbUser: _dbUser, dbName: _dbName, dbPassword: _dbPass);

  final conn = await MySQLConnection.createConnection(
    host: _dbHost,
    port: _dbPort,
    userName: _dbUser,
    password: _dbPass,
    databaseName: _dbName,
  );
  await conn.connect();
  stderr.writeln('✅ Connected to MySQL at $_dbHost:$_dbPort ($_dbName)');
  return conn;
}

// ---------------- Email helper ----------------
Future<void> _sendEmail({
  required String to,
  required String subject,
  required String bodyHtml,
}) async {
  if (_smtpUser.isEmpty || _smtpPass.isEmpty) {
    throw StateError('SMTP credentials missing. Set SMTP_USER and SMTP_PASS in environment.');
  }

  final smtpServer = gmail(_smtpUser, _smtpPass);

  final message = Message()
    ..from = Address(_smtpUser, 'Lions Club')
    ..recipients.add(to)
    ..subject = subject
    ..html = bodyHtml;

  await send(message, smtpServer);
  stderr.writeln('✉️ Email queued/sent to $to');
}

// ---------------- Template loader ----------------
final Map<String, String> _templateCache = {};

String _candidatePath(String filename) {
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final candidates = <String>[
    p.join(scriptDir, 'templates', filename),
    p.join(scriptDir, '..', 'templates', filename),
    p.join(Directory.current.path, 'templates', filename),
    p.join(Directory.current.path, filename),
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return '';
}

Future<String> _renderTemplate(String filename, Map<String, String> vars) async {
  if (_templateCache.containsKey(filename)) {
    var out = _templateCache[filename]!;
    vars.forEach((k, v) => out = out.replaceAll('{{$k}}', v));
    return out;
  }

  final path = _candidatePath(filename);
  if (path.isEmpty) {
    stderr.writeln('WARNING: template not found: $filename (checked script dir & cwd)');
    final fallback = filename.toLowerCase().endsWith('.html') ? '<p></p>' : 'Notification';
    _templateCache[filename] = fallback;
    var out = fallback;
    vars.forEach((k, v) => out = out.replaceAll('{{$k}}', v));
    return out;
  }

  try {
    final template = await File(path).readAsString();
    _templateCache[filename] = template;
    var out = template;
    vars.forEach((k, v) => out = out.replaceAll('{{$k}}', v));
    return out;
  } catch (e) {
    stderr.writeln('ERROR: failed to read template $path -> $e');
    final fallback = filename.toLowerCase().endsWith('.html') ? '<p></p>' : 'Notification';
    _templateCache[filename] = fallback;
    var out = fallback;
    vars.forEach((k, v) => out = out.replaceAll('{{$k}}', v));
    return out;
  }
}

// ---------------- Handlers ----------------
Future<Response> _members(Request req) async {
  stderr.writeln('🔵 GET /members');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final clubId = req.url.queryParameters['club_id'];
    final sql = '''
      SELECT m.id, m.name, m.email, m.phone_number, m.lions_club_id, m.is_admin, lc.name AS club_name
      FROM members m
      LEFT JOIN lions_club lc ON lc.id = m.lions_club_id
      ${clubId == null ? '' : 'WHERE m.lions_club_id = :clubId'}
      ORDER BY LOWER(m.name), m.id
    ''';
    final params = clubId == null ? null : {'clubId': clubId};
    final result = await conn.execute(sql, params);
    final list = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      final a = row.assoc();
      list.add({
        'id': a['id'],
        'name': a['name'],
        'email': a['email'],
        'phone_number': a['phone_number'],
        'lions_club_id': a['lions_club_id'],
        'is_admin': a['is_admin'],
        'club_name': a['club_name'],
      });
    }
    return Response.ok(jsonEncode(list), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _members: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _events(Request req) async {
  stderr.writeln('🔵 GET /events');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final clubId = req.url.queryParameters['club_id'];
    final sql = '''
      SELECT e.id, et.name AS event_type, lc.name AS club_name, e.event_date, e.location
      FROM events e
      LEFT JOIN event_types et ON e.event_type_id = et.id
      LEFT JOIN lions_club lc ON e.lions_club_id = lc.id
      ${clubId == null ? '' : 'WHERE e.lions_club_id = :clubId'}
      ORDER BY e.event_date
    ''';
    final params = clubId == null ? null : {'clubId': clubId};
    final result = await conn.execute(sql, params);
    final list = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      final a = row.assoc();
      list.add({
        'id': a['id'],
        'event_type': a['event_type'],
        'club_name': a['club_name'],
        'date': a['event_date']?.toString() ?? '',
        'location': a['location'],
      });
    }
    return Response.ok(jsonEncode(list), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _events: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _eventTypes(Request req) async {
  stderr.writeln('🔵 GET /event_types');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final result = await conn.execute('SELECT id, name FROM event_types ORDER BY name');
    final list = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      final a = row.assoc();
      list.add({'id': a['id'], 'name': a['name']});
    }
    return Response.ok(jsonEncode(list), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _eventTypes: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _createEvent(Request req) async {
  stderr.writeln('🔵 POST /events');
  MySQLConnection? conn;
  try {
    final raw = await req.readAsString();
    if (raw.isEmpty) return Response(400, body: 'Missing body');
    final bodyJson = jsonDecode(raw) as Map<String, dynamic>;

    final eventTypeId = bodyJson['event_type_id'];
    final clubId = bodyJson['lions_club_id'];
    final eventDate = bodyJson['event_date']?.toString() ?? '';
    final location = bodyJson['location']?.toString() ?? '';
    final notes = bodyJson['notes']?.toString() ?? '';
    final roles = (bodyJson['roles'] as List<dynamic>?)?.cast<Map<String, dynamic>>();

    if (eventTypeId == null || clubId == null || eventDate.isEmpty) {
      return Response(400, body: 'Missing required fields: event_type_id, lions_club_id, event_date');
    }

    conn = await _connect();

    await conn.execute('''
      INSERT INTO events (event_type_id, lions_club_id, event_date, location, notes)
      VALUES (:et, :club, :date, :loc, :notes)
    ''', {'et': eventTypeId.toString(), 'club': clubId.toString(), 'date': eventDate, 'loc': location, 'notes': notes});

    // get last insert id
    final idRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
    final newId = idRes.rows.first.assoc()['id'];

    // insert roles if provided
    if (roles != null && roles.isNotEmpty) {
      for (final r in roles) {
        final roleName = r['role_name']?.toString() ?? '';
        final timeIn = r['time_in']?.toString() ?? '';
        final timeOut = r['time_out']?.toString() ?? '';
        await conn.execute('''
          INSERT INTO roles (event_id, role_name, time_in, time_out)
          VALUES (:eid, :name, :tin, :tout)
        ''', {'eid': newId.toString(), 'name': roleName, 'tin': timeIn, 'tout': timeOut});
      }
    }

    final resp = {'event_id': newId.toString()};
    return Response.ok(jsonEncode(resp), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _createEvent: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _eventDetails(Request req, String eventId) async {
  stderr.writeln('🔵 GET /events/$eventId');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final eventResult = await conn.execute('''
      SELECT e.id, et.id AS event_type_id, et.name AS event_type, lc.id AS club_id, lc.name AS club_name,
             e.event_date AS date, e.location, e.notes
      FROM events e
      LEFT JOIN event_types et ON e.event_type_id = et.id
      LEFT JOIN lions_club lc ON lc.id = e.lions_club_id
      WHERE e.id = :eventId
    ''', {'eventId': eventId});
    if (eventResult.rows.isEmpty) return Response.notFound('Event not found');

    final e = eventResult.rows.first.assoc();
    final isOther = (e['event_type'] ?? '').toString() == 'Other';

    final rolesResult = await conn.execute(isOther
      ? '''
      SELECT r.id AS role_id, r.role_name, r.time_in, r.time_out, m.id AS member_id, m.name AS volunteer_name
      FROM roles r
      LEFT JOIN event_volunteers v ON v.role_id = r.id AND v.event_id = :eventId
      LEFT JOIN members m ON m.id = v.member_id
      WHERE r.event_id = :eventId
      ORDER BY r.time_in, r.role_name
    '''
      : '''
      SELECT r.id AS role_id, r.role_name, r.time_in, r.time_out, m.id AS member_id, m.name AS volunteer_name
      FROM roles r
      LEFT JOIN event_volunteers v ON v.role_id = r.id AND v.event_id = :eventId
      LEFT JOIN members m ON m.id = v.member_id
      WHERE r.event_id = :eventId
      ORDER BY r.time_in, r.role_name
    ''', {'eventId': eventId});

       stderr.writeln('DEBUG: /events/$eventId rolesResult.rows.length=${rolesResult.rows.length} (isOther=$isOther)');

    final roles = rolesResult.rows.map((row) {
      final a = row.assoc();
      return {
        'role_id': a['role_id'],
        'role_name': a['role_name'],
        'time_in': a['time_in']?.toString() ?? '',
        'time_out': a['time_out']?.toString() ?? '',
        'member_id': a['member_id'],
        'volunteer_name': a['volunteer_name'],
      };
    }).toList();

    final resp = {
      'event': {
        'id': e['id'],
        'event_type_id': e['event_type_id'],
        'event_type': e['event_type'],
        'club_id': e['club_id'],
        'club_name': e['club_name'],
        'date': e['date']?.toString() ?? '',
        'location': e['location'],
        'notes': e['notes'],
      },
      'roles': roles,
    };
    return Response.ok(jsonEncode(resp), headers: {'Content-Type': 'application/json'});
  } catch (err, st) {
    stderr.writeln('❌ Error in _eventDetails: $err\n$st');
    return Response.internalServerError(body: 'Error: $err');
  } finally {
    await conn?.close();
  }
}

Future<Response> _clubs(Request req) async {
  stderr.writeln('🔵 GET /clubs');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final result = await conn.execute('SELECT id, name FROM lions_club ORDER BY name');
    final list = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      final a = row.assoc();
      list.add({
        'id': a['id'],
        'name': a['name'],
      });
    }
    return Response.ok(jsonEncode(list), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _clubs: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ---------------- Notify (email) ----------------
Future<Response> _notifyEventMembers(Request req, String eventId) async {
  stderr.writeln('📧 POST /events/$eventId/notify');
  Map<String, dynamic> bodyJson = {};
  try {
    final raw = await req.readAsString();
    if (raw.isNotEmpty) bodyJson = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {}
  final qp = req.url.queryParameters;

  final onlyAssigned   = (bodyJson['only_assigned'] == true)   || (qp['only_assigned'] == 'true');
  final resendUnfilled = (bodyJson['resend_unfilled'] == true) || (qp['resend_unfilled'] == 'true');
  final dryRun         = (bodyJson['dry_run'] == true)         || (qp['dry_run'] == 'true');

  final overrideSubject  = (bodyJson['subject'] as String?)?.trim();
  final overrideBodyHtml = (bodyJson['body_html'] as String?)?.trim();
  final overrideBodyText = (bodyJson['body'] as String?)?.trim();

  MySQLConnection? conn;
  try {
    conn = await _connect();

    final eventResult = await conn.execute('''
      SELECT e.id, et.name AS event_type, lc.name AS club_name, e.event_date, e.location, e.notes, e.lions_club_id
      FROM events e
      LEFT JOIN event_types et ON e.event_type_id = et.id
      LEFT JOIN lions_club lc ON lc.id = e.lions_club_id
      WHERE e.id = :eventId
    ''', {'eventId': eventId});
    if (eventResult.rows.isEmpty) return Response.notFound('Event not found');

    final event = eventResult.rows.first.assoc();
    final clubId = event['lions_club_id'];
    final isOther = (event['event_type'] ?? '').toString() == 'Other';

    // roles listing
    final rolesQuery = isOther
        ? '''
          SELECT r.role_name, r.time_in, r.time_out
          FROM roles r
          WHERE r.event_id = :eventId
          ORDER BY r.time_in, r.role_name
        '''
        : '''
          SELECT r.role_name, r.time_in, r.time_out
          FROM roles r
          JOIN events e ON e.id = :eventId
          WHERE (r.role_type_id IS NULL OR r.event_type_id = e.event_type_id)
            AND (r.event_id IS NULL)
          ORDER BY r.time_in, r.role_name
        ''';
    final rolesResult = await conn.execute(rolesQuery, {'eventId': eventId});

    if (!dryRun && isOther && rolesResult.rows.isEmpty) {
      return Response(400, body: 'No roles defined for this event yet.');
    }

    final rolesHtml = StringBuffer()..write('<h3>Volunteer Roles:</h3><ul>');
    for (final row in rolesResult.rows) {
      final r = row.assoc();
      rolesHtml.write('<li>${r['role_name']}: ${r['time_in']} - ${r['time_out']}</li>');
    }
    rolesHtml.write('</ul>');

    final notesHtml = ((event['notes']?.toString().isNotEmpty) ?? false)
        ? '<p><b>Notes:</b> ${htmlEscape.convert(event['notes']?.toString() ?? '')}</p>'
        : '';

    // Build template variables
    final vars = <String, String>{
      'event_name': '${event['event_type'] ?? ''} · ${event['club_name'] ?? ''}',
      'date': event['event_date']?.toString() ?? '',
      'location': event['location']?.toString() ?? '',
      'club_name': event['club_name']?.toString() ?? '',
      'roles_html': rolesHtml.toString(),
      'notes_html': notesHtml,
    };

    // Choose templates
    final subjectTemplateFile = resendUnfilled ? 'resend_unfilled_subject.txt' : 'new_event_subject.txt';
    final bodyTemplateFile = resendUnfilled ? 'resend_unfilled_body.html' : 'new_event_body.html';

    final subject = overrideSubject ?? await _renderTemplate(subjectTemplateFile, vars);
    final bodyHtml = overrideBodyHtml ?? await _renderTemplate(bodyTemplateFile, vars);

    // Determine recipients
    List<String> recipients = [];
    if (onlyAssigned) {
      final rRes = await conn.execute('''
        SELECT DISTINCT m.email
        FROM event_volunteers v
        JOIN members m ON m.id = v.member_id
        WHERE v.event_id = :eventId AND m.email IS NOT NULL AND m.email <> ''
      ''', {'eventId': eventId});
      for (final row in rRes.rows) {
        final e = row.assoc()['email'];
        if (e != null && e.toString().trim().isNotEmpty) recipients.add(e.toString());
      }
    } else {
      // club members
      final rRes = await conn.execute('''
        SELECT DISTINCT m.email
        FROM members m
        WHERE m.lions_club_id = :clubId AND m.email IS NOT NULL AND m.email <> ''
      ''', {'clubId': clubId});
      for (final row in rRes.rows) {
        final e = row.assoc()['email'];
        if (e != null && e.toString().trim().isNotEmpty) recipients.add(e.toString());
      }
    }

    final recipientsCsv = recipients.join(', ');

    if (dryRun) {
      final resp = {
        'subject': subject,
        'body_html': bodyHtml,
        'recipients': recipientsCsv,
      };
      return Response.ok(jsonEncode(resp), headers: {'Content-Type': 'application/json'});
    }

    // Send emails (sequential to simplify; switch to concurrency if needed)
    final failures = <String>[];
    for (final to in recipients) {
      try {
        await _sendEmail(to: to, subject: subject, bodyHtml: bodyHtml);
      } catch (e) {
        stderr.writeln('ERROR: send to $to -> $e');
        failures.add('$to: $e');
      }
    }

    if (failures.isEmpty) {
      return Response.ok('Emails sent to ${recipients.length} recipients');
    } else {
      final msg = 'Some emails failed: ${failures.join('; ')}';
      stderr.writeln('❌ $msg');
      return Response(500, body: msg);
    }
  } catch (e, st) {
    stderr.writeln('❌ Error in _notifyEventMembers: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ---------------- Router & Server ----------------
Handler _router() {
  final router = Router();
  router.get('/members', _members);
  router.get('/clubs', _clubs);
  router.get('/event_types', _eventTypes);
  router.post('/events', _createEvent);
  router.post('/members', _createMember);
  router.put('/members/<id>', (Request req, String id) => _updateMember(req, id));
  router.delete('/members/<id>', (Request req, String id) => _deleteMember(req, id));
  router.get('/events', _events);
  router.get('/events/<id>', (Request req, String id) => _eventDetails(req, id));
  router.post('/events/<id>/notify', (Request req, String id) => _notifyEventMembers(req, id));

  // Add other routes (create/update events, roles, volunteers) as required...
  return router;
}

// Minimal wrappers for member create/update/delete to keep file self-contained
Future<Response> _createMember(Request req) async {
  // reuse the earlier implementation from _createMember section
  // For brevity in this full example, delegate to existing handler above
  return await _createMember(req); // if duplicate, adjust accordingly in your file
}
Future<Response> _updateMember(Request req, String id) async {
  // placeholder: your existing implementation should be used
  return Response(501, body: 'Not implemented in this snippet');
}
Future<Response> _deleteMember(Request req, String id) async {
  return Response(501, body: 'Not implemented in this snippet');
}

Future<void> main(List<String> args) async {
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(_router());

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stderr.writeln('Server listening on port ${server.port}');
}