import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/theme_controller.dart';
import '../../pos/application/cart_controller.dart';
import '../data/auth_repository.dart';
import '../domain/app_session.dart';

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  static const _storePreference = 'session.lastStoreId';

  AuthRepository get _auth => ref.read(authRepositoryProvider);
  SharedPreferences get _preferences => ref.read(sharedPreferencesProvider);

  @override
  SessionState build() => const SessionSignedOut();

  Future<void> login(String username, String password) async {
    var session = await _auth.authenticate(username, password);
    final preferredStore = _preferences.getString(_storePreference);
    if (preferredStore != null) {
      try {
        final store = await _auth.requireStoreForUser(
          session.user,
          preferredStore,
        );
        session = session.copyWith(store: store);
      } on AuthenticationException {
        await _preferences.remove(_storePreference);
      }
    }
    state = SessionActive(session);
    await _preferences.setString(_storePreference, session.store.id);
  }

  Future<void> switchStore(String storeId) async {
    final current = state;
    if (current is! SessionActive) {
      throw StateError('A user must be signed in to switch stores.');
    }
    final store = await _auth.requireStoreForUser(
      current.session.user,
      storeId,
    );
    ref.invalidate(cartControllerProvider);
    state = SessionActive(current.session.copyWith(store: store));
    await _preferences.setString(_storePreference, store.id);
  }

  void lock() {
    final current = state;
    if (current is SessionActive) {
      state = SessionActive(current.session.copyWith(isLocked: true));
    }
  }

  Future<void> unlock(String password) async {
    final current = state;
    if (current is! SessionActive) return;
    final refreshed = await _auth.authenticate(
      current.session.user.username,
      password,
    );
    state = SessionActive(
      refreshed.copyWith(store: current.session.store, isLocked: false),
    );
  }

  void logout() {
    ref.invalidate(cartControllerProvider);
    state = const SessionSignedOut();
  }
}

final activeSessionProvider = Provider<AppSession?>((ref) {
  final state = ref.watch(sessionControllerProvider);
  return state is SessionActive ? state.session : null;
});
