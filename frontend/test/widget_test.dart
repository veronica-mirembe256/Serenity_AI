// frontend/test/widget_test.dart
//
// FIX: The default Flutter counter template referenced `MyApp` and
// `find.text('0')` — neither of which exist in this project.
// Replaced with a smoke test that verifies SerenityApp mounts without
// throwing, which is the minimum meaningful test for this codebase.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenity/main.dart';   // exports SerenityApp

void main() {
  testWidgets('SerenityApp mounts without throwing', (WidgetTester tester) async {
    // Pump the real app root.
    await tester.pumpWidget(const SerenityApp());

    // The app should render at least one widget in the tree.
    // This confirms the widget hierarchy builds without errors.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}