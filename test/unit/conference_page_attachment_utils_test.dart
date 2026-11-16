import 'package:flutter_test/flutter_test.dart';
import 'package:lions_app_3/conference_page.dart';

void main() {
  group('conference attachment URL helpers', () {
    test('prefers thumbnail storage keys when available', () {
      final url = buildConferenceAttachmentUrl(
        bucket: 'demo-bucket',
        storageKey: 'conference/sections/1/original.jpg',
        defaultS3Region: 'ap-southeast-2',
        thumbnailStorageKey: 'conference/sections/1/thumb.jpg',
      );

      expect(
        url,
        'https://demo-bucket.s3.ap-southeast-2.amazonaws.com/conference/sections/1/thumb.jpg',
      );
    });

    test('falls back to the main storage key when no thumbnail exists', () {
      final url = buildConferenceAttachmentUrl(
        bucket: 'demo-bucket',
        storageKey: 'conference/sections/1/original.jpg',
        defaultS3Region: 'ap-southeast-2',
      );

      expect(
        url,
        'https://demo-bucket.s3.ap-southeast-2.amazonaws.com/conference/sections/1/original.jpg',
      );
    });

    test('returns null for blank bucket or storage key and trims whitespace',
        () {
      expect(
        buildConferenceAttachmentUrl(
          bucket: '  ',
          storageKey: 'key.jpg',
          defaultS3Region: 'ap-southeast-2',
        ),
        isNull,
      );
      expect(
        buildConferenceAttachmentUrl(
          bucket: 'demo-bucket',
          storageKey: '   ',
          defaultS3Region: 'ap-southeast-2',
        ),
        isNull,
      );
      expect(
        buildConferenceAttachmentUrl(
          bucket: ' demo-bucket ',
          storageKey: ' key.jpg ',
          defaultS3Region: 'ap-southeast-2',
        ),
        'https://demo-bucket.s3.ap-southeast-2.amazonaws.com/key.jpg',
      );
    });
  });

  group('attachmentMimeFromFilename', () {
    test('maps allowed extensions case-insensitively', () {
      expect(attachmentMimeFromFilename('photo.jpg'), 'image/jpeg');
      expect(attachmentMimeFromFilename('PHOTO.JPG'), 'image/jpeg');
      expect(attachmentMimeFromFilename('scan.jpeg'), 'image/jpeg');
      expect(attachmentMimeFromFilename('logo.png'), 'image/png');
      expect(attachmentMimeFromFilename('agenda.pdf'), 'application/pdf');
      expect(attachmentMimeFromFilename('notes.txt'), 'text/plain');
      expect(
        attachmentMimeFromFilename('budget.xlsx'),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    });

    test('uses the last extension for dotted names', () {
      expect(attachmentMimeFromFilename('archive.tar.pdf'), 'application/pdf');
    });

    test('rejects missing or disallowed extensions', () {
      expect(attachmentMimeFromFilename('README'), isNull);
      expect(attachmentMimeFromFilename('malware.exe'), isNull);
      expect(attachmentMimeFromFilename('page.html'), isNull);
    });
  });

  group('formatAttachmentBytes', () {
    test('formats bytes, kilobytes and megabytes', () {
      expect(formatAttachmentBytes(0), '0 B');
      expect(formatAttachmentBytes(512), '512 B');
      expect(formatAttachmentBytes(1023), '1023 B');
      expect(formatAttachmentBytes(1024), '1.0 KB');
      expect(formatAttachmentBytes(1536), '1.5 KB');
      expect(formatAttachmentBytes(1024 * 1024 - 1), '1024.0 KB');
      expect(formatAttachmentBytes(1024 * 1024), '1.0 MB');
      expect(formatAttachmentBytes(10 * 1024 * 1024), '10.0 MB');
    });
  });
}
