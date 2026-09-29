import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../stores/data/store_repository.dart';
import '../data/user_repository.dart';

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider)!;
    final canManage = session.can(Permissions.usersManage);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Users & roles',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              if (canManage) ...[
                OutlinedButton.icon(
                  onPressed: () => _manageRoles(context, ref),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: const Text('Role permissions'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _edit(context, ref),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('New user'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: StreamBuilder<List<UserWithRole>>(
                stream: ref.watch(userRepositoryProvider).watchAll(session),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView.separated(
                    itemCount: snapshot.data!.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = snapshot.data![index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        leading: CircleAvatar(
                          child: Text(
                            item.user.displayName.characters.first
                                .toUpperCase(),
                          ),
                        ),
                        title: Text(
                          item.user.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${item.user.username} · ${item.role.name}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text(
                                item.user.isActive ? 'Active' : 'Inactive',
                              ),
                            ),
                            if (canManage)
                              IconButton(
                                onPressed: () =>
                                    _edit(context, ref, item: item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manageRoles(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(userRepositoryProvider);
    final roles = await repository.roles();
    if (!context.mounted || roles.isEmpty) return;
    var selected = roles.first;
    Set<String> selectedPermissions() =>
        (jsonDecode(selected.permissionsJson) as List<dynamic>)
            .cast<String>()
            .toSet();
    var permissions = selectedPermissions();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isOwner = selected.name == 'Owner';
          final allPermissions = Permissions.all.toList()..sort();
          return AlertDialog(
            title: const Text('Role permissions'),
            content: SizedBox(
              width: 680,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected.id,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: roles
                        .map(
                          (role) => DropdownMenuItem(
                            value: role.id,
                            child: Text(role.name),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      setDialogState(() {
                        selected = roles.firstWhere((role) => role.id == id);
                        permissions = selectedPermissions();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (isOwner)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'The Owner role always has every permission.',
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: allPermissions.length,
                      itemBuilder: (context, index) {
                        final permission = allPermissions[index];
                        return CheckboxListTile(
                          dense: true,
                          value: isOwner || permissions.contains(permission),
                          onChanged: isOwner
                              ? null
                              : (enabled) => setDialogState(() {
                                  if (enabled == true) {
                                    permissions.add(permission);
                                  } else {
                                    permissions.remove(permission);
                                  }
                                }),
                          title: Text(permission),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isOwner ? null : () => Navigator.pop(context, true),
                child: const Text('Save permissions'),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true) {
      await repository.updateRolePermissions(
        ref.read(activeSessionProvider)!,
        selected,
        permissions,
      );
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    UserWithRole? item,
  }) async {
    final repository = ref.read(userRepositoryProvider);
    final roles = await repository.roles();
    final stores = await ref.read(storeRepositoryProvider).watchAll().first;
    if (!context.mounted) return;
    final username = TextEditingController(text: item?.user.username ?? '');
    final name = TextEditingController(text: item?.user.displayName ?? '');
    final password = TextEditingController();
    String? roleId = item?.role.id ?? roles.firstOrNull?.id;
    String? storeId = item?.user.storeId;
    var active = item?.user.isActive ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item == null ? 'New user' : 'Edit user'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: username,
                  enabled: item == null,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: item == null
                        ? 'Password'
                        : 'New password (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: roleId,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: roles
                      .map(
                        (role) => DropdownMenuItem(
                          value: role.id,
                          child: Text(role.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => roleId = value,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: storeId,
                  decoration: const InputDecoration(labelText: 'Store scope'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All stores'),
                    ),
                    ...stores.map(
                      (store) => DropdownMenuItem(
                        value: store.id,
                        child: Text(store.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => storeId = value,
                ),
                if (item != null)
                  SwitchListTile(
                    value: active,
                    onChanged: (value) => setDialogState(() => active = value),
                    title: const Text('Active'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || roleId == null) return;
    final session = ref.read(activeSessionProvider)!;
    if (item == null) {
      await repository.create(
        session: session,
        username: username.text,
        displayName: name.text,
        password: password.text,
        roleId: roleId!,
        storeId: storeId,
      );
    } else {
      await repository.update(
        session: session,
        user: item.user,
        displayName: name.text,
        roleId: roleId!,
        storeId: storeId,
        isActive: active,
        newPassword: password.text,
      );
    }
  }
}
