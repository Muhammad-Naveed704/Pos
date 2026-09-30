import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui_kit.dart';
import '../data/account_recovery_service.dart';

/// Shows a freshly generated recovery key exactly once.
Future<void> showRecoveryKeyDialog(BuildContext context, String key) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecoveryKeyDialog(recoveryKey: key),
    );

class _RecoveryKeyDialog extends StatefulWidget {
  const _RecoveryKeyDialog({required this.recoveryKey});
  final String recoveryKey;
  @override
  State<_RecoveryKeyDialog> createState() => _RecoveryKeyDialogState();
}

class _RecoveryKeyDialogState extends State<_RecoveryKeyDialog> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.key_rounded, size: 36),
    title: const Text('Save your recovery key'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'If you forget your password, this key lets you set a new one on the '
            'sign-in screen. Write it down or store it somewhere safe. It is '
            'shown only once and works once.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color: context.colors.primaryContainer,
              borderRadius: context.tokens.borderRadius,
            ),
            child: SelectableText(
              widget.recoveryKey,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 22,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
                color: context.colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.recoveryKey));
                Toast.success(context, 'Recovery key copied.');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy'),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _saved,
            onChanged: (value) => setState(() => _saved = value ?? false),
            title: const Text('I have saved this key somewhere safe'),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: _saved ? () => Navigator.pop(context) : null,
        child: const Text('Continue'),
      ),
    ],
  );
}

/// "Forgot password" flow on the sign-in screen.
Future<void> showForgotPasswordDialog(
  BuildContext context, {
  String username = '',
}) => showDialog<void>(
  context: context,
  builder: (_) => _ForgotPasswordDialog(username: username),
);

class _ForgotPasswordDialog extends ConsumerStatefulWidget {
  const _ForgotPasswordDialog({required this.username});
  final String username;
  @override
  ConsumerState<_ForgotPasswordDialog> createState() =>
      _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<_ForgotPasswordDialog> {
  late final _username = TextEditingController(text: widget.username);
  final _key = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_username, _key, _password, _confirm]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _key.text.trim().isEmpty) {
      setState(() => _error = 'Enter your username and recovery key.');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = 'New password must have at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
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
          .resetPassword(
            username: _username.text,
            recoveryKey: _key.text,
            newPassword: _password.text,
          );
      if (!mounted) return;
      Navigator.pop(context);
      Toast.success(
        context,
        'Password reset. Sign in, then generate a new recovery key in Settings → Security.',
      );
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.lock_reset_rounded, size: 34),
    title: const Text('Reset your password'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.tokens.infoContainer,
              borderRadius: context.tokens.borderRadius,
            ),
            child: Text(
              'Staff: ask an owner or admin to reset your password from '
              'Users & roles.\nOwners: use the recovery key saved during setup.',
              style: TextStyle(color: context.tokens.info),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _username,
            autofocus: widget.username.isEmpty,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            autofocus: widget.username.isNotEmpty,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Recovery key',
              hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX',
              prefixIcon: Icon(Icons.key_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: context.colors.error)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Reset password'),
      ),
    ],
  );
}
