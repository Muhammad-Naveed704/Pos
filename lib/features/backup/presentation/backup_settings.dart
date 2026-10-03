import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_host.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../application/backup_providers.dart';
import '../data/backup_service.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

final _dateTime = DateFormat('d MMM y, h:mm a');

/// Settings → Data & Backup.
class BackupSettingsTab extends ConsumerStatefulWidget {
  const BackupSettingsTab({super.key});
  @override
  ConsumerState<BackupSettingsTab> createState() => _BackupSettingsTabState();
}

class _BackupSettingsTabState extends ConsumerState<BackupSettingsTab> {
  late Future<BackupStatus> _status;
  BackupSettings? _draft;
  String? _defaultFolder;
  bool _busy = false;
  String? _busyLabel;

  @override
  void initState() {
    super.initState();
    _reload();
    BackupService.defaultDirectory().then((dir) {
      if (mounted) setState(() => _defaultFolder = dir.path);
    }, onError: (_) {});
  }

  void _reload() {
    _status = ref
        .read(backupServiceProvider)
        .status(ref.read(activeSessionProvider)!)
        .then((status) {
          if (mounted) setState(() => _draft ??= status.settings);
          return status;
        });
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) Toast.error(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
          _reload();
        });
      }
    }
  }

  String _folderOf(BackupSettings settings) =>
      settings.directory ?? _defaultFolder ?? 'Documents\\StoreFlow Backups';

  Future<void> _create() => _run('Creating backup…', () async {
    final result = await ref
        .read(backupServiceProvider)
        .create(ref.read(activeSessionProvider)!);
    if (mounted) {
      Toast.success(
        context,
        'Backup verified: ${p.basename(result.file.path)} (${formatBytes(result.sizeBytes)})',
      );
    }
  });

  Future<void> _openFolder(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      Toast.show(
        context,
        'The folder does not exist yet. Create a backup first.',
      );
      return;
    }
    await Process.run('explorer', [dir.path]);
  }

  Future<File?> _pickBackup(String title) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: [backupExtension],
    );
    final path = files.isEmpty ? null : files.first.path;
    return path == null ? null : File(path);
  }

  Future<void> _verify() async {
    final file = await _pickBackup('Choose a backup to verify');
    if (file == null) return;
    await _run('Verifying backup…', () async {
      final manifest = await ref
          .read(backupServiceProvider)
          .verify(ref.read(activeSessionProvider)!, file);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.verified_rounded, color: context.tokens.success),
          title: const Text('Backup is valid'),
          content: SizedBox(
            width: 440,
            child: BackupDetails(file: file, manifest: manifest),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _restore() async {
    final host = ref.read(databaseHostProvider);
    if (host == null) {
      Toast.show(context, 'Restore is not available in this mode.');
      return;
    }
    final file = await _pickBackup('Choose a backup to restore');
    if (file == null || !mounted) return;
    final service = ref.read(backupServiceProvider);
    BackupInspection? inspection;
    setState(() {
      _busy = true;
      _busyLabel = 'Checking backup…';
    });
    try {
      inspection = await service.inspect(file);
    } catch (error) {
      if (mounted) Toast.error(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
    if (inspection == null || !mounted) return;
    final confirmed = await showRestoreConfirmation(
      context,
      file: file,
      manifest: inspection.manifest,
    );
    if (!confirmed || !mounted) {
      inspection.dispose();
      return;
    }
    final session = ref.read(activeSessionProvider)!;
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ProgressDialog('Restoring data…'),
    );
    try {
      final restored = await service.restore(
        session,
        inspection: inspection,
        liveFile: await host.databaseFile(),
        closeDatabase: host.database.close,
        openDatabase: host.openDatabase,
      );
      inspection.dispose();
      navigator.pop();
      // Rebuilds the app on the restored data; everyone signs in again.
      host.replace(restored);
    } on RestoreFailedException catch (error) {
      inspection.dispose();
      navigator.pop();
      host.replace(error.database);
    } catch (error) {
      inspection.dispose();
      navigator.pop();
      if (mounted) Toast.error(context, error);
    }
  }

  Future<void> _chooseFolder() async {
    final draft = _draft;
    if (draft == null) return;
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose the backup folder',
      initialDirectory: _folderOf(draft),
    );
    if (path != null && mounted) {
      setState(() => _draft = draft.copyWith(directory: path));
    }
  }

  Future<void> _saveSchedule() => _run('Saving…', () async {
    await ref
        .read(backupServiceProvider)
        .saveSettings(ref.read(activeSessionProvider)!, _draft!);
    if (mounted) Toast.success(context, 'Backup settings saved.');
  });

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    final canCreate = session.can(Permissions.backupCreate);
    final canRestore = session.can(Permissions.backupRestore);
    final canSchedule = session.can(Permissions.backupSettings);
    return FutureBuilder<BackupStatus>(
      future: _status,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Backup status could not be loaded',
            message: friendlyError(snapshot.error!),
          );
        }
        final status = snapshot.data;
        final draft = _draft;
        if (status == null || draft == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final folder = _folderOf(status.settings);
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 20),
          children: [
            if (_busy) ...[
              LinearProgressIndicator(
                borderRadius: context.tokens.borderRadius,
              ),
              const SizedBox(height: 6),
              Text(_busyLabel ?? '', style: context.text.bodySmall),
              const SizedBox(height: 10),
            ],
            _overview(context, status, folder),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Backup now',
              subtitle:
                  'One portable file with the database, settings, theme, receipt layout and images. '
                  'Every backup is checked after it is written.',
              icon: Icons.backup_rounded,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: canCreate && !_busy ? _create : null,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Create backup'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openFolder(folder),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Open backup folder'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canCreate && !_busy ? _verify : null,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Verify a backup'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: canRestore && !_busy ? _restore : null,
                    style: FilledButton.styleFrom(
                      foregroundColor: context.colors.error,
                    ),
                    icon: const Icon(Icons.settings_backup_restore_rounded),
                    label: const Text('Restore from backup…'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _schedule(context, draft, canSchedule),
            const SizedBox(height: 16),
            _history(context, status),
          ],
        );
      },
    );
  }

  Widget _overview(BuildContext context, BackupStatus status, String folder) {
    final last = status.lastBackup;
    final age = last == null ? null : DateTime.now().difference(last.createdAt);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 36) / 4;
        final cards = [
          StatCard(
            label: 'Last backup',
            value: last == null ? 'Never' : _dateTime.format(last.createdAt),
            icon: Icons.history_rounded,
            color: last == null || age!.inDays > 7
                ? context.tokens.warning
                : context.tokens.success,
            footnote: last == null
                ? 'No verified backup yet'
                : '${formatBytes(last.sizeBytes)} · ${last.kind}',
          ),
          StatCard(
            label: 'Database size',
            value: formatBytes(status.databaseSize),
            icon: Icons.storage_rounded,
            color: context.colors.primary,
            footnote: status.databasePath == null
                ? null
                : p.basename(status.databasePath!),
          ),
          StatCard(
            label: 'Schedule',
            value: status.settings.frequency.label,
            icon: Icons.event_repeat_rounded,
            color: context.tokens.info,
            footnote: 'Keeps ${status.settings.retention} scheduled backups',
          ),
          StatCard(
            label: 'Stores in backup',
            value: '${status.stores.length}',
            icon: Icons.storefront_rounded,
            color: context
                .tokens
                .chartPalette[3 % context.tokens.chartPalette.length],
            footnote: status.stores.map((s) => s.code).join(', '),
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: width < 200
                        ? (constraints.maxWidth - 12) / 2
                        : width,
                    child: card,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 16,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Backups are saved to $folder',
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _schedule(
    BuildContext context,
    BackupSettings draft,
    bool canEdit,
  ) => SectionCard(
    title: 'Automatic backups',
    subtitle:
        'Runs while StoreFlow is open and someone is signed in. Old scheduled backups '
        'beyond the limit are deleted; other files in the folder are never touched.',
    icon: Icons.schedule_rounded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Backup folder',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
                child: Text(
                  _folderOf(draft),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: canEdit ? _chooseFolder : null,
              child: const Text('Change…'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 24,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Labeled(
              label: 'Frequency',
              child: AppSegmented<BackupFrequency>(
                items: [
                  for (final f in BackupFrequency.values)
                    SegmentItem(f, f.label),
                ],
                value: draft.frequency,
                onChanged: canEdit
                    ? (f) =>
                          setState(() => _draft = draft.copyWith(frequency: f))
                    : (_) {},
              ),
            ),
            _Labeled(
              label: 'Keep',
              child: AppSegmented<int>(
                items: const [
                  SegmentItem(5, '5'),
                  SegmentItem(10, '10'),
                  SegmentItem(20, '20'),
                ],
                value: draft.retention,
                onChanged: canEdit
                    ? (v) =>
                          setState(() => _draft = draft.copyWith(retention: v))
                    : (_) {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: draft.beforeRiskyOperations,
          onChanged: canEdit
              ? (v) => setState(
                  () => _draft = draft.copyWith(beforeRiskyOperations: v),
                )
              : null,
          title: const Text('Safety backup before restore and bulk imports'),
          subtitle: const Text(
            'Recommended. Saved in the app data folder under safety-backups.',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: canEdit && !_busy ? _saveSchedule : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Save backup settings'),
        ),
      ],
    ),
  );

  Widget _history(BuildContext context, BackupStatus status) => SectionCard(
    title: 'Recent backups',
    icon: Icons.list_alt_rounded,
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: status.recent.isEmpty
        ? const EmptyState(
            compact: true,
            icon: Icons.cloud_off_rounded,
            title: 'No backups yet',
            message: 'Create the first backup above.',
          )
        : Column(
            children: [
              for (final record in status.recent)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(switch (record.kind) {
                    'scheduled' => Icons.event_repeat_rounded,
                    'safety' => Icons.shield_outlined,
                    _ => Icons.backup_outlined,
                  }),
                  title: Text(
                    p.basename(record.filePath),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_dateTime.format(record.createdAt)} · ${record.kind}'
                    '${record.sizeBytes > 0 ? ' · ${formatBytes(record.sizeBytes)}' : ''}'
                    '${record.status == 'failed' && record.note.isNotEmpty ? ' · ${record.note}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: StatusPill(
                    switch (record.status) {
                      'verified' => 'Verified',
                      'failed' => 'Failed',
                      'pruned' => 'Removed',
                      _ => record.status,
                    },
                    tone: switch (record.status) {
                      'verified' => PillTone.success,
                      'failed' => PillTone.danger,
                      _ => PillTone.neutral,
                    },
                    icon: switch (record.status) {
                      'verified' => Icons.verified_rounded,
                      'failed' => Icons.error_outline_rounded,
                      _ => Icons.remove_circle_outline_rounded,
                    },
                  ),
                ),
            ],
          ),
  );
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: context.text.labelMedium),
      const SizedBox(height: 6),
      child,
    ],
  );
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      content: Row(
        children: [
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(),
          ),
          const SizedBox(width: 18),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

/// Backup metadata shown before verify/restore.
class BackupDetails extends StatelessWidget {
  const BackupDetails({required this.file, required this.manifest, super.key});
  final File file;
  final BackupManifest manifest;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('File', p.basename(file.path)),
        row('Created', _dateTime.format(manifest.createdAt)),
        row('Created by', manifest.createdBy),
        row('Kind', manifest.kind),
        row('App version', manifest.appVersion),
        row('Database version', '${manifest.schemaVersion}'),
        row(
          'Stores',
          manifest.stores.map((s) => '${s.name} (${s.code})').join(', '),
        ),
        row('Database size', formatBytes(manifest.databaseSize)),
        row('Images & logos', '${manifest.assetCount}'),
        row('Checksum', '${manifest.databaseSha256.substring(0, 16)}…'),
      ],
    );
  }
}

/// Asks the user to confirm a restore by typing RESTORE.
Future<bool> showRestoreConfirmation(
  BuildContext context, {
  required File file,
  required BackupManifest manifest,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) =>
          _RestoreConfirmDialog(file: file, manifest: manifest),
    ) ??
    false;

class _RestoreConfirmDialog extends StatefulWidget {
  const _RestoreConfirmDialog({required this.file, required this.manifest});
  final File file;
  final BackupManifest manifest;

  @override
  State<_RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<_RestoreConfirmDialog> {
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _typed.text.trim().toUpperCase() == 'RESTORE';
    return AlertDialog(
      icon: Icon(
        Icons.settings_backup_restore_rounded,
        color: context.colors.error,
      ),
      title: const Text('Restore this backup?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.errorContainer,
                  borderRadius: context.tokens.borderRadius,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: context.colors.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All current sales, products, customers and settings will be replaced '
                        'by this backup. A safety backup of the current data is made first. '
                        'Everyone will need to sign in again.',
                        style: TextStyle(
                          color: context.colors.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              BackupDetails(file: widget.file, manifest: widget.manifest),
              const SizedBox(height: 14),
              TextField(
                controller: _typed,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Type RESTORE to confirm',
                  prefixIcon: Icon(Icons.keyboard_rounded),
                ),
                onSubmitted: (_) {
                  if (ready) Navigator.pop(context, true);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.error,
            foregroundColor: context.colors.onError,
          ),
          icon: const Icon(Icons.restore_rounded),
          label: const Text('Restore'),
        ),
      ],
    );
  }
}
