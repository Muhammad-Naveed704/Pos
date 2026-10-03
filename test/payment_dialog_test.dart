import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/money/currency.dart';
import 'package:storeflow_pos/core/money/money.dart';
import 'package:storeflow_pos/core/money/money_format.dart';
import 'package:storeflow_pos/core/theme/app_theme.dart';
import 'package:storeflow_pos/core/theme/theme_settings.dart';
import 'package:storeflow_pos/features/pos/presentation/payment_dialog.dart';

void main() {
  final money = MoneyFormatter(currency: Currencies.byCode('PKR'));

  Future<PaymentDecision?> open(
    WidgetTester tester, {
    bool allowCredit = true,
    CreditCustomer? customer,
    Future<CreditCustomer?> Function()? onPick,
    required Future<void> Function() interact,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    PaymentDecision? decision;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(const ThemeSettings()),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  decision = await showPaymentDialog(
                    context,
                    total: Money.fromMajor(1000),
                    money: money,
                    denominations: const [1000, 5000],
                    allowCredit: allowCredit,
                    customer: customer,
                    onPickCustomer: onPick,
                  );
                  closed = true;
                },
                child: const Text('Pay'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    await interact();
    await tester.pumpAndSettle();
    expect(closed, isTrue, reason: 'dialog should have closed');
    return decision;
  }

  testWidgets('pay in full stays the default and hides credit without '
      'permission', (tester) async {
    final decision = await open(
      tester,
      allowCredit: false,
      interact: () async {
        expect(find.text('Credit'), findsNothing);
        await tester.tap(find.text('Complete sale'));
      },
    );
    expect(decision!.payments.single.amount, Money.fromMajor(1000));
    expect(decision.payments.single.method, 'cash');
    expect(decision.dueDate, isNull);
  });

  testWidgets('credit sale requires a customer, then has a due date', (
    tester,
  ) async {
    final decision = await open(
      tester,
      onPick: () async => CreditCustomer(
        id: 'c1',
        name: 'Bilal',
        outstanding: Money.fromMajor(200),
        limit: Money.fromMajor(5000),
      ),
      interact: () async {
        await tester.tap(find.text('Credit'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Select a customer to create a credit sale'),
          findsOneWidget,
        );
        final button = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Complete credit sale'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(button.onPressed, isNull);
        await tester.tap(find.text('Select customer (F3)'));
        await tester.pumpAndSettle();
        expect(find.text('Bilal'), findsOneWidget);
        expect(find.text('Within limit'), findsOneWidget);
        await tester.tap(find.text('Complete credit sale'));
      },
    );
    expect(decision!.payments, isEmpty);
    expect(decision.customerId, 'c1');
    final today = DateTime.now();
    expect(
      decision.dueDate,
      DateTime(today.year, today.month, today.day).add(const Duration(days: 7)),
    );
  });

  testWidgets('partial payment takes part now and flags the limit', (
    tester,
  ) async {
    final decision = await open(
      tester,
      customer: CreditCustomer(
        id: 'c1',
        name: 'Bilal',
        outstanding: Money.fromMajor(900),
        limit: Money.fromMajor(1000),
      ),
      interact: () async {
        await tester.tap(find.text('Partial'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '400');
        await tester.pumpAndSettle();
        expect(find.text('Over limit'), findsOneWidget);
        await tester.tap(find.text('No due date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Complete credit sale'));
      },
    );
    expect(decision!.payments.single.amount, Money.fromMajor(400));
    expect(decision.dueDate, isNull);
  });
}
