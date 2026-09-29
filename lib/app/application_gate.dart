import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/application/session_controller.dart';
import '../features/auth/domain/app_session.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/setup/data/first_run_service.dart';
import '../features/setup/presentation/setup_wizard.dart';
import '../core/ui/brand_mark.dart';

/// Chooses between first-run setup, sign-in, the lock screen and the app.
///
/// This widget sits in `MaterialApp.builder`, above the router's Navigator.
/// Screens rendered here therefore get their own [Navigator] (and with it an
/// [Overlay]); without one, text fields cannot show selection handles and
/// dropdowns/dialogs cannot open, which corrupted text editing on Windows.
class ApplicationGate extends ConsumerWidget {
  const ApplicationGate({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(setupRequiredProvider);
    return setup.when(
      loading: () => const _StartupScreen(),
      error: (error, stack) => _GateNavigator(
        key: const ValueKey('startup-error'),
        child: _StartupError(
          error: error,
          onRetry: () => ref.invalidate(setupRequiredProvider),
        ),
      ),
      data: (required) {
        if (required) {
          return const _GateNavigator(
            key: ValueKey('setup'),
            child: SetupWizard(),
          );
        }
        final session = ref.watch(sessionControllerProvider);
        if (session is! SessionActive) {
          return const _GateNavigator(
            key: ValueKey('login'),
            child: LoginPage(),
          );
        }
        // Keep the workspace mounted while locked so an in-progress sale and
        // page state survive; it is hidden and cannot receive focus.
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(
              excluding: session.session.isLocked,
              child: Offstage(offstage: session.session.isLocked, child: child),
            ),
            if (session.session.isLocked)
              _GateNavigator(
                key: const ValueKey('lock'),
                child: LoginPage(lockedSession: session.session),
              ),
          ],
        );
      },
    );
  }
}

class _GateNavigator extends StatelessWidget {
  const _GateNavigator({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Navigator(
    pages: [MaterialPage<void>(child: child)],
    onDidRemovePage: (_) {},
  );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandMark(size: 56),
          const SizedBox(height: 18),
          const Text('Starting StoreFlow…'),
          const SizedBox(height: 16),
          SizedBox(
            width: 180,
            child: LinearProgressIndicator(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
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
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                  size: 42,
                ),
                const SizedBox(height: 12),
                Text(
                  'StoreFlow could not open its local database.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SelectableText('$error', textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
