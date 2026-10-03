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

final cashbookServiceProvider = Provider<CashbookService>(
  (ref) => CashbookService(ref.watch(databaseProvider)),
);

class CashbookException implements Exception {
  const CashbookException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cash entry types. Pay-outs reduce the drawer; everything else adds.
abstract final class CashType {
  static const opening = 'opening';
  static const cashSale = 'cash_sale';
  static const payIn = 'pay_in';
  static const payOut = 'pay_out';
  static const refund = 'cash_refund';

  /// Cash received against a customer account (credit payments).
  static const customerPayment = 'customer_payment';

  /// A reversed customer payment paid back from the drawer.
  static const customerRefund = 'customer_refund';

  static bool isOutflow(String type) =>
      type == payOut || type == refund || type == customerRefund;
}

const payOutCategories = [
  'Expenses',
  'Supplier payment',
  'Salary / wages',
  'Utilities',
  'Owner drawing',
  'Bank deposit',
  'Other',
];

const payInCategories = [
  'Change float top-up',
  'Owner investment',
  'Customer payment',
  'Other',
];

class CashSessionSummary {
  const CashSessionSummary({
    required this.session,
    required this.userName,
    required this.cashSales,
    required this.payIns,
    required this.payOuts,
  });
  final CashSession session;
  final String userName;
  final Money cashSales;
  final Money payIns;
  final Money payOuts;

  Money get opening => Money.fromMajor(session.openingBalance);

  Money get expected => opening + cashSales + payIns - payOuts;

  Money? get counted => session.actualClosing == null
      ? null
      : Money.fromMajor(session.actualClosing!);

  /// Positive = over, negative = short.
  Money? get difference {
    final value = counted;
    if (value == null) return null;
    final expectedAtClose = session.expectedClosing == null
        ? expected
        : Money.fromMajor(session.expectedClosing!);
    return value - expectedAtClose;
  }

  bool get isOpen => session.status == 'open';
}

class CashbookService {
  CashbookService(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  static const _summarySql = '''
    SELECT cs.*, u.display_name AS user_name,
      COALESCE((SELECT SUM(amount) FROM cash_transactions t
        WHERE t.session_id = cs.id AND t.type = 'cash_sale'), 0.0) AS cash_sales,
      COALESCE((SELECT SUM(amount) FROM cash_transactions t
        WHERE t.session_id = cs.id AND t.type IN ('pay_in', 'customer_payment')), 0.0) AS pay_ins,
      COALESCE((SELECT SUM(amount) FROM cash_transactions t
        WHERE t.session_id = cs.id AND t.type IN ('pay_out', 'cash_refund', 'customer_refund')), 0.0) AS pay_outs
    FROM cash_sessions cs
    JOIN users u ON u.id = cs.user_id
  ''';

  CashSessionSummary _map(QueryRow row) => CashSessionSummary(
    session: _database.cashSessions.map(row.data),
    userName: row.read<String>('user_name'),
    cashSales: Money.fromMajor(row.read<double>('cash_sales')),
    payIns: Money.fromMajor(row.read<double>('pay_ins')),
    payOuts: Money.fromMajor(row.read<double>('pay_outs')),
  );

  Set<ResultSetImplementation<dynamic, dynamic>> get _tables => {
    _database.cashSessions,
    _database.cashTransactions,
    _database.users,
  };

  /// The signed-in user's open session in the active store, if any.
  Stream<CashSessionSummary?> watchCurrent(AppSession session) {
    PermissionGuard.require(session, Permissions.cashbookManage);
    return _database
        .customSelect(
          '$_summarySql WHERE cs.store_id = ? AND cs.user_id = ? AND cs.status = \'open\' LIMIT 1',
          variables: [
            Variable.withString(session.store.id),
            Variable.withString(session.user.id),
          ],
          readsFrom: _tables,
        )
        .watch()
        .map((rows) => rows.isEmpty ? null : _map(rows.first));
  }

  /// Session history. Users without cashbook.view only see their own.
  Stream<List<CashSessionSummary>> watchSessions(
    AppSession session, {
    int limit = 100,
  }) {
    if (!session.can(Permissions.cashbookView)) {
      PermissionGuard.require(session, Permissions.cashbookManage);
    }
    final all = session.can(Permissions.cashbookView);
    return _database
        .customSelect(
          '$_summarySql WHERE cs.store_id = ?${all ? '' : ' AND cs.user_id = ?'} '
          'ORDER BY cs.opened_at DESC, cs.rowid DESC LIMIT $limit',
          variables: [
            Variable.withString(session.store.id),
            if (!all) Variable.withString(session.user.id),
          ],
          readsFrom: _tables,
        )
        .watch()
        .map((rows) => rows.map(_map).toList());
  }

  Stream<List<CashTransaction>> watchEntries(
    AppSession session,
    String sessionId,
  ) {
    if (!session.can(Permissions.cashbookView)) {
      PermissionGuard.require(session, Permissions.cashbookManage);
    }
    return (_database.select(_database.cashTransactions)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<CashSession?> _open(AppSession session) =>
      (_database.select(_database.cashSessions)..where(
            (row) =>
                row.storeId.equals(session.store.id) &
                row.userId.equals(session.user.id) &
                row.status.equals('open'),
          ))
          .getSingleOrNull();

  Future<String> openSession(AppSession session, Money openingFloat) async {
    PermissionGuard.require(session, Permissions.cashbookManage);
    if (openingFloat.minorUnits < 0) {
      throw const CashbookException('Opening cash cannot be negative.');
    }
    final id = _uuid.v4();
    await _database.transaction(() async {
      if (await _open(session) != null) {
        throw const CashbookException('You already have an open cash session.');
      }
      final now = DateTime.now();
      await _database
          .into(_database.cashSessions)
          .insert(
            CashSessionsCompanion.insert(
              id: id,
              storeId: session.store.id,
              userId: session.user.id,
              openingBalance: openingFloat.majorUnits,
              status: 'open',
              openedAt: now,
            ),
          );
      await _audit(
        session,
        'cashbook.opened',
        id,
        'Opened cash session with $openingFloat.',
      );
    });
    return id;
  }

  Future<void> record(
    AppSession session, {
    required String type,
    required Money amount,
    required String category,
    String description = '',
  }) async {
    PermissionGuard.require(session, Permissions.cashbookManage);
    if (type != CashType.payIn && type != CashType.payOut) {
      throw const CashbookException('Unsupported cash entry.');
    }
    if (amount.minorUnits <= 0) {
      throw const CashbookException('Amount must be greater than zero.');
    }
    await _database.transaction(() async {
      final open = await _open(session);
      if (open == null) {
        throw const CashbookException('Open a cash session first.');
      }
      if (type == CashType.payOut) {
        final current = _map(
          await _database
              .customSelect(
                '$_summarySql WHERE cs.id = ?',
                variables: [Variable.withString(open.id)],
              )
              .getSingle(),
        );
        if (amount.compareTo(current.expected) > 0) {
          throw CashbookException(
            'Only ${current.expected} should be in the drawer.',
          );
        }
      }
      final now = DateTime.now();
      await _database
          .into(_database.cashTransactions)
          .insert(
            CashTransactionsCompanion.insert(
              id: _uuid.v4(),
              storeId: session.store.id,
              userId: session.user.id,
              sessionId: Value(open.id),
              type: type,
              category: category,
              amount: amount.majorUnits,
              description: Value(description.trim()),
              createdAt: now,
            ),
          );
      await _audit(
        session,
        'cashbook.$type',
        open.id,
        '${type == CashType.payIn ? 'Pay-in' : 'Pay-out'} $amount · $category'
            '${description.trim().isEmpty ? '' : ' · ${description.trim()}'}',
      );
    });
  }

  /// Closes the user's open session with the counted cash.
  Future<CashSessionSummary> closeSession(
    AppSession session, {
    required Money counted,
    String note = '',
    Map<String, int> denominations = const {},
  }) async {
    PermissionGuard.require(session, Permissions.cashbookManage);
    if (counted.minorUnits < 0) {
      throw const CashbookException('Counted cash cannot be negative.');
    }
    late CashSessionSummary result;
    await _database.transaction(() async {
      final open = await _open(session);
      if (open == null) throw const CashbookException('No open cash session.');
      final summary = _map(
        await _database
            .customSelect(
              '$_summarySql WHERE cs.id = ?',
              variables: [Variable.withString(open.id)],
            )
            .getSingle(),
      );
      final now = DateTime.now();
      await (_database.update(
        _database.cashSessions,
      )..where((row) => row.id.equals(open.id))).write(
        CashSessionsCompanion(
          expectedClosing: Value(summary.expected.majorUnits),
          actualClosing: Value(counted.majorUnits),
          status: const Value('closed'),
          closedAt: Value(now),
        ),
      );
      final difference = counted - summary.expected;
      await _audit(
        session,
        'cashbook.closed',
        open.id,
        'Closed cash session. Expected ${summary.expected}, counted $counted, '
            'difference $difference.',
        json: jsonEncode({'note': note, 'denominations': denominations}),
      );
      result = _map(
        await _database
            .customSelect(
              '$_summarySql WHERE cs.id = ?',
              variables: [Variable.withString(open.id)],
            )
            .getSingle(),
      );
    });
    return result;
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
          entityType: 'cash_session',
          entityId: Value(entityId),
          description: description,
          newValueJson: Value(json),
          createdAt: DateTime.now(),
        ),
      );
}
