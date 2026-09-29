import '../../../core/database/app_database.dart';

class AppSession {
  const AppSession({
    required this.user,
    required this.role,
    required this.store,
    required this.permissions,
    this.isLocked = false,
  });

  final User user;
  final Role role;
  final Store store;
  final Set<String> permissions;
  final bool isLocked;

  bool can(String permission) => permissions.contains(permission);

  AppSession copyWith({Store? store, bool? isLocked}) => AppSession(
    user: user,
    role: role,
    store: store ?? this.store,
    permissions: permissions,
    isLocked: isLocked ?? this.isLocked,
  );
}

sealed class SessionState {
  const SessionState();
}

class SessionSignedOut extends SessionState {
  const SessionSignedOut();
}

class SessionActive extends SessionState {
  const SessionActive(this.session);
  final AppSession session;
}
