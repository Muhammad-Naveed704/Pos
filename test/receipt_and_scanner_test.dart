import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/features/pos/presentation/barcode_scanner.dart';
import 'package:storeflow_pos/features/receipts/data/receipt_service.dart';
import 'package:storeflow_pos/features/settings/domain/business_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('receipt PDF', () {
    // Regression: roll paper has infinite height and used to crash MultiPage.
    for (final paper in ReceiptPaper.values) {
      test('renders ${paper.name}', () async {
        final settings =
            const BusinessSettings(
              businessName: 'Test Traders',
              taxNumber: 'NTN-123',
              receiptFooter: 'Thanks',
            ).copyWith(
              receipt: ReceiptLayout(
                paper: paper,
                policy: 'Exchange within 7 days.',
                website: 'example.com',
                showSku: true,
              ),
            );
        final bytes = await buildReceiptPdf(ReceiptData.sample(settings));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      });
    }

    test('non Latin-1 currency symbols render', () async {
      const settings = BusinessSettings(
        businessName: 'Dhaka Mart',
        currencyCode: 'BDT',
      );
      final bytes = await buildReceiptPdf(ReceiptData.sample(settings));
      expect(bytes, isNotEmpty);
    });

    test('receipt layout round-trips through the settings map', () {
      const layout = ReceiptLayout(
        paper: ReceiptPaper.a4,
        fontSize: ReceiptFontSize.large,
        policy: 'No refunds',
        showBarcode: false,
      );
      final restored = BusinessSettings.fromMap(
        const BusinessSettings(receipt: layout).toMap(),
      ).receipt;
      expect(restored.paper, ReceiptPaper.a4);
      expect(restored.fontSize, ReceiptFontSize.large);
      expect(restored.policy, 'No refunds');
      expect(restored.showBarcode, isFalse);
    });
  });

  group('scanner buffer', () {
    KeyDownEvent key(LogicalKeyboardKey logical, [String? character]) =>
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: logical,
          character: character,
          timeStamp: Duration.zero,
        );

    test('a burst ending with Enter is delivered as a scan', () {
      String? scanned;
      final buffer = ScannerKeyBuffer(
        isActive: () => true,
        onScan: (code) => scanned = code,
        onTyped: (_) => fail('should not be treated as typing'),
      );
      for (final char in '8964000123'.split('')) {
        expect(buffer.handle(key(LogicalKeyboardKey.digit0, char)), isTrue);
      }
      expect(buffer.handle(key(LogicalKeyboardKey.enter)), isTrue);
      expect(scanned, '8964000123');
      expect(buffer.hasPending, isFalse);
    });

    test('typing without Enter becomes search text after a pause', () async {
      String? typed;
      final buffer = ScannerKeyBuffer(
        isActive: () => true,
        onScan: (_) => fail('should not be a scan'),
        onTyped: (text) => typed = text,
        humanTimeout: const Duration(milliseconds: 20),
      );
      buffer.handle(key(LogicalKeyboardKey.keyT, 't'));
      buffer.handle(key(LogicalKeyboardKey.keyE, 'e'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(typed, 'te');
    });

    test('nothing is captured while inactive', () {
      final buffer = ScannerKeyBuffer(
        isActive: () => false,
        onScan: (_) => fail('inactive'),
        onTyped: (_) => fail('inactive'),
      );
      expect(buffer.handle(key(LogicalKeyboardKey.keyA, 'a')), isFalse);
      expect(buffer.handle(key(LogicalKeyboardKey.enter)), isFalse);
    });
  });
}
