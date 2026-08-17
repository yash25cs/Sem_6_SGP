// Smoke tests for the two things that render before any network call happens.
//
// `flutter test` runs without `--dart-define`, so `SupabaseConfig.isConfigured`
// is false and `StudyTrailApp` deliberately shows the config screen rather than
// the onboarding flow (see main.dart). Pumping the app and expecting the welcome
// headline is therefore the wrong assertion — the welcome screen is pumped on
// its own instead, which also keeps this file clear of `Supabase.initialize`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/config/supabase_config.dart';
import 'package:studytrail_flutter/main.dart';
import 'package:studytrail_flutter/screens/welcome_screen.dart';
import 'package:studytrail_flutter/theme/app_theme.dart';

void main() {
  testWidgets('Welcome screen renders its headline and Next action',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const WelcomeScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Turn your exams\ninto a plan.'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('App boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const StudyTrailApp());
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);

    // Guarded rather than asserted flat: a run with
    // `--dart-define-from-file=dart_define.json` produces a configured build,
    // and that branch needs a live Supabase, so there is nothing to check here.
    if (!SupabaseConfig.isConfigured) {
      expect(find.text('Backend not configured'), findsOneWidget);
    }
  });
}
