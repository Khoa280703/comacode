// Comacode widget tests
//
// Phase 04: Mobile App
// Phase 06: Riverpod update - wrap test with ProviderScope

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:comacode/main.dart';

void main() {
  testWidgets('ComacodeApp smoke test', (WidgetTester tester) async {
    // Wrap with ProviderScope for Riverpod
    await tester.pumpWidget(
      const ProviderScope(
        child: ComacodeApp(),
      ),
    );

    // Trigger a frame after ProviderScope is set up
    await tester.pumpAndSettle();

    // Verify that the app title is displayed.
    expect(find.text('Comacode'), findsOneWidget);

    // Verify that "Vibe Coding" text is present (HomePage title + button).
    expect(find.text('Vibe Coding'), findsWidgets);
  });
}
