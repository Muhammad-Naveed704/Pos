import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money_format.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../credit/domain/credit.dart';
import '../../credit/presentation/receivables_card.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/dashboard_insights.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  DashPeriod _period = DashPeriod.today;

  void _refresh() {
    ref.invalidate(dashboardInsightsProvider(_period));
    ref.invalidate(dashboardReceivablesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(dashboardInsightsProvider(_period));
    final money = ref.watch(moneyFormatterProvider);
    final session = ref.watch(activeSessionProvider)!;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '$greeting, ${session.user.displayName.split(' ').first}',
                            overflow: TextOverflow.ellipsis,
                            style: context.text.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.waving_hand_rounded,
                          color: Color(0xFFF5B301),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Here’s what’s happening at ${session.store.name}.',
                      style: TextStyle(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              AppSegmented<DashPeriod>(
                items: [
                  for (final p in DashPeriod.values) SegmentItem(p, p.label),
                ],
                value: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
              if (MediaQuery.sizeOf(context).width >= 1440) ...[
                const SizedBox(width: 12),
                _DateChip(),
              ],
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => context.go('/pos'),
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text('New sale'),
              ),
            ],
          ).entrance(context),
          const SizedBox(height: 22),
          insights.when(
            skipLoadingOnReload: true,
            loading: () => const Padding(
              padding: EdgeInsets.all(80),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Card(
              child: EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Dashboard data could not be loaded',
                message: friendlyError(error),
                action: FilledButton(
                  onPressed: _refresh,
                  child: const Text('Retry'),
                ),
              ),
            ),
            data: (value) => _Body(insights: value, money: money),
          ),
          if (session.can(Permissions.creditView) && insights.hasValue) ...[
            const SizedBox(height: 18),
            const ReceivablesCard().entrance(context, delay: 320),
          ],
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.theme.cardTheme.color,
        borderRadius: BorderRadius.circular(context.tokens.radius),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat('EEE, d MMM y').format(now)),
          const SizedBox(width: 10),
          Text(
            DateFormat('h:mm a').format(now),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.calendar_month_rounded,
            size: 18,
            color: context.colors.primary,
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.insights, required this.money});
  final DashboardInsights insights;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final i = insights;
    final cards = [
      _KpiCard(
        label:
            '${i.period == DashPeriod.today ? 'Today’s' : i.period.label} sales',
        value: money.major(i.sales.value),
        kpi: i.sales,
        icon: Icons.shopping_cart_rounded,
        color: context.colors.primary,
        footnote: '${i.invoices.value.round()} transactions',
        comparison: i.period.comparison,
      ),
      _KpiCard(
        label: 'Invoices',
        value: NumberFormat.decimalPattern().format(i.invoices.value.round()),
        kpi: i.invoices,
        icon: Icons.receipt_long_rounded,
        color: tokens.info,
        footnote: 'Avg ${money.major(i.averageSale)} per sale',
        comparison: i.period.comparison,
      ),
      _KpiCard(
        label: 'Net cash collected',
        value: money.major(i.cash.value),
        kpi: i.cash,
        icon: Icons.payments_rounded,
        color: tokens.success,
        footnote: 'Cash minus change and refunds',
        comparison: i.period.comparison,
      ),
      _KpiCard(
        label: 'Discounts given',
        value: money.major(i.discounts.value),
        kpi: i.discounts,
        icon: Icons.percent_rounded,
        color: context.colors.error,
        footnote: '${i.customers} active customers',
        comparison: i.period.comparison,
        inverse: true,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var n = 0; n < cards.length; n++) ...[
              if (n > 0) const SizedBox(width: 16),
              Expanded(child: cards[n].entrance(context, delay: 40 * n)),
            ],
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 380,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _SalesOverview(
                  insights: i,
                  money: money,
                ).entrance(context, delay: 160),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 2,
                child: _TopProducts(
                  insights: i,
                  money: money,
                ).entrance(context, delay: 200),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final payment = _PaymentMethods(
              insights: i,
              money: money,
            ).entrance(context, delay: 240);
            final recent = _RecentSales(
              insights: i,
              money: money,
            ).entrance(context, delay: 260);
            final health = _InventoryHealth(health: i.inventory)
                .entrance(context, delay: 280);
            // Three columns on wide screens; on compact ones the recent
            // sales table gets its own full-width row.
            if (constraints.maxWidth >= 1180) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 4, child: payment),
                    const SizedBox(width: 18),
                    Expanded(flex: 5, child: recent),
                    const SizedBox(width: 18),
                    Expanded(flex: 4, child: health),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: payment),
                      const SizedBox(width: 18),
                      Expanded(child: health),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                recent,
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- KPI card

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.kpi,
    required this.icon,
    required this.color,
    required this.footnote,
    required this.comparison,
    this.inverse = false,
  });
  final String label;
  final String value;
  final Kpi kpi;
  final IconData icon;
  final Color color;
  final String footnote;
  final String comparison;

  /// For costs like discounts, going up is not good news.
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final change = kpi.change;
    final good = change == null || (inverse ? change <= 0 : change >= 0);
    final trendColor = good ? context.tokens.success : context.colors.error;
    return Card(
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.tokens.radius + 4),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              color.withValues(alpha: 0.07),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            style: context.text.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                      if (change != null) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: comparison,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: trendColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  change >= 0
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 12,
                                  color: trendColor,
                                ),
                                Text(
                                  '${change.abs() >= 999 ? '999+' : change.abs().toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: trendColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          footnote,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 92,
                        height: 38,
                        child: _Sparkline(values: kpi.series, color: color),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (values.every((v) => v == 0)) return const SizedBox.shrink();
    final top = values.reduce(math.max);
    final bottom = values.reduce(math.min);
    return LineChart(
      LineChartData(
        minY: bottom - (top - bottom) * 0.15,
        maxY: top + (top - bottom) * 0.15 + 0.001,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i]),
            ],
            isCurved: true,
            curveSmoothness: 0.3,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.25),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

// ----------------------------------------------------------- Sales overview

class _SalesOverview extends StatefulWidget {
  const _SalesOverview({required this.insights, required this.money});
  final DashboardInsights insights;
  final MoneyFormatter money;

  @override
  State<_SalesOverview> createState() => _SalesOverviewState();
}

class _SalesOverviewState extends State<_SalesOverview> {
  bool _hourly = false;

  @override
  Widget build(BuildContext context) {
    final i = widget.insights;
    final money = widget.money;
    final scheme = context.colors;
    final light = Color.lerp(scheme.primary, Colors.white, 0.45)!;
    // (label, sales, transactions)
    final points = _hourly
        ? [
            for (var h = 7; h < 23; h++)
              (
                h == 12
                    ? '12p'
                    : h > 12
                    ? '${h - 12}p'
                    : '${h}a',
                i.hours[h].$1,
                i.hours[h].$2.toDouble(),
              ),
          ]
        : [
            for (final d in i.days)
              (
                i.days.length > 10
                    ? DateFormat('d').format(d.day)
                    : '${DateFormat('EEE').format(d.day)}\n${DateFormat('d MMM').format(d.day)}',
                d.sales,
                d.invoices.toDouble(),
              ),
          ];
    final maxSales = points.fold(0.0, (m, p) => math.max(m, p.$2));
    final maxCount = points.fold(0.0, (m, p) => math.max(m, p.$3));
    final topSales = maxSales <= 0 ? 1.0 : maxSales * 1.18;
    final topCount = maxCount <= 0 ? 1.0 : (maxCount * 1.18).ceilToDouble();
    final muted = context.text.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final empty = maxSales <= 0 && maxCount <= 0;
    const reserved = 58.0;
    final step = (points.length / 10).ceil().clamp(1, 100);

    FlTitlesData titles({required bool forBars}) => FlTitlesData(
      topTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: reserved,
          getTitlesWidget: (value, meta) => forBars && value != meta.max
              ? Text(money.compact(value), style: muted)
              : const SizedBox.shrink(),
        ),
      ),
      rightTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          getTitlesWidget: (value, meta) =>
              !forBars && value != meta.max && value == value.roundToDouble()
              ? Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(value.toStringAsFixed(0), style: muted),
                )
              : const SizedBox.shrink(),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: _hourly || points.length > 10 ? 24 : 36,
          getTitlesWidget: (value, meta) {
            final index = value.round();
            if (!forBars ||
                index < 0 ||
                index >= points.length ||
                index % step != 0 ||
                value != index.toDouble()) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                points[index].$1,
                textAlign: TextAlign.center,
                style: muted,
              ),
            );
          },
        ),
      ),
    );

    return SectionCard(
      title: 'Sales overview',
      subtitle: _hourly
          ? 'Today by hour · sales and transactions'
          : '${i.days.length} days · sales and transactions',
      icon: Icons.bar_chart_rounded,
      trailing: AppSegmented<bool>(
        dense: true,
        items: const [SegmentItem(false, 'Daily'), SegmentItem(true, 'Hourly')],
        value: _hourly,
        onChanged: (value) => setState(() => _hourly = value),
      ),
      child: SizedBox(
        height: 270,
        child: empty
            ? const EmptyState(
                compact: true,
                icon: Icons.insights_rounded,
                title: 'No sales in this period yet',
              )
            : Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Legend(color: scheme.primary, label: 'Sales'),
                      const SizedBox(width: 18),
                      _Legend(color: light, label: 'Transactions', line: true),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Stack(
                      children: [
                        BarChart(
                          BarChartData(
                            maxY: topSales,
                            minY: 0,
                            alignment: BarChartAlignment.spaceAround,
                            borderData: FlBorderData(show: false),
                            gridData: FlGridData(
                              drawVerticalLine: false,
                              horizontalInterval: topSales / 4,
                              getDrawingHorizontalLine: (_) => FlLine(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.45,
                                ),
                                strokeWidth: 1,
                                dashArray: [4, 4],
                              ),
                            ),
                            titlesData: titles(forBars: true),
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipColor: (_) => scheme.inverseSurface,
                                tooltipBorderRadius: BorderRadius.circular(8),
                                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                                  '${points[group.x].$1.replaceAll('\n', ' ')}\n'
                                  '${money.major(points[group.x].$2)} · '
                                  '${points[group.x].$3.toStringAsFixed(0)} sales',
                                  TextStyle(
                                    color: scheme.onInverseSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            barGroups: [
                              for (var n = 0; n < points.length; n++)
                                BarChartGroupData(
                                  x: n,
                                  barRods: [
                                    BarChartRodData(
                                      toY: math.max(points[n].$2, 0),
                                      width: (420 / points.length).clamp(8, 44),
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [light, scheme.primary],
                                      ),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(6),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          duration: context.tokens.motion(300),
                        ),
                        IgnorePointer(
                          child: LineChart(
                            LineChartData(
                              minX: -0.5,
                              maxX: points.length - 0.5,
                              minY: 0,
                              maxY: topCount,
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              titlesData: titles(forBars: false),
                              lineTouchData: const LineTouchData(
                                enabled: false,
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: [
                                    for (var n = 0; n < points.length; n++)
                                      FlSpot(n.toDouble(), points[n].$3),
                                  ],
                                  isCurved: true,
                                  preventCurveOverShooting: true,
                                  color: scheme.secondary,
                                  barWidth: 2.4,
                                  dotData: FlDotData(
                                    getDotPainter: (_, _, _, _) =>
                                        FlDotCirclePainter(
                                          radius: 3.6,
                                          color: scheme.secondary,
                                          strokeWidth: 2,
                                          strokeColor: Colors.white,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            duration: context.tokens.motion(300),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.line = false});
  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: line ? 18 : 10,
        height: line ? 3 : 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: context.text.bodySmall),
    ],
  );
}

// ------------------------------------------------------------ Top products

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.insights, required this.money});
  final DashboardInsights insights;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final products = insights.topProducts;
    final top = products.isEmpty ? 1.0 : products.first.revenue;
    return SectionCard(
      title: 'Top products',
      subtitle: 'By revenue · ${insights.period.label.toLowerCase()}',
      icon: Icons.emoji_events_outlined,
      trailing: TextButton(
        onPressed: () => context.go('/reports'),
        child: const Text('View all'),
      ),
      child: products.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: EmptyState(
                compact: true,
                icon: Icons.inventory_2_outlined,
                title: 'No product sales yet',
              ),
            )
          : Column(
              children: [
                for (var n = 0; n < products.length; n++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${n + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        ProductThumb(
                          name: products[n].name,
                          path: products[n].imagePath,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                products[n].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                products[n].sku,
                                style: context.text.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${_qty(products[n].quantity)} sold',
                                    style: context.text.bodySmall?.copyWith(
                                      color: n == 0
                                          ? context.colors.primary
                                          : context.colors.onSurfaceVariant,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    money.major(products[n].revenue),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  minHeight: 6,
                                  value: top <= 0
                                      ? 0
                                      : (products[n].revenue / top).clamp(
                                          0.03,
                                          1,
                                        ),
                                  backgroundColor:
                                      context.colors.surfaceContainerHighest,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// --------------------------------------------------------- Payment methods

class _PaymentMethods extends StatelessWidget {
  const _PaymentMethods({required this.insights, required this.money});
  final DashboardInsights insights;
  final MoneyFormatter money;

  static String _label(String method) => switch (method) {
    'cash' => 'Cash',
    'card' => 'Card',
    'bank' => 'Bank / wallet',
    'other' => 'Other',
    _ => method,
  };

  @override
  Widget build(BuildContext context) {
    final entries =
        insights.paymentMix.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (sum, e) => sum + e.value);
    final palette = [
      context.colors.primary,
      context.tokens.info,
      context.tokens.success,
      context.colors.tertiary,
    ];
    return SectionCard(
      title: 'Payment methods',
      subtitle: insights.period.label,
      icon: Icons.donut_large_rounded,
      child: entries.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: EmptyState(
                compact: true,
                icon: Icons.payments_outlined,
                title: 'No payments yet',
              ),
            )
          : Row(
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 50,
                          startDegreeOffset: -90,
                          sections: [
                            for (var n = 0; n < entries.length; n++)
                              PieChartSectionData(
                                value: entries[n].value,
                                color: palette[n % palette.length],
                                radius: 20,
                                showTitle: false,
                              ),
                          ],
                        ),
                        duration: context.tokens.motion(300),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                              ),
                              child: Text(
                                money.major(total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          Text('Total', style: context.text.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var n = 0; n < entries.length; n++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: palette[n % palette.length],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _label(entries[n].key),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                flex: 2,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '${money.major(entries[n].value)} '
                                    '(${total == 0 ? 0 : (entries[n].value / total * 100).round()}%)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ------------------------------------------------------------ Recent sales

class _RecentSales extends StatelessWidget {
  const _RecentSales({required this.insights, required this.money});
  final DashboardInsights insights;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final sales = insights.recentSales;
    final muted = context.text.labelMedium?.copyWith(
      color: context.colors.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return SectionCard(
      title: 'Recent sales',
      icon: Icons.schedule_rounded,
      trailing: TextButton(
        onPressed: () => context.go('/history'),
        child: const Text('View all'),
      ),
      child: sales.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: EmptyState(
                compact: true,
                icon: Icons.receipt_long_outlined,
                title: 'No sales yet',
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text('Invoice', style: muted)),
                      Expanded(flex: 2, child: Text('Time', style: muted)),
                      Expanded(flex: 3, child: Text('Customer', style: muted)),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Total',
                          style: muted,
                          textAlign: TextAlign.end,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(width: 78, child: Text('Payment', style: muted)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                for (final sale in sales.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            '#${sale.invoice.split('-').last}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            DateFormat('h:mm a').format(sale.time),
                            style: context.text.bodySmall,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            sale.customer ?? 'Walk-in',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            money.major(sale.total),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              decoration: sale.saleStatus == 'voided'
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 78,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _paymentPill(sale),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _paymentPill(RecentSale sale) {
    if (sale.saleStatus == 'voided') {
      return const StatusPill('Voided');
    }
    if (sale.paymentStatus != PaymentStatus.paid) {
      return StatusPill(
        sale.paymentStatus == PaymentStatus.credit ? 'Credit' : 'Partial',
        tone: PillTone.warning,
      );
    }
    final method = sale.methods.length > 1
        ? 'Split'
        : sale.methods.isEmpty
        ? '—'
        : sale.methods.single;
    return StatusPill(
      method[0].toUpperCase() + method.substring(1),
      tone: method == 'cash' ? PillTone.primary : PillTone.success,
    );
  }
}

// -------------------------------------------------------- Inventory health

class _InventoryHealth extends StatelessWidget {
  const _InventoryHealth({required this.health});
  final InventoryHealth health;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget tile(int value, String label, IconData icon, Color color) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(tokens.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: color),
                    const SizedBox(width: 6),
                    Text(
                      '$value',
                      style: context.text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ],
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        );
    Widget line(String label, int value, [Color? color]) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
    return SectionCard(
      title: 'Inventory health',
      icon: Icons.inventory_2_outlined,
      trailing: TextButton(
        onPressed: () => context.go('/inventory'),
        child: const Text('View all'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              tile(
                health.low,
                'Low stock',
                Icons.warning_amber_rounded,
                tokens.warning,
              ),
              const SizedBox(width: 8),
              tile(
                health.out,
                'Out of stock',
                Icons.remove_shopping_cart_outlined,
                context.colors.error,
              ),
              const SizedBox(width: 8),
              tile(
                health.inStock,
                'In stock',
                Icons.check_circle_outline_rounded,
                tokens.success,
              ),
            ],
          ),
          const SizedBox(height: 12),
          line('Tracked products', health.tracked),
          line('Available for sale', health.active, tokens.success),
          line('Low stock products', health.low, tokens.warning),
          line('Out of stock products', health.out, context.colors.error),
        ],
      ),
    );
  }
}

String _qty(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);
