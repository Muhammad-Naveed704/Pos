import 'dart:async';

import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_tokens.dart';

// ---------------------------------------------------------------------------
// AppSelect: searchable dropdown
// ---------------------------------------------------------------------------

class SelectItem<T> {
  const SelectItem(this.value, this.label, {this.icon, this.subtitle});
  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
}

/// Dropdown built on Material 3 `DropdownMenu`: keyboard friendly, optional
/// type-to-filter, and it follows [value] when it changes (unlike
/// `DropdownButtonFormField`, which only reads its initial value).
class AppSelect<T> extends StatefulWidget {
  const AppSelect({
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.helperText,
    this.icon,
    this.searchable,
    this.width,
    this.enabled = true,
    super.key,
  });

  final List<SelectItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hint;
  final String? helperText;
  final IconData? icon;

  /// Defaults to true when there are more than 8 items.
  final bool? searchable;

  /// Fixed width; null fills the available width.
  final double? width;
  final bool enabled;

  @override
  State<AppSelect<T>> createState() => _AppSelectState<T>();
}

class _AppSelectState<T> extends State<AppSelect<T>> {
  final _controller = TextEditingController();

  SelectItem<T>? get _selected =>
      widget.items.where((item) => item.value == widget.value).firstOrNull;

  @override
  void initState() {
    super.initState();
    _controller.text = _selected?.label ?? '';
  }

  @override
  void didUpdateWidget(covariant AppSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final label = _selected?.label ?? '';
    if (oldWidget.value != widget.value && _controller.text != label) {
      _controller.text = label;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchable = widget.searchable ?? widget.items.length > 8;
    final selectedIcon = _selected?.icon ?? widget.icon;
    final menu = DropdownMenu<T>(
      controller: _controller,
      enabled: widget.enabled && widget.onChanged != null,
      initialSelection: widget.value,
      label: widget.label == null ? null : Text(widget.label!),
      hintText: widget.hint,
      helperText: widget.helperText,
      leadingIcon: selectedIcon == null ? null : Icon(selectedIcon, size: 20),
      enableFilter: searchable,
      enableSearch: true,
      requestFocusOnTap: searchable,
      menuHeight: 340,
      // Same height as text fields so filter rows line up.
      inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
        isDense: true,
        constraints: BoxConstraints.tightFor(height: _fieldHeight(context)),
      ),
      width: widget.width,
      expandedInsets: widget.width == null ? EdgeInsets.zero : null,
      trailingIcon: const Icon(Icons.keyboard_arrow_down_rounded),
      selectedTrailingIcon: const Icon(Icons.keyboard_arrow_up_rounded),
      onSelected: (value) {
        widget.onChanged?.call(value);
        FocusScope.of(context).unfocus();
      },
      dropdownMenuEntries: [
        for (final item in widget.items)
          DropdownMenuEntry<T>(
            value: item.value,
            label: item.label,
            leadingIcon: item.icon == null ? null : Icon(item.icon, size: 18),
            labelWidget: item.subtitle == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.label),
                      Text(
                        item.subtitle!,
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
    return widget.width == null
        ? menu
        : SizedBox(width: widget.width, child: menu);
  }
}

double _fieldHeight(BuildContext context) {
  final density = Theme.of(context).visualDensity;
  return density.vertical <= -2
      ? 42
      : density.vertical > 0
      ? 54
      : 48;
}

// ---------------------------------------------------------------------------
// AppSegmented: sliding pill selector
// ---------------------------------------------------------------------------

class SegmentItem<T> {
  const SegmentItem(this.value, this.label, {this.icon, this.tooltip});
  final T value;
  final String? label;
  final IconData? icon;
  final String? tooltip;
}

/// Compact segmented control with an animated sliding thumb.
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    required this.items,
    required this.value,
    required this.onChanged,
    this.expand = false,
    this.dense = false,
    super.key,
  });

  final List<SegmentItem<T>> items;
  final T value;
  final ValueChanged<T>? onChanged;

  /// Stretch to fill the available width with equal segments.
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final tokens = context.tokens;
    final radius = tokens.radius.clamp(6.0, 14.0);
    final index = items.indexWhere((item) => item.value == value);
    final height = dense ? 34.0 : 40.0;

    Widget segment(int i) {
      final item = items[i];
      final selected = i == index;
      final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
      final child = InkWell(
        borderRadius: BorderRadius.circular(radius - 3),
        onTap: onChanged == null ? null : () => onChanged!(item.value),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (item.icon != null)
                Icon(item.icon, size: dense ? 16 : 18, color: color),
              if (item.icon != null && item.label != null)
                const SizedBox(width: 6),
              if (item.label != null)
                Flexible(
                  child: Text(
                    item.label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: dense ? 12.5 : 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      final wrapped = item.tooltip == null
          ? child
          : Tooltip(message: item.tooltip!, child: child);
      return expand ? Expanded(child: wrapped) : wrapped;
    }

    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final row = IntrinsicWidth(
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++)
                  expand ? segment(i) : Expanded(child: segment(i)),
              ],
            ),
          );
          return Stack(
            children: [
              if (index >= 0)
                Positioned.fill(
                  child: _Thumb(
                    index: index,
                    count: items.length,
                    radius: radius - 3,
                    duration: tokens.motion(180),
                  ),
                ),
              expand
                  ? Row(
                      children: [
                        for (var i = 0; i < items.length; i++) segment(i),
                      ],
                    )
                  : row,
            ],
          );
        },
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.index,
    required this.count,
    required this.radius,
    required this.duration,
  });
  final int index;
  final int count;
  final double radius;
  final Duration duration;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth / count;
      return Stack(
        children: [
          AnimatedPositioned(
            duration: duration,
            curve: Curves.easeOutCubic,
            left: width * index,
            top: 0,
            bottom: 0,
            width: width,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(radius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// SearchField
// ---------------------------------------------------------------------------

/// Rounded search input with a clear button and optional debounce. It owns
/// its controller, so rebuilding the parent never resets what was typed.
class SearchField extends StatefulWidget {
  const SearchField({
    required this.onChanged,
    this.hint = 'Search',
    this.debounce = const Duration(milliseconds: 220),
    this.onSubmitted,
    this.autofocus = false,
    this.width,
    this.initialValue = '',
    super.key,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hint;
  final Duration debounce;
  final bool autofocus;
  final double? width;
  final String initialValue;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final _controller = TextEditingController(text: widget.initialValue);
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    _timer?.cancel();
    if (widget.debounce == Duration.zero) {
      widget.onChanged(value);
    } else {
      _timer = Timer(widget.debounce, () {
        if (mounted) widget.onChanged(value);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: _changed,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                onPressed: () {
                  _controller.clear();
                  _timer?.cancel();
                  setState(() {});
                  widget.onChanged('');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
      ),
    );
    return widget.width == null
        ? field
        : SizedBox(width: widget.width, child: field);
  }
}

// ---------------------------------------------------------------------------
// DateRangeButton: presets + calendar popover
// ---------------------------------------------------------------------------

enum DatePreset {
  today('Today'),
  yesterday('Yesterday'),
  last7('Last 7 days'),
  last30('Last 30 days'),
  thisMonth('This month'),
  lastMonth('Last month'),
  thisYear('This year');

  const DatePreset(this.label);
  final String label;

  DateTimeRange get range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      DatePreset.today => DateTimeRange(start: today, end: today),
      DatePreset.yesterday => DateTimeRange(
        start: today.subtract(const Duration(days: 1)),
        end: today.subtract(const Duration(days: 1)),
      ),
      DatePreset.last7 => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      ),
      DatePreset.last30 => DateTimeRange(
        start: today.subtract(const Duration(days: 29)),
        end: today,
      ),
      DatePreset.thisMonth => DateTimeRange(
        start: DateTime(today.year, today.month),
        end: today,
      ),
      DatePreset.lastMonth => DateTimeRange(
        start: DateTime(today.year, today.month - 1),
        end: DateTime(today.year, today.month, 0),
      ),
      DatePreset.thisYear => DateTimeRange(
        start: DateTime(today.year),
        end: today,
      ),
    };
  }

  static DatePreset? matching(DateTimeRange? range) {
    if (range == null) return null;
    for (final preset in values) {
      final r = preset.range;
      if (r.start == range.start && r.end == range.end) return preset;
    }
    return null;
  }
}

String describeRange(DateTimeRange? range, {String empty = 'All dates'}) {
  if (range == null) return empty;
  final preset = DatePreset.matching(range);
  if (preset != null) return preset.label;
  final sameYear = range.start.year == range.end.year;
  final start = DateFormat(sameYear ? 'd MMM' : 'd MMM y').format(range.start);
  final end = DateFormat('d MMM y').format(range.end);
  return range.start == range.end
      ? DateFormat('d MMM y').format(range.start)
      : '$start – $end';
}

/// A button that opens an anchored date-range popover with quick presets
/// and a calendar. [value] null means "all dates" when [allowClear] is true.
class DateRangeButton extends StatefulWidget {
  const DateRangeButton({
    required this.value,
    required this.onChanged,
    this.allowClear = true,
    this.firstDate,
    super.key,
  });

  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;
  final bool allowClear;
  final DateTime? firstDate;

  @override
  State<DateRangeButton> createState() => _DateRangeButtonState();
}

class _DateRangeButtonState extends State<DateRangeButton> {
  final _menu = MenuController();
  List<DateTime?> _draft = const [];

  void _open() {
    final value = widget.value;
    setState(() => _draft = value == null ? [] : [value.start, value.end]);
    _menu.open();
  }

  void _apply(DateTimeRange? range) {
    _menu.close();
    widget.onChanged(range);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.tokens.radius + 4),
          ),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: 560,
          height: 360,
          child: Row(
            children: [
              Material(
                color: scheme.surfaceContainerLow,
                child: SizedBox(
                  width: 150,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    children: [
                      for (final preset in DatePreset.values)
                        ListTile(
                          dense: true,
                          selected: DatePreset.matching(widget.value) == preset,
                          title: Text(preset.label),
                          onTap: () => _apply(preset.range),
                        ),
                      if (widget.allowClear)
                        ListTile(
                          dense: true,
                          selected: widget.value == null,
                          title: const Text('All dates'),
                          onTap: () => _apply(null),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: CalendarDatePicker2(
                        config: CalendarDatePicker2Config(
                          calendarType: CalendarDatePicker2Type.range,
                          firstDate: widget.firstDate ?? DateTime(2020),
                          lastDate: today,
                          currentDate: today,
                          selectedDayHighlightColor: scheme.primary,
                          selectedRangeHighlightColor: scheme.primaryContainer,
                          dayBorderRadius: BorderRadius.circular(10),
                          controlsTextStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                          weekdayLabelTextStyle: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        value: _draft,
                        onValueChanged: (dates) =>
                            setState(() => _draft = dates),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _draft.isEmpty
                                  ? 'Pick a start and end date'
                                  : describeRange(
                                      DateTimeRange(
                                        start: _draft.first!,
                                        end: _draft.last ?? _draft.first!,
                                      ),
                                    ),
                              style: context.text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _menu.close,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 6),
                          FilledButton(
                            onPressed: _draft.isEmpty || _draft.first == null
                                ? null
                                : () => _apply(
                                    DateTimeRange(
                                      start: _draft.first!,
                                      end:
                                          _draft.length > 1 &&
                                              _draft.last != null
                                          ? _draft.last!
                                          : _draft.first!,
                                    ),
                                  ),
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : _open(),
        icon: const Icon(Icons.calendar_month_rounded, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(describeRange(widget.value)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
