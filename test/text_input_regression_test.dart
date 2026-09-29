import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storeflow_pos/app/storeflow_app.dart';
import 'package:storeflow_pos/core/database/database_provider.dart';
import 'package:storeflow_pos/core/theme/theme_controller.dart';
import 'package:storeflow_pos/core/theme/theme_settings.dart';

import 'support/storeflow_fixture.dart';

/// Screens shown by the application gate (setup, login, lock) live above the
/// router's Navigator. They previously had no Overlay, which broke text
/// editing (deleted text reappeared) and stopped dropdowns from opening.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(StoreFlowFixture, ProviderContainer)> pumpApp(
    WidgetTester tester, {
    required bool setUpBusiness,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final fixture = StoreFlowFixture();
    if (setUpBusiness) await tester.runAsync(fixture.initialize);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(fixture.database),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const StoreFlowApp(),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 100));
    }
    return (fixture, container);
  }

  Future<void> teardown(
    WidgetTester tester,
    StoreFlowFixture fixture,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(fixture.close);
  }

  testWidgets('login fields keep edits after delete and retype', (
    tester,
  ) async {
    final (fixture, container) = await pumpApp(tester, setUpBusiness: true);
    expect(find.text('Welcome back'), findsOneWidget);

    final username = find.byType(TextFormField).first;
    await tester.enterText(username, 'old-user');
    await tester.pump();
    await tester.enterText(username, '');
    await tester.pump();
    await tester.enterText(username, 'new');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('new'), findsOneWidget);
    expect(find.text('old-user'), findsNothing);
    await teardown(tester, fixture, container);
  });

  testWidgets('setup wizard fields and dropdowns work above the router', (
    tester,
  ) async {
    final (fixture, container) = await pumpApp(tester, setUpBusiness: false);
    expect(find.text('Set up StoreFlow'), findsOneWidget);

    final business = find.byType(TextField).first;
    await tester.enterText(business, 'Old Name');
    await tester.pump();
    await tester.enterText(business, '');
    await tester.pump();
    await tester.enterText(business, 'Fontwala Traders');
    await tester.pump();
    expect(find.text('Fontwala Traders'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Step 2 must not inherit the business-name text.
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Fontwala Traders'), findsNothing);
    expect(tester.takeException(), isNull);
    await teardown(tester, fixture, container);
  });

  testWidgets('legacy theme preferences migrate without crashing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'theme.palette': 'emerald',
      'theme.density': 'not-a-density',
      'theme.font': 'Roboto',
    });
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    final settings = container.read(themeControllerProvider);
    expect(settings.preset, ThemePreset.emerald);
    expect(settings.density, AppDensity.comfortable);
    // Roboto is not installed on Windows; fall back to a system font.
    expect(settings.fontFamily, 'Segoe UI');
  });
}
