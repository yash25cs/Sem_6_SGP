// Smoke test for the StudyTrail app: it boots to the onboarding welcome screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:studytrail_flutter/main.dart';

void main() {
  testWidgets('App boots to the welcome screen', (WidgetTester tester) async {
    await tester.pumpWidget(const StudyTrailApp());
    await tester.pumpAndSettle();

    // The onboarding welcome headline and its Next action are present.
    expect(find.text('Turn your exams\ninto a plan.'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });
}
