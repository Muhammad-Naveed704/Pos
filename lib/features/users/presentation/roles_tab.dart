import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../data/role_repository.dart';

final _rolesProvider = StreamProvider.autoDispose<List<RoleSummary>>((ref) {
  final session = ref.watch(activeSessionProvider);
  if (session == null) return const Stream.empty();
  return ref.watch(roleRepositoryProvider).watch(session);
});

/// Roles × permissions matrix with bulk editing.
class RolesTab extends ConsumerStatefulWidget {
  const RolesTab({super.key});
  @override
  ConsumerState<RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends ConsumerState<RolesTab>
    with AutomaticKeepAliveClientMixin {
  /// Unsaved edits: role id → full permission set.
  final _draft = <String, Set<String>>{};
  bool _saving = false;
  final _horizontal = ScrollController();

  static const _labelWidth = 330.0;
  static const _columnWidth = 132.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  Set<String> _current(RoleSummary role) =>
      _draft[role.role.id] ?? role.permissions;

  void _set(RoleSummary role, Iterable<String> keys, bool enabled) {
    if (role.isOwner) return;
    final session = ref.read(activeSessionProvider)!;
    final next = {..._current(role)};
    for (final key in keys) {
      if (enabled) {
        // Only grant what you hold yourself.
        if (session.can(key)) next.add(key);
      } else {
        next.remove(key);
      }
    }
    setState(() {
      if (next.length == role.permissions.length &&
          next.containsAll(role.permissions)) {
        _draft.remove(role.role.id);
      } else {
        _draft[role.role.id] = next;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(roleRepositoryProvider).savePermissions(
        ref.read(activeSessionProvider)!,
        {..._draft},
      );
      if (!mounted) return;
      setState(_draft.clear);
      Toast.success(
        context,
        'Permissions saved. Affected users get them at their next sign-in.',
      );
    } catch (error) {
      if (mounted) Toast.error(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createRoles(List<RoleSummary> roles) async {
    final result = await showDialog<(List<String>, Set<String>)>(
      context: context,
      builder: (_) => _NewRolesDialog(roles: roles),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(roleRepositoryProvider)
          .createRoles(
            ref.read(activeSessionProvider)!,
            names: result.$1,
            permissions: result.$2,
          );
      if (mounted) {
        Toast.success(context, '${result.$1.length} role(s) created.');
      }
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  Future<void> _roleAction(String action, RoleSummary role) async {
    final repository = ref.read(roleRepositoryProvider);
    final session = ref.read(activeSessionProvider)!;
    try {
      switch (action) {
        case 'duplicate':
          final name = await promptDialog(
            context,
            title: 'Duplicate ${role.role.name}',
            label: 'New role name',
            initialValue: '${role.role.name} copy',
            confirmLabel: 'Duplicate',
          );
          if (name == null) return;
          await repository.createRoles(
            session,
            names: [name],
            permissions: _current(role),
          );
        case 'rename':
          final name = await promptDialog(
            context,
            title: 'Rename role',
            label: 'Role name',
            initialValue: role.role.name,
            confirmLabel: 'Rename',
          );
          if (name == null) return;
          await repository.rename(session, role.role, name);
        case 'delete':
          final confirmed = await confirmDialog(
            context,
            title: 'Delete ${role.role.name}?',
            message: 'This role will be removed permanently.',
            confirmLabel: 'Delete',
            destructive: true,
          );
          if (!confirmed) return;
          await repository.delete(session, role.role);
          _draft.remove(role.role.id);
      }
    } catch (error) {
      if (mounted) Toast.error(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = ref.watch(activeSessionProvider)!;
    final canManage = session.can(Permissions.usersManage);
    final async = ref.watch(_rolesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Roles could not be loaded',
        message: friendlyError(error),
      ),
      data: (roles) {
        final dirty = _draft.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    canManage
                        ? 'Tick permissions for each role. Owner always has everything. '
                              'You can only grant permissions you have yourself.'
                        : 'You can view roles but not change them.',
                    style: TextStyle(color: context.colors.onSurfaceVariant),
                  ),
                ),
                if (canManage) ...[
                  if (dirty) ...[
                    TextButton(
                      onPressed: _saving ? null : () => setState(_draft.clear),
                      child: const Text('Discard'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(
                        'Save ${_draft.length} role${_draft.length == 1 ? '' : 's'}',
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => _createRoles(roles),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('New roles'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = math.max(
                      constraints.maxWidth,
                      _labelWidth + roles.length * _columnWidth,
                    );
                    return Scrollbar(
                      controller: _horizontal,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: width,
                          child: Column(
                            children: [
                              _header(context, roles, canManage),
                              const Divider(),
                              Expanded(
                                child: ListView(
                                  children: [
                                    for (final group
                                        in PermissionCatalog.groups)
                                      ..._group(
                                        context,
                                        group,
                                        roles,
                                        canManage,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    List<RoleSummary> roles,
    bool canManage,
  ) => Container(
    color: context.colors.surfaceContainerHigh,
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(
          width: _labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(
              'Permission',
              style: context.text.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        for (final role in roles)
          SizedBox(
            width: _columnWidth,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        role.role.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _draft.containsKey(role.role.id)
                              ? context.colors.primary
                              : null,
                        ),
                      ),
                    ),
                    if (canManage)
                      PopupMenuButton<String>(
                        tooltip: 'Role actions',
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        onSelected: (action) => _roleAction(action, role),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Text('Duplicate'),
                          ),
                          if (!role.role.isSystem) ...[
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
                Text(
                  '${role.userCount} user${role.userCount == 1 ? '' : 's'}'
                  '${role.role.isSystem ? ' · built-in' : ''}',
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  List<Widget> _group(
    BuildContext context,
    String group,
    List<RoleSummary> roles,
    bool canManage,
  ) {
    final items = PermissionCatalog.inGroup(group);
    final keys = items.map((item) => item.key).toList();
    return [
      Container(
        color: context.colors.surfaceContainerLow,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: _labelWidth,
              child: Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Text(
                  group.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                    color: context.colors.primary,
                  ),
                ),
              ),
            ),
            for (final role in roles)
              SizedBox(
                width: _columnWidth,
                child: () {
                  final current = _current(role);
                  final on = keys.where(current.contains).length;
                  return Checkbox(
                    tristate: true,
                    value: on == 0
                        ? false
                        : on == keys.length
                        ? true
                        : null,
                    onChanged: !canManage || role.isOwner
                        ? null
                        : (_) => _set(role, keys, on != keys.length),
                  );
                }(),
              ),
          ],
        ),
      ),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              SizedBox(
                width: _labelWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(30, 6, 12, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final role in roles)
                SizedBox(
                  width: _columnWidth,
                  child: Checkbox(
                    value: _current(role).contains(item.key),
                    onChanged: !canManage || role.isOwner
                        ? null
                        : (value) => _set(role, [item.key], value ?? false),
                  ),
                ),
            ],
          ),
        ),
    ];
  }
}

class _NewRolesDialog extends StatefulWidget {
  const _NewRolesDialog({required this.roles});
  final List<RoleSummary> roles;
  @override
  State<_NewRolesDialog> createState() => _NewRolesDialogState();
}

class _NewRolesDialogState extends State<_NewRolesDialog> {
  final _names = TextEditingController();
  late String? _templateId = widget.roles
      .where((role) => role.role.name == 'Cashier')
      .firstOrNull
      ?.role
      .id;
  String? _error;

  @override
  void dispose() {
    _names.dispose();
    super.dispose();
  }

  List<String> get _parsed => _names.text
      .split(RegExp(r'[\n,;]'))
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();

  void _submit() {
    final names = _parsed;
    if (names.isEmpty) {
      setState(() => _error = 'Enter at least one role name.');
      return;
    }
    final template = widget.roles
        .where((role) => role.role.id == _templateId)
        .firstOrNull;
    Navigator.pop(context, (names, template?.permissions ?? <String>{}));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.group_add_outlined),
    title: const Text('Create roles'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _names,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Role names',
              hintText: 'Senior Cashier\nStock Keeper\nAccountant',
              helperText:
                  'One per line (or comma separated). ${_parsed.length} role(s).',
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            menuMaxHeight: 360,
            initialValue: _templateId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Start with permissions from',
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('No permissions'),
              ),
              for (final role in widget.roles)
                DropdownMenuItem(
                  value: role.role.id,
                  child: Text(
                    '${role.role.name}  (${role.permissions.length} permissions)',
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _templateId = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Create')),
    ],
  );
}
