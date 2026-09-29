import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/dashboard_metrics.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(dashboardMetricsProvider);
    final money = NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(dashboardMetricsProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good day',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE, d MMMM y').format(DateTime.now()),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => context.go('/pos'),
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('New sale  Ctrl+N'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          metrics.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => _ErrorCard(
              onRetry: () => ref.invalidate(dashboardMetricsProvider),
            ),
            data: (value) => LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 48) / 4;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _MetricCard(
                      width: width,
                      label: 'Today sales',
                      value: money.format(value.sales),
                      icon: Icons.trending_up,
                      tint: const Color(0xFF1473E6),
                    ),
                    _MetricCard(
                      width: width,
                      label: 'Invoices',
                      value: '${value.invoices}',
                      icon: Icons.receipt_long_outlined,
                      tint: const Color(0xFF7C3AED),
                    ),
                    _MetricCard(
                      width: width,
                      label: 'Cash collected',
                      value: money.format(value.cashCollected),
                      icon: Icons.payments_outlined,
                      tint: const Color(0xFF098A6E),
                    ),
                    _MetricCard(
                      width: width,
                      label: 'Discounts',
                      value: money.format(value.discounts),
                      icon: Icons.percent,
                      tint: const Color(0xFFD97706),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 310,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sales trend',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Hourly performance appears after your first completed sale.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          const _EmptyChart(),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Inventory health',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 22),
                          metrics.maybeWhen(
                            data: (value) => Column(
                              children: [
                                _InventoryRow(
                                  label: 'Low stock',
                                  value: value.lowStock,
                                  color: const Color(0xFFD97706),
                                ),
                                const SizedBox(height: 14),
                                _InventoryRow(
                                  label: 'Out of stock',
                                  value: value.outOfStock,
                                  color: const Color(0xFFE13C65),
                                ),
                                const SizedBox(height: 14),
                                _InventoryRow(
                                  label: 'Customers',
                                  value: value.customers,
                                  color: const Color(0xFF1473E6),
                                ),
                              ],
                            ),
                            orElse: () => const LinearProgressIndicator(),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => context.go('/inventory'),
                              child: const Text('Open inventory'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick actions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        [
                              _QuickAction(
                                'Add product',
                                Icons.add_box_outlined,
                                '/products',
                              ),
                              _QuickAction(
                                'Add customer',
                                Icons.person_add_alt,
                                '/customers',
                              ),
                              _QuickAction(
                                'Import CSV',
                                Icons.upload_file_outlined,
                                '/products',
                              ),
                              _QuickAction(
                                'Open cashbook',
                                Icons.account_balance_wallet_outlined,
                                '/cashbook',
                              ),
                            ]
                            .map(
                              (item) => OutlinedButton.icon(
                                onPressed: () => context.go(item.path),
                                icon: Icon(item.icon, size: 18),
                                label: Text(item.label),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(icon, color: tint, size: 21),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 110,
    child: CustomPaint(
      painter: _GridPainter(Theme.of(context).colorScheme.outlineVariant),
      child: Center(
        child: Icon(
          Icons.show_chart,
          size: 34,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.55);
    for (var row = 0; row <= 4; row++) {
      final y = size.height * row / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(label)),
      Text('$value', style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.path);
  final String label;
  final IconData icon;
  final String path;
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: const Text('Dashboard data could not be loaded'),
      trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
    ),
  );
}
