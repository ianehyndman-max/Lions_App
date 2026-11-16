// Integration tests for the conference feature: content, sections (nesting,
// reorder, archive/restore), attachments in mock presign mode (full
// presign -> upload -> register -> list -> download flow), and ideas.
//
// Permission model under test: every conference route requires an identity;
// editing requires super or conference-member (admins can view but NOT edit).

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

  // The two roles allowed to edit conference content.
  const editors = [Fixtures.superId, Fixtures.conferenceId];

  Future<Map<String, dynamic>> getConference(
      {int as = Fixtures.memberId, bool includeArchived = false}) async {
    final res = await api.get(
        '/conference${includeArchived ? '?include_archived=true' : ''}',
        as: as);
    expect(res.statusCode, 200, reason: 'GET /conference failed: ${res.body}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<String> createSection(String title,
      {int as = Fixtures.conferenceId, Object? parentId, int? sortOrder}) async {
    final res = await api.post('/conference_sections', as: as, body: {
      'section_title': title,
      'section_body': '$title body',
      if (parentId != null) 'parent_id': parentId,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
    expect(res.statusCode, 201, reason: 'create section failed: ${res.body}');
    return jsonDecode(res.body)['id'].toString();
  }

  group('conference content', () {
    test('all conference routes require an identity', () async {
      expect((await api.get('/conference')).statusCode, 401);
      expect((await api.put('/conference', body: {'title': 'X'})).statusCode,
          401);
      expect(
          (await api.post('/conference_sections', body: {'section_title': 'X'}))
              .statusCode,
          401);
      expect((await api.get('/conference_ideas')).statusCode, 401);
    });

    test('returns an empty default document before any save', () async {
      final doc = await getConference();
      expect(doc['id'], isNull);
      expect(doc['title'], 'Conference');
      expect(doc['sections'], isEmpty);
    });

    test('only super or conference members can save (admins cannot)',
        () async {
      for (final who in [Fixtures.memberId, Fixtures.adminId]) {
        final res =
            await api.put('/conference', as: who, body: {'title': 'Nope'});
        expect(res.statusCode, 403, reason: 'member $who must not edit');
      }
    });

    test('saves and re-saves the single conference document', () async {
      final created = await api.put('/conference', as: Fixtures.conferenceId, body: {
        'title': 'Convention 2027',
        'theme': 'Service',
        'general_notes': 'First draft',
      });
      expect(created.statusCode, 200);
      final conferenceId = jsonDecode(created.body)['id'];

      var doc = await getConference();
      expect(doc['title'], 'Convention 2027');
      expect(doc['theme'], 'Service');
      expect(doc['last_updated_by_name'], 'Carl Conference');

      // A second save updates the same document rather than creating another.
      final updated = await api.put('/conference', as: Fixtures.superId, body: {
        'title': 'Convention 2027 v2',
      });
      expect(jsonDecode(updated.body)['id'], conferenceId);

      doc = await getConference();
      expect(doc['title'], 'Convention 2027 v2');
      expect(doc['last_updated_by_name'], 'Sue Super');
    });
  });

  group('conference sections', () {
    test('create validates title and permissions', () async {
      expect(
          (await api.post('/conference_sections',
                  as: Fixtures.adminId, body: {'section_title': 'X'}))
              .statusCode,
          403);
      expect(
          (await api.post('/conference_sections',
                  as: Fixtures.conferenceId, body: {'section_title': '  '}))
              .statusCode,
          400);
      expect(
          (await api.post('/conference_sections', as: Fixtures.conferenceId, body: {
            'section_title': 'X',
            'parent_id': 'abc',
          }))
              .statusCode,
          400);
      expect(
          (await api.post('/conference_sections', as: Fixtures.conferenceId, body: {
            'section_title': 'X',
            'parent_id': 9999,
          }))
              .statusCode,
          400);
    });

    test('assigns per-level sort orders and nests children', () async {
      final rootA = await createSection('Root A');
      final rootB = await createSection('Root B');
      final child = await createSection('Child A1', parentId: rootA);

      final sections = (await getConference())['sections'] as List;
      final byId = {for (final s in sections) s['id'].toString(): s};

      expect(byId[rootA]!['sort_order'].toString(), '0');
      expect(byId[rootB]!['sort_order'].toString(), '1');
      // Children restart their own ordering under the parent.
      expect(byId[child]!['sort_order'].toString(), '0');
      expect(byId[child]!['parent_id'].toString(), rootA);
    });

    test('update renames, changes status, and rejects invalid statuses',
        () async {
      final id = await createSection('Original');

      expect(
          (await api.put('/conference_sections/9999',
                  as: Fixtures.conferenceId, body: {'section_title': 'X'}))
              .statusCode,
          404);
      expect(
          (await api.put('/conference_sections/$id',
                  as: Fixtures.conferenceId, body: {'status': 'bogus'}))
              .statusCode,
          400);

      final res = await api.put('/conference_sections/$id',
          as: Fixtures.conferenceId,
          body: {'section_title': 'Renamed', 'status': 'approved'});
      expect(res.statusCode, 200);

      final section =
          ((await getConference())['sections'] as List).single;
      expect(section['section_title'], 'Renamed');
      expect(section['status'], 'approved');
    });

    test('rejects self-parenting and circular nesting', () async {
      final a = await createSection('A');
      final b = await createSection('B', parentId: a);

      expect(
          (await api.put('/conference_sections/$a',
                  as: Fixtures.conferenceId, body: {'parent_id': a}))
              .statusCode,
          400);
      // A -> B -> A would be a cycle.
      expect(
          (await api.put('/conference_sections/$a',
                  as: Fixtures.conferenceId, body: {'parent_id': b}))
              .statusCode,
          400);
    });

    test('DELETE archives instead of destroying; restore brings it back',
        () async {
      final id = await createSection('Disposable');

      final del = await api.delete('/conference_sections/$id',
          as: Fixtures.conferenceId);
      expect(del.statusCode, 200);
      expect(jsonDecode(del.body)['archived'], true);

      // Hidden by default, visible with include_archived.
      expect((await getConference())['sections'], isEmpty);
      final archived =
          (await getConference(as: Fixtures.superId, includeArchived: true))[
              'sections'] as List;
      expect(archived.single['status'], 'archived');

      final restore = await api.put('/conference_sections/$id/restore',
          as: Fixtures.conferenceId);
      expect(restore.statusCode, 200);

      final sections = (await getConference())['sections'] as List;
      expect(sections.single['status'], 'draft');
      expect(sections.single['archived_at'], isNull);
    });

    test('reorder swaps section positions transactionally', () async {
      final first = await createSection('First');
      final second = await createSection('Second');

      expect(
          (await api.put('/conference_sections/reorder',
                  as: Fixtures.conferenceId, body: {'section_orders': 'nope'}))
              .statusCode,
          400);

      final res = await api.put('/conference_sections/reorder',
          as: Fixtures.conferenceId,
          body: {
            'section_orders': [
              {'section_id': first, 'sort_order': 1},
              {'section_id': second, 'sort_order': 0},
            ],
          });
      expect(res.statusCode, 200);
      expect(jsonDecode(res.body)['updated'], 2);

      final sections = (await getConference())['sections'] as List;
      expect(sections.map((s) => s['section_title']), ['Second', 'First']);
    });
  });

  group('conference attachments (mock mode)', () {
    late String sectionId;

    setUp(() async {
      sectionId = await createSection('With attachments');
    });

    Map<String, dynamic> presignBody({
      String filename = 'photo.png',
      String mime = 'image/png',
      int size = 1024,
    }) =>
        {'filename': filename, 'mime_type': mime, 'file_size_bytes': size};

    test('presign validates permissions, mime type, and size caps', () async {
      expect(
          (await api.post('/conference_sections/$sectionId/attachments/presign',
                  body: presignBody()))
              .statusCode,
          401);
      expect(
          (await api.post('/conference_sections/$sectionId/attachments/presign',
                  as: Fixtures.adminId, body: presignBody()))
              .statusCode,
          403);
      expect(
          (await api.post('/conference_sections/$sectionId/attachments/presign',
                  as: Fixtures.conferenceId,
                  body: presignBody(filename: 'virus.exe', mime: 'application/x-msdownload')))
              .statusCode,
          400);
      expect(
          (await api.post('/conference_sections/$sectionId/attachments/presign',
                  as: Fixtures.conferenceId,
                  body: presignBody(size: 20 * 1024 * 1024)))
              .statusCode,
          413);
      expect(
          (await api.post('/conference_sections/9999/attachments/presign',
                  as: Fixtures.conferenceId, body: presignBody()))
              .statusCode,
          404);
    });

    test('full mock flow: presign, upload, register, list, download',
        () async {
      // 1. Presign.
      final presign = await api.post(
          '/conference_sections/$sectionId/attachments/presign',
          as: Fixtures.conferenceId,
          body: presignBody(filename: 'minutes.txt', mime: 'text/plain'));
      expect(presign.statusCode, 200);
      final grant = jsonDecode(presign.body) as Map<String, dynamic>;
      expect(grant['is_mock'], true);
      expect(grant['bucket'], 'local-mock');
      final storageKey = grant['storage_key'] as String;
      expect(storageKey, startsWith('conference/sections/$sectionId/'));

      // 2. Upload bytes to the mock URL.
      final content = utf8.encode('Meeting minutes: all agreed.');
      final upload = await api.putBytes(
          grant['upload_url'] as String, content,
          contentType: 'text/plain');
      expect(upload.statusCode, 200);
      expect(jsonDecode(upload.body)['size_bytes'], content.length);

      // 3. Register the attachment record.
      final register = await api.post(
          '/conference_sections/$sectionId/attachments',
          as: Fixtures.conferenceId,
          body: {
            'storage_key': storageKey,
            'original_filename': 'minutes.txt',
            'mime_type': 'text/plain',
            'file_size_bytes': content.length,
          });
      expect(register.statusCode, 201);

      // 4. List: any member sees it, with a signed download URL.
      final list = await api.get(
          '/conference_sections/$sectionId/attachments',
          as: Fixtures.memberId);
      expect(list.statusCode, 200);
      final items = jsonDecode(list.body)['items'] as List;
      expect(items, hasLength(1));
      final item = items.single as Map<String, dynamic>;
      expect(item['original_filename'], 'minutes.txt');
      expect(item['file_kind'], 'document');
      final downloadUrl = item['download_url'] as String;

      // 5. Download using only the signed URL (no auth header).
      final download = await api.get(downloadUrl);
      expect(download.statusCode, 200);
      expect(download.body, 'Meeting minutes: all agreed.');
      expect(download.headers['content-type'], contains('text/plain'));
    });

    test('mock upload rejects mismatched storage keys and empty bodies',
        () async {
      final otherSection = await createSection('Other');
      final res = await api.putBytes(
          '/conference_sections/$sectionId/attachments/mock_upload'
          '?storage_key=conference/sections/$otherSection/x.txt',
          utf8.encode('data'));
      expect(res.statusCode, 400);

      final empty = await api.putBytes(
          '/conference_sections/$sectionId/attachments/mock_upload'
          '?storage_key=conference/sections/$sectionId/x.txt',
          const []);
      expect(empty.statusCode, 400);
    });

    test('register validates mime, section, and required fields', () async {
      expect(
          (await api.post('/conference_sections/$sectionId/attachments',
                  as: Fixtures.conferenceId,
                  body: {'storage_key': 'k', 'original_filename': 'f'}))
              .statusCode,
          400);
      expect(
          (await api.post('/conference_sections/9999/attachments',
                  as: Fixtures.conferenceId,
                  body: {
                'storage_key': 'conference/sections/9999/x.txt',
                'original_filename': 'x.txt',
                'mime_type': 'text/plain',
                'file_size_bytes': 10,
              }))
              .statusCode,
          404);
    });

    test('archive hides an attachment from members; restore returns it',
        () async {
      // Register a record directly (no upload needed for listing behavior).
      final register = await api.post(
          '/conference_sections/$sectionId/attachments',
          as: Fixtures.conferenceId,
          body: {
            'storage_key': 'conference/sections/$sectionId/old.pdf',
            'original_filename': 'old.pdf',
            'mime_type': 'application/pdf',
            'file_size_bytes': 100,
          });
      final attachmentId = jsonDecode(register.body)['id'].toString();

      // Members may not request archived listings.
      expect(
          (await api.get(
                  '/conference_sections/$sectionId/attachments?include_archived=true',
                  as: Fixtures.memberId))
              .statusCode,
          403);

      final archive = await api.put(
          '/conference_sections/$sectionId/attachments/$attachmentId/archive',
          as: Fixtures.conferenceId);
      expect(archive.statusCode, 200);

      final memberList = jsonDecode((await api.get(
              '/conference_sections/$sectionId/attachments',
              as: Fixtures.memberId))
          .body)['items'] as List;
      expect(memberList, isEmpty);

      final editorList = jsonDecode((await api.get(
              '/conference_sections/$sectionId/attachments?include_archived=true',
              as: Fixtures.superId))
          .body)['items'] as List;
      expect(editorList.single['status'], 'archived');

      final restore = await api.put(
          '/conference_sections/$sectionId/attachments/$attachmentId/restore',
          as: Fixtures.conferenceId);
      expect(restore.statusCode, 200);

      final restored = jsonDecode((await api.get(
              '/conference_sections/$sectionId/attachments',
              as: Fixtures.memberId))
          .body)['items'] as List;
      expect(restored.single['status'], 'active');
    });

    test('reorder swaps attachment positions', () async {
      Future<String> register(String name) async {
        final res = await api.post(
            '/conference_sections/$sectionId/attachments',
            as: Fixtures.conferenceId,
            body: {
              'storage_key': 'conference/sections/$sectionId/$name',
              'original_filename': name,
              'mime_type': 'application/pdf',
              'file_size_bytes': 100,
            });
        return jsonDecode(res.body)['id'].toString();
      }

      final first = await register('a.pdf');
      final second = await register('b.pdf');

      final res = await api.put(
          '/conference_sections/$sectionId/attachments/reorder',
          as: Fixtures.conferenceId,
          body: {
            'attachment_orders': [
              {'attachment_id': first, 'sort_order': 1},
              {'attachment_id': second, 'sort_order': 0},
            ],
          });
      expect(res.statusCode, 200);

      final items = jsonDecode((await api.get(
              '/conference_sections/$sectionId/attachments',
              as: Fixtures.memberId))
          .body)['items'] as List;
      expect(items.map((i) => i['original_filename']), ['b.pdf', 'a.pdf']);
    });
  });

  group('conference ideas', () {
    test('any member can submit an idea; title is required', () async {
      expect(
          (await api.post('/conference_ideas',
                  as: Fixtures.memberId, body: {'title': '  '}))
              .statusCode,
          400);

      final res = await api.post('/conference_ideas',
          as: Fixtures.memberId,
          body: {
            'title': 'Karaoke night',
            'description': 'Fun fundraiser',
            'category': 'social',
          });
      expect(res.statusCode, 201);

      final ideas = jsonDecode(
              (await api.get('/conference_ideas', as: Fixtures.adminId)).body)
          as List;
      expect(ideas.single['title'], 'Karaoke night');
      expect(ideas.single['status'], 'new');
      expect(ideas.single['created_by_name'], 'Mel Member');
    });

    test('status updates: owner or conference team only, aliases normalized',
        () async {
      final created = await api.post('/conference_ideas',
          as: Fixtures.memberId, body: {'title': 'Karaoke night'});
      final ideaId = jsonDecode(created.body)['id'].toString();

      expect(
          (await api.put('/conference_ideas/$ideaId/status',
                  as: Fixtures.conferenceId, body: {'status': 'bogus'}))
              .statusCode,
          400);
      // Admin is neither owner nor conference team.
      expect(
          (await api.put('/conference_ideas/$ideaId/status',
                  as: Fixtures.adminId, body: {'status': 'accepted'}))
              .statusCode,
          403);

      // Owner may update; alias 'approved' normalizes to 'accepted'.
      final res = await api.put('/conference_ideas/$ideaId/status',
          as: Fixtures.memberId, body: {'status': 'approved'});
      expect(res.statusCode, 200);

      final ideas = jsonDecode(
              (await api.get('/conference_ideas', as: Fixtures.memberId)).body)
          as List;
      expect(ideas.single['status'], 'accepted');
    });

    test('only the conference team can delete ideas', () async {
      final created = await api.post('/conference_ideas',
          as: Fixtures.memberId, body: {'title': 'Karaoke night'});
      final ideaId = jsonDecode(created.body)['id'].toString();

      // Even the owner cannot delete.
      expect(
          (await api.delete('/conference_ideas/$ideaId', as: Fixtures.memberId))
              .statusCode,
          403);
      expect(
          (await api.delete('/conference_ideas/9999', as: Fixtures.superId))
              .statusCode,
          404);

      for (final editor in editors) {
        // Re-create for the second editor pass if needed.
        final res =
            await api.delete('/conference_ideas/$ideaId', as: editor);
        expect(res.statusCode, anyOf(204, 404));
      }

      expect(
          jsonDecode(
              (await api.get('/conference_ideas', as: Fixtures.memberId)).body),
          isEmpty);
    });
  });
}
