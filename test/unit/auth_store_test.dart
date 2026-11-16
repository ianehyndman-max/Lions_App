// Tests for AuthStore profile persistence and role-flag normalization.
//
// The API returns permission flags in several shapes depending on the MySQL
// driver and column type: int (1/0), bool, string ('1'/'0'), or a BIT blob
// that decodes to a List ([1]/[0]). saveProfile must normalize all of them,
// since these flags gate every admin-only control in the UI.
// (onboarding_page.dart contains a duplicate of this normalization — gap A8
// in regression_suite_plan.md — so this file defines the expected behavior.)

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lions_app_3/auth_store.dart';

Map<String, dynamic> _profile({dynamic flagValue}) => {
      'id': '7',
      'lions_club_id': '3',
      'is_super': flagValue,
      'is_admin': flagValue,
      'is_conference_member': flagValue,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthStore.saveProfile flag normalization', () {
    for (final truthy in [1, true, '1', [1]]) {
      test('treats $truthy (${truthy.runtimeType}) as true', () async {
        await AuthStore.saveProfile(_profile(flagValue: truthy));

        expect(await AuthStore.isSuper(), isTrue);
        expect(await AuthStore.isAdmin(), isTrue);
        expect(await AuthStore.isConferenceMember(), isTrue);
      });
    }

    for (final falsy in [0, false, '0', null, <int>[], [0]]) {
      test('treats $falsy (${falsy.runtimeType}) as false', () async {
        await AuthStore.saveProfile(_profile(flagValue: falsy));

        expect(await AuthStore.isSuper(), isFalse);
        expect(await AuthStore.isAdmin(), isFalse);
        expect(await AuthStore.isConferenceMember(), isFalse);
      });
    }
  });

  group('AuthStore ids', () {
    test('stores and returns member and club ids', () async {
      await AuthStore.saveProfile(_profile(flagValue: 1));

      expect(await AuthStore.getMemberId(), 7);
      expect(await AuthStore.getClubId(), 3);
    });

    test('accepts numeric ids as well as strings', () async {
      await AuthStore.saveProfile({
        'id': 12,
        'lions_club_id': 4,
        'is_super': 0,
        'is_admin': 0,
        'is_conference_member': 0,
      });

      expect(await AuthStore.getMemberId(), 12);
      expect(await AuthStore.getClubId(), 4);
    });

    test('unparseable ids are stored as sentinel and read back as null',
        () async {
      await AuthStore.saveProfile({
        'id': 'not-a-number',
        'lions_club_id': null,
        'is_super': 0,
        'is_admin': 0,
        'is_conference_member': 0,
      });

      expect(await AuthStore.getMemberId(), isNull);
      expect(await AuthStore.getClubId(), isNull);
    });
  });

  group('AuthStore defaults with no stored profile', () {
    test('flags default to false and ids to null', () async {
      expect(await AuthStore.isSuper(), isFalse);
      expect(await AuthStore.isAdmin(), isFalse);
      expect(await AuthStore.isConferenceMember(), isFalse);
      expect(await AuthStore.getMemberId(), isNull);
      expect(await AuthStore.getClubId(), isNull);
    });
  });
}
