import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/application/session_controller.dart';
import '../features/auth/domain/app_session.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/setup/data/first_run_service.dart';
import '../features/setup/presentation/setup_wizard.dart';

class ApplicationGate extends ConsumerWidget {
  const ApplicationGate({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(setupRequiredProvider);
    return setup.when(
      loading: () => const _StartupScreen(),
      error: (error, stack) => _StartupError(
        error: error,
        onRetry: () => ref.invalidate(setupRequiredProvider),
      ),
      data: (required) {
        if (required) return const SetupWizard();
        final session = ref.watch(sessionControllerProvider);
        if (session is! SessionActive || session.session.isLocked) {
          return LoginPage(
            lockedSession: session is SessionActive ? session.session : null,
          );
        }
        return child;
      },
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bolt_rounded,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          const Text('Starting StoreFlow…'),
          const SizedBox(height: 16),
          const SizedBox(width: 180, child: LinearProgressIndicator()),
        ],
      ),
    ),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  size: 38,
                ),
                const SizedBox(height: 12),
                const Text('StoreFlow could not open its local database.'),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
