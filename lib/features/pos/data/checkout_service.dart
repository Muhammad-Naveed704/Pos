import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/money/money.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';
import '../domain/pos_cart.dart';

class CheckoutException implements Exception {
  const CheckoutException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CheckoutResult {
  const CheckoutResult({
    required this.saleId,
    required this.invoiceNumber,
    required this.total,
    required this.received,
    required this.change,
  });
  final String saleId;
  final String invoiceNumber;
  final Money total;
  final Money received;
  final Money change;
}

final checkoutServiceProvider = Provider<CheckoutService>(
  (ref) => CheckoutService(ref.watch(databaseProvider)),
);

class CheckoutService {
  CheckoutService(this._database, {Uuid? uuid, this._transactionProbe})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;
  final Future<void> Function()? _transactionProbe;

  Future<CheckoutResult> checkout({
    required AppSession session,
    required PosCart cart,
    required List<PaymentInput> payments,
  }) async {
    PermissionGuard.require(session, Permissions.posCreateSale);
    if (cart.lines.isEmpty) throw const CheckoutException('The cart is empty.');
    if (cart.saleDiscount.minorUnits > 0 || cart.saleDiscountPercent > 0) {
      PermissionGuard.require(session, Permissions.posApplyDiscount);
    }
    if (cart.lines.any(
      (line) =>
          line.manualDiscount.minorUnits > 0 || line.manualDiscountPercent > 0,
    )) {
      PermissionGuard.require(session, Permissions.posApplyDiscount);
    }
    if (cart.lines.any((line) => line.overrideUnitPrice != null)) {
      PermissionGuard.require(session, Permissions.posOverridePrice);
      if (!await _boolSetting('sales.allowPriceOverride', fallback: false)) {
        throw const CheckoutException('Price overrides are disabled.');
      }
    }

    final taxMode = await _taxMode();
    final totals = cart.totals(taxMode);
    final maximumDiscount =
        double.tryParse(await _setting('sales.maxDiscountPercent') ?? '') ??
        100;
    for (final line in cart.lines) {
      final gross = line.unitPrice.multiply(line.quantityMilli / 1000);
      final manualDiscount =
          line.manualDiscount +
          gross.multiply(line.manualDiscountPercent.clamp(0, 100) / 100);
      if (gross.minorUnits > 0 &&
          manualDiscount.minorUnits * 100 >
              gross.minorUnits * maximumDiscount) {
        throw CheckoutException(
          'The discount on ${line.catalogProduct.product.name} exceeds the allowed maximum.',
        );
      }
    }
    final discountable = (totals.subtotal - totals.lineDiscount).max(
      Money.zero,
    );
    if (discountable.minorUnits > 0 &&
        totals.saleDiscount.minorUnits * 100 >
            discountable.minorUnits * maximumDiscount) {
      throw CheckoutException(
        'The sale discount exceeds the ${maximumDiscount.toStringAsFixed(0)}% maximum.',
      );
    }
    const paymentMethods = {'cash', 'card', 'bank', 'other'};
    if (payments.any(
      (payment) =>
          payment.amount.minorUnits <= 0 ||
          !paymentMethods.contains(payment.method.toLowerCase()),
    )) {
      throw const CheckoutException('Use a valid positive payment amount.');
    }
    final received = payments.fold(
      Money.zero,
      (sum, payment) => sum + payment.amount,
    );
    if (payments.isEmpty || received.compareTo(totals.grandTotal) < 0) {
      throw const CheckoutException('Payment is less than the amount due.');
    }
    final change = received - totals.grandTotal;
    final cashTendered = payments
        .where((payment) => payment.method.toLowerCase() == 'cash')
        .fold(Money.zero, (sum, payment) => sum + payment.amount);
    if (change.compareTo(cashTendered) > 0) {
      throw const CheckoutException(
        'Change cannot exceed the cash amount tendered.',
      );
    }
    final allowNegativeStock = await _boolSetting(
      'inventory.allowNegative',
      fallback: false,
    );

    return _database.transaction(() async {
      final now = DateTime.now();
      final saleId = _uuid.v4();
      for (final line in cart.lines) {
        final product = await (_database.select(
          _database.products,
        )..where((row) => row.id.equals(line.productId))).getSingleOrNull();
        final storeProduct =
            await (_database.select(_database.productStores)..where(
                  (row) =>
                      row.productId.equals(line.productId) &
                      row.storeId.equals(session.store.id),
                ))
                .getSingleOrNull();
        if (product == null ||
            storeProduct == null ||
            !product.isActive ||
            !storeProduct.isAvailable) {
          throw CheckoutException(
            '${line.catalogProduct.product.name} is no longer available.',
          );
        }
        final currentPrice = Money.fromMajor(
          storeProduct.customSalePrice ?? product.salePrice,
        );
        if (line.overrideUnitPrice == null && line.unitPrice != currentPrice) {
          throw CheckoutException(
            'The price of ${product.name} changed. Refresh the cart and try again.',
          );
        }
      }
      final sequence =
          await (_database.select(_database.invoiceSequences)..where(
                (row) =>
                    row.storeId.equals(session.store.id) &
                    row.year.equals(now.year),
              ))
              .getSingleOrNull();
      final nextSequence = (sequence?.lastValue ?? 0) + 1;
      final invoiceNumber =
          '${session.store.code}-${now.year}-${nextSequence.toString().padLeft(6, '0')}';

      await _database
          .into(_database.sales)
          .insert(
            SalesCompanion.insert(
              id: saleId,
              invoiceNumber: invoiceNumber,
              storeId: session.store.id,
              userId: session.user.id,
              customerId: Value(cart.customerId),
              subtotal: totals.subtotal.majorUnits,
              discountAmount: Value(
                (totals.lineDiscount + totals.saleDiscount).majorUnits,
              ),
              taxAmount: Value(totals.tax.majorUnits),
              grandTotal: totals.grandTotal.majorUnits,
              paidAmount: Value(received.majorUnits),
              changeAmount: Value(change.majorUnits),
              paymentStatus: 'paid',
              saleStatus: 'completed',
              notes: Value(cart.notes.trim()),
              createdAt: now,
              updatedAt: now,
            ),
          );

      for (final line in cart.lines) {
        final lineTotals = cart.lineTotals(line, taxMode);
        await _database
            .into(_database.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                id: _uuid.v4(),
                saleId: saleId,
                productId: line.productId,
                productNameSnapshot: line.catalogProduct.product.name,
                skuSnapshot: line.catalogProduct.product.sku,
                qty: line.quantityMilli / 1000,
                unitPrice: line.unitPrice.majorUnits,
                discountAmount: Value(lineTotals.discount.majorUnits),
                taxAmount: Value(lineTotals.tax.majorUnits),
                lineTotal: lineTotals.total.majorUnits,
              ),
            );
      }

      for (final payment in payments) {
        await _database
            .into(_database.payments)
            .insert(
              PaymentsCompanion.insert(
                id: _uuid.v4(),
                saleId: saleId,
                method: payment.method.toLowerCase(),
                amount: payment.amount.majorUnits,
                reference: Value(payment.reference?.trim()),
                receivedBy: session.user.id,
                createdAt: now,
              ),
            );
      }

      if (_transactionProbe != null) await _transactionProbe();

      for (final line in cart.lines) {
        if (!line.catalogProduct.product.trackInventory) continue;
        final stock =
            await (_database.select(_database.productStores)..where(
                  (row) =>
                      row.storeId.equals(session.store.id) &
                      row.productId.equals(line.productId),
                ))
                .getSingle();
        final quantity = line.quantityMilli / 1000;
        final next = stock.stockQty - quantity;
        if (!allowNegativeStock && next < 0) {
          throw CheckoutException(
            'Insufficient stock for ${line.catalogProduct.product.name}.',
          );
        }
        await (_database.update(_database.productStores)..where(
              (row) =>
                  row.storeId.equals(session.store.id) &
                  row.productId.equals(line.productId),
            ))
            .write(
              ProductStoresCompanion(
                stockQty: Value(next),
                updatedAt: Value(now),
              ),
            );
        await _database
            .into(_database.stockMovements)
            .insert(
              StockMovementsCompanion.insert(
                id: _uuid.v4(),
                storeId: session.store.id,
                productId: line.productId,
                type: 'sale',
                quantity: -quantity,
                previousQty: stock.stockQty,
                newQty: next,
                referenceType: 'sale',
                referenceId: Value(saleId),
                note: Value('Invoice $invoiceNumber'),
                userId: session.user.id,
                createdAt: now,
              ),
            );
      }

      final cashReceived = payments
          .where((payment) => payment.method.toLowerCase() == 'cash')
          .fold(Money.zero, (sum, payment) => sum + payment.amount);
      final netCash = (cashReceived - change).max(Money.zero);
      if (netCash.minorUnits > 0) {
        await _database
            .into(_database.cashTransactions)
            .insert(
              CashTransactionsCompanion.insert(
                id: _uuid.v4(),
                storeId: session.store.id,
                userId: session.user.id,
                type: 'cash_sale',
                category: 'sales',
                amount: netCash.majorUnits,
                description: Value('Cash sale $invoiceNumber'),
                reference: Value(saleId),
                createdAt: now,
              ),
            );
      }

      if (cart.customerId != null) {
        final customer = await (_database.select(
          _database.customers,
        )..where((row) => row.id.equals(cart.customerId!))).getSingle();
        await (_database.update(
          _database.customers,
        )..where((row) => row.id.equals(customer.id))).write(
          CustomersCompanion(
            loyaltyPoints: Value(
              customer.loyaltyPoints + totals.grandTotal.majorUnits.floor(),
            ),
            updatedAt: Value(now),
          ),
        );
      }

      await _database
          .into(_database.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              userId: Value(session.user.id),
              storeId: Value(session.store.id),
              action: 'sale.created',
              entityType: 'sale',
              entityId: Value(saleId),
              description: 'Completed invoice $invoiceNumber',
              newValueJson: Value(
                jsonEncode({
                  'invoiceNumber': invoiceNumber,
                  'grandTotalMinor': totals.grandTotal.minorUnits,
                  'paymentMethods': payments
                      .map((item) => item.method)
                      .toList(),
                }),
              ),
              createdAt: now,
            ),
          );

      await _database
          .into(_database.invoiceSequences)
          .insertOnConflictUpdate(
            InvoiceSequencesCompanion.insert(
              storeId: session.store.id,
              year: now.year,
              lastValue: Value(nextSequence),
            ),
          );

      return CheckoutResult(
        saleId: saleId,
        invoiceNumber: invoiceNumber,
        total: totals.grandTotal,
        received: received,
        change: change,
      );
    });
  }

  Future<TaxMode> _taxMode() async {
    final value = await _setting('tax.mode') ?? 'exclusive';
    return TaxMode.values.where((mode) => mode.name == value).firstOrNull ??
        TaxMode.exclusive;
  }

  Future<bool> _boolSetting(String key, {required bool fallback}) async {
    final value = await _setting(key);
    return value == null ? fallback : value == 'true';
  }

  Future<String?> _setting(String key) async {
    final row = await _database
        .customSelect(
          'SELECT value FROM app_settings WHERE key = ? ORDER BY store_id IS NULL DESC LIMIT 1',
          variables: [Variable.withString(key)],
        )
        .getSingleOrNull();
    return row?.read<String>('value');
  }
}
