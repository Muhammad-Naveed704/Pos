import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/csv/csv_table.dart';
import '../../../core/csv/import_models.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/domain/app_session.dart';
import '../../auth/domain/permission_guard.dart';
import '../../auth/domain/permissions.dart';
import '../../credit/data/credit_ledger.dart';

final customerImportServiceProvider = Provider<CustomerImportService>(
  (ref) => CustomerImportService(ref.watch(databaseProvider)),
);

class _CustomerRow {
  const _CustomerRow({
    required this.line,
    required this.name,
    this.existingId,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.creditLimit,
    this.openingBalance,
    this.loyaltyPoints,
    this.active,
  });
  final int line;
  final String name;
  final String? existingId;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final double? creditLimit;
  final double? openingBalance;
  final int? loyaltyPoints;
  final bool? active;
}

class CustomerImportPlan {
  const CustomerImportPlan._(this.preview, this._rows);
  final ImportPreview preview;
  final List<_CustomerRow> _rows;
}

/// Digits only, so "0300-123 4567" and "03001234567" match.
String phoneKey(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

class CustomerImportService {
  CustomerImportService(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();
  final AppDatabase _database;
  final Uuid _uuid;

  static const columns = [
    'name',
    'phone',
    'email',
    'address',
    'notes',
    'credit_limit',
    'opening_balance',
    'loyalty_points',
    'active',
  ];

  static const aliases = {
    'customer': 'name',
    'customer_name': 'name',
    'full_name': 'name',
    'mobile': 'phone',
    'phone_number': 'phone',
    'contact': 'phone',
    'cell': 'phone',
    'e_mail': 'email',
    'email_address': 'email',
    'credit': 'credit_limit',
    'balance': 'opening_balance',
    'points': 'loyalty_points',
    'loyalty': 'loyalty_points',
    'remarks': 'notes',
  };

  static List<List<Object?>> template() => [
    columns,
    [
      'Ali Khan',
      '0300-1234567',
      'ali@example.com',
      'Street 4, Lahore',
      'Prefers delivery',
      5000,
      0,
      0,
      'yes',
    ],
    ['Sara Ahmed', '+44 7700 900123', '', '', '', 0, 0, 120, 'yes'],
  ];

  Future<CustomerImportPlan> prepare(
    AppSession session,
    CsvTable table, {
    bool updateExisting = true,
  }) async {
    PermissionGuard.require(session, Permissions.customersCreate);
    if (!table.has('name')) {
      throw const ImportFormatException(
        'Missing required column: name. Download the template to see the expected headers.',
      );
    }
    final existing = await _database
        .customSelect('SELECT id, phone FROM customers WHERE phone IS NOT NULL')
        .get();
    final idByPhone = <String, String>{
      for (final row in existing)
        if (phoneKey(row.read<String>('phone')).isNotEmpty)
          phoneKey(row.read<String>('phone')): row.read<String>('id'),
    };
    final results = <ImportRowResult>[];
    final rows = <_CustomerRow>[];
    final seenPhones = <String, int>{};

    for (final row in table.rows) {
      final messages = <String>[];
      final name = row.text('name');
      final phone = row.optional('phone');
      final key = phone == null ? '' : phoneKey(phone);
      if (name.isEmpty) messages.add('Name is required.');
      if (name.length > 160) {
        messages.add('Name is longer than 160 characters.');
      }
      if (key.isNotEmpty && seenPhones.containsKey(key)) {
        messages.add('Duplicate phone (also on line ${seenPhones[key]}).');
      }
      final email = row.optional('email');
      if (email != null &&
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        messages.add('“$email” is not a valid email.');
      }
      double? number(String column) {
        if (row.text(column).isEmpty) return null;
        final value = row.number(column);
        if (value == null) {
          messages.add('“${row.text(column)}” is not a valid $column.');
        }
        return value;
      }

      final credit = number('credit_limit');
      if (credit != null && credit < 0) {
        messages.add('credit_limit cannot be negative.');
      }
      final opening = number('opening_balance');
      final points = number('loyalty_points');
      bool? active;
      if (row.text('active').isNotEmpty) {
        active = row.flag('active');
        if (active == null) messages.add('active must be yes or no.');
      }
      if (key.isNotEmpty) seenPhones.putIfAbsent(key, () => row.line);

      final existingId = key.isEmpty ? null : idByPhone[key];
      final ImportAction action;
      if (messages.isNotEmpty) {
        action = ImportAction.error;
      } else if (existingId != null) {
        action = updateExisting ? ImportAction.update : ImportAction.skip;
        if (!updateExisting) messages.add('Phone exists; left unchanged.');
      } else {
        action = ImportAction.create;
      }
      if (action == ImportAction.create || action == ImportAction.update) {
        rows.add(
          _CustomerRow(
            line: row.line,
            name: name,
            existingId: existingId,
            phone: phone,
            email: email,
            address: row.optional('address'),
            notes: row.optional('notes'),
            creditLimit: credit,
            openingBalance: opening,
            loyaltyPoints: points?.round(),
            active: active,
          ),
        );
      }
      results.add(
        ImportRowResult(
          line: row.line,
          action: action,
          label: [name, ?phone].join(' · '),
          messages: messages,
        ),
      );
    }
    return CustomerImportPlan._(
      ImportPreview(
        rows: results,
        notes: const [
          'Existing customers are matched by phone number (digits only).',
        ],
      ),
      rows,
    );
  }

  Future<ImportOutcome> apply(
    AppSession session,
    CustomerImportPlan plan,
  ) async {
    PermissionGuard.require(session, Permissions.customersCreate);
    if (plan._rows.any((row) => row.existingId != null)) {
      PermissionGuard.require(session, Permissions.customersEdit);
    }
    final now = DateTime.now();
    var created = 0;
    var updated = 0;
    await _database.transaction(() async {
      for (final row in plan._rows) {
        final current = row.existingId == null
            ? null
            : await (_database.select(
                _database.customers,
              )..where((c) => c.id.equals(row.existingId!))).getSingle();
        final customerId = row.existingId ?? _uuid.v4();
        await _database
            .into(_database.customers)
            .insertOnConflictUpdate(
              CustomersCompanion.insert(
                id: customerId,
                name: row.name,
                phone: Value(row.phone ?? current?.phone),
                email: Value(row.email ?? current?.email),
                address: Value(row.address ?? current?.address ?? ''),
                notes: Value(row.notes ?? current?.notes ?? ''),
                loyaltyPoints: Value(
                  row.loyaltyPoints ?? current?.loyaltyPoints ?? 0,
                ),
                creditLimit: Value(
                  row.creditLimit ?? current?.creditLimit ?? 0,
                ),
                openingBalance: Value(
                  row.openingBalance ?? current?.openingBalance ?? 0,
                ),
                isActive: Value(row.active ?? current?.isActive ?? true),
                createdAt: current?.createdAt ?? now,
                updatedAt: now,
              ),
            );
        await CreditLedger(_database, uuid: _uuid).syncOpeningBalance(
          customerId: customerId,
          previous: current?.openingBalance ?? 0,
          next: row.openingBalance ?? current?.openingBalance ?? 0,
          storeId: session.store.id,
          userId: session.user.id,
          at: now,
        );
        if (row.existingId == null) {
          created++;
        } else {
          updated++;
        }
      }
      await _database
          .into(_database.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              userId: Value(session.user.id),
              storeId: Value(session.store.id),
              action: 'customers.imported',
              entityType: 'customer',
              description: 'CSV import: $created created, $updated updated.',
              createdAt: now,
            ),
          );
    });
    return ImportOutcome(
      created: created,
      updated: updated,
      skipped: plan.preview.count(ImportAction.skip),
    );
  }

  Future<List<List<Object?>>> export(AppSession session) async {
    PermissionGuard.require(session, Permissions.customersView);
    final customers = await (_database.select(
      _database.customers,
    )..orderBy([(c) => OrderingTerm.asc(c.name)])).get();
    return [
      columns,
      for (final c in customers)
        [
          c.name,
          c.phone,
          c.email,
          c.address,
          c.notes,
          c.creditLimit,
          c.openingBalance,
          c.loyaltyPoints,
          c.isActive ? 'yes' : 'no',
        ],
    ];
  }
}
