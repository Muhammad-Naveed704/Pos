import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money_format.dart';
import '../../../core/ui/import_dialog.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../receipts/data/receipt_service.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/report_export.dart';
import '../data/reports_service.dart';

enum _Preset { today, yesterday, week, month, lastMonth, custom }

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  late ReportKind _kind;
  _Preset _preset = _Preset.month;
  late DateTimeRange _range = _rangeFor(_Preset.month);
  Future<ReportResult>? _result;
  int? _sortColumn;
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(activeSessionProvider)!;
    _kind = ReportKind.values.firstWhere(
      (kind) => session.can(kind.permission),
      orElse: () => ReportKind.summary,
    );
    _load();
  }

  static DateTimeRange _rangeFor(_Preset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (preset) {
      _Preset.today ||
      _Preset.custom => DateTimeRange(start: today, end: today),
      _Preset.yesterday => DateTimeRange(
        start: today.subtract(const Duration(days: 1)),
        end: today.subtract(const Duration(days: 1)),
      ),
      _Preset.week => DateTimeRange(
        start: today.subtract(Duration(days: today.weekday - 1)),
        end: today,
      ),
      _Preset.month => DateTimeRange(
        start: DateTime(today.year, today.month),
        end: today,
      ),
      _Preset.lastMonth => DateTimeRange(
        start: DateTime(today.year, today.month - 1),
        end: DateTime(today.year, today.month, 0),
      ),
    };
  }

  void _load() {
    _sortColumn = null;
    _result = ref
        .read(reportsServiceProvider)
        .run(ref.read(activeSessionProvider)!, _kind, _range);
  }

  String get _period {
    final f = DateFormat('d MMM y');
    return _range.start == _range.end
        ? f.format(_range.start)
        : '${f.format(_range.start)} – ${f.format(_range.end)}';
  }

  String _format(Object value, ColumnKind kind, MoneyFormatter money) {
    if (value is String) return value;
    final number = (value as num).toDouble();
    return switch (kind) {
      ColumnKind.money => money.major(number),
      ColumnKind.percent => '${number.toStringAsFixed(1)}%',
      ColumnKind.integer => NumberFormat.decimalPattern().format(
        number.round(),
      ),
      ColumnKind.quantity =>
        number == number.roundToDouble()
            ? NumberFormat.decimalPattern().format(number.round())
            : number.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), ''),
      ColumnKind.text => '$value',
    };
  }

  List<List<Object>> _sorted(ReportResult result) {
    final column = _sortColumn;
    if (column == null) return result.rows;
    final rows = [...result.rows];
    rows.sort((a, b) {
      final x = a[column];
      final y = b[column];
      final compare = x is num && y is num
          ? x.compareTo(y)
          : '$x'.toLowerCase().compareTo('$y'.toLowerCase());
      return _sortAscending ? compare : -compare;
    });
    return rows;
  }

  Future<void> _exportCsv(ReportResult result) async {
    try {
      final path = await saveCsvFile(
        [
          [for (final column in result.columns) column.label],
          ...result.rows,
        ],
        fileName:
            'storeflow-${result.kind.name}-${DateFormat('yyyyMMdd').format(_range.start)}-${DateFormat('yyyyMMdd').format(_range.end)}.csv',
        dialogTitle: 'Export report',
      );
      if (path != null && mounted) Toast.success(context, 'Saved $path');
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  Future<void> _exportPdf(ReportResult result) async {
    final money = ref.read(moneyFormatterProvider);
    final session = ref.read(activeSessionProvider)!;
    final settings = ref.read(currentBusinessSettingsProvider);
    try {
      final bytes = await generateReportPdf(
        ReportPdfData(
          title: result.kind.label,
          businessName: settings.businessName,
          storeName: session.store.name,
          period: result.kind.usesDates ? _period : 'As of today',
          kpis: [
            for (final kpi in result.kpis)
              (kpi.label, _format(kpi.value, kpi.kind, money)),
          ],
          headers: [for (final c in result.columns) c.label],
          numeric: [for (final c in result.columns) c.numeric],
          rows: [
            for (final row in _sorted(result))
              [
                for (var i = 0; i < row.length; i++)
                  _format(row[i], result.columns[i].kind, money),
              ],
          ],
          footnote: result.footnote,
        ),
      );
      final path = await ref
          .read(receiptServiceProvider)
          .saveBytes(bytes, 'storeflow-${result.kind.name}.pdf');
      if (path != null && mounted) Toast.success(context, 'Saved $path');
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final money = ref.watch(moneyFormatterProvider);
    final kinds = ReportKind.values
        .where((kind) => session.can(kind.permission))
        .toList();
    final canExport = session.can(Permissions.reportsExport);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 220,
            child: Card(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Text(
                      'REPORTS',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final kind in kinds)
                    ListTile(
                      dense: true,
                      selected: kind == _kind,
                      selectedTileColor: context.colors.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: context.tokens.borderRadius,
                      ),
                      leading: Icon(kind.icon, size: 20),
                      title: Text(kind.label),
                      onTap: () => setState(() {
                        _kind = kind;
                        _load();
                      }),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: FutureBuilder<ReportResult>(
              future: _result,
              builder: (context, snapshot) {
                final result = snapshot.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeader(
                      title: _kind.label,
                      subtitle: _kind.usesDates
                          ? '${session.store.name} · $_period'
                          : '${session.store.name} · current stock',
                      actions: [
                        if (canExport && result != null) ...[
                          OutlinedButton.icon(
                            onPressed: () => _exportCsv(result),
                            icon: const Icon(Icons.table_view_outlined),
                            label: const Text('CSV'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _exportPdf(result),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('PDF'),
                          ),
                        ],
                      ],
                    ),
                    if (_kind.usesDates) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (preset, label) in const [
                            (_Preset.today, 'Today'),
                            (_Preset.yesterday, 'Yesterday'),
                            (_Preset.week, 'This week'),
                            (_Preset.month, 'This month'),
                            (_Preset.lastMonth, 'Last month'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _preset == preset,
                              onSelected: (_) => setState(() {
                                _preset = preset;
                                _range = _rangeFor(preset);
                                _load();
                              }),
                            ),
                          ChoiceChip(
                            avatar: const Icon(
                              Icons.date_range_rounded,
                              size: 16,
                            ),
                            label: Text(
                              _preset == _Preset.custom ? _period : 'Custom…',
                            ),
                            selected: _preset == _Preset.custom,
                            onSelected: (_) async {
                              final picked = await pickDateRange(
                                context,
                                initial: _range,
                              );
                              if (picked != null) {
                                setState(() {
                                  _preset = _Preset.custom;
                                  _range = picked;
                                  _load();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Expanded(
                      child: snapshot.hasError
                          ? Card(
                              child: EmptyState(
                                icon: Icons.error_outline_rounded,
                                title: 'Report could not be generated',
                                message: friendlyError(snapshot.error!),
                              ),
                            )
                          : result == null
                          ? const Center(child: CircularProgressIndicator())
                          : _body(context, result, money),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ReportResult result,
    MoneyFormatter money,
  ) {
    final rows = _sorted(result);
    return ListView(
      children: [
        if (result.kpis.isNotEmpty) ...[
          Row(
            children: [
              for (var i = 0; i < result.kpis.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    label: result.kpis[i].label,
                    value: _format(
                      result.kpis[i].value,
                      result.kpis[i].kind,
                      money,
                    ),
                    icon: switch (result.kpis[i].kind) {
                      ColumnKind.percent => Icons.percent_rounded,
                      ColumnKind.money => Icons.payments_outlined,
                      _ => Icons.tag_rounded,
                    },
                    color: context
                        .tokens
                        .chartPalette[i % context.tokens.chartPalette.length],
                    footnote: result.kpis[i].note,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (result.chart.length > 1)
          SizedBox(
            height: 260,
            child: SectionCard(
              title: result.chartLabel,
              icon: Icons.bar_chart_rounded,
              child: _ReportChart(data: result.chart, money: money),
            ),
          ),
        if (result.chart.length > 1) const SizedBox(height: 14),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                color: context.colors.surfaceContainerHigh,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < result.columns.length; i++)
                      Expanded(
                        flex: result.columns[i].flex,
                        child: InkWell(
                          onTap: () => setState(() {
                            if (_sortColumn == i) {
                              _sortAscending = !_sortAscending;
                            } else {
                              _sortColumn = i;
                              _sortAscending = !result.columns[i].numeric;
                            }
                          }),
                          child: Row(
                            mainAxisAlignment: result.columns[i].numeric
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Text(
                                  result.columns[i].label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (_sortColumn == i)
                                Icon(
                                  _sortAscending
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 14,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: EmptyState(
                    compact: true,
                    icon: Icons.inbox_outlined,
                    title: 'No data for this period',
                  ),
                )
              else
                for (var r = 0; r < rows.length; r++)
                  Container(
                    color: r.isOdd
                        ? context.colors.surfaceContainerLowest.withValues(
                            alpha: 0.5,
                          )
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < result.columns.length; i++)
                          Expanded(
                            flex: result.columns[i].flex,
                            child: Text(
                              _format(
                                rows[r][i],
                                result.columns[i].kind,
                                money,
                              ),
                              textAlign: result.columns[i].numeric
                                  ? TextAlign.end
                                  : TextAlign.start,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: i == 0 ? FontWeight.w600 : null,
                                color:
                                    rows[r][i] is num && (rows[r][i] as num) < 0
                                    ? context.colors.error
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        if (result.footnote != null) ...[
          const SizedBox(height: 10),
          Text(
            result.footnote!,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ReportChart extends StatelessWidget {
  const _ReportChart({required this.data, required this.money});
  final List<(String, double)> data;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final muted = context.text.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    final step = (data.length / 12).ceil().clamp(1, 1000);
    return BarChart(
      BarChartData(
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: context.colors.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => context.colors.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${data[group.x].$1}\n${money.major(data[group.x].$2)}',
              TextStyle(
                color: context.colors.onInverseSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) => value == meta.max
                  ? const SizedBox.shrink()
                  : Text(money.compact(value), style: muted),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index % step != 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                final label = data[index].$1;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label.length > 12 ? '${label.substring(0, 11)}…' : label,
                    style: muted,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].$2 < 0 ? 0 : data[i].$2,
                  width: (300 / data.length).clamp(6, 28).toDouble(),
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
