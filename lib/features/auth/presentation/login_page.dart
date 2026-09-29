import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/session_controller.dart';
import '../domain/app_session.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({this.lockedSession, super.key});
  final AppSession? lockedSession;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _username.text = widget.lockedSession?.user.username ?? '';
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _busy) return;
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
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        Expanded(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.primary,
            child: Padding(
              padding: const EdgeInsets.all(56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.bolt_rounded, size: 54, color: Colors.white),
                  const SizedBox(height: 24),
                  Text(
                    'Fast at the counter.\nReliable everywhere.',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Your sales and inventory stay on this PC and remain available offline.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
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
                    Text(
                      widget.lockedSession == null
                          ? 'Welcome back'
                          : 'StoreFlow is locked',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      widget.lockedSession == null
                          ? 'Sign in with your local StoreFlow account.'
                          : 'Enter your password to continue.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _username,
                      enabled: widget.lockedSession == null && !_busy,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter your username.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      autofocus: widget.lockedSession != null,
                      obscureText: _obscure,
                      enabled: !_busy,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
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
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                        widget.lockedSession == null ? 'Sign in' : 'Unlock',
                      ),
                    ),
                    if (widget.lockedSession != null) ...[
                      const SizedBox(height: 8),
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
