import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../credit/presentation/receivables_card.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/dashboard_metrics.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(dashboardMetricsProvider);
    final money = ref.watch(moneyFormatterProvider);
    final session = ref.watch(activeSessionProvider)!;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(dashboardReceivablesProvider);
        return ref.refresh(dashboardMetricsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          PageHeader(
            title: '$greeting, ${session.user.displayName.split(' ').first}',
            subtitle:
                '${DateFormat('EEEE, d MMMM y').format(DateTime.now())} · ${session.store.name}',
            actions: [
              IconButton.outlined(
                tooltip: 'Refresh',
                onPressed: () {
                  ref.invalidate(dashboardMetricsProvider);
                  ref.invalidate(dashboardReceivablesProvider);
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
              FilledButton.icon(
                onPressed: () => context.go('/pos'),
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text('New sale'),
              ),
            ],
          ).entrance(context),
          const SizedBox(height: 22),
          metrics.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(60),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => Card(
              child: EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Dashboard data could not be loaded',
                message: friendlyError(error),
                action: FilledButton(
                  onPressed: () => ref.invalidate(dashboardMetricsProvider),
                  child: const Text('Retry'),
                ),
              ),
            ),
            data: (value) => _DashboardBody(metrics: value, money: money),
          ),
          if (session.can(Permissions.creditView) && metrics.hasValue) ...[
            const SizedBox(height: 16),
            const ReceivablesCard().entrance(context, delay: 280),
          ],
        ],
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.metrics, required this.money});
  final DashboardMetrics metrics;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final change = metrics.yesterdaySales == 0
        ? null
        : (metrics.sales - metrics.yesterdaySales) /
              metrics.yesterdaySales *
              100;
    final kpis = [
      StatCard(
        label: 'Today’s sales',
        value: money.major(metrics.sales),
        icon: Icons.trending_up_rounded,
        footnote: change == null
            ? 'No sales yesterday to compare'
            : '${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(1)}% vs yesterday',
      ),
      StatCard(
        label: 'Invoices',
        value: '${metrics.invoices}',
        icon: Icons.receipt_long_rounded,
        color: context.colors.tertiary,
        footnote: 'Avg ${money.major(metrics.averageSale)} per sale',
      ),
      StatCard(
        label: 'Net cash collected',
        value: money.major(metrics.cashCollected),
        icon: Icons.payments_rounded,
        color: tokens.success,
        footnote: 'Cash tendered minus change',
      ),
      StatCard(
        label: 'Discounts given',
        value: money.major(metrics.discounts),
        icon: Icons.percent_rounded,
        color: tokens.warning,
        footnote: '${metrics.customers} active customers',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < kpis.length; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(child: kpis[i].entrance(context, delay: 40 * i)),
            ],
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 330,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: SectionCard(
                  title: 'Sales by hour',
                  subtitle: 'Today, completed sales',
                  icon: Icons.bar_chart_rounded,
                  child: metrics.sales == 0
                      ? const EmptyState(
                          compact: true,
                          icon: Icons.insights_rounded,
                          title: 'No sales yet today',
                          message:
                              'The hourly trend appears after the first sale.',
                        )
                      : _HourlyChart(values: metrics.hourly, money: money),
                ).entrance(context, delay: 120),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: SectionCard(
                  title: 'Last 7 days',
                  subtitle: 'Daily revenue',
                  icon: Icons.calendar_view_week_rounded,
                  child: _WeekChart(days: metrics.week, money: money),
                ).entrance(context, delay: 160),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: SectionCard(
                title: 'Top products',
                subtitle: 'By revenue, last 7 days',
                icon: Icons.emoji_events_outlined,
                child: metrics.topProducts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: EmptyState(
                          compact: true,
                          icon: Icons.inventory_2_outlined,
                          title: 'No product sales yet',
                        ),
                      )
                    : _RankedBars(
                        rows: [
                          for (final item in metrics.topProducts)
                            (
                              item.name,
                              item.revenue,
                              '${_qty(item.quantity)} sold',
                            ),
                        ],
                        money: money,
                      ),
              ).entrance(context, delay: 200),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  SectionCard(
                    title: 'Payment mix',
                    subtitle: 'Today, by tender',
                    icon: Icons.account_balance_wallet_outlined,
                    child: metrics.paymentMix.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('No payments yet today.'),
                          )
                        : _RankedBars(
                            rows: [
                              for (final entry
                                  in (metrics.paymentMix.entries.toList()..sort(
                                    (a, b) => b.value.compareTo(a.value),
                                  )))
                                (entry.key.toUpperCase(), entry.value, null),
                            ],
                            money: money,
                          ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Inventory health',
                    icon: Icons.warehouse_outlined,
                    trailing: TextButton(
                      onPressed: () => context.go('/inventory'),
                      child: const Text('Inventory'),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _HealthTile(
                            label: 'Low stock',
                            value: metrics.lowStock,
                            icon: Icons.warning_amber_rounded,
                            tone: PillTone.warning,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _HealthTile(
                            label: 'Out of stock',
                            value: metrics.outOfStock,
                            icon: Icons.remove_shopping_cart_outlined,
                            tone: PillTone.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ).entrance(context, delay: 240),
            ),
          ],
        ),
      ],
    );
  }
}

String _qty(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

FlGridData _grid(BuildContext context) => FlGridData(
  drawVerticalLine: false,
  getDrawingHorizontalLine: (_) => FlLine(
    color: context.colors.outlineVariant.withValues(alpha: 0.45),
    strokeWidth: 1,
  ),
);

BarTouchData _barTouch(BuildContext context, String Function(int x) label) =>
    BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => context.colors.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(8),
        getTooltipItem: (group, _, rod, _) => BarTooltipItem(
          label(group.x),
          TextStyle(
            color: context.colors.onInverseSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

class _HourlyChart extends StatelessWidget {
  const _HourlyChart({required this.values, required this.money});
  final List<double> values;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final first = values.indexWhere((value) => value > 0);
    final start = (first == -1 ? 8 : first).clamp(0, 8);
    final end = 23;
    final muted = context.text.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return BarChart(
      BarChartData(
        gridData: _grid(context),
        borderData: FlBorderData(show: false),
        barTouchData: _barTouch(
          context,
          (x) =>
              '${x.toString().padLeft(2, '0')}:00\n${money.major(values[x])}',
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (value, meta) => value == meta.max
                  ? const SizedBox.shrink()
                  : Text(money.compact(value), style: muted),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => value.toInt() % 3 == 0
                  ? Text('${value.toInt()}h', style: muted)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        barGroups: [
          for (var hour = start; hour <= end; hour++)
            BarChartGroupData(
              x: hour,
              barRods: [
                BarChartRodData(
                  toY: values[hour],
                  width: 12,
                  color: context.colors.primary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: context.tokens.motion(300),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days, required this.money});
  final List<(DateTime, double)> days;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final muted = context.text.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return BarChart(
      BarChartData(
        gridData: _grid(context),
        borderData: FlBorderData(show: false),
        barTouchData: _barTouch(
          context,
          (x) =>
              '${DateFormat('EEE d MMM').format(days[x].$1)}\n${money.major(days[x].$2)}',
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Text(
                DateFormat('E').format(days[value.toInt()].$1),
                style: value.toInt() == days.length - 1
                    ? muted?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.colors.onSurface,
                      )
                    : muted,
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].$2,
                  width: 22,
                  // Today is emphasised; earlier days are the same hue, lighter.
                  color: i == days.length - 1
                      ? context.colors.primary
                      : context.colors.primary.withValues(alpha: 0.45),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: context.tokens.motion(300),
    );
  }
}

/// Labelled horizontal magnitude bars in a single hue.
class _RankedBars extends StatelessWidget {
  const _RankedBars({required this.rows, required this.money});
  final List<(String, double, String?)> rows;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold<double>(0, (m, row) => row.$2 > m ? row.$2 : m);
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (row.$3 != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          row.$3!,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Text(
                      money.major(row.$2),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: max == 0 ? 0 : row.$2 / max,
                    minHeight: 6,
                    color: context.colors.primary,
                    backgroundColor: context.colors.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });
  final String label;
  final int value;
  final IconData icon;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == PillTone.danger
        ? context.colors.error
        : context.tokens.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: context.tokens.borderRadius,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: value == 0 ? context.colors.outline : color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: context.text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(label, style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
