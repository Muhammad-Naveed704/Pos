import 'package:flutter/material.dart';
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

  testWidgets('desktop shell renders dashboard, POS, and theme studio', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
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
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Today’s sales'), findsOneWidget);

    appRouter.go('/pos');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('Current sale'), findsOneWidget);
    expect(find.text('Pay'), findsOneWidget);
    expect(find.text('Cart is empty'), findsOneWidget);

    appRouter.go('/settings');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Colour mode'), findsOneWidget);
    expect(find.text('Business & regional'), findsOneWidget);

    appRouter.go('/history');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('Sales history'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(fixture.close);
    await tester.pump(const Duration(milliseconds: 1));
  });
}
