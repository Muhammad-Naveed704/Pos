import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../../stores/data/store_repository.dart';
import '../data/user_repository.dart';
import 'roles_tab.dart';

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider)!;
    final canManage = session.can(Permissions.usersManage);
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Users & roles',
              subtitle:
                  'Local accounts, store access and what each role can do.',
              actions: [
                if (canManage)
                  FilledButton.icon(
                    onPressed: () => showUserEditor(context, ref),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('New user'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                AppTab(icon: Icons.people_alt_outlined, text: 'Users'),
                AppTab(
                  icon: Icons.admin_panel_settings_outlined,
                  text: 'Roles & permissions',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                children: [
                  _UsersList(canManage: canManage),
                  const RolesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsersList extends ConsumerStatefulWidget {
  const _UsersList({required this.canManage});
  final bool canManage;

  @override
  ConsumerState<_UsersList> createState() => _UsersListState();
}

IconData roleIcon(String role) => switch (role.toLowerCase()) {
  'owner' => Icons.workspace_premium_rounded,
  'admin' => Icons.admin_panel_settings_outlined,
  'manager' => Icons.insights_rounded,
  'cashier' => Icons.point_of_sale_rounded,
  'inventory staff' => Icons.inventory_2_outlined,
  _ => Icons.badge_outlined,
};

class _UsersListState extends ConsumerState<_UsersList> {
  String _search = '';
  String? _role;
  bool? _active;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider)!;
    return CachedStreamBuilder<List<UserWithRole>>(
      keys: [session.user.id, session.store.id],
      create: () => ref.read(userRepositoryProvider).watchAll(session),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Users could not be loaded',
              message: friendlyError(snapshot.error!),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final roles = {for (final u in all) u.role.name}.toList()..sort();
        final term = _search.trim().toLowerCase();
        final users = all.where((u) {
          if (_role != null && u.role.name != _role) return false;
          if (_active != null && u.user.isActive != _active) return false;
          if (term.isEmpty) return true;
          return u.user.displayName.toLowerCase().contains(term) ||
              u.user.username.toLowerCase().contains(term) ||
              u.role.name.toLowerCase().contains(term);
        }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Row(
              children: [
                SearchField(
                  width: 360,
                  hint: 'Search users by name, username or role',
                  onChanged: (value) => setState(() => _search = value),
                ),
                const Spacer(),
                AppSelect<String?>(
                  width: 190,
                  label: 'Role',
                  items: [
                    const SelectItem(null, 'All roles'),
                    for (final role in roles)
                      SelectItem(role, role, icon: roleIcon(role)),
                  ],
                  value: _role,
                  onChanged: (value) => setState(() => _role = value),
                ),
                const SizedBox(width: 10),
                AppSelect<bool?>(
                  width: 170,
                  label: 'Status',
                  items: const [
                    SelectItem(null, 'All status'),
                    SelectItem(true, 'Active'),
                    SelectItem(false, 'Inactive'),
                  ],
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: AppTable(
                columns: const [
                  AppColumn('User', flex: 4),
                  AppColumn('Role', flex: 3),
                  AppColumn('Status', flex: 2),
                  AppColumn('Last sign-in', flex: 3),
                  AppColumn('Actions', width: 110, center: true),
                ],
                rowCount: users.length,
                rowHeight: 72,
                onTap: widget.canManage
                    ? (index) =>
                          showUserEditor(context, ref, item: users[index])
                    : null,
                empty: const EmptyState(
                  compact: true,
                  icon: Icons.person_search_rounded,
                  title: 'No users match these filters',
                ),
                footer: Text(
                  'Showing ${users.length} of ${all.length} users',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                cells: (context, index) {
                  final item = users[index];
                  final user = item.user;
                  return [
                    Row(
                      children: [
                        NameAvatar(user.displayName),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      user.displayName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (user.id == session.user.id) ...[
                                    const SizedBox(width: 8),
                                    const StatusPill(
                                      'You',
                                      tone: PillTone.primary,
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                '@${user.username}',
                                style: context.text.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.primaryContainer.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            roleIcon(item.role.name),
                            size: 16,
                            color: context.colors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item.role.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: context.colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    user.isActive
                        ? const StatusPill(
                            'Active',
                            tone: PillTone.success,
                            icon: Icons.circle,
                          )
                        : const StatusPill('Inactive', icon: Icons.circle),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.lastLoginAt == null
                              ? 'Never'
                              : DateFormat('d MMM y, h:mm a')
                                    .format(user.lastLoginAt!),
                        ),
                        Text(
                          'Last sign-in',
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    widget.canManage
                        ? IconButton.outlined(
                            tooltip: 'Edit / reset password',
                            onPressed: () =>
                                showUserEditor(context, ref, item: item),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          )
                        : const SizedBox.shrink(),
                  ];
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> showUserEditor(
  BuildContext context,
  WidgetRef ref, {
  UserWithRole? item,
}) async {
  final roles = await ref.read(userRepositoryProvider).roles();
  final stores = await ref.read(storeRepositoryProvider).watchAll().first;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _UserEditor(item: item, roles: roles, stores: stores),
  );
}

class _UserEditor extends ConsumerStatefulWidget {
  const _UserEditor({
    required this.item,
    required this.roles,
    required this.stores,
  });
  final UserWithRole? item;
  final List<Role> roles;
  final List<Store> stores;

  @override
  ConsumerState<_UserEditor> createState() => _UserEditorState();
}

class _UserEditorState extends ConsumerState<_UserEditor> {
  late final _username = TextEditingController(
    text: widget.item?.user.username ?? '',
  );
  late final _name = TextEditingController(
    text: widget.item?.user.displayName ?? '',
  );
  final _password = TextEditingController();
  late String? _roleId =
      widget.item?.role.id ??
      widget.roles.where((role) => role.name == 'Cashier').firstOrNull?.id ??
      widget.roles.firstOrNull?.id;
  late String? _storeId = widget.item?.user.storeId;
  late bool _active = widget.item?.user.isActive ?? true;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final creating = widget.item == null;
    if (_name.text.trim().isEmpty ||
        (creating && _username.text.trim().isEmpty)) {
      setState(() => _error = 'Name and username are required.');
      return;
    }
    if ((creating || _password.text.isNotEmpty) && _password.text.length < 8) {
      setState(() => _error = 'Password must have at least 8 characters.');
      return;
    }
    if (_roleId == null) {
      setState(() => _error = 'Choose a role.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(userRepositoryProvider);
      final session = ref.read(activeSessionProvider)!;
      if (creating) {
        await repository.create(
          session: session,
          username: _username.text,
          displayName: _name.text,
          password: _password.text,
          roleId: _roleId!,
          storeId: _storeId,
        );
      } else {
        await repository.update(
          session: session,
          user: widget.item!.user,
          displayName: _name.text,
          roleId: _roleId!,
          storeId: _storeId,
          isActive: _active,
          newPassword: _password.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      Toast.success(
        context,
        creating
            ? 'User @${_username.text.trim().toLowerCase()} created.'
            : 'User updated. Changes apply at their next sign-in.',
      );
    } catch (error) {
      final text = friendlyError(error);
      if (mounted) {
        setState(
          () => _error = text.contains('UNIQUE')
              ? 'That username is already taken.'
              : text,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return AlertDialog(
      title: Text(editing ? 'Edit user' : 'New user'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Display name',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              enabled: !editing,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: editing ? 'New password (optional)' : 'Password',
                helperText: editing
                    ? 'Fill in only to reset this user’s password.'
                    : 'At least 8 characters.',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppSelect<String>(
                    items: [
                      for (final role in widget.roles)
                        SelectItem(role.id, role.name),
                    ],
                    value: _roleId,
                    onChanged: (value) => setState(() => _roleId = value),
                    label: 'Role',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppSelect<String?>(
                    items: [
                      SelectItem(null, 'All stores'),
                      for (final store in widget.stores)
                        SelectItem(store.id, store.name),
                    ],
                    value: _storeId,
                    onChanged: (value) => setState(() => _storeId = value),
                    label: 'Store access',
                  ),
                ),
              ],
            ),
            if (editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Active'),
                subtitle: const Text('Inactive users cannot sign in.'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: context.colors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
