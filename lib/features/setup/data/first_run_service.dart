import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../auth/data/password_hasher.dart';
import '../../auth/domain/permissions.dart';

class FirstRunInput {
  const FirstRunInput({
    required this.businessName,
    required this.storeName,
    required this.storeCode,
    required this.address,
    required this.phone,
    required this.currency,
    required this.timezone,
    required this.ownerName,
    required this.username,
    required this.password,
    required this.taxMode,
    required this.receiptFooter,
    this.numberStyle = 'international',
    this.taxLabel = 'Tax',
  });

  final String businessName;
  final String storeName;
  final String storeCode;
  final String address;
  final String phone;
  final String currency;
  final String timezone;
  final String ownerName;
  final String username;
  final String password;
  final String taxMode;
  final String receiptFooter;
  final String numberStyle;
  final String taxLabel;
}

final firstRunServiceProvider = Provider<FirstRunService>(
  (ref) => FirstRunService(ref.watch(databaseProvider), PasswordHasher()),
);

final setupRequiredProvider = FutureProvider<bool>(
  (ref) => ref.watch(firstRunServiceProvider).isSetupRequired(),
);

class FirstRunService {
  FirstRunService(this._database, this._passwordHasher, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final PasswordHasher _passwordHasher;
  final Uuid _uuid;

  Future<bool> isSetupRequired() async {
    final storeCount = await _database.stores.count().getSingle();
    final ownerRole =
        await (_database.select(_database.roles)
              ..where((role) => role.name.equals('Owner'))
              ..limit(1))
            .getSingleOrNull();
    if (storeCount == 0 || ownerRole == null) return true;
    final ownerCount =
        await (_database.select(_database.users)
              ..where((user) => user.roleId.equals(ownerRole.id)))
            .get()
            .then((rows) => rows.length);
    return ownerCount == 0;
  }

  Future<void> complete(FirstRunInput input) async {
    if (!await isSetupRequired()) {
      throw StateError('First-run setup has already been completed.');
    }
    final username = input.username.trim().toLowerCase();
    if (username.isEmpty || input.storeName.trim().isEmpty) {
      throw ArgumentError('Store and username are required.');
    }
    final password = await _passwordHasher.hash(input.password);
    final now = DateTime.now();
    final storeId = _uuid.v4();
    final ownerRoleId = _uuid.v4();

    await _database.transaction(() async {
      await _database
          .into(_database.stores)
          .insert(
            StoresCompanion.insert(
              id: storeId,
              name: input.storeName.trim(),
              code: input.storeCode.trim().toUpperCase(),
              address: Value(input.address.trim()),
              phone: Value(input.phone.trim()),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final roles = <({String id, String name, Set<String> permissions})>[
        (id: ownerRoleId, name: 'Owner', permissions: Permissions.all),
        (id: _uuid.v4(), name: 'Admin', permissions: Permissions.admin),
        (id: _uuid.v4(), name: 'Manager', permissions: Permissions.manager),
        (id: _uuid.v4(), name: 'Cashier', permissions: Permissions.cashier),
        (
          id: _uuid.v4(),
          name: 'Inventory Staff',
          permissions: Permissions.inventoryStaff,
        ),
      ];
      await _database.batch((batch) {
        batch.insertAll(
          _database.roles,
          roles
              .map(
                (role) => RolesCompanion.insert(
                  id: role.id,
                  name: role.name,
                  permissionsJson: Value(
                    jsonEncode(role.permissions.toList()..sort()),
                  ),
                  isSystem: const Value(true),
                  createdAt: now,
                  updatedAt: now,
                ),
              )
              .toList(),
        );
      });

      final userId = _uuid.v4();
      await _database
          .into(_database.users)
          .insert(
            UsersCompanion.insert(
              id: userId,
              username: username,
              displayName: input.ownerName.trim(),
              passwordHash: password.hash,
              passwordSalt: password.salt,
              roleId: ownerRoleId,
              storeId: const Value(null),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final settings = <String, String>{
        'business.name': input.businessName.trim(),
        'currency.code': input.currency,
        'currency.numberStyle': input.numberStyle,
        'tax.label': input.taxLabel.trim().isEmpty
            ? 'Tax'
            : input.taxLabel.trim(),
        'timezone': input.timezone,
        'tax.mode': input.taxMode,
        'receipt.footer': input.receiptFooter.trim(),
        'inventory.allowNegative': 'false',
        'sales.maxDiscountPercent': '100',
        'sales.allowPriceOverride': 'true',
      };
      await _database.batch((batch) {
        batch.insertAll(
          _database.appSettings,
          settings.entries
              .map(
                (entry) => AppSettingsCompanion.insert(
                  key: entry.key,
                  value: entry.value,
                  updatedAt: now,
                ),
              )
              .toList(),
        );
      });
      await _database
          .into(_database.invoiceSequences)
          .insert(
            InvoiceSequencesCompanion.insert(storeId: storeId, year: now.year),
          );
      await _database
          .into(_database.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              userId: Value(userId),
              storeId: Value(storeId),
              action: 'setup.completed',
              entityType: 'application',
              description: 'Initial business, store and owner account created.',
              createdAt: now,
            ),
          );
    });
  }
}
