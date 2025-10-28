import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:mysql_client/mysql_client.dart';

Future<MySQLConnection> _connect() async {
  final conn = await MySQLConnection.createConnection(
    host: '127.0.0.1',
    port: 3306,
    userName: 'root',
    password: 'IanMySql1*.*',
    databaseName: 'lions',
  );
  await conn.connect();
  stderr.writeln('✅ Connected to MySQL');
  return conn;
}

// ---------------- Members ----------------

Future<Response> _members(Request req) async {
  stderr.writeln('🔵 GET /members');
  MySQLConnection? conn;
  try {
    conn = await _connect();

    final clubId = req.url.queryParameters['club_id'];
    final sql = '''
      SELECT 
        m.id,
        m.name,
        m.email,
        m.phone_number,
        m.lions_club_id,
        m.is_admin,
        lc.name AS club_name
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
  } catch (e) {
    stderr.writeln('❌ Error: $e');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _createMember(Request req) async {
  stderr.writeln('🟢 POST /members');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final body = await req.readAsString();
    if (body.isEmpty) return Response(400, body: 'Missing body');
    final data = jsonDecode(body) as Map<String, dynamic>;

    final name = (data['name'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    final phone = (data['phone_number'] ?? '').toString().trim();
    final clubId = data['lions_club_id']?.toString();
    if (name.isEmpty || clubId == null) {
      return Response(400, body: 'name and lions_club_id are required');
    }

    await conn.execute(
      '''
      INSERT INTO members (lions_club_id, name, email, phone_number)
      VALUES (:clubId, :name, :email, :phone)
      ''',
      {'clubId': clubId, 'name': name, 'email': email, 'phone': phone},
    );

    final idRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
    final newId = idRes.rows.first.assoc()['id'];

    final r = await conn.execute(
      '''
      SELECT m.id, m.name, m.email, m.phone_number, m.lions_club_id, lc.name AS club_name
      FROM members m
      LEFT JOIN lions_club lc ON lc.id = m.lions_club_id
      WHERE m.id = :id
      ''',
      {'id': newId.toString()},
    );
    return Response(201, body: jsonEncode(r.rows.first.assoc()), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    stderr.writeln('❌ POST /members error: $e');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _updateMember(Request req, String id) async {
  stderr.writeln('🟡 PUT /members/$id');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final body = await req.readAsString();
    if (body.isEmpty) return Response(400, body: 'Missing body');
    final data = jsonDecode(body) as Map<String, dynamic>;

    final name = (data['name'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    final phone = (data['phone_number'] ?? '').toString().trim();
    final clubId = data['lions_club_id']?.toString();
    if (name.isEmpty || clubId == null) {
      return Response(400, body: 'name and lions_club_id are required');
    }

    final upd = await conn.execute(
      '''
      UPDATE members
      SET lions_club_id = :clubId, name = :name, email = :email, phone_number = :phone
      WHERE id = :id
      ''',
      {'clubId': clubId, 'name': name, 'email': email, 'phone': phone, 'id': id},
    );
    if ((upd.affectedRows ?? 0) == 0) return Response.notFound('Member not found');

    final r = await conn.execute(
      '''
      SELECT m.id, m.name, m.email, m.phone_number, m.lions_club_id, lc.name AS club_name
      FROM members m
      LEFT JOIN lions_club lc ON lc.id = m.lions_club_id
      WHERE m.id = :id
      ''',
      {'id': id},
    );
    return Response.ok(jsonEncode(r.rows.first.assoc()), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    stderr.writeln('❌ PUT /members/$id error: $e');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _deleteMember(Request req, String id) async {
  stderr.writeln('🔴 DELETE /members/$id');
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final res = await conn.execute('DELETE FROM members WHERE id = :id', {'id': id});
    if ((res.affectedRows ?? 0) == 0) return Response.notFound('Member not found');
    return Response.ok(jsonEncode({'deleted': id}), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    stderr.writeln('❌ DELETE /members/$id error: $e');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ---------------- Events ----------------

Future<Response> _events(Request req) async {
  stderr.writeln('🔵 GET /events');
  MySQLConnection? conn;
  try {
    conn = await _connect();

    final clubId = req.url.queryParameters['club_id'];
    final sql = '''
      SELECT 
        e.id,
        et.name AS event_type,
        lc.name AS club_name,
        e.event_date,
        e.location
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
  } catch (e) {
    stderr.writeln('❌ Error: $e');
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
      SELECT 
        e.id,
        et.id AS event_type_id,
        et.name AS event_type,
        lc.id AS club_id,
        lc.name AS club_name,
        e.event_date AS date,
        e.location,
        e.notes
      FROM events e
      LEFT JOIN event_types et ON e.event_type_id = et.id
      LEFT JOIN lions_club lc ON e.lions_club_id = lc.id
      WHERE e.id = :eventId
    ''', {'eventId': eventId});

    if (eventResult.rows.isEmpty) return Response.notFound('Event not found');

    final e = eventResult.rows.first.assoc();

    final rolesResult = await conn.execute('''
      SELECT 
        r.id AS role_id,
        r.role_name,
        r.time_in,
        r.time_out,
        m.id AS member_id,
        m.name AS volunteer_name
      FROM roles r
      JOIN events ev ON ev.id = :eventId AND r.event_type_id = ev.event_type_id
      LEFT JOIN event_volunteers v ON v.role_id = r.id AND v.event_id = ev.id
      LEFT JOIN members m ON m.id = v.member_id
      ORDER BY r.time_in, r.role_name
    ''', {'eventId': eventId});

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

Future<Response> _assignVolunteer(Request req, String eventId) async {
  stderr.writeln('🟠 POST /events/$eventId/volunteer');
  final body = await req.readAsString();
  if (body.isEmpty) return Response(400, body: 'Missing body');
  final data = jsonDecode(body) as Map<String, dynamic>;
  final roleId = data['role_id'];
  final memberId = data['member_id'];

  if (roleId == null) return Response(400, body: 'role_id required');

  MySQLConnection? conn;
  try {
    conn = await _connect();

    final chk = await conn.execute('''
      SELECT 1
      FROM roles r
      JOIN events e ON e.id = :eventId
      WHERE r.id = :roleId AND r.event_type_id = e.event_type_id
      LIMIT 1
    ''', {'eventId': eventId.toString(), 'roleId': roleId.toString()});
    if (chk.rows.isEmpty) return Response(400, body: 'Role not valid for event');

    await conn.execute('''
      INSERT INTO event_volunteers (event_id, role_id, member_id)
      VALUES (:eventId, :roleId, :memberId)
      ON DUPLICATE KEY UPDATE member_id = VALUES(member_id)
    ''', {
      'eventId': eventId.toString(),
      'roleId': roleId.toString(),
      'memberId': memberId?.toString()
    });

    return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    stderr.writeln('❌ Error: $e');
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// --------------- Reference data ---------------

Future<Response> _eventTypes(Request req) async {
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final r = await conn.execute('SELECT id, name FROM event_types ORDER BY name');
    final list = [for (final row in r.rows) row.assoc()];
    return Response.ok(jsonEncode(list), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _clubs(Request req) async {
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final r = await conn.execute('SELECT id, name FROM lions_club ORDER BY name');
    final list = [for (final row in r.rows) row.assoc()];
    return Response.ok(jsonEncode(list), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ---------------- Events CRUD ----------------

Future<Response> _createEvent(Request req) async {
  final body = await req.readAsString();
  if (body.isEmpty) return Response(400, body: 'Missing body');
  final data = jsonDecode(body) as Map<String, dynamic>;

  final et = data['event_type_id'];
  final club = data['lions_club_id'];
  final date = data['event_date'];
  final loc = (data['location'] ?? '').toString();
  final notes = (data['notes'] ?? '').toString();
  if (et == null || club == null || date == null) {
    return Response(400, body: 'event_type_id, lions_club_id, event_date required');
  }

  MySQLConnection? conn;
  try {
    conn = await _connect();
    await conn.execute(
      'INSERT INTO events (event_type_id, lions_club_id, event_date, location) VALUES (:et,:club,:date,:loc:notes)',
      {'et': et.toString(), 'club': club.toString(), 'date': date.toString(), 'loc': loc, 'notes': notes},
    );
    final idRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
    final newId = idRes.rows.first.assoc()['id'];

    await conn.execute('''
      INSERT INTO event_volunteers (event_id, role_id, member_id)
      SELECT :eventId, r.id, NULL
      FROM roles r
      WHERE r.event_type_id = :eventTypeId
    ''', {'eventId': newId.toString(), 'eventTypeId': et.toString()});

    return Response(201, body: jsonEncode({'id': newId}), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _updateEvent(Request req, String id) async {
  final body = await req.readAsString();
  if (body.isEmpty) return Response(400, body: 'Missing body');
  final data = jsonDecode(body) as Map<String, dynamic>;

  final et = data['event_type_id'];
  final club = data['lions_club_id'];
  final date = data['event_date'];
  final loc = (data['location'] ?? '').toString();
  final notes = (data['notes'] ?? '').toString();
  if (et == null || club == null || date == null) {
    return Response(400, body: 'event_type_id, lions_club_id, event_date required');
  }

  MySQLConnection? conn;
  try {
    conn = await _connect();

    final curRes = await conn.execute('SELECT event_type_id FROM events WHERE id = :id', {'id': id});
    if (curRes.rows.isEmpty) return Response.notFound('Event not found');
    final currentTypeId = curRes.rows.first.assoc()['event_type_id'];

    await conn.execute('''
      UPDATE events
      SET event_type_id = :et, lions_club_id = :club, event_date = :date, location = :loc, notes = :notes
      WHERE id = :id
    ''', {'et': et.toString(), 'club': club.toString(), 'date': date.toString(), 'loc': loc, 'notes': notes, 'id': id});

    if (currentTypeId.toString() != et.toString()) {
      await conn.execute('DELETE FROM event_volunteers WHERE event_id = :id', {'id': id});
      await conn.execute('''
        INSERT INTO event_volunteers (event_id, role_id, member_id)
        SELECT :eventId, r.id, NULL
        FROM roles r
        WHERE r.event_type_id = :eventTypeId
      ''', {'eventId': id, 'eventTypeId': et.toString()});
    }

    return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _deleteEvent(Request req, String id) async {
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final r = await conn.execute('DELETE FROM events WHERE id = :id', {'id': id});
    final affected = r.affectedRows ?? 0;
    if (affected == 0) return Response.notFound('Event not found');
    return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

// ---------------- Server ----------------

void main() async {
  final handler = Pipeline()
      .addMiddleware(corsHeaders(headers: {
        ACCESS_CONTROL_ALLOW_ORIGIN: '*',
        ACCESS_CONTROL_ALLOW_METHODS: 'GET, POST, PUT, DELETE, OPTIONS',
        ACCESS_CONTROL_ALLOW_HEADERS: 'Origin, Content-Type',
      }))
      .addMiddleware(logRequests())
      .addHandler((req) {
        if (req.method == 'OPTIONS') return Response.ok('');

        // Members
        if (req.method == 'GET' && req.url.path == 'members') return _members(req);
        if (req.method == 'POST' && req.url.path == 'members') return _createMember(req);
        final memberDetail = RegExp(r'^members/(\d+)$').firstMatch(req.url.path);
        if (memberDetail != null) {
          if (req.method == 'PUT') return _updateMember(req, memberDetail.group(1)!);
          if (req.method == 'DELETE') return _deleteMember(req, memberDetail.group(1)!);
        }

        // Events
        if (req.method == 'GET' && req.url.path == 'events') return _events(req);
        if (req.method == 'POST' && req.url.path == 'events') return _createEvent(req);
        final eventDetail = RegExp(r'^events/(\d+)$').firstMatch(req.url.path);
        if (eventDetail != null) {
          if (req.method == 'GET') return _eventDetails(req, eventDetail.group(1)!);
          if (req.method == 'PUT') return _updateEvent(req, eventDetail.group(1)!);
          if (req.method == 'DELETE') return _deleteEvent(req, eventDetail.group(1)!);
        }
        final volunteer = RegExp(r'^events/(\d+)/volunteer$').firstMatch(req.url.path);
        if (req.method == 'POST' && volunteer != null) {
          return _assignVolunteer(req, volunteer.group(1)!);
        }

        // Reference
        if (req.method == 'GET' && req.url.path == 'event_types') return _eventTypes(req);
        if (req.method == 'GET' && req.url.path == 'clubs') return _clubs(req);

        return Response.notFound('Not Found');
      });

  final server = await io.serve(handler, 'localhost', 8080);
  stderr.writeln('✅ Server running on http://${server.address.host}:${server.port}');
}