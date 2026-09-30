import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../csv/csv_table.dart';
import '../csv/import_models.dart';
import 'ui_kit.dart';

/// Saves [rows] as a CSV file chosen by the user. Returns the path.
Future<String?> saveCsvFile(
  List<List<Object?>> rows, {
  required String fileName,
  String dialogTitle = 'Save CSV',
}) async {
  final bytes = Uint8List.fromList(utf8.encode(encodeCsv(rows)));
  final uri = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: ['csv'],
  );
  if (uri == null) return null;
  final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  final file = File(path);
  if (!file.existsSync() || file.lengthSync() == 0) {
    await file.writeAsBytes(bytes, flush: true);
  }
  return path;
}

CsvTable _decode((String, Map<String, String>) input) =>
    parseCsvTable(input.$1, aliases: input.$2);

/// Guided CSV import: choose file → review every row → import.
class ImportDialog<P> extends StatefulWidget {
  const ImportDialog({
    required this.title,
    required this.subject,
    required this.templateFileName,
    required this.template,
    required this.aliases,
    required this.prepare,
    required this.previewOf,
    required this.apply,
    this.columnsHelp = const [],
    super.key,
  });

  final String title;

  /// Plural noun, e.g. "products".
  final String subject;
  final String templateFileName;
  final List<List<Object?>> Function() template;
  final Map<String, String> aliases;
  final Future<P> Function(CsvTable table, bool updateExisting) prepare;
  final ImportPreview Function(P plan) previewOf;
  final Future<ImportOutcome> Function(P plan) apply;

  /// (column, description) pairs shown on the first step.
  final List<(String, String)> columnsHelp;

  @override
  State<ImportDialog<P>> createState() => _ImportDialogState<P>();
}

enum _Stage { choose, review, importing, done }

class _ImportDialogState<P> extends State<ImportDialog<P>> {
  _Stage _stage = _Stage.choose;
  CsvTable? _table;
  String? _fileName;
  P? _plan;
  ImportOutcome? _outcome;
  bool _updateExisting = true;
  bool _busy = false;
  String? _error;
  ImportAction? _filter;

  Future<void> _downloadTemplate() async {
    try {
      final path = await saveCsvFile(
        widget.template(),
        fileName: widget.templateFileName,
        dialogTitle: 'Save template',
      );
      if (path != null && mounted) {
        Toast.success(context, 'Template saved to $path');
      }
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  Future<void> _choose() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose a CSV file',
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await File(path).readAsBytes();
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        // Older Excel exports are often Windows-1252 / Latin-1.
        text = latin1.decode(bytes);
      }
      final table = await compute(_decode, (text, widget.aliases));
      if (table.rows.isEmpty) {
        throw const ImportFormatException('The file has no data rows.');
      }
      final plan = await widget.prepare(table, _updateExisting);
      if (!mounted) return;
      setState(() {
        _table = table;
        _fileName = path.split(RegExp(r'[\\/]')).last;
        _plan = plan;
        _stage = _Stage.review;
        _filter = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reprepare(bool updateExisting) async {
    setState(() {
      _updateExisting = updateExisting;
      _busy = true;
    });
    try {
      final plan = await widget.prepare(_table!, updateExisting);
      if (mounted) setState(() => _plan = plan);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _stage = _Stage.importing;
      _error = null;
    });
    try {
      final outcome = await widget.apply(_plan as P);
      if (mounted) {
        setState(() {
          _outcome = outcome;
          _stage = _Stage.done;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = friendlyError(error);
          _stage = _Stage.review;
        });
      }
    }
  }

  Future<void> _downloadErrors(ImportPreview preview) async {
    final rows = preview.rows
        .where(
          (row) =>
              row.action == ImportAction.error ||
              row.action == ImportAction.skip,
        )
        .toList();
    await saveCsvFile(
      [
        ['line', 'row', 'status', 'problem'],
        for (final row in rows)
          [row.line, row.label, row.action.name, row.messages.join(' ')],
      ],
      fileName: '${widget.subject}-import-issues.csv',
      dialogTitle: 'Save issue report',
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconTile(icon: Icons.upload_file_rounded, size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: context.text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        switch (_stage) {
                          _Stage.choose => 'Step 1 of 2 · Choose a CSV file',
                          _Stage.review ||
                          _Stage.importing => 'Step 2 of 2 · Review $_fileName',
                          _Stage.done => 'Import complete',
                        },
                        style: TextStyle(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _stage == _Stage.importing
                      ? null
                      : () => Navigator.pop(context, _outcome != null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: switch (_stage) {
                _Stage.choose => _chooseStep(context),
                _Stage.review || _Stage.importing => _reviewStep(context),
                _Stage.done => _doneStep(context),
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.errorContainer,
                  borderRadius: context.tokens.borderRadius,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: context.colors.onErrorContainer),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _chooseStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: InkWell(
          borderRadius: context.tokens.borderRadius,
          onTap: _busy ? null : _choose,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: context.tokens.borderRadius,
              border: Border.all(
                color: context.colors.outlineVariant,
                width: 2,
              ),
              color: context.colors.surfaceContainerLow,
            ),
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : EmptyState(
                    icon: Icons.table_view_rounded,
                    title: 'Click to choose a CSV file',
                    message: 'Save your Excel sheet as “CSV UTF-8”. The first row must be the column headers.',
                    action: widget.columnsHelp.isEmpty
                        ? null
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final (column, help) in widget.columnsHelp)
                                Tooltip(
                                  message: help,
                                  child: StatusPill(
                                    column,
                                    tone: help.startsWith('Required')
                                        ? PillTone.primary
                                        : PillTone.neutral,
                                  ),
                                ),
                            ],
                          ),
                  ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          TextButton.icon(
            onPressed: _downloadTemplate,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download template'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _busy ? null : _choose,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Choose file'),
          ),
        ],
      ),
    ],
  );

  Widget _reviewStep(BuildContext context) {
    final preview = widget.previewOf(_plan as P);
    final importing = _stage == _Stage.importing;
    final rows = _filter == null
        ? preview.rows
        : preview.rows.where((row) => row.action == _filter).toList();
    Widget counter(ImportAction? action, String label, PillTone tone) {
      final count = action == null
          ? preview.rows.length
          : preview.count(action);
      return ChoiceChip(
        label: Text('$label  $count'),
        selected: _filter == action,
        onSelected: (_) => setState(() => _filter = action),
        avatar: action == null
            ? null
            : Icon(_icon(action), size: 16, color: _color(context, tone)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            counter(null, 'All', PillTone.neutral),
            counter(ImportAction.create, 'New', PillTone.success),
            counter(ImportAction.update, 'Update', PillTone.info),
            counter(ImportAction.skip, 'Skip', PillTone.neutral),
            counter(ImportAction.error, 'Errors', PillTone.danger),
          ],
        ),
        const SizedBox(height: 10),
        for (final note in preview.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: context.tokens.info,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(note, style: context.text.bodySmall)),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: rows.isEmpty
                ? const EmptyState(
                    compact: true,
                    icon: Icons.filter_alt_off_outlined,
                    title: 'No rows in this filter',
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final tone = _tone(row.action);
                      return ListTile(
                        dense: true,
                        leading: SizedBox(
                          width: 58,
                          child: Text(
                            'Line ${row.line}',
                            style: context.text.labelSmall,
                          ),
                        ),
                        title: Text(
                          row.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: row.messages.isEmpty
                            ? null
                            : Text(
                                row.messages.join(' '),
                                style: TextStyle(
                                  color: row.action == ImportAction.error
                                      ? context.colors.error
                                      : null,
                                ),
                              ),
                        trailing: StatusPill(
                          switch (row.action) {
                            ImportAction.create => 'New',
                            ImportAction.update => 'Update',
                            ImportAction.skip => 'Skip',
                            ImportAction.error => 'Error',
                          },
                          tone: tone,
                          icon: _icon(row.action),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Switch(
              value: _updateExisting,
              onChanged: importing || _busy ? null : _reprepare,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Update ${widget.subject} that already exist',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (preview.count(ImportAction.error) +
                    preview.count(ImportAction.skip) >
                0)
              TextButton.icon(
                onPressed: () => _downloadErrors(preview),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Issue report'),
              ),
            TextButton(
              onPressed: importing
                  ? null
                  : () => setState(() {
                      _stage = _Stage.choose;
                      _plan = null;
                    }),
              child: const Text('Choose another file'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: importing || _busy || !preview.hasWork
                  ? null
                  : _import,
              icon: importing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                'Import ${preview.count(ImportAction.create) + preview.count(ImportAction.update)} rows',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _doneStep(BuildContext context) {
    final outcome = _outcome!;
    return Column(
      children: [
        Expanded(
          child: EmptyState(
            icon: Icons.task_alt_rounded,
            title:
                '${outcome.created} created · ${outcome.updated} updated · ${outcome.skipped} skipped',
            message: outcome.extra.isEmpty ? null : outcome.extra.join(' · '),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  static PillTone _tone(ImportAction action) => switch (action) {
    ImportAction.create => PillTone.success,
    ImportAction.update => PillTone.info,
    ImportAction.skip => PillTone.neutral,
    ImportAction.error => PillTone.danger,
  };

  static IconData _icon(ImportAction action) => switch (action) {
    ImportAction.create => Icons.add_circle_outline_rounded,
    ImportAction.update => Icons.sync_rounded,
    ImportAction.skip => Icons.remove_circle_outline_rounded,
    ImportAction.error => Icons.error_outline_rounded,
  };

  static Color _color(BuildContext context, PillTone tone) => switch (tone) {
    PillTone.success => context.tokens.success,
    PillTone.info => context.tokens.info,
    PillTone.danger => context.colors.error,
    _ => context.colors.outline,
  };
}

/// "Import / Export" menu button used on list pages.
class DataMenu extends StatelessWidget {
  const DataMenu({
    required this.canImport,
    required this.onImport,
    required this.onTemplate,
    required this.onExport,
    super.key,
  });
  final bool canImport;
  final VoidCallback onImport;
  final VoidCallback onTemplate;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      if (canImport)
        MenuItemButton(
          leadingIcon: const Icon(Icons.upload_file_rounded, size: 18),
          onPressed: onImport,
          child: const Text('Import from CSV...'),
        ),
      if (canImport)
        MenuItemButton(
          leadingIcon: const Icon(Icons.description_outlined, size: 18),
          onPressed: onTemplate,
          child: const Text('Download CSV template'),
        ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.download_rounded, size: 18),
        onPressed: onExport,
        child: const Text('Export to CSV'),
      ),
    ],
    builder: (context, controller, _) => OutlinedButton.icon(
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.import_export_rounded),
      label: const Text('Import / Export'),
    ),
  );
}
