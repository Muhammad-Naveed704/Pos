import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/credit_service.dart';
import '../domain/credit.dart';
import 'receive_payment_dialog.dart';

final dashboardReceivablesProvider =
    FutureProvider.autoDispose<ReceivablesSummary>(
      (ref) => ref
          .watch(creditServiceProvider)
          .receivables(ref.watch(activeSessionProvider)!),
    );

/// Dashboard summary of customer balances (all stores).
class ReceivablesCard extends ConsumerWidget {
  const ReceivablesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyFormatterProvider);
    final summary = ref.watch(dashboardReceivablesProvider);
    return SectionCard(
      title: 'Receivables',
      subtitle: 'Customer balances across all stores',
      icon: Icons.request_quote_outlined,
      trailing: TextButton(
        onPressed: () => context.go('/receivables'),
        child: const Text('All balances'),
      ),
      child: summary.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text(friendlyError(error)),
        data: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Figure(
                  label: 'Total receivable',
                  value: money.format(s.total),
                  note: '${s.customers} customer(s)',
                  onTap: () => context.go('/receivables'),
                ),
                _Figure(
                  label: 'Overdue',
                  value: money.format(s.overdue),
                  icon: Icons.error_outline_rounded,
                  color: s.overdue.minorUnits > 0 ? context.colors.error : null,
                  onTap: () => context.go('/receivables?filter=overdue'),
                ),
                _Figure(
                  label: 'Due this week',
                  value: money.format(s.dueThisWeek),
                  icon: Icons.schedule_rounded,
                  color: s.dueThisWeek.minorUnits > 0
                      ? context.tokens.warning
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (s.topDebtors.isEmpty)
              const EmptyState(
                compact: true,
                icon: Icons.task_alt_rounded,
                title: 'No customer owes money',
              )
            else ...[
              Text(
                'TOP BALANCES',
                style: context.text.labelSmall?.copyWith(
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              for (final debtor in s.topDebtors)
                InkWell(
                  borderRadius: context.tokens.borderRadius,
                  onTap: () => context.go('/customers/${debtor.customerId}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            debtor.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (debtor.oldestDue != null) ...[
                          DueStatusPill(DueStatus.of(debtor.oldestDue)),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('d MMM').format(debtor.oldestDue!),
                            style: context.text.bodySmall,
                          ),
                        ],
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: Text(
                            money.format(debtor.outstanding),
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.note,
    this.icon,
    this.color,
    this.onTap,
  });
  final String label;
  final String value;
  final String? note;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: context.tokens.borderRadius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            Text(
              value,
              style: context.text.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            if (note != null) Text(note!, style: context.text.bodySmall),
          ],
        ),
      ),
    ),
  );
}

/// Opens Receive payment from anywhere (Ctrl+Shift+P).
Future<void> receivePaymentShortcut(BuildContext context, WidgetRef ref) async {
  final money = ref.read(moneyFormatterProvider);
  final result = await showReceivePaymentDialog(context);
  if (result == null || !context.mounted) return;
  ref.invalidate(dashboardReceivablesProvider);
  Toast.success(
    context,
    '${result.number}: ${money.format(result.amount)} received. '
    'Balance now ${money.format(result.balance)}.',
  );
}
