import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui_kit.dart';
import '../../settings/data/business_settings_repository.dart';
import '../application/session_controller.dart';
import '../domain/app_session.dart';
import 'recovery_dialogs.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({this.lockedSession, super.key});
  final AppSession? lockedSession;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final _username = TextEditingController(
    text: widget.lockedSession?.user.username ?? '',
  );
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = ref.read(sessionControllerProvider.notifier);
      if (widget.lockedSession == null) {
        await controller.login(_username.text, _password.text);
      } else {
        await controller.unlock(_password.text);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyError(error));
        _password.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.lockedSession;
    final scheme = context.colors;
    final business = ref.watch(currentBusinessSettingsProvider).businessName;
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary,
                    // Darker shade of the same hue keeps white text readable
                    // with every preset (tertiary can be very light).
                    Color.alphaBlend(
                      Colors.black.withValues(alpha: 0.35),
                      scheme.primary,
                    ),
                  ],
                ),
              ),
              padding: const EdgeInsets.all(56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 44, onDark: true),
                      const SizedBox(width: 12),
                      Text(
                        'StoreFlow POS',
                        style: context.text.titleLarge?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    business.isEmpty
                        ? 'Fast at the counter.\nReliable everywhere.'
                        : business,
                    style: context.text.displaySmall?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ).entrance(context),
                  const SizedBox(height: 18),
                  for (final (icon, text) in const [
                    (Icons.wifi_off_rounded, 'Works fully offline'),
                    (Icons.shield_outlined, 'Your data stays on this PC'),
                    (
                      Icons.keyboard_rounded,
                      'Keyboard & barcode-scanner first',
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: scheme.onPrimary.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            text,
                            style: TextStyle(
                              color: scheme.onPrimary.withValues(alpha: 0.85),
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 500,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(54),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (locked != null) ...[
                        Center(
                          child: CircleAvatar(
                            radius: 34,
                            backgroundColor: scheme.primaryContainer,
                            child: Icon(
                              Icons.lock_rounded,
                              size: 30,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      Text(
                        locked == null
                            ? 'Welcome back'
                            : 'Locked · ${locked.user.displayName}',
                        textAlign: locked == null
                            ? TextAlign.start
                            : TextAlign.center,
                        style: context.text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        locked == null
                            ? 'Sign in with your StoreFlow account.'
                            : 'Enter your password to continue. Your sale is kept.',
                        textAlign: locked == null
                            ? TextAlign.start
                            : TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),
                      if (locked == null) ...[
                        TextFormField(
                          controller: _username,
                          autofocus: true,
                          enabled: !_busy,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter your username.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _password,
                        autofocus: locked != null,
                        obscureText: _obscure,
                        enabled: !_busy,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter your password.'
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => showForgotPasswordDialog(
                                  context,
                                  username:
                                      locked?.user.username ??
                                      _username.text.trim(),
                                ),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      AnimatedSize(
                        duration: context.tokens.motion(160),
                        child: _error == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: scheme.errorContainer,
                                    borderRadius: context.tokens.borderRadius,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline_rounded,
                                        color: scheme.onErrorContainer,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(
                                            color: scheme.onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  locked == null
                                      ? Icons.login_rounded
                                      : Icons.lock_open_rounded,
                                ),
                          label: Text(locked == null ? 'Sign in' : 'Unlock'),
                        ),
                      ),
                      if (locked != null) ...[
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : ref
                                    .read(sessionControllerProvider.notifier)
                                    .logout,
                          child: const Text('Sign in as another user'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
