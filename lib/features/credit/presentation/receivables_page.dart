import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/credit_service.dart';
import '../domain/credit.dart';
import 'receive_payment_dialog.dart';

/// Business-wide accounts receivable: who owes what, and what is overdue.
class ReceivablesPage extends ConsumerStatefulWidget {
  const ReceivablesPage({this.overdueOnly = false, super.key});
  final bool overdueOnly;

  @override
  ConsumerState<ReceivablesPage> createState() => _ReceivablesPageState();
}

class _ReceivablesPageState extends ConsumerState<ReceivablesPage> {
  late bool _overdueOnly = widget.overdueOnly;
  late Future<ReceivablesSummary> _summary;
  late Future<List<Debtor>> _debtors;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(ReceivablesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overdueOnly != widget.overdueOnly) {
      _overdueOnly = widget.overdueOnly;
      _reload();
    }
  }

  void _reload() {
    final session = ref.read(activeSessionProvider)!;
    final service = ref.read(creditServiceProvider);
    _summary = service.receivables(session);
    _debtors = service.debtorList(session, overdueOnly: _overdueOnly);
  }

  Future<void> _receive([String? customerId]) async {
    if (!ref
        .read(activeSessionProvider)!
        .can(Permissions.creditReceivePayment)) {
      return;
    }
    final result = await showReceivePaymentDialog(
      context,
      customerId: customerId,
    );
    if (result != null && mounted) {
      final money = ref.read(moneyFormatterProvider);
      Toast.success(
        context,
        '${result.number}: ${money.format(result.amount)} received.',
      );
      setState(_reload);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final money = ref.watch(moneyFormatterProvider);
    final canReceive = session.can(Permissions.creditReceivePayment);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
          shift: true,
        ): _receive,
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Receivables',
                subtitle: 'Customer balances across all stores. Click a customer to see their ledger.',
                actions: [
                  if (canReceive)
                    FilledButton.icon(
                      onPressed: _receive,
                      icon: const Icon(Icons.price_check_rounded),
                      label: const Text('Receive payment'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<ReceivablesSummary>(
                future: _summary,
                builder: (context, snapshot) {
                  final s = snapshot.data;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 36) / 4;
                      Widget card(
                        String label,
                        String value,
                        IconData icon,
                        Color color, {
                        String? note,
                        VoidCallback? onTap,
                      }) => SizedBox(
                        width: width,
                        child: InkWell(
                          borderRadius: context.tokens.borderRadius,
                          onTap: onTap,
                          child: StatCard(
                            label: label,
                            value: value,
                            icon: icon,
                            color: color,
                            footnote: note,
                          ),
                        ),
                      );
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          card(
                            'Total receivable',
                            s == null ? '…' : money.format(s.total),
                            Icons.account_balance_wallet_outlined,
                            context.colors.primary,
                            note: 'Owed by customers',
                            onTap: () => setState(() {
                              _overdueOnly = false;
                              _reload();
                            }),
                          ),
                          card(
                            'Overdue',
                            s == null ? '…' : money.format(s.overdue),
                            Icons.error_outline_rounded,
                            context.colors.error,
                            note: 'Past due · tap to filter',
                            onTap: () => setState(() {
                              _overdueOnly = true;
                              _reload();
                            }),
                          ),
                          card(
                            'Due this week',
                            s == null ? '…' : money.format(s.dueThisWeek),
                            Icons.schedule_rounded,
                            context.tokens.warning,
                            note: 'Next 7 days',
                          ),
                          card(
                            'Customers owing',
                            s == null ? '…' : '${s.customers}',
                            Icons.groups_outlined,
                            context.tokens.info,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  AppSegmented<bool>(
                    items: const [
                      SegmentItem(false, 'All balances'),
                      SegmentItem(
                        true,
                        'Overdue only',
                        icon: Icons.error_outline_rounded,
                      ),
                    ],
                    value: _overdueOnly,
                    onChanged: (value) => setState(() {
                      _overdueOnly = value;
                      _reload();
                    }),
                  ),
                  const SizedBox(width: 12),
                  SearchField(
                    width: 280,
                    hint: 'Search customer or phone',
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: FutureBuilder<List<Debtor>>(
                    future: _debtors,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: 'Receivables could not be loaded',
                          message: friendlyError(snapshot.error!),
                        );
                      }
                      final all = snapshot.data;
                      if (all == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final term = _search.trim().toLowerCase();
                      final debtors = term.isEmpty
                          ? all
                          : all
                                .where(
                                  (d) =>
                                      d.name.toLowerCase().contains(term) ||
                                      (d.phone ?? '').contains(term),
                                )
                                .toList();
                      return Column(
                        children: [
                          Container(
                            color: context.colors.surfaceContainerHigh,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: const Row(
                              children: [
                                Expanded(flex: 4, child: _Head('Customer')),
                                Expanded(
                                  flex: 2,
                                  child: _Head('Outstanding', end: true),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: _Head('Overdue', end: true),
                                ),
                                SizedBox(width: 16),
                                Expanded(flex: 3, child: _Head('Oldest due')),
                                SizedBox(width: 120),
                              ],
                            ),
                          ),
                          Expanded(
                            child: debtors.isEmpty
                                ? EmptyState(
                                    icon: Icons.task_alt_rounded,
                                    title: _overdueOnly
                                        ? 'Nothing overdue'
                                        : 'No customer owes money',
                                    message: 'Credit and partial sales appear here until they are paid.',
                                  )
                                : ListView.separated(
                                    itemCount: debtors.length,
                                    separatorBuilder: (_, _) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final d = debtors[index];
                                      return InkWell(
                                        onTap: () => context.go(
                                          '/customers/${d.customerId}',
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 4,
                                                child: Row(
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 16,
                                                      child: Text(
                                                        d.name.characters.first
                                                            .toUpperCase(),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            d.name,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                          ),
                                                          if (d.phone != null)
                                                            Text(
                                                              d.phone!,
                                                              style: context
                                                                  .text
                                                                  .bodySmall,
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  money.format(d.outstanding),
                                                  textAlign: TextAlign.end,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  d.overdue.minorUnits == 0
                                                      ? '—'
                                                      : money.format(d.overdue),
                                                  textAlign: TextAlign.end,
                                                  style: TextStyle(
                                                    color:
                                                        d.overdue.minorUnits > 0
                                                        ? context.colors.error
                                                        : null,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                flex: 3,
                                                child: d.oldestDue == null
                                                    ? const Text('No due date')
                                                    : Row(
                                                        children: [
                                                          DueStatusPill(
                                                            DueStatus.of(
                                                              d.oldestDue,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Text(
                                                            DateFormat(
                                                              'd MMM y',
                                                            ).format(
                                                              d.oldestDue!,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                              SizedBox(
                                                width: 120,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: canReceive
                                                      ? TextButton(
                                                          onPressed: () =>
                                                              _receive(
                                                                d.customerId,
                                                              ),
                                                          child: const Text(
                                                            'Receive',
                                                          ),
                                                        )
                                                      : const Icon(
                                                          Icons
                                                              .chevron_right_rounded,
                                                        ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.label, {this.end = false});
  final String label;
  final bool end;

  @override
  Widget build(BuildContext context) => Text(
    label,
    textAlign: end ? TextAlign.end : TextAlign.start,
    style: const TextStyle(fontWeight: FontWeight.w800),
  );
}
