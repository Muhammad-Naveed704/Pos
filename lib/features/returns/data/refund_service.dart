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
import '../../credit/data/credit_ledger.dart';
import '../../credit/domain/credit.dart';
import '../../history/data/sales_repository.dart';

final refundServiceProvider = Provider<RefundService>(
  (ref) => RefundService(ref.watch(databaseProvider)),
);

class RefundException implements Exception {
  const RefundException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class SaleStatus {
  static const completed = 'completed';
  static const partiallyRefunded = 'partially_refunded';
  static const refunded = 'refunded';
  static const voided = 'voided';

  static String label(String status) => switch (status) {
    completed => 'Completed',
    partiallyRefunded => 'Partly refunded',
    refunded => 'Refunded',
    voided => 'Voided',
    _ => status,
  };
}

const refundReasons = [
  'Customer changed mind',
  'Damaged / defective',
  'Wrong item',
  'Expired',
  'Price adjustment',
  'Other',
];

const voidReasons = [
  'Entered by mistake',
  'Wrong items or quantity',
  'Customer cancelled',
  'Payment problem',
  'Other',
];

/// One sale line with what can still be returned.
class RefundableLine {
  const RefundableLine({
    required this.item,
    required this.refundedQty,
    required this.unit,
    required this.tracksStock,
    required this.factor,
  });
  final SaleItem item;
  final double refundedQty;
  final String unit;
  final bool tracksStock;

  /// grand total / sum of line totals: spreads sale-level discounts.
  final double factor;

  double get remaining {
    final value = item.qty - refundedQty;
    return value < 1e-9 ? 0 : value;
  }

  /// Refund value of [quantity] units of this line.
  Money amountFor(double quantity) => item.qty <= 0
      ? Money.zero
      : Money.fromMajor(item.lineTotal).multiply(quantity / item.qty * factor);
}

class RefundRecord {
  const RefundRecord(this.refund, this.userName, this.items);
  final SaleRefund refund;
  final String userName;
  final List<(SaleRefundItem, String)> items;
}

class SaleReturnState {
  const SaleReturnState({
    required this.details,
    required this.lines,
    required this.refunds,
    required this.refunded,
    this.outstanding = Money.zero,
    this.hasPayments = false,
  });
  final SaleDetails details;
  final List<RefundableLine> lines;
  final List<RefundRecord> refunds;

  /// Total already refunded (excluding voids).
  final Money refunded;

  /// Unpaid credit balance of this invoice. Returns reduce it first.
  final Money outstanding;

  /// Whether customer payments were applied to this invoice.
  final bool hasPayments;

  Sale get sale => details.summary.sale;
  Money get total => Money.fromMajor(sale.grandTotal);
  Money get remaining => (total - refunded).max(Money.zero);

  bool get canRefund =>
      (sale.saleStatus == SaleStatus.completed ||
          sale.saleStatus == SaleStatus.partiallyRefunded) &&
      lines.any((line) => line.remaining > 0);

  /// Voids are for same-day mistakes on untouched sales.
  bool get canVoid {
    if (sale.saleStatus != SaleStatus.completed || hasPayments) return false;
    final created = sale.createdAt.toLocal();
    final now = DateTime.now();
    return created.year == now.year &&
        created.month == now.month &&
        created.day == now.day;
  }

  /// Payment method used most on the original sale.
  String get primaryMethod {
    final payments = [...details.payments]
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return payments.isEmpty ? 'cash' : payments.first.method;
  }
}

class RefundLineInput {
  const RefundLineInput({
    required this.saleItemId,
    required this.quantity,
    this.restock = true,
  });
  final String saleItemId;
  final double quantity;
  final bool restock;
}

class RefundResult {
  const RefundResult(
    this.refundId,
    this.number,
    this.amount, {
    this.creditApplied = Money.zero,
  });
  final String refundId;
  final String number;
  final Money amount;

  /// Part of [amount] that reduced the invoice's unpaid balance.
  final Money creditApplied;

  /// Money actually handed back to the customer.
  Money get paidOut => amount - creditApplied;
}

class RefundService {
  RefundService(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  static const _methods = {'cash', 'card', 'bank', 'other'};

  /// Finds a sale in the active store by its exact invoice number (e.g. a
  /// scanned receipt barcode).
  Future<String?> findByInvoice(AppSession session, String invoice) async {
    PermissionGuard.require(session, Permissions.posView);
    final sale =
        await (_database.select(_database.sales)..where(
              (s) =>
                  s.invoiceNumber.equals(invoice.trim().toUpperCase()) &
                  s.storeId.equals(session.store.id),
            ))
            .getSingleOrNull();
    return sale?.id;
  }

  Future<SaleReturnState> load(AppSession session, String saleId) async {
    final details = await SalesRepository(_database).details(session, saleId);
    final sumLines = details.items.fold(0.0, (sum, i) => sum + i.lineTotal);
    final factor = sumLines <= 0
        ? 0.0
        : details.summary.sale.grandTotal / sumLines;
    final refundedRows = await _database
        .customSelect(
          '''
          SELECT ri.sale_item_id AS id, SUM(ri.qty) AS qty
          FROM sale_refund_items ri
          JOIN sale_refunds r ON r.id = ri.refund_id
          WHERE r.sale_id = ? GROUP BY ri.sale_item_id
          ''',
          variables: [Variable.withString(saleId)],
        )
        .get();
    final refundedQty = {
      for (final row in refundedRows)
        row.read<String>('id'): row.read<double>('qty'),
    };
    final productIds = details.items.map((i) => i.productId).toSet();
    final products = {
      for (final product in await (_database.select(
        _database.products,
      )..where((p) => p.id.isIn(productIds))).get())
        product.id: product,
    };
    final refunds = await _records(saleId);
    final refunded = refunds
        .where((r) => r.refund.kind == 'refund')
        .fold(Money.zero, (sum, r) => sum + Money.fromMajor(r.refund.amount));
    final allocated = await _database
        .customSelect(
          '''
          SELECT COUNT(*) AS n FROM payment_allocations a
          JOIN customer_payments cp ON cp.id = a.payment_id
          WHERE a.sale_id = ? AND cp.status = 'posted'
          ''',
          variables: [Variable.withString(saleId)],
        )
        .getSingle();
    return SaleReturnState(
      outstanding: await CreditLedger(_database).saleOutstanding(saleId),
      hasPayments: allocated.read<int>('n') > 0,
      details: details,
      lines: [
        for (final item in details.items)
          RefundableLine(
            item: item,
            refundedQty: refundedQty[item.id] ?? 0,
            unit: products[item.productId]?.unit ?? 'each',
            tracksStock: products[item.productId]?.trackInventory ?? false,
            factor: factor,
          ),
      ],
      refunds: refunds,
      refunded: refunded,
    );
  }

  Future<List<RefundRecord>> _records(String saleId) async {
    final refunds = _database.saleRefunds;
    final users = _database.users;
    final rows =
        await (_database.select(refunds).join([
                innerJoin(users, users.id.equalsExp(refunds.userId)),
              ])
              ..where(refunds.saleId.equals(saleId))
              ..orderBy([OrderingTerm.asc(refunds.createdAt)]))
            .get();
    final result = <RefundRecord>[];
    for (final row in rows) {
      final refund = row.readTable(refunds);
      final items = await (_database.select(_database.saleRefundItems).join([
        innerJoin(
          _database.saleItems,
          _database.saleItems.id.equalsExp(
            _database.saleRefundItems.saleItemId,
          ),
        ),
      ])..where(_database.saleRefundItems.refundId.equals(refund.id))).get();
      result.add(
        RefundRecord(refund, row.readTable(users).displayName, [
          for (final item in items)
            (
              item.readTable(_database.saleRefundItems),
              item.readTable(_database.saleItems).productNameSnapshot,
            ),
        ]),
      );
    }
    return result;
  }

  /// Returns some or all items of a sale.
  Future<RefundResult> refund(
    AppSession session, {
    required String saleId,
    required List<RefundLineInput> lines,
    required String method,
    required String reason,
  }) async {
    PermissionGuard.require(session, Permissions.posRefund);
    if (!_methods.contains(method) && method != 'credit') {
      throw const RefundException('Choose how the money is returned.');
    }
    if (reason.trim().isEmpty) {
      throw const RefundException('Enter a reason for the refund.');
    }
    final requested = lines.where((line) => line.quantity > 0).toList();
    if (requested.isEmpty) {
      throw const RefundException('Choose at least one item to return.');
    }
    late RefundResult result;
    await _database.transaction(() async {
      final state = await load(session, saleId);
      if (!state.canRefund) {
        throw RefundException(
          'This sale cannot be refunded (${SaleStatus.label(state.sale.saleStatus).toLowerCase()}).',
        );
      }
      final byId = {for (final line in state.lines) line.item.id: line};
      var amount = Money.zero;
      final planned = <(RefundableLine, RefundLineInput, Money)>[];
      for (final input in requested) {
        final line = byId[input.saleItemId];
        if (line == null) {
          throw const RefundException('Item is not part of this sale.');
        }
        if (input.quantity > line.remaining + 1e-9) {
          throw RefundException(
            'Only ${_qty(line.remaining)} of ${line.item.productNameSnapshot} can still be returned.',
          );
        }
        final value = line.amountFor(input.quantity);
        planned.add((line, input, value));
        amount += value;
      }
      // When this refund returns everything left, settle the exact balance so
      // rounding never leaves a few cents behind.
      final everything = state.lines.every((line) {
        final input = requested
            .where((r) => r.saleItemId == line.item.id)
            .firstOrNull;
        return line.remaining - (input?.quantity ?? 0) <= 1e-9;
      });
      if (everything || amount.compareTo(state.remaining) > 0) {
        final delta = state.remaining - amount;
        amount = state.remaining;
        if (planned.isNotEmpty && delta.minorUnits != 0) {
          final last = planned.removeLast();
          planned.add((last.$1, last.$2, last.$3 + delta));
        }
      }
      if (amount.minorUnits <= 0) {
        throw const RefundException('Nothing to refund.');
      }
      // A return on an invoice that is not fully paid first reduces what the
      // customer still owes; only the rest is handed back.
      final applied = amount.compareTo(state.outstanding) > 0
          ? state.outstanding
          : amount;
      final paidOut = amount - applied;
      if (paidOut.minorUnits > 0 && method == 'credit') {
        throw const RefundException('Choose how the money is returned.');
      }
      if (paidOut.minorUnits == 0) method = 'credit';
      final now = DateTime.now();
      if (method == 'cash') await _checkDrawer(session, paidOut);

      final refundId = _uuid.v4();
      final count = state.refunds
          .where((r) => r.refund.kind == 'refund')
          .length;
      final number = '${state.sale.invoiceNumber}-R${count + 1}';
      await _database
          .into(_database.saleRefunds)
          .insert(
            SaleRefundsCompanion.insert(
              id: refundId,
              saleId: saleId,
              storeId: session.store.id,
              userId: session.user.id,
              number: number,
              kind: 'refund',
              method: method,
              amount: amount.majorUnits,
              creditApplied: Value(applied.majorUnits),
              reason: Value(reason.trim()),
              createdAt: now,
            ),
          );
      for (final (line, input, value) in planned) {
        final restock = input.restock && line.tracksStock;
        await _database
            .into(_database.saleRefundItems)
            .insert(
              SaleRefundItemsCompanion.insert(
                id: _uuid.v4(),
                refundId: refundId,
                saleItemId: line.item.id,
                productId: line.item.productId,
                qty: input.quantity,
                amount: value.majorUnits,
                cost: Value(
                  Money.fromMajor(line.item.unitCost)
                      .multiply(input.quantity)
                      .majorUnits,
                ),
                restocked: Value(restock),
              ),
            );
        if (restock) {
          await _restock(
            session,
            productId: line.item.productId,
            quantity: input.quantity,
            type: 'refund',
            referenceId: refundId,
            note: 'Refund $number',
            now: now,
          );
        }
      }
      if (method == 'cash') {
        await _cashOut(session, paidOut, 'Cash refund $number', refundId, now);
      }
      final customerId = state.sale.customerId;
      if (customerId != null) {
        final ledger = CreditLedger(_database, uuid: _uuid);
        await ledger.entry(
          customerId: customerId,
          type: LedgerType.refund,
          storeId: session.store.id,
          userId: session.user.id,
          referenceType: 'refund',
          referenceId: refundId,
          referenceNumber: number,
          credit: amount,
          note: reason.trim(),
          at: now,
        );
        await ledger.entry(
          customerId: customerId,
          type: LedgerType.refundPaid,
          storeId: session.store.id,
          userId: session.user.id,
          referenceType: 'refund',
          referenceId: refundId,
          referenceNumber: number,
          debit: paidOut,
          note: method.toUpperCase(),
          at: now,
        );
      }
      await _reverseLoyalty(state.sale.customerId, amount, now);
      final fullyReturned = state.lines.every((line) {
        final returned = requested
            .where((r) => r.saleItemId == line.item.id)
            .fold(0.0, (sum, r) => sum + r.quantity);
        return line.remaining - returned <= 1e-9;
      });
      await (_database.update(
        _database.sales,
      )..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(
          saleStatus: Value(
            fullyReturned ? SaleStatus.refunded : SaleStatus.partiallyRefunded,
          ),
          updatedAt: Value(now),
        ),
      );
      await _audit(
        session,
        'sale.refunded',
        saleId,
        'Refund $number of ${state.sale.invoiceNumber}: $amount ($applied off the balance, $paidOut by $method) (${reason.trim()}).',
        json: jsonEncode({
          for (final (line, input, _) in planned)
            line.item.productNameSnapshot: {
              'qty': input.quantity,
              'restocked': input.restock && line.tracksStock,
            },
        }),
      );
      result = RefundResult(refundId, number, amount, creditApplied: applied);
    });
    return result;
  }

  /// Cancels a same-day sale completely.
  Future<RefundResult> voidSale(
    AppSession session, {
    required String saleId,
    required String reason,
  }) async {
    PermissionGuard.require(session, Permissions.posVoidSale);
    if (reason.trim().isEmpty) {
      throw const RefundException('Enter a reason for voiding the sale.');
    }
    late RefundResult result;
    await _database.transaction(() async {
      final state = await load(session, saleId);
      if (!state.canVoid) {
        throw const RefundException(
          'Only today’s sales without refunds can be voided. Use a refund instead.',
        );
      }
      final sale = state.sale;
      final now = DateTime.now();
      final cashPaid = state.details.payments
          .where((p) => p.method == 'cash')
          .fold(Money.zero, (sum, p) => sum + Money.fromMajor(p.amount));
      final netCash = (cashPaid - Money.fromMajor(sale.changeAmount)).max(
        Money.zero,
      );
      if (netCash.minorUnits > 0) await _checkDrawer(session, netCash);

      final refundId = _uuid.v4();
      final number = '${sale.invoiceNumber}-V';
      final methods = state.details.payments.map((p) => p.method).toSet();
      await _database
          .into(_database.saleRefunds)
          .insert(
            SaleRefundsCompanion.insert(
              id: refundId,
              saleId: saleId,
              storeId: session.store.id,
              userId: session.user.id,
              number: number,
              kind: 'void',
              method: methods.isEmpty
                  ? 'credit'
                  : methods.length == 1
                  ? methods.single
                  : 'mixed',
              amount: sale.grandTotal,
              creditApplied: Value(state.outstanding.majorUnits),
              reason: Value(reason.trim()),
              createdAt: now,
            ),
          );
      for (final line in state.lines) {
        await _database
            .into(_database.saleRefundItems)
            .insert(
              SaleRefundItemsCompanion.insert(
                id: _uuid.v4(),
                refundId: refundId,
                saleItemId: line.item.id,
                productId: line.item.productId,
                qty: line.item.qty,
                amount: line.item.lineTotal,
                cost: Value(
                  Money.fromMajor(line.item.unitCost)
                      .multiply(line.item.qty)
                      .majorUnits,
                ),
                restocked: Value(line.tracksStock),
              ),
            );
        if (line.tracksStock) {
          await _restock(
            session,
            productId: line.item.productId,
            quantity: line.item.qty,
            type: 'void',
            referenceId: refundId,
            note: 'Void ${sale.invoiceNumber}',
            now: now,
          );
        }
      }
      if (netCash.minorUnits > 0) {
        await _cashOut(
          session,
          netCash,
          'Void ${sale.invoiceNumber}',
          refundId,
          now,
        );
      }
      if (sale.customerId != null) {
        final ledger = CreditLedger(_database, uuid: _uuid);
        final total = Money.fromMajor(sale.grandTotal);
        await ledger.entry(
          customerId: sale.customerId!,
          type: LedgerType.voidSale,
          storeId: session.store.id,
          userId: session.user.id,
          referenceType: 'refund',
          referenceId: refundId,
          referenceNumber: number,
          credit: total,
          note: reason.trim(),
          at: now,
        );
        await ledger.entry(
          customerId: sale.customerId!,
          type: LedgerType.voidPaid,
          storeId: session.store.id,
          userId: session.user.id,
          referenceType: 'refund',
          referenceId: refundId,
          referenceNumber: number,
          debit: total - state.outstanding,
          at: now,
        );
      }
      await _reverseLoyalty(
        sale.customerId,
        Money.fromMajor(sale.grandTotal),
        now,
      );
      await (_database.update(
        _database.sales,
      )..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(
          saleStatus: const Value(SaleStatus.voided),
          updatedAt: Value(now),
        ),
      );
      await _audit(
        session,
        'sale.voided',
        saleId,
        'Voided ${sale.invoiceNumber} (${reason.trim()}).',
      );
      result = RefundResult(
        refundId,
        number,
        Money.fromMajor(sale.grandTotal),
        creditApplied: state.outstanding,
      );
    });
    return result;
  }

  Future<CashSession?> _openSession(AppSession session) =>
      (_database.select(_database.cashSessions)..where(
            (s) =>
                s.storeId.equals(session.store.id) &
                s.userId.equals(session.user.id) &
                s.status.equals('open'),
          ))
          .getSingleOrNull();

  /// Cash can only be handed back if the open drawer holds enough.
  Future<void> _checkDrawer(AppSession session, Money amount) async {
    final open = await _openSession(session);
    if (open == null) return;
    final row = await _database
        .customSelect(
          '''
          SELECT ?2 + COALESCE(SUM(CASE WHEN type IN ('pay_out', 'cash_refund', 'customer_refund')
                 THEN -amount ELSE amount END), 0.0) AS expected
          FROM cash_transactions WHERE session_id = ?1
          ''',
          variables: [
            Variable.withString(open.id),
            Variable.withReal(open.openingBalance),
          ],
        )
        .getSingle();
    final expected = Money.fromMajor(row.read<double>('expected'));
    if (amount.compareTo(expected) > 0) {
      throw RefundException(
        'Not enough cash in the drawer ($expected). Refund by another method.',
      );
    }
  }

  Future<void> _cashOut(
    AppSession session,
    Money amount,
    String description,
    String reference,
    DateTime now,
  ) async {
    final open = await _openSession(session);
    await _database
        .into(_database.cashTransactions)
        .insert(
          CashTransactionsCompanion.insert(
            id: _uuid.v4(),
            storeId: session.store.id,
            userId: session.user.id,
            sessionId: Value(open?.id),
            type: 'cash_refund',
            category: 'refunds',
            amount: amount.majorUnits,
            description: Value(description),
            reference: Value(reference),
            createdAt: now,
          ),
        );
  }

  Future<void> _restock(
    AppSession session, {
    required String productId,
    required double quantity,
    required String type,
    required String referenceId,
    required String note,
    required DateTime now,
  }) async {
    final storeId = session.store.id;
    final current =
        await (_database.select(_database.productStores)..where(
              (r) => r.productId.equals(productId) & r.storeId.equals(storeId),
            ))
            .getSingleOrNull();
    final previous = current?.stockQty ?? 0;
    final next = previous + quantity;
    if (current == null) {
      await _database
          .into(_database.productStores)
          .insert(
            ProductStoresCompanion.insert(
              productId: productId,
              storeId: storeId,
              stockQty: Value(next),
              updatedAt: now,
            ),
          );
    } else {
      await (_database.update(_database.productStores)..where(
            (r) => r.productId.equals(productId) & r.storeId.equals(storeId),
          ))
          .write(
            ProductStoresCompanion(
              stockQty: Value(next),
              updatedAt: Value(now),
            ),
          );
    }
    await _database
        .into(_database.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            id: _uuid.v4(),
            storeId: storeId,
            productId: productId,
            type: type,
            quantity: quantity,
            previousQty: previous,
            newQty: next,
            referenceType: 'refund',
            referenceId: Value(referenceId),
            note: Value(note),
            userId: session.user.id,
            createdAt: now,
          ),
        );
  }

  /// Checkout awards floor(total) points; take back the same for the refund.
  Future<void> _reverseLoyalty(
    String? customerId,
    Money amount,
    DateTime now,
  ) async {
    if (customerId == null) return;
    final customer = await (_database.select(
      _database.customers,
    )..where((c) => c.id.equals(customerId))).getSingleOrNull();
    if (customer == null) return;
    final points = (customer.loyaltyPoints - amount.majorUnits.floor()).clamp(
      0,
      1 << 31,
    );
    await (_database.update(
      _database.customers,
    )..where((c) => c.id.equals(customerId))).write(
      CustomersCompanion(loyaltyPoints: Value(points), updatedAt: Value(now)),
    );
  }

  Future<void> _audit(
    AppSession session,
    String action,
    String entityId,
    String description, {
    String? json,
  }) => _database
      .into(_database.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          id: _uuid.v4(),
          userId: Value(session.user.id),
          storeId: Value(session.store.id),
          action: action,
          entityType: 'sale',
          entityId: Value(entityId),
          description: description,
          newValueJson: Value(json),
          createdAt: DateTime.now(),
        ),
      );

  static String _qty(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}
