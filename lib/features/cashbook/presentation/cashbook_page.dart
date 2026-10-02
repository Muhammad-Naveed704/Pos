import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/cashbook_service.dart';

class CashbookPage extends ConsumerStatefulWidget {
  const CashbookPage({super.key});
  @override
  ConsumerState<CashbookPage> createState() => _CashbookPageState();
}

class _CashbookPageState extends ConsumerState<CashbookPage> {
  Stream<CashSessionSummary?>? _current;
  late final Stream<List<CashSessionSummary>> _history;

  @override
  void initState() {
    super.initState();
    final session = ref.read(activeSessionProvider)!;
    final service = ref.read(cashbookServiceProvider);
    if (session.can(Permissions.cashbookManage)) {
      _current = service.watchCurrent(session);
    }
    _history = service.watchSessions(session);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final money = ref.watch(moneyFormatterProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Cashbook',
            subtitle:
                'Cash drawer sessions for ${session.store.name}: opening float, cash sales, pay-ins, pay-outs and closing count.',
          ),
          const SizedBox(height: 16),
          if (_current != null)
            StreamBuilder<CashSessionSummary?>(
              stream: _current,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final current = snapshot.data;
                return current == null
                    ? _OpenSessionCard(money: money)
                    : _CurrentSessionCard(summary: current, money: money);
              },
            ),
          const SizedBox(height: 16),
          Text(
            session.can(Permissions.cashbookView)
                ? 'All sessions'
                : 'My sessions',
            style: context.text.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: StreamBuilder<List<CashSessionSummary>>(
                stream: _history,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Sessions could not be loaded',
                      message: friendlyError(snapshot.error!),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = snapshot.data!;
                  if (rows.isEmpty) {
                    return const EmptyState(
                      icon: Icons.point_of_sale_outlined,
                      title: 'No cash sessions yet',
                      message: 'Open the drawer at the start of a shift and close it with a cash count at the end.',
                    );
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) =>
                        _SessionTile(summary: rows[index], money: money),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenSessionCard extends ConsumerStatefulWidget {
  const _OpenSessionCard({required this.money});
  final MoneyFormatter money;
  @override
  ConsumerState<_OpenSessionCard> createState() => _OpenSessionCardState();
}

class _OpenSessionCardState extends ConsumerState<_OpenSessionCard> {
  final _float = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final value = widget.money.parse(_float.text) ?? 0;
    setState(() => _busy = true);
    try {
      await ref
          .read(cashbookServiceProvider)
          .openSession(
            ref.read(activeSessionProvider)!,
            Money.fromMajor(value),
          );
      if (mounted) Toast.success(context, 'Cash session opened.');
    } catch (error) {
      if (mounted) Toast.error(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Drawer is closed',
    subtitle: 'Count the cash in the drawer and open your session.',
    icon: Icons.lock_clock_outlined,
    child: Row(
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _float,
            autofocus: true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Opening cash (float)',
              prefixText: '${widget.money.symbol} ',
            ),
            onSubmitted: (_) => _open(),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _open,
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('Open session'),
        ),
      ],
    ),
  );
}

class _CurrentSessionCard extends ConsumerWidget {
  const _CurrentSessionCard({required this.summary, required this.money});
  final CashSessionSummary summary;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = [
      ('Opening', summary.opening, Icons.flag_outlined, null),
      (
        'Cash sales',
        summary.cashSales,
        Icons.point_of_sale_rounded,
        context.colors.primary,
      ),
      (
        'Pay-ins',
        summary.payIns,
        Icons.south_west_rounded,
        context.tokens.success,
      ),
      (
        'Pay-outs',
        summary.payOuts,
        Icons.north_east_rounded,
        context.colors.error,
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusPill(
                  'Open since ${DateFormat('h:mm a, d MMM').format(summary.session.openedAt)}',
                  tone: PillTone.success,
                  icon: Icons.circle,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _entry(context, ref, CashType.payIn),
                  icon: const Icon(Icons.south_west_rounded),
                  label: const Text('Pay in'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _entry(context, ref, CashType.payOut),
                  icon: const Icon(Icons.north_east_rounded),
                  label: const Text('Pay out'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => _CloseDialog(summary: summary),
                  ),
                  icon: const Icon(Icons.lock_rounded),
                  label: const Text('Close & count'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                for (final (label, value, icon, color) in stats) ...[
                  Expanded(
                    child: Row(
                      children: [
                        IconTile(icon: icon, color: color, size: 36),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              money.format(value),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    borderRadius: context.tokens.borderRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Expected in drawer',
                        style: TextStyle(
                          color: context.colors.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        money.format(summary.expected),
                        style: context.text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: context.colors.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _entry(BuildContext context, WidgetRef ref, String type) =>
      showDialog<void>(
        context: context,
        builder: (_) => _EntryDialog(type: type),
      );
}

class _EntryDialog extends ConsumerStatefulWidget {
  const _EntryDialog({required this.type});
  final String type;
  @override
  ConsumerState<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends ConsumerState<_EntryDialog> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  late String _category =
      (widget.type == CashType.payOut ? payOutCategories : payInCategories)
          .first;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = ref.read(moneyFormatterProvider).parse(_amount.text);
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(cashbookServiceProvider)
          .record(
            ref.read(activeSessionProvider)!,
            type: widget.type,
            amount: Money.fromMajor(value),
            category: _category,
            description: _description.text,
          );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payOut = widget.type == CashType.payOut;
    final money = ref.watch(moneyFormatterProvider);
    return AlertDialog(
      icon: Icon(payOut ? Icons.north_east_rounded : Icons.south_west_rounded),
      title: Text(payOut ? 'Pay out from drawer' : 'Pay into drawer'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _amount,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${money.symbol} ',
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            AppSelect<String>(
              items: [
                for (final category
                    in payOut ? payOutCategories : payInCategories)
                  SelectItem(category, category),
              ],
              value: _category,
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
              label: 'Category',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description (e.g. tea for staff, electricity bill)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(payOut ? 'Record pay-out' : 'Record pay-in'),
        ),
      ],
    );
  }
}

class _CloseDialog extends ConsumerStatefulWidget {
  const _CloseDialog({required this.summary});
  final CashSessionSummary summary;
  @override
  ConsumerState<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends ConsumerState<_CloseDialog> {
  late final List<int> _notes;
  final _counts = <int, TextEditingController>{};
  final _other = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(currentBusinessSettingsProvider);
    _notes = {
      ...settings.quickCashDenominations,
      5000,
      1000,
      500,
      100,
      50,
      20,
      10,
      5,
      1,
    }.toList()..sort((a, b) => b.compareTo(a));
    for (final note in _notes) {
      _counts[note] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _counts.values) {
      controller.dispose();
    }
    _other.dispose();
    _note.dispose();
    super.dispose();
  }

  Money get _total {
    var total = Money.zero;
    for (final entry in _counts.entries) {
      final count = int.tryParse(entry.value.text.trim()) ?? 0;
      total += Money.fromMajor(entry.key * count);
    }
    final other = ref.read(moneyFormatterProvider).parse(_other.text) ?? 0;
    return total + Money.fromMajor(other);
  }

  Future<void> _close() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(cashbookServiceProvider)
          .closeSession(
            ref.read(activeSessionProvider)!,
            counted: _total,
            note: _note.text,
            denominations: {
              for (final entry in _counts.entries)
                if ((int.tryParse(entry.value.text) ?? 0) > 0)
                  '${entry.key}': int.parse(entry.value.text),
            },
          );
      if (!mounted) return;
      Navigator.pop(context);
      final money = ref.read(moneyFormatterProvider);
      final diff = result.difference ?? Money.zero;
      Toast.show(
        context,
        diff.minorUnits == 0
            ? 'Session closed. Cash matches exactly.'
            : 'Session closed. Cash is ${diff.minorUnits > 0 ? 'over' : 'short'} by ${money.format(Money.fromMinor(diff.minorUnits.abs()))}.',
        tone: diff.minorUnits == 0 ? PillTone.success : PillTone.warning,
      );
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyFormatterProvider);
    final expected = widget.summary.expected;
    final total = _total;
    final diff = total - expected;
    return AlertDialog(
      icon: const Icon(Icons.calculate_outlined),
      title: const Text('Close session · count cash'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                childAspectRatio: 3.2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final note in _notes)
                    TextField(
                      controller: _counts[note],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText:
                            '${money.symbol} ${money.number(note).replaceAll(RegExp(r'[.,]00$'), '')}',
                        suffixText: '×',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _other,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Coins / other amount',
                prefixText: '${money.symbol} ',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Expected ${money.format(expected)}',
                    style: TextStyle(color: context.colors.onSurfaceVariant),
                  ),
                ),
                Text(
                  'Counted ${money.format(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                StatusPill(
                  diff.minorUnits == 0
                      ? 'Exact'
                      : '${diff.minorUnits > 0 ? 'Over' : 'Short'} ${money.format(Money.fromMinor(diff.minorUnits.abs()))}',
                  tone: diff.minorUnits == 0
                      ? PillTone.success
                      : PillTone.warning,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
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
          onPressed: _busy ? null : _close,
          child: const Text('Close session'),
        ),
      ],
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.summary, required this.money});
  final CashSessionSummary summary;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary.session;
    final diff = summary.difference;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: IconTile(
        icon: summary.isOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
        color: summary.isOpen ? context.tokens.success : null,
        size: 38,
      ),
      title: Text(
        '${summary.userName} · ${DateFormat('d MMM y, h:mm a').format(s.openedAt)}'
        '${s.closedAt == null ? '' : ' → ${DateFormat('h:mm a').format(s.closedAt!)}'}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        'Opening ${money.format(summary.opening)} · sales ${money.format(summary.cashSales)} · '
        'in ${money.format(summary.payIns)} · out ${money.format(summary.payOuts)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (summary.isOpen)
            const StatusPill('Open', tone: PillTone.success)
          else if (diff != null)
            StatusPill(
              diff.minorUnits == 0
                  ? 'Balanced'
                  : '${diff.minorUnits > 0 ? 'Over' : 'Short'} ${money.format(Money.fromMinor(diff.minorUnits.abs()))}',
              tone: diff.minorUnits == 0 ? PillTone.success : PillTone.warning,
            ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              money.format(summary.counted ?? summary.expected),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _SessionEntries(summary: summary),
      ),
    );
  }
}

class _SessionEntries extends ConsumerStatefulWidget {
  const _SessionEntries({required this.summary});
  final CashSessionSummary summary;
  @override
  ConsumerState<_SessionEntries> createState() => _SessionEntriesState();
}

class _SessionEntriesState extends ConsumerState<_SessionEntries> {
  late final Stream<List<CashTransaction>> _entries = ref
      .read(cashbookServiceProvider)
      .watchEntries(
        ref.read(activeSessionProvider)!,
        widget.summary.session.id,
      );

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyFormatterProvider);
    return AlertDialog(
      title: Text('Cash session · ${widget.summary.userName}'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: StreamBuilder<List<CashTransaction>>(
          stream: _entries,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return const EmptyState(
                icon: Icons.receipt_outlined,
                title: 'No cash entries in this session',
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final e = entries[index];
                final out = CashType.isOutflow(e.type);
                return ListTile(
                  dense: true,
                  title: Text(
                    e.description.isEmpty ? e.category : e.description,
                  ),
                  subtitle: Text(
                    '${e.category} · ${DateFormat('d MMM, h:mm a').format(e.createdAt)}',
                  ),
                  trailing: Text(
                    '${out ? '−' : '+'}${money.major(e.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: out
                          ? context.colors.error
                          : context.tokens.success,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
