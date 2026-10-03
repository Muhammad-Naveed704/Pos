import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// One column of an [AppTable]: a fixed [width] or a share of the rest.
class AppColumn {
  const AppColumn(
    this.label, {
    this.flex = 1,
    this.width,
    this.numeric = false,
    this.center = false,
  });
  final String label;
  final int flex;
  final double? width;
  final bool numeric;
  final bool center;
}

/// Card table with an uppercase header row, hover highlight and an optional
/// footer (counts, pagination). Rows are built lazily.
class AppTable extends StatelessWidget {
  const AppTable({
    required this.columns,
    required this.rowCount,
    required this.cells,
    this.onTap,
    this.footer,
    this.empty,
    this.rowHeight = 64,
    super.key,
  });

  final List<AppColumn> columns;
  final int rowCount;
  final List<Widget> Function(BuildContext context, int index) cells;
  final void Function(int index)? onTap;
  final Widget? footer;
  final Widget? empty;
  final double rowHeight;

  Widget _cell(AppColumn column, Widget child) {
    final aligned = Align(
      alignment: column.numeric
          ? Alignment.centerRight
          : column.center
          ? Alignment.center
          : Alignment.centerLeft,
      child: child,
    );
    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: aligned,
    );
    return column.width != null
        ? SizedBox(width: column.width, child: padded)
        : Expanded(flex: column.flex, child: padded);
  }

  @override
  Widget build(BuildContext context) {
    final header = context.text.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: context.colors.onSurfaceVariant,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: context.colors.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              children: [
                for (final column in columns)
                  _cell(
                    column,
                    Text(
                      column.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: header,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: rowCount == 0
                ? (empty ?? const SizedBox.shrink())
                : ListView.separated(
                    itemCount: rowCount,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: context.colors.outlineVariant.withValues(
                        alpha: 0.45,
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final row = cells(context, index);
                      return InkWell(
                        onTap: onTap == null ? null : () => onTap!(index),
                        hoverColor: context.colors.primary.withValues(
                          alpha: 0.04,
                        ),
                        child: SizedBox(
                          height: rowHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                for (var i = 0; i < columns.length; i++)
                                  _cell(columns[i], row[i]),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (footer != null) ...[
            Divider(
              height: 1,
              color: context.colors.outlineVariant.withValues(alpha: 0.45),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: footer,
            ),
          ],
        ],
      ),
    );
  }
}

/// Avatar circle with initials in a colour derived from the name.
class NameAvatar extends StatelessWidget {
  const NameAvatar(this.name, {this.radius = 20, super.key});
  final String name;
  final double radius;

  static const _colors = [
    Color(0xFFF26A1B),
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFF9333EA),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
    Color(0xFFCA8A04),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final color = _colors[trimmed.hashCode.abs() % _colors.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.13),
      foregroundColor: color,
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: radius * 0.8),
      ),
    );
  }
}
