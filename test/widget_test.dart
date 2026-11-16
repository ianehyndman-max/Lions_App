// App smoke tests.
//
// In widget tests Flutter replaces the real HTTP client with one that always
// returns HTTP 400, so pages that fetch data in initState (e.g. the club list
// on the onboarding page) deterministically take their error/empty path.
// These tests verify the app boots into the correct screen for both the
// first-run and the returning-user cases.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lions_app_3/main.dart';

void main() {
  testWidgets('shows onboarding page when no profile is stored',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const LionsApp(showOnboarding: true));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Lions Club'), findsOneWidget);
    expect(find.text('Select your club:'), findsOneWidget);
    // Continue button is disabled until a club and member are chosen.
    final continueButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
    expect(continueButton.onPressed, isNull);
  });

  testWidgets('shows main screen when a profile is stored',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'member_id': 1,
      'club_id': 1,
      'is_admin': false,
      'is_super': false,
      'is_conference_member': false,
    });

    await tester.pumpWidget(const LionsApp(showOnboarding: false));
    await tester.pumpAndSettle();

    expect(find.text('Lions Club'), findsWidgets);
    // Main navigation tabs are present.
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    // Reports action is hidden for non-admin members.
    expect(find.byTooltip('Reports'), findsNothing);
  });
}
