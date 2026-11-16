// Contract tests for the email templates in lions_api/templates/.
//
// The API's _renderTemplate (bin/lions_api.dart) substitutes {{variable}}
// placeholders into these files. These tests guard against templates being
// renamed, deleted, or having placeholders drift out of sync with what the
// API provides when sending event emails.

import 'dart:io';

import 'package:test/test.dart';

const _templatesDir = 'templates';

// Every subject/body pair the API renders, with the placeholders each file
// is expected to contain.
const _expectedTemplates = <String, List<String>>{
  'new_event_subject.txt': ['club_name'],
  'new_event_body.html': [
    'club_name',
    'event_type',
    'event_date',
    'location',
    'notes',
    'roles_html',
    'calendar_link',
  ],
  'assigned_reminder_subject.txt': ['club_name'],
  'assigned_reminder_body.html': [
    'club_name',
    'event_type',
    'event_date',
    'location',
    'notes',
    'roles_html',
    'calendar_link',
  ],
  'resend_unfilled_subject.txt': ['club_name'],
  'resend_unfilled_body.html': [
    'club_name',
    'event_type',
    'event_date',
    'location',
    'notes',
    'roles_html',
    'calendar_link',
  ],
};

final _placeholderPattern = RegExp(r'\{\{([a-z_]+)\}\}');

void main() {
  group('email templates', () {
    for (final entry in _expectedTemplates.entries) {
      final fileName = entry.key;
      final expectedPlaceholders = entry.value;

      test('$fileName exists and contains its expected placeholders', () {
        final file = File('$_templatesDir/$fileName');
        expect(file.existsSync(), isTrue,
            reason: 'Template $fileName is missing; the API will fall back '
                'to a generic hardcoded email.');

        final content = file.readAsStringSync();
        final found = _placeholderPattern
            .allMatches(content)
            .map((m) => m.group(1))
            .toSet();

        for (final placeholder in expectedPlaceholders) {
          expect(found, contains(placeholder),
              reason: 'Template $fileName no longer contains '
                  '{{$placeholder}}; emails will render without this value.');
        }

        // No unknown placeholders: anything not supplied by the API would be
        // sent to members as literal {{text}}.
        expect(found.difference(expectedPlaceholders.toSet()), isEmpty,
            reason: 'Template $fileName contains placeholders the API does '
                'not substitute.');
      });
    }

    test('body templates are non-trivial HTML', () {
      for (final fileName in _expectedTemplates.keys) {
        if (!fileName.endsWith('.html')) continue;
        final content = File('$_templatesDir/$fileName').readAsStringSync();
        expect(content, contains('<'),
            reason: '$fileName does not look like HTML.');
        expect(content.trim().length, greaterThan(100),
            reason: '$fileName looks suspiciously empty.');
      }
    });
  });
}
