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
  });
}
