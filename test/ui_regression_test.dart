import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storeflow_pos/app/router.dart';
import 'package:storeflow_pos/app/storeflow_app.dart';
import 'package:storeflow_pos/core/database/database_provider.dart';
import 'package:storeflow_pos/core/theme/theme_controller.dart';
import 'package:storeflow_pos/features/auth/application/session_controller.dart';

import 'support/storeflow_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(StoreFlowFixture, ProviderContainer)> boot(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final fixture = StoreFlowFixture();
    await tester.runAsync(fixture.initialize);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(fixture.database),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    await tester.runAsync(
      () => container
          .read(sessionControllerProvider.notifier)
          .login('owner', 'test-password'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const StoreFlowApp(),
      ),
    );
    return (fixture, container);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('categories: create a main category, then a sub-category '
      'inside it from the dropdown', (tester) async {
    final (fixture, container) = await boot(tester);
    appRouter.go('/categories');
    await settle(tester);
    Finder dialogField() => find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .first;

    await tester.tap(find.text('Create first category'));
    await settle(tester);
    await tester.enterText(dialogField(), 'Grocery');
    await tester.tap(find.text('Create'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Grocery'), findsWidgets);

    // The sub-category dialog offers the main category in its dropdown and
    // pre-selects the one being viewed.
    await tester.tap(find.text('New sub-category'));
    await settle(tester);
    expect(find.text('New sub-category'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextField, 'Grocery'),
      ),
      findsOneWidget,
    );
    final nameField = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .at(1);
    await tester.enterText(nameField, 'Rice');
    await tester.tap(find.text('Create'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('1 sub · 0 products'), findsOneWidget);

    // A duplicate main category is refused with a clear message.
    await tester.tap(find.text('New category').first);
    await settle(tester);
    await tester.enterText(dialogField(), 'grocery');
    await tester.tap(find.text('Create'));
    await settle(tester);
    expect(find.textContaining('already exists'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(fixture.close);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('F2 in the POS search opens the camera scanner', (tester) async {
    final (fixture, container) = await boot(tester);
    appRouter.go('/pos');
    await settle(tester);
    // First F2 focuses the search box, the second opens the scanner.
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);
    expect(find.text('Scan product'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(fixture.close);
    await tester.pump(const Duration(milliseconds: 1));
  });
}
