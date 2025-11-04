import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

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

// ---------------- Email Configuration ----------------
// TODO: Replace with your actual Gmail credentials
const String _smtpUsername = 'ianehyndman@gmail.com';
const String _smtpPassword = 'wtms yhne yutr unms';  // Use App Password, not regular password

Future<void> _sendEmail({
  required String to,
  required String subject,
  required String body,
}) async {
  final smtpServer = gmail(_smtpUsername, _smtpPassword);
  
  final message = Message()
    ..from = Address(_smtpUsername, 'Lions Club')
    ..recipients.add(to)
    ..subject = subject
    ..html = body;

  try {
    await send(message, smtpServer);
    stderr.writeln('✉️ Email sent to $to');
  } catch (e) {
    stderr.writeln('❌ Failed to send email to $to: $e');
    rethrow;
  }
}

// Template cache/renderer
final Map<String, String> _templateCache = {};

Future<String> _renderTemplate(String filename, Map<String, String> vars) async {
  // reads from lions_api/templates/<filename>
  final path = 'templates/$filename';
  final cached = _templateCache[path];
  final template = cached ?? await File(path).readAsString();
  _templateCache[path] = template;

  var out = template;
  vars.forEach((k, v) {
    out = out.replaceAll('{{$k}}', v);
  });
  return out;
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
        '' AS club_email,
        '' AS club_phone,
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
    final isOther = (e['event_type'] ?? '').toString() == 'Other';

    // Roles: for "Other" use event-specific roles only; else use template roles
    final rolesResult = await conn.execute(isOther
      ? '''
      SELECT 
        r.id AS role_id,
        r.role_name,
        r.time_in,
        r.time_out,
        m.id AS member_id,
        m.name AS volunteer_name
      FROM roles r
      JOIN events ev ON ev.id = :eventId
      LEFT JOIN event_volunteers v ON v.role_id = r.id AND v.event_id = ev.id
      LEFT JOIN members m ON m.id = v.member_id
      WHERE r.event_id = ev.id
      ORDER BY r.time_in, r.role_name
    '''
      : '''
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
      WHERE r.event_id IS NULL      -- template roles only
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
        'club_email': e['club_email'],
        'club_phone': e['club_phone'],
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

// ...existing code...
// ...existing code...
Future<Response> _notifyEventMembers(Request req, String eventId) async {
  stderr.writeln('📧 POST /events/$eventId/notify');

  // Parse body and query params
  Map<String, dynamic> bodyJson = {};
  try {
    final raw = await req.readAsString();
    if (raw.isNotEmpty) bodyJson = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {}
  final qp = req.url.queryParameters;

  final onlyAssigned   = (bodyJson['only_assigned'] == true)   || (qp['only_assigned'] == 'true');
  final resendUnfilled = (bodyJson['resend_unfilled'] == true) || (qp['resend_unfilled'] == 'true');
  final dryRun         = (bodyJson['dry_run'] == true)         || (qp['dry_run'] == 'true');

  // Optional overrides from app (subject always allowed; body_html only when user edits)
  final overrideSubject  = (bodyJson['subject'] as String?)?.trim();
  final overrideBodyHtml = (bodyJson['body_html'] as String?)?.trim();
  final overrideBodyText = (bodyJson['body'] as String?)?.trim(); // legacy plain text (we'll convert to <br>)

  String _textToHtml(String s) => s.replaceAll('\n', '<br>');

  MySQLConnection? conn;
  try {
    conn = await _connect();

    // Event details
    final eventResult = await conn.execute('''
      SELECT 
        e.id,
        et.name AS event_type,
        lc.name AS club_name,
        e.event_date,
        e.location,
        e.notes,
        e.lions_club_id
      FROM events e
      LEFT JOIN event_types et ON e.event_type_id = et.id
      LEFT JOIN lions_club lc ON e.lions_club_id = lc.id
      WHERE e.id = :eventId
    ''', {'eventId': eventId});
    if (eventResult.rows.isEmpty) return Response.notFound('Event not found');

    final event  = eventResult.rows.first.assoc();
    final clubId = event['lions_club_id'];
    final isOther = (event['event_type'] ?? '').toString() == 'Other';

    // Roles section for email body
    final rolesResult = await conn.execute(isOther
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
        WHERE r.event_type_id = e.event_type_id
          AND r.event_id IS NULL
        ORDER BY r.time_in, r.role_name
      ''', {'eventId': eventId});

    // If "Other" has no roles yet, block sending to avoid empty content
    if (!dryRun && isOther && rolesResult.rows.isEmpty) {
      return Response(400, body: 'No roles defined for this event yet.');
    }

    final rolesHtml = StringBuffer()
      ..write('<h3>Volunteer Roles:</h3><ul>');
    for (final row in rolesResult.rows) {
      final r = row.assoc();
      rolesHtml.write('<li>${r['role_name']}: ${r['time_in']} - ${r['time_out']}</li>');
    }
    rolesHtml.write('</ul>');

    final notesHtml = ((event['notes']?.toString().isNotEmpty) ?? false)
        ? '<p><b>Notes:</b> ${event['notes']}</p>'
        : '';

    // Choose templates: default = new-event; flags switch to resend/assigned
    String subjectTpl, bodyTpl;
    if (onlyAssigned) {
      subjectTpl = 'assigned_reminder_subject.txt';
      bodyTpl    = 'assigned_reminder_body.html';
    } else if (resendUnfilled) {
      subjectTpl = 'resend_unfilled_subject.txt';
      bodyTpl    = 'resend_unfilled_body.html';
    } else {
      subjectTpl = 'new_event_subject.txt';
      bodyTpl    = 'new_event_body.html';
    }

    final subject = overrideSubject ??
        await _renderTemplate(subjectTpl, {
          'event_type': (event['event_type'] ?? '').toString(),
          'club_name':  (event['club_name']  ?? '').toString(),
        });

    // Render HTML body from template first, then apply any override
    final templateHtml = await _renderTemplate(bodyTpl, {
      'event_type': (event['event_type'] ?? '').toString(),
      'club_name':  (event['club_name']  ?? '').toString(),
      'event_date': (event['event_date'] ?? '').toString(),
      'location':   (event['location']   ?? 'TBA').toString(),
      'notes_html': notesHtml,
      'roles_html': rolesHtml.toString(),
    });

    final bodyHtml = (overrideBodyHtml?.isNotEmpty ?? false)
        ? overrideBodyHtml!
        : ((overrideBodyText?.isNotEmpty ?? false) ? _textToHtml(overrideBodyText!) : templateHtml);

    // Resolve recipients
    late final IResultSet membersResult;
    if (onlyAssigned) {
      membersResult = await conn.execute('''
        SELECT DISTINCT m.id, m.name, m.email
        FROM members m
        JOIN event_volunteers ev ON ev.member_id = m.id
        WHERE ev.event_id = :eventId
          AND m.email IS NOT NULL AND m.email <> ''
      ''', {'eventId': eventId});
    } else {
      membersResult = await conn.execute('''
        SELECT id, name, email
        FROM members
        WHERE lions_club_id = :clubId
          AND email IS NOT NULL
          AND email <> ''
      ''', {'clubId': clubId.toString()});
    }

    // Build a simple list for preview count
    final recipientEmails = <String>[];
    for (final row in membersResult.rows) {
      final email = (row.assoc()['email'] ?? '').toString();
      if (email.isNotEmpty) recipientEmails.add(email);
    }

    // If preview requested, return subject/body_html and recipient count without sending
    if (dryRun) {
      return Response.ok(
        jsonEncode({
          'subject': subject,
          'body_html': bodyHtml,
          'recipients': recipientEmails.length,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (recipientEmails.isEmpty) {
      return Response.ok(
        jsonEncode({'message': 'No recipients with email addresses found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Send HTML emails
    int successCount = 0;
    int failCount = 0;
    for (final email in recipientEmails) {
      try {
        await _sendEmail(to: email, subject: subject, body: bodyHtml); // _sendEmail uses .html
        successCount++;
      } catch (e) {
        stderr.writeln('❌ Failed to send to $email: $e');
        failCount++;
      }
    }

    return Response.ok(
      jsonEncode({
        'success': true,
        'sent': successCount,
        'failed': failCount,
        'message': 'Emails sent to $successCount members${failCount > 0 ? ', $failCount failed' : ''}',
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, st) {
    stderr.writeln('❌ Error in _notifyEventMembers: $e\n$st');
    return Response.internalServerError(body: 'Error: $e');
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

    // Determine if event type is "Other"
    final etRes = await conn.execute('''
      SELECT et.name AS et_name
      FROM events e
      JOIN event_types et ON et.id = e.event_type_id
      WHERE e.id = :eventId
    ''', {'eventId': eventId.toString()});
    final etName = etRes.rows.isNotEmpty ? (etRes.rows.first.assoc()['et_name'] ?? '').toString() : '';
    final isOther = etName == 'Other';

    final chk = await conn.execute(isOther
      ? '''
        SELECT 1 FROM roles r
        WHERE r.id = :roleId AND r.event_id = :eventId
        LIMIT 1
      '''
      : '''
        SELECT 1
        FROM roles r
        JOIN events e ON e.id = :eventId
        WHERE r.id = :roleId
          AND r.event_type_id = e.event_type_id
          AND r.event_id IS NULL     -- template role
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


// ...existing code...
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

    // Start a simple transaction
    await conn.execute('START TRANSACTION');

    await conn.execute(
      'INSERT INTO events (event_type_id, lions_club_id, event_date, location, notes) VALUES (:et,:club,:date,:loc,:notes)',
      {'et': et.toString(), 'club': club.toString(), 'date': date.toString(), 'loc': loc, 'notes': notes},
    );
    final idRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
    final newId = idRes.rows.first.assoc()['id']?.toString();
    if (newId == null || newId.isEmpty) {
      await conn.execute('ROLLBACK');
      return Response.internalServerError(body: 'Failed to create event id');
    }

    final etNameRes = await conn.execute('SELECT name FROM event_types WHERE id = :id', {'id': et.toString()});
    final etName = etNameRes.rows.isNotEmpty ? (etNameRes.rows.first.assoc()['name'] ?? '').toString() : '';

    if (etName == 'Other') {
      final roles = data['roles'];
      if (roles is List) {
        for (final r in roles) {
          if (r is Map) {
            final roleName = (r['role_name'] ?? '').toString().trim();
            if (roleName.isEmpty) continue;
            final timeIn = (r['time_in'] ?? '').toString();
            final timeOut = (r['time_out'] ?? '').toString();

            // Insert event-specific role with BOTH type and event id
            await conn.execute('''
              INSERT INTO roles (event_type_id, event_id, role_name, time_in, time_out)
              VALUES (:et, :eventId, :name, :timeIn, :timeOut)
            ''', {
              'et': et.toString(),
              'eventId': newId,
              'name': roleName,
              'timeIn': timeIn,
              'timeOut': timeOut,
            });

            final ridRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
            final newRoleId = ridRes.rows.first.assoc()['id']?.toString();
            if (newRoleId != null && newRoleId.isNotEmpty) {
              await conn.execute('''
                INSERT INTO event_volunteers (event_id, role_id, member_id)
                VALUES (:eventId, :roleId, NULL)
                ON DUPLICATE KEY UPDATE member_id = member_id
              ''', {'eventId': newId, 'roleId': newRoleId});
            }
          }
        }
      }
    } else {
      // Pull template roles ONLY (event_id IS NULL)
      await conn.execute('''
        INSERT INTO event_volunteers (event_id, role_id, member_id)
        SELECT :eventId, r.id, NULL
        FROM roles r
        WHERE r.event_type_id = :eventTypeId
          AND r.event_id IS NULL
      ''', {'eventId': newId, 'eventTypeId': et.toString()});
    }

    await conn.execute('COMMIT');
    return Response(201, body: jsonEncode({'id': newId}), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    try { await conn?.execute('ROLLBACK'); } catch (_) {}
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}
// ...existing code...


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
      SET event_type_id = :et, lions_club_id = :club, event_date = :date, location = :loc, notes = :notes,
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

// ...existing code...
Future<Response> _listEventRoles(Request req, String eventId) async {
  MySQLConnection? conn;
  try {
    conn = await _connect();
    final r = await conn.execute('''
      SELECT id AS role_id, role_name, time_in, time_out
      FROM roles
      WHERE event_id = :eventId
      ORDER BY time_in, role_name
    ''', {'eventId': eventId});
    final list = [for (final row in r.rows) row.assoc()];
    return Response.ok(jsonEncode(list), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _createEventRole(Request req, String eventId) async {
  final body = await req.readAsString();
  if (body.isEmpty) return Response(400, body: 'Missing body');
  final data = jsonDecode(body) as Map<String, dynamic>;
  final name = (data['role_name'] ?? '').toString().trim();
  final timeIn = (data['time_in'] ?? '').toString();
  final timeOut = (data['time_out'] ?? '').toString();
  if (name.isEmpty) return Response(400, body: 'role_name required');

  MySQLConnection? conn;
  try {
    conn = await _connect();
    await conn.execute('''
      INSERT INTO roles (event_type_id, event_id, role_name, time_in, time_out)
      VALUES (NULL, :eventId, :name, :timeIn, :timeOut)
    ''', {'eventId': eventId, 'name': name, 'timeIn': timeIn, 'timeOut': timeOut});
    final idRes = await conn.execute('SELECT LAST_INSERT_ID() AS id');
    final newRoleId = idRes.rows.first.assoc()['id'];

    await conn.execute('''
      INSERT INTO event_volunteers (event_id, role_id, member_id)
      VALUES (:eventId, :roleId, NULL)
      ON DUPLICATE KEY UPDATE member_id = member_id
    ''', {'eventId': eventId, 'roleId': newRoleId.toString()});

    return Response(201, body: jsonEncode({'role_id': newRoleId}), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _updateEventRole(Request req, String eventId, String roleId) async {
  final body = await req.readAsString();
  if (body.isEmpty) return Response(400, body: 'Missing body');
  final data = jsonDecode(body) as Map<String, dynamic>;
  final name = (data['role_name'] ?? '').toString().trim();
  final timeIn = (data['time_in'] ?? '').toString();
  final timeOut = (data['time_out'] ?? '').toString();

  MySQLConnection? conn;
  try {
    conn = await _connect();
    final r = await conn.execute('''
      UPDATE roles
      SET role_name = :name, time_in = :timeIn, time_out = :timeOut
      WHERE id = :roleId AND event_id = :eventId
    ''', {'name': name, 'timeIn': timeIn, 'timeOut': timeOut, 'roleId': roleId, 'eventId': eventId});
    if ((r.affectedRows ?? 0) == 0) return Response.notFound('Role not found for this event');
    return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}

Future<Response> _deleteEventRole(Request req, String eventId, String roleId) async {
  MySQLConnection? conn;
  try {
    conn = await _connect();

    await conn.execute('DELETE FROM event_volunteers WHERE event_id = :eventId AND role_id = :roleId',
        {'eventId': eventId, 'roleId': roleId});

    final r = await conn.execute('DELETE FROM roles WHERE id = :roleId AND event_id = :eventId',
        {'roleId': roleId, 'eventId': eventId});
    if ((r.affectedRows ?? 0) == 0) return Response.notFound('Role not found for this event');

    return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(body: 'Error: $e');
  } finally {
    await conn?.close();
  }
}
// ...existing code...


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

        // Event-specific roles
        final rolesList = RegExp(r'^events/(\d+)/roles$').firstMatch(req.url.path);
        if (rolesList != null) {
          if (req.method == 'GET') return _listEventRoles(req, rolesList.group(1)!);
          if (req.method == 'POST') return _createEventRole(req, rolesList.group(1)!);
        }
        final roleDetail = RegExp(r'^events/(\d+)/roles/(\d+)$').firstMatch(req.url.path);
        if (roleDetail != null) {
          if (req.method == 'PUT') return _updateEventRole(req, roleDetail.group(1)!, roleDetail.group(2)!);
          if (req.method == 'DELETE') return _deleteEventRole(req, roleDetail.group(1)!, roleDetail.group(2)!);
        }
        final volunteer = RegExp(r'^events/(\d+)/volunteer$').firstMatch(req.url.path);
        if (req.method == 'POST' && volunteer != null) {
          return _assignVolunteer(req, volunteer.group(1)!);
        }
        
        // Email notifications
        final notify = RegExp(r'^events/(\d+)/notify$').firstMatch(req.url.path);
        if (req.method == 'POST' && notify != null) {
          return _notifyEventMembers(req, notify.group(1)!);
        }

        // Reference
        if (req.method == 'GET' && req.url.path == 'event_types') return _eventTypes(req);
        //if (req.method == 'GET' && req.url.path == 'event-types') return _eventTypes(req);
        if (req.method == 'GET' && req.url.path == 'clubs') return _clubs(req);

        return Response.notFound('Not Found');
      });

  final server = await io.serve(handler, 'localhost', 8080);
  stderr.writeln('✅ Server running on http://${server.address.host}:${server.port}');
}