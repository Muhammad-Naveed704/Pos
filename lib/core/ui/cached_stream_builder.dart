import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A [StreamBuilder] that creates its stream once and only recreates it when
/// [keys] change.
///
/// Drift `watch()` queries run again on every subscription, so a stream built
/// inside `build()` re-queried the database on every rebuild (for example on
/// each item added to the POS cart). Use this instead.
class CachedStreamBuilder<T> extends StatefulWidget {
  const CachedStreamBuilder({
    required this.create,
    required this.builder,
    this.keys = const [],
    super.key,
  });

  final Stream<T> Function() create;
  final AsyncWidgetBuilder<T> builder;

  /// Values the stream depends on (filters, store, user).
  final List<Object?> keys;

  @override
  State<CachedStreamBuilder<T>> createState() => _CachedStreamBuilderState<T>();
}

class _CachedStreamBuilderState<T> extends State<CachedStreamBuilder<T>> {
  late Stream<T> _stream = widget.create();

  @override
  void didUpdateWidget(CachedStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.keys, widget.keys)) _stream = widget.create();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<T>(stream: _stream, builder: widget.builder);
}
