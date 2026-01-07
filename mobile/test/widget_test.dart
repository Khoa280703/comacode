// Comacode widget tests
//
// Phase 04: Mobile App
// Basic widget test for Comacode app

import 'package:flutter_test/flutter_test.dart';

import 'package:comacode/main.dart';

void main() {
  testWidgets('ComacodeApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ComacodeApp());

    // Verify that the app title is displayed.
    expect(find.text('Comacode'), findsOneWidget);

    // Verify that "Connect to Host" text is present.
    expect(find.text('Connect to Host'), findsOneWidget);
  });
}
