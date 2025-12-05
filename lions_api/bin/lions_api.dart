import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart' as shelf_cors;
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
final _dbHost = _envOr('DB_HOST', 'lions-club-db.c12ge624w2tu.ap-southeast-2.rds.amazonaws.com');
final _dbPort = int.tryParse(Platform.environment['DB_PORT'] ?? '') ?? 3306;
final _dbUser = _envOr('DB_USER', 'admin');
final _dbPass = _envOr('DB_PASS', 'ML4231LionsApp!');
final _dbName = _envOr('DB_NAME', 'lions');


final _smtpUser = _envOr('SMTP_USER', '');
final _smtpPass = _envOr('SMTP_PASS', '');

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

Future<void> _logAudit(
  MySQLConnection conn, {
  required String entityType,
  required int entityId,
  required String action,
  int? changedByMemberId,
  Map<String, dynamic>? oldValue,
  Map<String, dynamic>? newValue,
}) async {
  try {
    final sql = '''
      INSERT INTO audit_log (entity_type, entity_id, action, changed_by_member_id, old_value, new_value)
      VALUES (:entityType, :entityId, :action, :changedBy, :oldVal, :newVal)
    ''';
    
    await conn.execute(sql, {
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'changedBy': changedByMemberId,
      'oldVal': oldValue != null ? jsonEncode(oldValue) : null,
      'newVal': newValue != null ? jsonEncode(newValue) : null,
    });
    
    stderr.writeln('✅ Audit logged: $action $entityType #$entityId by member #$changedByMemberId');
  } catch (e) {
    stderr.writeln('⚠️ Audit log failed: $e');
  }
}


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
      SELECT m.id, m.name, m.email, m.phone_number, m.lions_club_id, m.is_admin, m.is_super, lc.name AS club_name
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
      // Ensure is_admin and is_super are integers
      final isAdminVal = a['is_admin'];
      final isSuperVal = a['is_super'];
      final isAdminInt = (isAdminVal == 1 || isAdminVal == true || isAdminVal == '1') ? 1 : 0;
      final isSuperInt = (isSuperVal == 1 || isSuperVal == true || isSuperVal == '1') ? 1 : 0;
      
      list.add({
        'id': a['id'],
        'name': a['name'],
        'email': a['email'],
        'phone_number': a['phone_number'],
        'lions_club_id': a['lions_club_id'],
        'is_admin': isAdminInt,
        'is_super': isSuperInt,
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

// ---------------- Auth Helpers ----------------
/// Extract member_id from request headers (placeholder - add real auth later)
int? _getMemberIdFromRequest(Request req) {
  // For now, accept member_id from query param or header for testing
  // TODO: Replace with JWT/session token validation
  final fromQuery = req.url.queryParameters['_auth_member_id'];
  final fromHeader = req.headers['x-member-id'];
  final idStr = fromQuery ?? fromHeader;
  return idStr == null ? null : int.tryParse(idStr);
}

/// Check if member is super user
Future<bool> _isSuper(MySQLConnection conn, int memberId) async {
  final r = await conn.execute('SELECT is_super FROM members WHERE id=:id', {'id': memberId.toString()});
  if (r.rows.isEmpty) return false;
  final val = r.rows.first.assoc()['is_super'];
  if (val == null) return false;
  return val == 1 || val == true || val == '1' || (val is List && val.isNotEmpty && val[0] == 1);
}

/// Check if member is admin
Future<bool> _isAdmin(MySQLConnection conn, int memberId) async {
  final r = await conn.execute('SELECT is_admin FROM members WHERE id=:id', {'id': memberId.toString()});
  if (r.rows.isEmpty) return false;
  final val = r.rows.first.assoc()['is_admin'];
  if (val == null) return false;
  return val == 1 || val == true || val == '1' || (val is List && val.isNotEmpty && val[0] == 1);
}

/// Get member's club_id
Future<int?> _getMemberClubId(MySQLConnection conn, int memberId) async {
  final r = await conn.execute('SELECT lions_club_id FROM members WHERE id=:id', {'id': memberId.toString()});
  if (r.rows.isEmpty) return null;
  final val = r.rows.first.assoc()['lions_club_id'];
  return val == null ? null : int.tryParse(val.toString());
}

Future<Response> _events(Request req) async {
  stderr.writeln('🔵 GET /events');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    
    // Get query parameters for filtering
    final typeIdStr = req.url.queryParameters['type_id'];
    final dateRange = req.url.queryParameters['date_range']; // 'today', 'week', 'month'
    
    // Authorization: filter by club unless super user
    final authMemberId = _getMemberIdFromRequest(req);
    final isSuper = authMemberId != null ? await _isSuper(conn, authMemberId) : false;
    final memberClubId = authMemberId != null && !isSuper ? await _getMemberClubId(conn, authMemberId) : null;
    
    stderr.writeln('DEBUG: authMemberId=$authMemberId isSuper=$isSuper memberClubId=$memberClubId typeId=$typeIdStr dateRange=$dateRange');
    
    // Build SQL with filters
    var sql = '''
      SELECT e.id, e.event_type_id, et.name AS event_type, lc.name AS club_name, e.event_date, e.location
      FROM events e
      LEFT JOIN event_types et ON e.event_type_id = et.id
      LEFT JOIN lions_club lc ON e.lions_club_id = lc.id
      WHERE e.event_date >= CURDATE()
    ''';
    
    final params = <String, String>{};
    
    // Add club filter for non-super users
    if (memberClubId != null) {
      sql += ' AND e.lions_club_id = :clubId';
      params['clubId'] = memberClubId.toString();
    }
    
    // Add event type filter
    if (typeIdStr != null && typeIdStr.isNotEmpty) {
      sql += ' AND e.event_type_id = :typeId';
      params['typeId'] = typeIdStr;
    }
    
    // Add date range filter
    if (dateRange != null && dateRange.isNotEmpty) {
      final now = DateTime.now();
      switch (dateRange) {
        case 'today':
          final today = DateTime(now.year, now.month, now.day);
          sql += ' AND e.event_date = :today';
          params['today'] = today.toIso8601String().split('T')[0];
          break;
        case 'week':
          final today = DateTime(now.year, now.month, now.day);
          final weekFromNow = today.add(const Duration(days: 7));
          sql += ' AND e.event_date >= :startDate AND e.event_date < :endDate';
          params['startDate'] = today.toIso8601String().split('T')[0];
          params['endDate'] = weekFromNow.toIso8601String().split('T')[0];
          break;
        case 'month':
          final today = DateTime(now.year, now.month, now.day);
          final monthFromNow = today.add(const Duration(days: 30));
          sql += ' AND e.event_date >= :startDate AND e.event_date < :endDate';
          params['startDate'] = today.toIso8601String().split('T')[0];
          params['endDate'] = monthFromNow.toIso8601String().split('T')[0];
          break;
      }
    }
    
    sql += ' ORDER BY e.event_date';
    
    stderr.writeln('DEBUG: SQL=$sql params=$params');
    
    final result = await conn.execute(sql, params.isNotEmpty ? params : null);
    final list = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      final a = row.assoc();
      list.add({
        'id': a['id'],
        'event_type_id': a['event_type_id'],
        'event_type': a['event_type'],
        'club_name': a['club_name'],
        'date': a['event_date']?.toString() ?? '',
        'location': a['location'],
      });
    }
    stderr.writeln('DEBUG: Returning ${list.length} events (filtered by type=$typeIdStr range=$dateRange)');
    return Response.ok(jsonEncode(list), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _events: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ...existing code after _events...

Future<Response> _eventsCalendar(Request req) async {
  stderr.writeln('🔵 GET /events/calendar');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    // Authorization: filter by club unless super user
    final authMemberId = _getMemberIdFromRequest(req);
    final isSuper = authMemberId != null ? await _isSuper(conn, authMemberId) : false;
    final memberClubId = authMemberId != null && !isSuper ? await _getMemberClubId(conn, authMemberId) : null;
    
    stderr.writeln('DEBUG: calendar authMemberId=$authMemberId isSuper=$isSuper memberClubId=$memberClubId');
    final sql = '''
      SELECT e.id, et.name AS event_type, lc.name AS club_name, e.event_date, e.location
      FROM events e
      LEFT JOIN event_types et ON e.event_type_id = et.id
      LEFT JOIN lions_club lc ON e.lions_club_id = lc.id
      ${memberClubId != null ? 'WHERE e.lions_club_id = :clubId' : ''}
      ORDER BY e.event_date
    ''';
    final result = await conn.execute(sql, memberClubId != null ? {'clubId': memberClubId.toString()} : null);
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
    stderr.writeln('❌ Error in _eventsCalendar: $e\n$st');
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
  stderr.writeln('🔵 POST /events - VERSION 2');
  MySQLConnection? conn;
  try {
    // Read body ONCE and store it
    String raw;
    try {
      raw = await req.readAsString();
      stderr.writeln('🔵 Body read successfully: ${raw.length} bytes');
    } catch (e) {
      stderr.writeln('❌ Failed to read body: $e');
      return Response(400, body: 'Failed to read request body');
    }
    
    if (raw.isEmpty) {
      stderr.writeln('❌ Empty body');
      return Response(400, body: 'Missing body');
    }

    // Parse JSON
    Map<String, dynamic> bodyJson;
    try {
      bodyJson = jsonDecode(raw) as Map<String, dynamic>;
      stderr.writeln('🔵 JSON parsed. Keys: ${bodyJson.keys.join(", ")}');
    } catch (e) {
      stderr.writeln('❌ JSON parse failed: $e');
      stderr.writeln('Raw body was: $raw');
      return Response(400, body: 'Invalid JSON: $e');
    }

    final eventTypeId = bodyJson['event_type_id'];
    final clubId = bodyJson['lions_club_id'];
    final eventDate = bodyJson['event_date']?.toString() ?? '';
    final location = bodyJson['location']?.toString() ?? '';
    final notes = bodyJson['notes']?.toString() ?? '';
    final customRoles = (bodyJson['roles'] as List<dynamic>?)?.cast<Map<String, dynamic>>();

    stderr.writeln('🔵 Parsed values:');
    stderr.writeln('  - eventTypeId: $eventTypeId');
    stderr.writeln('  - clubId: $clubId');
    stderr.writeln('  - eventDate: $eventDate');
    stderr.writeln('  - location: $location');
    stderr.writeln('  - notes: $notes');
    stderr.writeln('  - roles count: ${customRoles?.length ?? 0}');

    if (eventTypeId == null || clubId == null || eventDate.isEmpty) {
      return Response(400, body: 'Missing required fields: event_type_id, lions_club_id, event_date');
    }

    conn = await _connect();

    // Insert event
    await conn.execute('''
      INSERT INTO events (event_type_id, lions_club_id, event_date, location, notes)
      VALUES (:et, :club, :date, :loc, :notes)
    ''', {
      'et': eventTypeId.toString(),
      'club': clubId.toString(),
      'date': eventDate,
      'loc': location,
      'notes': notes
    });

    final idRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
    final newId = idRes.rows.first.assoc()['id'];
    final newEventId = int.parse(newId!);

    stderr.writeln('✅ Event created with ID: $newEventId');

    // Insert roles
    if (customRoles != null && customRoles.isNotEmpty) {
      stderr.writeln('🔵 Inserting ${customRoles.length} roles...');
      for (final r in customRoles) {
        final roleName = r['role_name']?.toString() ?? '';
        final timeIn = r['time_in']?.toString() ?? '';
        final timeOut = r['time_out']?.toString() ?? '';
        
        if (roleName.isEmpty) continue;

        await conn.execute('''
          INSERT INTO roles (event_id, event_type_id, role_name, time_in, time_out)
          VALUES (:eid, :etid, :name, :tin, :tout)
        ''', {
          'eid': newEventId.toString(),
          'etid': eventTypeId.toString(),
          'name': roleName,
          'tin': timeIn,
          'tout': timeOut
        });
      }
      stderr.writeln('✅ Inserted ${customRoles.length} roles');
    }

    // Log audit
    final authMemberId = _getMemberIdFromRequest(req);
    await _logAudit(
      conn,
      entityType: 'event',
      entityId: newEventId,
      action: 'CREATE',
      changedByMemberId: authMemberId,
      newValue: {
        'event_type_id': eventTypeId.toString(),
        'lions_club_id': clubId.toString(),
        'event_date': eventDate,
        'location': location,
        'notes': notes,
      },
    );

    return Response.ok(
      jsonEncode({'event_id': newId.toString()}),
      headers: {'Content-Type': 'application/json'}
    );
  } catch (e, st) {
    stderr.writeln('❌ ERROR in _createEvent:');
    stderr.writeln('  Exception: $e');
    stderr.writeln('  Stack trace: $st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _deleteEvent(Request req, String eventId) async {
  stderr.writeln('🔵 DELETE /events/$eventId');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final eid = int.tryParse(eventId.toString()) ?? 0;
    if (eid == 0) return Response(400, body: 'Invalid event id');

    // Fetch old value BEFORE delete for audit log
    final oldRow = await conn.execute('SELECT * FROM events WHERE id = :eid', {'eid': eid});
    final oldValue = oldRow.rows.isNotEmpty ? oldRow.rows.first.assoc() : null;

    await conn.execute('START TRANSACTION');
    try {
      await conn.execute('DELETE FROM event_volunteers WHERE event_id = :eid', {'eid': eid});
      await conn.execute('DELETE FROM roles WHERE event_id = :eid', {'eid': eid});
      await conn.execute('DELETE FROM events WHERE id = :eid', {'eid': eid});
      await conn.execute('COMMIT');
    } catch (e) {
      try {
        await conn.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }

    // Log audit
    final authMemberId = _getMemberIdFromRequest(req);
    await _logAudit(
      conn,
      entityType: 'event',
      entityId: eid,
      action: 'DELETE',
      changedByMemberId: authMemberId,
      oldValue: oldValue,
    );

    stderr.writeln('✅ Deleted event $eid and related rows');
    return Response(204);
  } catch (e, st) {
    stderr.writeln('❌ Error in _deleteEvent: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// Update event details (location, notes, date)
Future<Response> _updateEvent(Request req, String eventId) async {
  stderr.writeln('🔵 PUT /events/$eventId');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) return Response(401, body: 'Unauthorized');

    conn = await _connect();
    
    final isAdmin = await _isAdmin(conn, authMemberId);
    final isSuper = await _isSuper(conn, authMemberId);
    if (!isAdmin && !isSuper) {
      return Response(403, body: 'Forbidden: admin access required');
    }

    // Get old values for audit
    final oldRow = await conn.execute('SELECT * FROM events WHERE id = :id', {'id': eventId});
    final oldValue = oldRow.rows.isNotEmpty ? oldRow.rows.first.assoc() : null;

    final raw = await req.readAsString();
    if (raw.isEmpty) return Response(400, body: 'Missing body');
    final bodyJson = jsonDecode(raw) as Map<String, dynamic>;

    final eventTypeId = bodyJson['event_type_id'];
    final clubId = bodyJson['lions_club_id'];
    final eventDate = bodyJson['event_date']?.toString() ?? '';
    final location = bodyJson['location']?.toString() ?? '';
    final notes = bodyJson['notes']?.toString() ?? '';

    if (eventTypeId == null || clubId == null || eventDate.isEmpty) {
      return Response(400, body: 'Missing required fields');
    }

    await conn.execute('''
      UPDATE events
      SET event_type_id = :eventTypeId,
          lions_club_id = :clubId,
          event_date = :eventDate,
          location = :location,
          notes = :notes
      WHERE id = :id
    ''', {
      'id': eventId,
      'eventTypeId': eventTypeId.toString(),
      'clubId': clubId.toString(),
      'eventDate': eventDate,
      'location': location,
      'notes': notes,
    });

    // Log audit
    await _logAudit(
      conn,
      entityType: 'event',
      entityId: int.parse(eventId),
      action: 'UPDATE',
      changedByMemberId: authMemberId,
      oldValue: oldValue,
      newValue: {
        'event_type_id': eventTypeId.toString(),
        'lions_club_id': clubId.toString(),
        'event_date': eventDate,
        'location': location,
        'notes': notes,
      },
    );

    stderr.writeln('✅ Event $eventId updated');
    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _updateEvent: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ...existing code...

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
    final eid = int.tryParse(eventId.toString()) ?? 0;

    stderr.writeln('DEBUG: fetching roles for event $eid');

    // **UPDATED: Only fetch event-specific roles (templates already copied)**
    final rolesSql = '''
      SELECT r.id AS role_id, r.role_name, r.time_in, r.time_out, v.member_id, m.name AS volunteer_name
      FROM roles r
      LEFT JOIN event_volunteers v ON v.role_id = r.id AND v.event_id = :eventId
      LEFT JOIN members m ON m.id = v.member_id
      WHERE r.event_id = :eventId
      ORDER BY r.time_in, r.role_name
    ''';

    final rolesResult = await conn.execute(rolesSql, {'eventId': eid});
    stderr.writeln('DEBUG: /events/$eventId found ${rolesResult.rows.length} roles');

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

// Get role templates for an event type
Future<Response> _getRoleTemplates(Request req, String eventTypeId) async {
  stderr.writeln('🔵 GET /event_types/$eventTypeId/role_templates');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    
    final result = await conn.execute('''
      SELECT id, role_name, time_in, time_out
      FROM roles
      WHERE event_type_id = :eventTypeId AND event_id IS NULL
      ORDER BY time_in, role_name
    ''', {'eventTypeId': eventTypeId});

    final templates = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      final r = row.assoc();
      templates.add({
        'id': r['id'],
        'role_name': r['role_name'],
        'time_in': r['time_in']?.toString() ?? '',
        'time_out': r['time_out']?.toString() ?? '',
      });
    }

    return Response.ok(jsonEncode(templates), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _getRoleTemplates: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// Create or update a role template
Future<Response> _saveRoleTemplate(Request req, String eventTypeId) async {
  stderr.writeln('🔵 POST /event_types/$eventTypeId/role_templates');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) {
      return Response(401, body: 'Unauthorized');
    }

    conn = await _connect();
    
    // Only admins/super can manage templates
    final isAdmin = await _isAdmin(conn, authMemberId);
    final isSuper = await _isSuper(conn, authMemberId);
    if (!isAdmin && !isSuper) {
      return Response(403, body: 'Forbidden: admin access required');
    }

    final raw = await req.readAsString();
    if (raw.isEmpty) return Response(400, body: 'Missing body');
    final bodyJson = jsonDecode(raw) as Map<String, dynamic>;

    final templateId = bodyJson['id']; // null for new, int for update
    final roleName = bodyJson['role_name']?.toString() ?? '';
    final timeIn = bodyJson['time_in']?.toString() ?? '';
    final timeOut = bodyJson['time_out']?.toString() ?? '';

    if (roleName.isEmpty) {
      return Response(400, body: 'Role name required');
    }

    if (templateId == null) {
      // Create new template
      await conn.execute('''
        INSERT INTO roles (event_type_id, role_name, time_in, time_out)
        VALUES (:eventTypeId, :roleName, :timeIn, :timeOut)
      ''', {
        'eventTypeId': eventTypeId,
        'roleName': roleName,
        'timeIn': timeIn,
        'timeOut': timeOut,
      });

      final idRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
      final newId = idRes.rows.first.assoc()['id'];

      // Log audit
      await _logAudit(
        conn,
        entityType: 'role_template',
        entityId: int.parse(newId!),
        action: 'CREATE',
        changedByMemberId: authMemberId,
        newValue: {'event_type_id': eventTypeId, 'role_name': roleName, 'time_in': timeIn, 'time_out': timeOut},
      );

      return Response.ok(jsonEncode({'id': newId}), headers: {'Content-Type': 'application/json'});
    } else {
      // Update existing template
      final oldRow = await conn.execute('SELECT * FROM roles WHERE id = :id', {'id': templateId});
      final oldValue = oldRow.rows.isNotEmpty ? oldRow.rows.first.assoc() : null;

      await conn.execute('''
        UPDATE roles
        SET role_name = :roleName, time_in = :timeIn, time_out = :timeOut
        WHERE id = :id AND event_id IS NULL
      ''', {
        'id': templateId.toString(),
        'roleName': roleName,
        'timeIn': timeIn,
        'timeOut': timeOut,
      });

      // Log audit
      await _logAudit(
        conn,
        entityType: 'role_template',
        entityId: int.parse(templateId.toString()),
        action: 'UPDATE',
        changedByMemberId: authMemberId,
        oldValue: oldValue,
        newValue: {'role_name': roleName, 'time_in': timeIn, 'time_out': timeOut},
      );

      return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
    }
  } catch (e, st) {
    stderr.writeln('❌ Error in _saveRoleTemplate: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// Delete a role template
Future<Response> _deleteRoleTemplate(Request req, String templateId) async {
  stderr.writeln('🔵 DELETE /role_templates/$templateId');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) {
      return Response(401, body: 'Unauthorized');
    }

    conn = await _connect();
    
    final isAdmin = await _isAdmin(conn, authMemberId);
    final isSuper = await _isSuper(conn, authMemberId);
    if (!isAdmin && !isSuper) {
      return Response(403, body: 'Forbidden: admin access required');
    }

    // Fetch before delete for audit
    final oldRow = await conn.execute('SELECT * FROM roles WHERE id = :id AND event_id IS NULL', {'id': templateId});
    final oldValue = oldRow.rows.isNotEmpty ? oldRow.rows.first.assoc() : null;

    await conn.execute('DELETE FROM roles WHERE id = :id AND event_id IS NULL', {'id': templateId});

    // Log audit
    await _logAudit(
      conn,
      entityType: 'role_template',
      entityId: int.parse(templateId),
      action: 'DELETE',
      changedByMemberId: authMemberId,
      oldValue: oldValue,
    );

    return Response(204);
  } catch (e, st) {
    stderr.writeln('❌ Error in _deleteRoleTemplate: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
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

// ---------------- Create Club (super only) ----------------
Future<Response> _createClub(Request req) async {
  stderr.writeln('🔵 POST /clubs');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) {
      return Response(401, body: 'Unauthorized: member_id required');
    }

    conn = await _connect();
    
    // Check super user permission
    if (!await _isSuper(conn, authMemberId)) {
      return Response(403, body: 'Forbidden: super user access required');
    }

    final raw = await req.readAsString();
    if (raw.isEmpty) return Response(400, body: 'Missing body');
    final bodyJson = jsonDecode(raw) as Map<String, dynamic>;

    final name = (bodyJson['name'] ?? '').toString().trim();
    if (name.isEmpty) return Response(400, body: 'Club name required');

    await conn.execute('INSERT INTO lions_club (name) VALUES (:n)', {'n': name});
    final idRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
    final newId = idRes.rows.first.assoc()['id'];

    stderr.writeln('✅ Created club: $name (id=$newId)');
    return Response.ok(jsonEncode({'id': newId.toString(), 'name': name}), 
                      headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _createClub: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ---------------- Update Club (super only) ----------------
Future<Response> _updateClub(Request req, String id) async {
  stderr.writeln('🔵 PUT /clubs/$id');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) {
      return Response(401, body: 'Unauthorized');
    }

    conn = await _connect();
    if (!await _isSuper(conn, authMemberId)) {
      return Response(403, body: 'Forbidden: super user required');
    }

    final raw = await req.readAsString();
    if (raw.isEmpty) return Response(400, body: 'Missing body');
    final bodyJson = jsonDecode(raw) as Map<String, dynamic>;

    final name = (bodyJson['name'] ?? '').toString().trim();
    if (name.isEmpty) return Response(400, body: 'Club name required');

    await conn.execute('UPDATE lions_club SET name = :name WHERE id = :id', {'name': name, 'id': id});

    stderr.writeln('✅ Updated club id=$id name=$name');
    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _updateClub: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ---------------- Delete Club (super only) ----------------
Future<Response> _deleteClub(Request req, String id) async {
  stderr.writeln('🔵 DELETE /clubs/$id');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) {
      return Response(401, body: 'Unauthorized');
    }

    conn = await _connect();
    if (!await _isSuper(conn, authMemberId)) {
      return Response(403, body: 'Forbidden: super user required');
    }

    await conn.execute('DELETE FROM lions_club WHERE id = :id', {'id': id});

    stderr.writeln('✅ Deleted club id=$id');
    return Response(204);
  } catch (e, st) {
    stderr.writeln('❌ Error in _deleteClub: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ---------------- Assign volunteer to role ----------------
Future<Response> _assignVolunteer(Request req, String eventId) async {
  stderr.writeln('🔵 POST /events/$eventId/volunteers');
  MySQLConnection? conn;
  try {
    final raw = await req.readAsString();
    if (raw.isEmpty) return Response(400, body: 'Missing body');
    final bodyJson = jsonDecode(raw) as Map<String, dynamic>;

    final roleId = bodyJson['role_id'];
    final memberId = bodyJson['member_id'];

    if (roleId == null || memberId == null) {
      return Response(400, body: 'Missing required fields: role_id, member_id');
    }

    conn = await _connect();

    // Check if assignment already exists
    final existing = await conn.execute('''
      SELECT id FROM event_volunteers 
      WHERE event_id = :eventId AND role_id = :roleId
    ''', {'eventId': eventId, 'roleId': roleId.toString()});

    if (existing.rows.isNotEmpty) {
      // Update existing assignment
      await conn.execute('''
        UPDATE event_volunteers 
        SET member_id = :memberId 
        WHERE event_id = :eventId AND role_id = :roleId
      ''', {'memberId': memberId.toString(), 'eventId': eventId, 'roleId': roleId.toString()});
      stderr.writeln('✅ Updated volunteer assignment for role $roleId');
    } else {
      // Create new assignment
      await conn.execute('''
        INSERT INTO event_volunteers (event_id, role_id, member_id)
        VALUES (:eventId, :roleId, :memberId)
      ''', {'eventId': eventId, 'roleId': roleId.toString(), 'memberId': memberId.toString()});
      stderr.writeln('✅ Created volunteer assignment for role $roleId');
    }

    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _assignVolunteer: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ---------------- Unassign volunteer from role ----------------
Future<Response> _unassignVolunteer(Request req, String eventId, String roleId) async {
  stderr.writeln('🔵 DELETE /events/$eventId/volunteers/$roleId');
  MySQLConnection? conn;
  try {
    conn = await _connect();

    await conn.execute('''
      DELETE FROM event_volunteers 
      WHERE event_id = :eventId AND role_id = :roleId
    ''', {'eventId': eventId, 'roleId': roleId});

    stderr.writeln('✅ Removed volunteer assignment for role $roleId');
    return Response(204); // No Content
  } catch (e, st) {
    stderr.writeln('❌ Error in _unassignVolunteer: $e\n$st');
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
          WHERE (r.event_id IS NULL AND r.event_type_id = e.event_type_id)
            AND (r.event_id IS NULL)
          ORDER BY r.time_in, r.role_name
        ''';
    final rolesResult = await conn.execute(rolesQuery, {'eventId': eventId});

    if (!dryRun && isOther && rolesResult.rows.isEmpty) {
      return Response(400, body: 'No roles defined for this event yet.');
    }

    final rolesHtml = StringBuffer()..write('<ul>');
    for (final row in rolesResult.rows) {
      final r = row.assoc();
      rolesHtml.write('<li>${r['role_name']}: ${r['time_in']} - ${r['time_out']}</li>');
    }
    rolesHtml.write('</ul>');

    
    // Build template variables
    final vars = <String, String>{
      'event_type': event['event_type']?.toString() ?? '',
      'event_name': '${event['event_type'] ?? ''} · ${event['club_name'] ?? ''}', // keep for other templates
      'date': event['event_date']?.toString() ?? '',
      'event_date': event['event_date']?.toString() ?? '', // add legacy alias
      'location': event['location']?.toString() ?? '',
      'event_location': event['location']?.toString() ?? '', // add legacy alias
      'club_name': event['club_name']?.toString() ?? '',
      'roles_html': rolesHtml.toString(),
      'notes': event['notes']?.toString() ?? '',
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

Future<Response> _getAuditLogs(Request req) async {
  stderr.writeln('🔵 GET /audit_logs');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) {
      return Response(401, body: 'Unauthorized');
    }

    conn = await _connect();
    
    // Only super users can view audit logs
    if (!await _isSuper(conn, authMemberId)) {
      return Response(403, body: 'Forbidden: super user access required');
    }

    // Get optional filters
    final entityType = req.url.queryParameters['entity_type']; // 'member', 'event', etc.
    final entityId = req.url.queryParameters['entity_id'];
    final action = req.url.queryParameters['action']; // 'CREATE', 'UPDATE', 'DELETE'
    final memberId = req.url.queryParameters['member_id']; // who made the change
    final limit = int.tryParse(req.url.queryParameters['limit'] ?? '100') ?? 100;

    var sql = '''
      SELECT 
        a.id,
        a.entity_type,
        a.entity_id,
        a.action,
        a.changed_by_member_id,
        m.name AS changed_by_name,
        a.changed_at,
        a.old_value,
        a.new_value
      FROM audit_log a
      LEFT JOIN members m ON m.id = a.changed_by_member_id
      WHERE 1=1
    ''';

    final params = <String, dynamic>{};

    if (entityType != null && entityType.isNotEmpty) {
      sql += ' AND a.entity_type = :entityType';
      params['entityType'] = entityType;
    }

    if (entityId != null && entityId.isNotEmpty) {
      sql += ' AND a.entity_id = :entityId';
      params['entityId'] = int.tryParse(entityId) ?? 0;
    }

    if (action != null && action.isNotEmpty) {
      sql += ' AND a.action = :action';
      params['action'] = action;
    }

    if (memberId != null && memberId.isNotEmpty) {
      sql += ' AND a.changed_by_member_id = :memberId';
      params['memberId'] = int.tryParse(memberId) ?? 0;
    }

    sql += ' ORDER BY a.changed_at DESC LIMIT :limit';
    params['limit'] = limit;

    stderr.writeln('DEBUG: audit_logs SQL=$sql params=$params');

    final result = await conn.execute(sql, params);
    final logs = <Map<String, dynamic>>[];

    for (final row in result.rows) {
      final a = row.assoc();
      logs.add({
        'id': a['id'],
        'entity_type': a['entity_type'],
        'entity_id': a['entity_id'],
        'action': a['action'],
        'changed_by_member_id': a['changed_by_member_id'],
        'changed_by_name': a['changed_by_name'],
        'changed_at': a['changed_at']?.toString() ?? '',
        'old_value': a['old_value'],
        'new_value': a['new_value'],
      });
    }

    stderr.writeln('DEBUG: Returning ${logs.length} audit log entries');
    return Response.ok(jsonEncode(logs), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _getAuditLogs: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// Add role to event
Future<Response> _addRoleToEvent(Request req, String eventId) async {
  stderr.writeln('🔵 POST /events/$eventId/roles');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) return Response(401, body: 'Unauthorized');

    conn = await _connect();
    
    final isAdmin = await _isAdmin(conn, authMemberId);
    final isSuper = await _isSuper(conn, authMemberId);
    if (!isAdmin && !isSuper) {
      return Response(403, body: 'Forbidden: admin access required');
    }

    final raw = await req.readAsString();
    if (raw.isEmpty) return Response(400, body: 'Missing body');
    final bodyJson = jsonDecode(raw) as Map<String, dynamic>;

    final roleName = bodyJson['role_name']?.toString() ?? '';
    final timeIn = bodyJson['time_in']?.toString() ?? '';
    final timeOut = bodyJson['time_out']?.toString() ?? '';

    if (roleName.isEmpty) {
      return Response(400, body: 'Role name required');
    }

    await conn.execute('''
      INSERT INTO roles (event_id, role_name, time_in, time_out)
      VALUES (:eventId, :roleName, :timeIn, :timeOut)
    ''', {
      'eventId': eventId,
      'roleName': roleName,
      'timeIn': timeIn,
      'timeOut': timeOut,
    });

    final idRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
    final newId = idRes.rows.first.assoc()['id'];

    // Log audit
    await _logAudit(
      conn,
      entityType: 'role',
      entityId: int.parse(newId!),
      action: 'CREATE',
      changedByMemberId: authMemberId,
      newValue: {'event_id': eventId, 'role_name': roleName, 'time_in': timeIn, 'time_out': timeOut},
    );

    return Response.ok(jsonEncode({'id': newId}), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _addRoleToEvent: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// Update role
Future<Response> _updateRole(Request req, String roleId) async {
  stderr.writeln('🔵 PUT /roles/$roleId');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) return Response(401, body: 'Unauthorized');

    conn = await _connect();
    
    final isAdmin = await _isAdmin(conn, authMemberId);
    final isSuper = await _isSuper(conn, authMemberId);
    if (!isAdmin && !isSuper) {
      return Response(403, body: 'Forbidden: admin access required');
    }

    final oldRow = await conn.execute('SELECT * FROM roles WHERE id = :id', {'id': roleId});
    final oldValue = oldRow.rows.isNotEmpty ? oldRow.rows.first.assoc() : null;

    final raw = await req.readAsString();
    if (raw.isEmpty) return Response(400, body: 'Missing body');
    final bodyJson = jsonDecode(raw) as Map<String, dynamic>;

    final roleName = bodyJson['role_name']?.toString() ?? '';
    final timeIn = bodyJson['time_in']?.toString() ?? '';
    final timeOut = bodyJson['time_out']?.toString() ?? '';

    if (roleName.isEmpty) {
      return Response(400, body: 'Role name required');
    }

    await conn.execute('''
      UPDATE roles
      SET role_name = :roleName, time_in = :timeIn, time_out = :timeOut
      WHERE id = :id
    ''', {
      'id': roleId,
      'roleName': roleName,
      'timeIn': timeIn,
      'timeOut': timeOut,
    });

    // Log audit
    await _logAudit(
      conn,
      entityType: 'role',
      entityId: int.parse(roleId),
      action: 'UPDATE',
      changedByMemberId: authMemberId,
      oldValue: oldValue,
      newValue: {'role_name': roleName, 'time_in': timeIn, 'time_out': timeOut},
    );

    return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _updateRole: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// Delete role
Future<Response> _deleteRole(Request req, String roleId) async {
  stderr.writeln('🔵 DELETE /roles/$roleId');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) return Response(401, body: 'Unauthorized');

    conn = await _connect();
    
    final isAdmin = await _isAdmin(conn, authMemberId);
    final isSuper = await _isSuper(conn, authMemberId);
    if (!isAdmin && !isSuper) {
      return Response(403, body: 'Forbidden: admin access required');
    }

    final oldRow = await conn.execute('SELECT * FROM roles WHERE id = :id', {'id': roleId});
    final oldValue = oldRow.rows.isNotEmpty ? oldRow.rows.first.assoc() : null;

    // Delete volunteer assignments first
    await conn.execute('DELETE FROM event_volunteers WHERE role_id = :roleId', {'roleId': roleId});
    
    // Delete role
    await conn.execute('DELETE FROM roles WHERE id = :id', {'id': roleId});

    // Log audit
    await _logAudit(
      conn,
      entityType: 'role',
      entityId: int.parse(roleId),
      action: 'DELETE',
      changedByMemberId: authMemberId,
      oldValue: oldValue,
    );

    return Response(204);
  } catch (e, st) {
    stderr.writeln('❌ Error in _deleteRole: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// Events report - breakdown by type
Future<Response> _reportEvents(Request req) async {
  stderr.writeln('🔵 GET /reports/events');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) return Response(401, body: 'Unauthorized');

    conn = await _connect();

    final params = req.url.queryParameters;
    final startDate = params['start_date'] ?? '';
    final endDate = params['end_date'] ?? '';
    final clubIdParam = params['club_id'];

    // Build WHERE clause
    final conditions = <String>[];
    final queryParams = <String, dynamic>{};

    if (startDate.isNotEmpty) {
      conditions.add('e.event_date >= :startDate');
      queryParams['startDate'] = startDate;
    }
    if (endDate.isNotEmpty) {
      conditions.add('e.event_date <= :endDate');
      queryParams['endDate'] = endDate;
    }
    if (clubIdParam != null) {
      conditions.add('e.lions_club_id = :clubId');
      queryParams['clubId'] = clubIdParam;
    }

    final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    // Total events
    final totalRes = await conn.execute('''
      SELECT COUNT(*) as total
      FROM events e
      $whereClause
    ''', queryParams);
    final totalEvents = int.parse(totalRes.rows.first.assoc()['total'] ?? '0');

    // Events by type
    final byTypeRes = await conn.execute('''
      SELECT 
        et.name as event_type,
        COUNT(*) as count
      FROM events e
      JOIN event_types et ON e.event_type_id = et.id
      $whereClause
      GROUP BY et.name
      ORDER BY count DESC
    ''', queryParams);

    final byType = byTypeRes.rows.map((r) => r.assoc()).toList();

    final report = {
      'total_events': totalEvents,
      'by_type': byType,
    };

    return Response.ok(jsonEncode(report), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _reportEvents: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// Volunteer statistics report
Future<Response> _reportVolunteers(Request req) async {
  stderr.writeln('🔵 GET /reports/volunteers');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) return Response(401, body: 'Unauthorized');

    conn = await _connect();

    final params = req.url.queryParameters;
    final startDate = params['start_date'] ?? '';
    final endDate = params['end_date'] ?? '';
    final clubIdParam = params['club_id'];

    // Build WHERE clause
    final conditions = <String>[];
    final queryParams = <String, dynamic>{};

    if (startDate.isNotEmpty) {
      conditions.add('e.event_date >= :startDate');
      queryParams['startDate'] = startDate;
    }
    if (endDate.isNotEmpty) {
      conditions.add('e.event_date <= :endDate');
      queryParams['endDate'] = endDate;
    }
    if (clubIdParam != null) {
      conditions.add('e.lions_club_id = :clubId');
      queryParams['clubId'] = clubIdParam;
    }

    final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    // Calculate total volunteer hours
    final hoursRes = await conn.execute('''
      SELECT 
        SUM(
          TIMESTAMPDIFF(MINUTE, r.time_in, r.time_out) / 60.0
        ) as total_hours
      FROM event_volunteers ev
      JOIN roles r ON ev.role_id = r.id
      JOIN events e ON r.event_id = e.id
      $whereClause
    ''', queryParams);
    
    final totalHours = double.tryParse(hoursRes.rows.first.assoc()['total_hours']?.toString() ?? '0') ?? 0.0;

    // Top volunteers by hours
    final topVolunteersRes = await conn.execute('''
      SELECT 
        m.first_name,
        m.last_name,
        SUM(
          TIMESTAMPDIFF(MINUTE, r.time_in, r.time_out) / 60.0
        ) as hours,
        COUNT(DISTINCT ev.role_id) as shifts
      FROM event_volunteers ev
      JOIN roles r ON ev.role_id = r.id
      JOIN events e ON r.event_id = e.id
      JOIN members m ON ev.member_id = m.id
      $whereClause
      GROUP BY m.id, m.first_name, m.last_name
      ORDER BY hours DESC
      LIMIT 10
    ''', queryParams);

    final topVolunteers = topVolunteersRes.rows.map((r) {
      final row = r.assoc();
      return {
        'name': '${row['first_name']} ${row['last_name']}',
        'hours': double.tryParse(row['hours']?.toString() ?? '0')?.toStringAsFixed(1) ?? '0.0',
        'shifts': row['shifts'],
      };
    }).toList();

    final report = {
      'total_hours': totalHours,
      'top_volunteers': topVolunteers,
    };

    return Response.ok(jsonEncode(report), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _reportVolunteers: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// Fill rate statistics report
Future<Response> _reportFillRates(Request req) async {
  stderr.writeln('🔵 GET /reports/fill_rates');
  MySQLConnection? conn;
  try {
    final authMemberId = _getMemberIdFromRequest(req);
    if (authMemberId == null) return Response(401, body: 'Unauthorized');

    conn = await _connect();

    final params = req.url.queryParameters;
    final startDate = params['start_date'] ?? '';
    final endDate = params['end_date'] ?? '';
    final clubIdParam = params['club_id'];

    // Build WHERE clause
    final conditions = <String>[];
    final queryParams = <String, dynamic>{};

    if (startDate.isNotEmpty) {
      conditions.add('e.event_date >= :startDate');
      queryParams['startDate'] = startDate;
    }
    if (endDate.isNotEmpty) {
      conditions.add('e.event_date <= :endDate');
      queryParams['endDate'] = endDate;
    }
    if (clubIdParam != null) {
      conditions.add('e.lions_club_id = :clubId');
      queryParams['clubId'] = clubIdParam;
    }

    final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    // Overall fill rate
    final overallRes = await conn.execute('''
      SELECT 
        COUNT(DISTINCT r.id) as total_roles,
        COUNT(DISTINCT ev.role_id) as filled_roles
      FROM roles r
      JOIN events e ON r.event_id = e.id
      LEFT JOIN event_volunteers ev ON r.id = ev.role_id
      $whereClause
    ''', queryParams);

    final row = overallRes.rows.first.assoc();
    final totalRoles = int.parse(row['total_roles'] ?? '0');
    final filledRoles = int.parse(row['filled_roles'] ?? '0');
    final overallFillRate = totalRoles > 0 ? filledRoles / totalRoles : 0.0;

    // Fill rate by event
    final byEventRes = await conn.execute('''
      SELECT 
        e.id as event_id,
        et.name as event_type,
        e.event_date as date,
        COUNT(DISTINCT r.id) as total_roles,
        COUNT(DISTINCT ev.role_id) as filled_roles
      FROM events e
      JOIN event_types et ON e.event_type_id = et.id
      LEFT JOIN roles r ON e.id = r.event_id
      LEFT JOIN event_volunteers ev ON r.id = ev.role_id
      $whereClause
      GROUP BY e.id, et.name, e.event_date
      HAVING total_roles > 0
      ORDER BY e.event_date DESC
      LIMIT 20
    ''', queryParams);

    final byEvent = byEventRes.rows.map((r) {
      final row = r.assoc();
      final total = int.parse(row['total_roles'] ?? '0');
      final filled = int.parse(row['filled_roles'] ?? '0');
      final fillRate = total > 0 ? filled / total : 0.0;
      
      return {
        'event_id': row['event_id'],
        'event_type': row['event_type'],
        'date': row['date'],
        'total_roles': total,
        'filled_roles': filled,
        'fill_rate': fillRate,
      };
    }).toList();

    final report = {
      'overall_fill_rate': overallFillRate,
      'total_roles': totalRoles,
      'filled_roles': filledRoles,
      'by_event': byEvent,
    };

    return Response.ok(jsonEncode(report), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _reportFillRates: $e\n$st');
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
  router.post('/clubs', _createClub);
  router.put('/clubs/<id>', (Request req, String id) => _updateClub(req, id));
  router.delete('/clubs/<id>', (Request req, String id) => _deleteClub(req, id));
  router.get('/event_types', _eventTypes);
  
  // THESE THREE LINES SHOULD BE HERE:
  router.get('/event_types/<id>/role_templates', (Request req, String id) => _getRoleTemplates(req, id));
  router.post('/event_types/<id>/role_templates', (Request req, String id) => _saveRoleTemplate(req, id));
  router.delete('/role_templates/<id>', (Request req, String id) => _deleteRoleTemplate(req, id));
  
  router.post('/events', _createEvent);
  router.delete('/events/<id>', (Request req, String id) => _deleteEvent(req, id));
  router.post('/members', _createMember);
  router.put('/members/<id>', (Request req, String id) => _updateMember(req, id));
  router.delete('/members/<id>', (Request req, String id) => _deleteMember(req, id));
  router.get('/events/calendar', _eventsCalendar);
  router.get('/events/<id>', (Request req, String id) => _eventDetails(req, id));
  router.get('/events', _events);
  router.put('/events/<id>', (Request req, String id) => _updateEvent(req, id));
  router.post('/events/<id>/notify', (Request req, String id) => _notifyEventMembers(req, id));
  router.post('/events/<id>/volunteers', (Request req, String id) => _assignVolunteer(req, id));
  router.delete('/events/<eventId>/volunteers/<roleId>', (Request req, String eventId, String roleId) => _unassignVolunteer(req, eventId, roleId));
  
  // THESE THREE LINES SHOULD ALSO BE HERE (for event role management):
  router.post('/events/<id>/roles', (Request req, String id) => _addRoleToEvent(req, id));
  router.put('/roles/<id>', (Request req, String id) => _updateRole(req, id));
  router.delete('/roles/<id>', (Request req, String id) => _deleteRole(req, id));
  
  router.get('/audit_logs', _getAuditLogs);
  router.get('/reports/events', _reportEvents);
  router.get('/reports/volunteers', _reportVolunteers);
  router.get('/reports/fill_rates', _reportFillRates);
  
  
  return router;
}


Future<Response> _createMember(Request req) async {
  stderr.writeln('🔵 POST /members');
  MySQLConnection? conn;
  try {
    final raw = await req.readAsString();
    if (raw.isEmpty) return Response(400, body: 'Missing body');
    final bodyJson = jsonDecode(raw) as Map<String, dynamic>;

    final name = bodyJson['name']?.toString() ?? '';
    final email = bodyJson['email']?.toString() ?? '';
    final phoneNumber = bodyJson['phone_number']?.toString() ?? '';
    final clubId = bodyJson['lions_club_id'];
    final isAdmin = (bodyJson['is_admin'] == true) ? 1 : 0;

    if (name.isEmpty || clubId == null) {
      return Response(400, body: 'Missing required fields: name, lions_club_id');
    }

    conn = await _connect();
    
    // Capture params for reuse in audit log
    final params = {
      'name': name,
      'email': email,
      'phone': phoneNumber,
      'club': clubId.toString(),
      'admin': isAdmin
    };
    
    await conn.execute('''
      INSERT INTO members (name, email, phone_number, lions_club_id, is_admin)
      VALUES (:name, :email, :phone, :club, :admin)
    ''', params);

    final idRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
    final newId = idRes.rows.first.assoc()['id'];

    // Log audit
    final authMemberId = _getMemberIdFromRequest(req);
    await _logAudit(
      conn,
      entityType: 'member',
      entityId: int.parse(newId!),
      action: 'CREATE',
      changedByMemberId: authMemberId,
      newValue: params,
    );
    
    return Response.ok(jsonEncode({'id': newId.toString()}), headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    stderr.writeln('❌ Error in _createMember: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}


Future<Response> _updateMember(Request req, String idStr) async {
  stderr.writeln('🔵 PUT /members/$idStr');
  final id = int.tryParse(idStr);
  if (id == null) {
    return Response.badRequest(body: 'Invalid member ID');
  }

  MySQLConnection? conn;
  try {
    conn = await _connect();
    
    // Get requesting member info
    final authMemberId = _getMemberIdFromRequest(req);
    final isSuper = authMemberId != null ? await _isSuper(conn, authMemberId) : false;
    final isAdmin = authMemberId != null ? await _isAdmin(conn, authMemberId) : false;
    final isSelf = authMemberId == id;

    stderr.writeln('DEBUG: updateMember authMemberId=$authMemberId isSuper=$isSuper isAdmin=$isAdmin isSelf=$isSelf targetId=$id');

    // Authorization: must be admin, super, or updating own profile
    if (!isAdmin && !isSuper && !isSelf) {
      return Response.forbidden('Admin access required or edit own profile only');
    }

    // Fetch old value BEFORE update for audit log
    final oldRow = await conn.execute('SELECT * FROM members WHERE id = :id', {'id': id});
    final oldValue = oldRow.rows.isNotEmpty ? oldRow.rows.first.assoc() : null;

    final body = await req.readAsString();
    final data = json.decode(body) as Map<String, dynamic>;

    // Build update query based on permissions
    final updates = <String>[];
    final params = <String, dynamic>{};
    
    // All users can update these fields
    if (data.containsKey('name')) {
      updates.add('name = :name');
      params['name'] = data['name'];
    }
    if (data.containsKey('email')) {
      updates.add('email = :email');
      params['email'] = data['email'];
    }
    if (data.containsKey('phone_number')) {
      updates.add('phone_number = :phone');
      params['phone'] = data['phone_number'];
    }

    // Only admins/super can update these fields
    if (isAdmin || isSuper) {
      if (data.containsKey('lions_club_id')) {
        updates.add('lions_club_id = :clubId');
        params['clubId'] = data['lions_club_id'];
      }
      if (data.containsKey('is_admin')) {
        updates.add('is_admin = :isAdmin');
        params['isAdmin'] = data['is_admin'] == 1 || data['is_admin'] == true ? 1 : 0;
      }
    }

    if (updates.isEmpty) {
      return Response.badRequest(body: 'No valid fields to update');
    }

    params['id'] = id;
    final sql = 'UPDATE members SET ${updates.join(', ')} WHERE id = :id';
    
    stderr.writeln('DEBUG: updateMember SQL=$sql params=$params');
    
    await conn.execute(sql, params);
    
    // Log audit
    await _logAudit(
      conn,
      entityType: 'member',
      entityId: id,
      action: 'UPDATE',
      changedByMemberId: authMemberId,
      oldValue: oldValue,
      newValue: params,
    );
    
    return Response.ok(json.encode({'message': 'Member updated'}));
  } catch (e, st) {
    stderr.writeln('❌ Error in _updateMember: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _deleteMember(Request req, String idStr) async {
  stderr.writeln('🔵 DELETE /members/$idStr');
  final id = int.tryParse(idStr);
  if (id == null) {
    return Response.badRequest(body: 'Invalid member ID');
  }

  MySQLConnection? conn;
  try {
    conn = await _connect();
    
    // Fetch old value BEFORE delete for audit log
    final oldRow = await conn.execute('SELECT * FROM members WHERE id = :id', {'id': id});
    final oldValue = oldRow.rows.isNotEmpty ? oldRow.rows.first.assoc() : null;
    
    await conn.execute('DELETE FROM members WHERE id = :id', {'id': id});
    
    // Log audit
    final authMemberId = _getMemberIdFromRequest(req);
    await _logAudit(
      conn,
      entityType: 'member',
      entityId: id,
      action: 'DELETE',
      changedByMemberId: authMemberId,
      oldValue: oldValue,
    );
    
    return Response(204);
  } catch (e, st) {
    stderr.writeln('❌ Error in _deleteMember: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ✅ ADD THIS FUNCTION (place it before main())
Middleware _handleOptions = (Handler innerHandler) {
  return (Request request) async {
    if (request.method == 'OPTIONS') {
      stderr.writeln('🔵 OPTIONS ${request.url.path} - returning 200');
      return Response.ok('', headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, X-Member-Id',
      });
    }
    return innerHandler(request);
  };
};

// ...existing code...
void main(List<String> args) async {
  final ip = InternetAddress.anyIPv4;
  
  // ✅ UPDATED: Handle OPTIONS requests BEFORE the router
  final handler = Pipeline()
      .addMiddleware(shelf_cors.corsHeaders(headers: {
        shelf_cors.ACCESS_CONTROL_ALLOW_ORIGIN: '*',
        shelf_cors.ACCESS_CONTROL_ALLOW_METHODS: 'GET, POST, PUT, DELETE, OPTIONS',
        shelf_cors.ACCESS_CONTROL_ALLOW_HEADERS: 'Origin, Content-Type, X-Member-Id',
      }))
      //.addMiddleware(logRequests())
      .addMiddleware(_handleOptions) // ✅ ADD THIS LINE
      .addHandler(_router().call);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await io.serve(handler, ip, port);
  print('Server listening on port ${server.port}');
}

