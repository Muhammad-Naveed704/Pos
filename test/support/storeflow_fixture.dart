import 'package:drift/native.dart';
import 'package:storeflow_pos/core/database/app_database.dart';
import 'package:storeflow_pos/features/auth/data/auth_repository.dart';
import 'package:storeflow_pos/features/auth/data/password_hasher.dart';
import 'package:storeflow_pos/features/auth/domain/app_session.dart';
import 'package:storeflow_pos/features/setup/data/first_run_service.dart';

class StoreFlowFixture {
  StoreFlowFixture()
    : database = AppDatabase(executor: NativeDatabase.memory());
  final AppDatabase database;

  Future<AppSession> initialize() async {
    await FirstRunService(database, PasswordHasher()).complete(
      const FirstRunInput(
        businessName: 'Test Business',
        storeName: 'Main Store',
        storeCode: 'MAIN',
        address: 'Test address',
        phone: '000',
        currency: 'PKR',
        timezone: 'Asia/Karachi',
        ownerName: 'Test Owner',
        username: 'owner',
        password: 'test-password',
        taxMode: 'exclusive',
        receiptFooter: 'Thanks',
      ),
    );
    return AuthRepository(
      database,
      PasswordHasher(),
    ).authenticate('owner', 'test-password');
  }

  Future<void> close() => database.close();
}
