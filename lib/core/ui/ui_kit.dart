import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_tokens.dart';

export '../theme/app_tokens.dart' show AppThemeContext, AppTokens;
export 'app_table.dart';
export 'brand_mark.dart';
export 'cached_stream_builder.dart';
export 'inputs.dart';
export 'product_thumb.dart';

/// Standard page title row with optional subtitle and trailing actions.
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[
        IconTile(icon: icon!, size: 44),
        const SizedBox(width: 14),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        actions[i],
      ],
    ],
  );
}

/// Rounded, tinted square behind an icon.
class IconTile extends StatelessWidget {
  const IconTile({required this.icon, this.color, this.size = 40, super.key});
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: tint, size: size * 0.5),
    );
  }
}

/// Card with a title bar, used for dashboard panels and settings groups.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: context.colors.primary),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        style: context.text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
          ],
          Flexible(child: child),
        ],
      ),
    ),
  );
}

/// KPI tile with icon, value, label and optional footnote.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.footnote,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -18,
            child: Icon(icon, size: 96, color: tint.withValues(alpha: 0.06)),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconTile(icon: icon, color: tint, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: context.text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (footnote != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    footnote!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered illustration + message for empty, error and placeholder states.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 56 : 76,
            height: compact ? 56 : 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.primaryContainer.withValues(alpha: 0.55),
            ),
            child: Icon(
              icon,
              size: compact ? 26 : 34,
              color: context.colors.onPrimaryContainer,
            ),
          ),
          SizedBox(height: compact ? 10 : 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style:
                (compact ? context.text.titleSmall : context.text.titleMedium)
                    ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

enum PillTone { neutral, primary, success, warning, danger, info }

/// Small rounded status label.
class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    this.tone = PillTone.neutral,
    this.icon,
    super.key,
  });
  final String label;
  final PillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = context.colors;
    final (background, foreground) = switch (tone) {
      PillTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      PillTone.primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
      PillTone.success => (tokens.successContainer, tokens.success),
      PillTone.warning => (tokens.warningContainer, tokens.warning),
      PillTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
      PillTone.info => (tokens.infoContainer, tokens.info),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            // Icons.circle renders as a small status dot.
            Icon(icon, size: icon == Icons.circle ? 8 : 13, color: foreground),
            SizedBox(width: icon == Icons.circle ? 6 : 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Keyboard shortcut badge, e.g. `F7`.
class KeyHint extends StatelessWidget {
  const KeyHint(this.label, {this.onPrimary = false, super.key});
  final String label;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final color = onPrimary ? context.colors.onPrimary : context.colors.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

extension MotionX on Widget {
  /// Fade + slight rise, honouring the user's animation level.
  Widget entrance(BuildContext context, {int delay = 0, double dy = 0.04}) {
    final tokens = context.tokens;
    if (!tokens.animate) return this;
    return animate(delay: tokens.motion(delay))
        .fadeIn(duration: tokens.motion(260), curve: Curves.easeOutCubic)
        .slideY(
          begin: dy,
          end: 0,
          duration: tokens.motion(300),
          curve: Curves.easeOutCubic,
        );
  }
}

/// Consistent toast messages.
abstract final class Toast {
  static void show(
    BuildContext context,
    String message, {
    PillTone tone = PillTone.neutral,
    IconData? icon,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final scheme = Theme.of(context).colorScheme;
    final tokens = AppTokens.of(context);
    final (color, fallbackIcon) = switch (tone) {
      PillTone.success => (tokens.success, Icons.check_circle_rounded),
      PillTone.danger => (scheme.error, Icons.error_rounded),
      PillTone.warning => (tokens.warning, Icons.warning_amber_rounded),
      _ => (scheme.inversePrimary, Icons.info_rounded),
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon ?? fallbackIcon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  static void success(BuildContext context, String message) =>
      show(context, message, tone: PillTone.success);

  static void error(BuildContext context, Object error) =>
      show(context, friendlyError(error), tone: PillTone.danger);
}

/// Strips exception class prefixes for display.
String friendlyError(Object error) => error.toString().replaceFirst(
  RegExp(r'^(Exception|Bad state|Invalid argument\(s\)): '),
  '',
);

/// Yes/no confirmation dialog.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: icon == null ? null : Icon(icon),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          autofocus: true,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Single text-field prompt. The dialog owns and disposes its controller.
Future<String?> promptDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
  String confirmLabel = 'Confirm',
  String? hint,
  String? prefixText,
  String? suffixText,
  bool numeric = false,
  int maxLines = 1,
  String? Function(String value)? validator,
}) => showDialog<String>(
  context: context,
  builder: (context) => _PromptDialog(
    title: title,
    label: label,
    initialValue: initialValue,
    confirmLabel: confirmLabel,
    hint: hint,
    prefixText: prefixText,
    suffixText: suffixText,
    numeric: numeric,
    maxLines: maxLines,
    validator: validator,
  ),
);

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.confirmLabel,
    required this.numeric,
    required this.maxLines,
    this.hint,
    this.prefixText,
    this.suffixText,
    this.validator,
  });

  final String title;
  final String label;
  final String initialValue;
  final String confirmLabel;
  final String? hint;
  final String? prefixText;
  final String? suffixText;
  final bool numeric;
  final int maxLines;
  final String? Function(String value)? validator;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _controller = TextEditingController(text: widget.initialValue)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = widget.validator?.call(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 400,
      child: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
        keyboardType: widget.numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        inputFormatters: widget.numeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))]
            : null,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixText: widget.prefixText,
          suffixText: widget.suffixText,
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ],
  );
}

/// Date-range picker sized as a dialog on desktop (the Material default is
/// full screen).
Future<DateTimeRange?> pickDateRange(
  BuildContext context, {
  DateTimeRange? initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return showDateRangePicker(
    context: context,
    firstDate: firstDate ?? DateTime(2020),
    lastDate: lastDate ?? today,
    initialDateRange: initial,
    builder: (context, child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.of(context).radius + 8),
          child: child,
        ),
      ),
    ),
  );
}

/// Single date picker sized for desktop.
Future<DateTime?> pickDate(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: firstDate ?? DateTime(2020),
    lastDate: lastDate ?? DateTime(now.year + 5),
    builder: (context, child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: child,
      ),
    ),
  );
}
