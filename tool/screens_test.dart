// Visual QA harness (not part of the test suite): renders key pages with real
// Windows fonts and saves PNG screenshots.
//
//   flutter test tool/screens_test.dart --dart-define=SHOTS=<folder>
//     [--dart-define=MODE=light|dark] [--dart-define=SIZE=1280x720]
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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
import 'package:storeflow_pos/features/backup/data/backup_service.dart';
import 'package:storeflow_pos/features/categories/data/category_repository.dart';
import 'package:storeflow_pos/features/backup/presentation/backup_settings.dart';
import 'package:storeflow_pos/features/credit/data/credit_service.dart';
import 'package:storeflow_pos/features/customers/data/customer_repository.dart';
import 'package:storeflow_pos/features/pos/data/checkout_service.dart';
import 'package:storeflow_pos/features/pos/domain/pos_cart.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';

import '../test/support/storeflow_fixture.dart';

const _out = String.fromEnvironment('SHOTS', defaultValue: 'shots');
const _mode = String.fromEnvironment('MODE', defaultValue: 'light');
const _size = String.fromEnvironment('SIZE', defaultValue: '1440x900');

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = File(file).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

/// Simple generated product "photos" so thumbnails appear in screenshots.
String _sampleImage(int seed) {
  const colors = [
    (0xF2, 0x6A, 0x1B),
    (0x25, 0x63, 0xEB),
    (0x16, 0xA3, 0x4A),
    (0x93, 0x33, 0xEA),
    (0xDB, 0x27, 0x77),
  ];
  final (r, g, b) = colors[seed % colors.length];
  final image = img.Image(width: 240, height: 240);
  img.fill(image, color: img.ColorRgb8(250, 248, 246));
  img.fillCircle(
    image,
    x: 120,
    y: 130,
    radius: 80,
    color: img.ColorRgb8(r, g, b),
  );
  img.fillRect(
    image,
    x1: 90,
    y1: 30,
    x2: 150,
    y2: 70,
    color: img.ColorRgb8(r ~/ 2, g ~/ 2, b ~/ 2),
  );
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}storeflow-shot-$seed.png',
  )..writeAsBytesSync(img.encodePng(image));
  return file.path;
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
    // Render as the Windows desktop app does (scrollbars, no primary
    // scroll controller sharing as on mobile).
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final dims = _size.split('x').map(double.parse).toList();
    await tester.binding.setSurfaceSize(Size(dims[0], dims[1]));
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'theme.mode': _mode});
    final preferences = await SharedPreferences.getInstance();
    final fixture = StoreFlowFixture();
    final owner = (await tester.runAsync(fixture.initialize))!;
    late String customerId;
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
            imagePath: i.isEven ? _sampleImage(i) : null,
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
      // A customer with credit sales, one overdue, and a payment.
      final categories = CategoryRepository(fixture.database);
      final grocery = await categories.save(
        session: owner,
        name: 'Grocery',
        code: 'GROC',
      );
      for (final (name, code) in const [('Rice', 'RICE'), ('Oil', 'OIL')]) {
        await categories.save(
          session: owner,
          name: name,
          code: code,
          parentId: grocery,
        );
      }
      await categories.save(session: owner, name: 'Pharmacy', code: 'PHAR');
      customerId = await CustomerRepository(fixture.database).save(
        session: owner,
        name: 'Bilal Traders',
        phone: '0300 1234567',
        creditLimit: 20000,
        openingBalance: 1500,
      );
      final rice = (await products.exactLookup(
        storeId: owner.store.id,
        code: 'SKU-102',
      ))!;
      for (final (qty, paid, days) in [(3, 500.0, -12), (2, 0.0, 10)]) {
        final result = await CheckoutService(fixture.database).checkout(
          session: owner,
          cart: PosCart(
            lines: [CartLine(catalogProduct: rice, quantityMilli: qty * 1000)],
            customerId: customerId,
          ),
          payments: [
            if (paid > 0)
              PaymentInput(method: 'cash', amount: Money.fromMajor(paid)),
          ],
          dueDate: DateTime.now().add(Duration(days: days.abs())),
        );
        if (days < 0) {
          await CreditService(fixture.database).setDueDate(
            owner,
            saleId: result.saleId,
            dueDate: DateTime.now().add(Duration(days: days)),
          );
        }
      }
      await CreditService(fixture.database).receivePayment(
        owner,
        customerId: customerId,
        amount: Money.fromMajor(1200),
        method: 'bank',
        reference: 'IBFT-88231',
      );
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
        File('$_out/$_mode-$_size-$name.png')
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
      '/customers',
      '/categories',
      '/stores',
    ]) {
      appRouter.go(route);
      await shot(route.substring(1));
    }

    // POS with a cart.
    appRouter.go('/pos');
    await settle();
    await tester.tap(find.text('Premium Tea 500g').first);
    await tester.tap(find.text('Basmati Rice 5kg').first);
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
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();

    // Settings tabs and parent categories.
    appRouter.go('/settings');
    await settle();
    await tester.tap(find.text('Checkout & tax'));
    await shot('settings-checkout');
    await tester.tap(find.text('Receipt designer'));
    await shot('settings-receipt');
    appRouter.go('/categories');
    await settle();
    await shot('categories-parents');
    await tester.tap(find.text('New sub-category'));
    await shot('category-editor');
    await tester.tap(find.text('Cancel').last);
    await settle();

    // Customer account screens.
    appRouter.go('/customers/$customerId');
    await shot('customer-detail');
    await tester.tap(find.text('Ledger'));
    await shot('customer-ledger');
    await tester.tap(find.text('Receive payment').first);
    await shot('receive-payment');
    await tester.tap(find.text('Cancel').last);
    await settle();

    appRouter.go('/receivables');
    await shot('receivables');

    appRouter.go('/reports');
    await settle();
    await tester.scrollUntilVisible(
      find.text('Outstanding receivables'),
      120,
      scrollable: find
          .ancestor(of: find.text('REPORTS'), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.text('Outstanding receivables'));
    await shot('report-receivables');

    // Credit checkout.
    appRouter.go('/pos');
    await settle();
    await tester.tap(find.text('Premium Tea 500g').first);
    await settle();
    await tester.tap(find.text('Pay').last);
    await settle();
    await tester.tap(find.text('Credit'));
    await shot('credit-checkout');
    await tester.tap(find.byTooltip('Cancel (Esc)'));
    await settle();

    // Data & backup and the restore confirmation.
    appRouter.go('/settings');
    await settle();
    await tester.tap(find.text('Data & backup'));
    await shot('backup');
    final context = tester.element(find.byType(BackupSettingsTab));
    showRestoreConfirmation(
      context,
      file: File(r'C:\Backups\StoreFlow-MAIN-20261003-101500.storeflowbackup'),
      manifest: BackupManifest(
        appVersion: '0.1.0',
        schemaVersion: 5,
        createdAt: DateTime(2026, 10, 3, 10, 15),
        createdBy: 'owner',
        kind: 'manual',
        stores: const [BackupStoreInfo('MAIN', 'Main Store')],
        databaseSha256:
            '9f2c4e1a7b3d5f60817263544a5b6c7d8e9f00112233445566778899aabbccdd',
        databaseSize: 4718592,
        assetCount: 3,
      ),
    );
    await shot('restore-confirm');
    await tester.tap(find.text('Cancel').last);
    await settle();

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    debugDefaultTargetPlatformOverride = null;
    await tester.runAsync(fixture.close);
  });
}
