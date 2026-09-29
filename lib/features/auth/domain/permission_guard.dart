import 'app_session.dart';

class PermissionDeniedException implements Exception {
  const PermissionDeniedException(this.permission);
  final String permission;
  @override
  String toString() => 'Permission denied: $permission';
}

abstract final class PermissionGuard {
  static void require(AppSession session, String permission) {
    if (!session.can(permission)) {
      throw PermissionDeniedException(permission);
    }
  }
}
