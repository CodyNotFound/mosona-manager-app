// This is a basic Flutter widget test for the Mosona Manager app.
//
// It verifies the Riverpod-driven counter increments when the forui button is
// tapped.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosona_manager/app.dart';

void main() {
  testWidgets('Counter increments when the button is tapped',
      (WidgetTester tester) async {
    // Build the app inside a ProviderScope (required by Riverpod).
    await tester.pumpWidget(const ProviderScope(child: MosonaManagerApp()));

    // The counter starts at 0.
    expect(find.text('0'), findsOneWidget);

    // Tap the "Increment" button and settle any animations.
    await tester.tap(find.text('Increment'));
    await tester.pumpAndSettle();

    // The counter should now show 1.
    expect(find.text('1'), findsOneWidget);
  });
}
