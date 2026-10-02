// Visual QA harness (not part of the test suite): renders key pages with real
// Windows fonts and saves PNG screenshots.
//
//   flutter test tool/screens_test.dart --dart-define=SHOTS=<folder>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storeflow_pos/app/router.dart';
import 'package:storeflow_pos/app/storeflow_app.dart';
import 'package:storeflow_pos/core/database/database_provider.dart';
import 'package:storeflow_pos/core/money/money.dart';
import 'package:storeflow_pos/core/theme/theme_controller.dart';
import 'package:storeflow_pos/features/auth/application/session_controller.dart';
import 'package:storeflow_pos/features/pos/data/checkout_service.dart';
import 'package:storeflow_pos/features/pos/domain/pos_cart.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';

import '../test/support/storeflow_fixture.dart';

const _out = String.fromEnvironment('SHOTS', defaultValue: 'shots');
const _mode = String.fromEnvironment('MODE', defaultValue: 'light');

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = File(file).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screens', (tester) async {
    await tester.runAsync(() async {
      await _font('Segoe UI', [
        r'C:\Windows\Fonts\segoeui.ttf',
        r'C:\Windows\Fonts\segoeuib.ttf',
        r'C:\Windows\Fonts\seguisb.ttf',
      ]);
      await _font('MaterialIcons', [
        r'C:\src\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
      ]);
    });
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'theme.mode': _mode});
    final preferences = await SharedPreferences.getInstance();
    final fixture = StoreFlowFixture();
    final owner = (await tester.runAsync(fixture.initialize))!;
    await tester.runAsync(() async {
      final products = ProductRepository(fixture.database);
      final names = [
        'Premium Tea 500g',
        'Sugar 1kg',
        'Basmati Rice 5kg',
        'Cooking Oil 1L',
        'Biscuits Family Pack',
        'Mineral Water 1.5L',
        'Shampoo 200ml',
        'Toothpaste',
      ];
      for (var i = 0; i < names.length; i++) {
        final id = await products.save(
          session: owner,
          input: ProductInput(
            sku: 'SKU-${100 + i}',
            name: names[i],
            barcode: '89640001234${10 + i}',
            salePrice: 120.0 + i * 85,
            costPrice: 90.0 + i * 60,
            stockQty: i == 3 ? 2 : 20.0 + i,
            reorderLevel: 5,
            defaultDiscount: i == 1 ? 10 : 0,
          ),
        );
        if (i < 4) {
          final product = (await products.byId(
            storeId: owner.store.id,
            productId: id,
          ))!;
          await CheckoutService(fixture.database).checkout(
            session: owner,
            cart: PosCart(
              lines: [CartLine(catalogProduct: product, quantityMilli: 2000)],
            ),
            payments: [
              PaymentInput(method: 'cash', amount: Money.fromMajor(5000)),
            ],
          );
        }
      }
    });
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
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: UncontrolledProviderScope(
          container: container,
          child: const StoreFlowApp(),
        ),
      ),
    );
    Directory(_out).createSync(recursive: true);

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> shot(String name) async {
      await settle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/$_mode-$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    for (final route in const [
      '/dashboard',
      '/pos',
      '/history',
      '/inventory',
      '/products',
      '/reports',
      '/settings',
      '/purchases',
      '/cashbook',
      '/users',
    ]) {
      appRouter.go(route);
      await shot(route.substring(1));
    }

    // POS with a cart.
    appRouter.go('/pos');
    await settle();
    await tester.tap(find.text('Premium Tea 500g').first);
    await tester.tap(find.text('Sugar 1kg').first);
    await shot('pos-cart');

    // Product editor dialog.
    appRouter.go('/products');
    await settle();
    await tester.tap(find.text('New product'));
    await shot('product-editor');
    await tester.tap(find.text('Cancel').last);
    await settle();

    // Date range popover.
    appRouter.go('/history');
    await settle();
    await tester.tap(find.text('Today').first);
    await shot('date-range');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.runAsync(fixture.close);
  });
}
