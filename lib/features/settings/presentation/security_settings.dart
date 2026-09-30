import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/data/account_recovery_service.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/recovery_dialogs.dart';

final _recoveryKeyDateProvider = FutureProvider.autoDispose<DateTime?>(
  (ref) => ref.watch(accountRecoveryServiceProvider).keyCreatedAt(),
);

class SecuritySettings extends ConsumerStatefulWidget {
  const SecuritySettings({super.key});
  @override
  ConsumerState<SecuritySettings> createState() => _SecuritySettingsState();
}

class _SecuritySettingsState extends ConsumerState<SecuritySettings> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final exists = ref.read(_recoveryKeyDateProvider).value != null;
    if (exists) {
      final confirmed = await confirmDialog(
        context,
        title: 'Replace the recovery key?',
        message: 'The current recovery key will stop working immediately.',
        confirmLabel: 'Generate new key',
      );
      if (!confirmed) return;
    }
    try {
      final key = await ref
          .read(accountRecoveryServiceProvider)
          .generate(ref.read(activeSessionProvider)!);
      ref.invalidate(_recoveryKeyDateProvider);
      if (mounted) await showRecoveryKeyDialog(context, key);
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  Future<void> _changePassword() async {
    if (_next.text.length < 8) {
      setState(() => _error = 'New password must have at least 8 characters.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(accountRecoveryServiceProvider)
          .changeOwnPassword(
            session: ref.read(activeSessionProvider)!,
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      _current.clear();
      _next.clear();
      _confirm.clear();
      if (mounted) Toast.success(context, 'Password changed.');
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final keyDate = ref.watch(_recoveryKeyDateProvider);
    final canManage = session.can(Permissions.usersManage);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      children: [
        if (canManage)
          SectionCard(
            title: 'Account recovery key',
            subtitle: 'Lets an owner reset a forgotten password on the sign-in screen, without internet.',
            icon: Icons.key_rounded,
            child: Row(
              children: [
                keyDate.when(
                  loading: () => const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, _) => const StatusPill('Unknown'),
                  data: (date) => date == null
                      ? const StatusPill(
                          'No key set up',
                          tone: PillTone.warning,
                          icon: Icons.warning_amber_rounded,
                        )
                      : StatusPill(
                          'Active since ${DateFormat('d MMM y').format(date)}',
                          tone: PillTone.success,
                          icon: Icons.verified_user_outlined,
                        ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.autorenew_rounded),
                  label: Text(
                    keyDate.value == null ? 'Generate key' : 'Generate new key',
                  ),
                ),
              ],
            ),
          ),
        if (canManage) const SizedBox(height: 16),
        SectionCard(
          title: 'Change my password',
          subtitle: 'Signed in as @${session.user.username}',
          icon: Icons.password_rounded,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _current,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _next,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    helperText: 'At least 8 characters.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                  onSubmitted: (_) => _changePassword(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: context.colors.error)),
                ],
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _changePassword,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Update password'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
