import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui_kit.dart';

import '../../../core/database/app_database.dart';
import '../../auth/application/session_controller.dart';
import '../data/store_repository.dart';

class StoresPage extends ConsumerWidget {
  const StoresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(storeRepositoryProvider);
    final session = ref.watch(activeSessionProvider)!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Stores',
            subtitle: 'Branches are deactivated instead of deleted.',
            actions: [
              FilledButton.icon(
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.add_business_rounded),
                label: const Text('New store'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Card(
              child: CachedStreamBuilder(
                create: repository.watchAll,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final stores = snapshot.data!;
                  return ListView.separated(
                    itemCount: stores.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final store = stores[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 7,
                        ),
                        leading: CircleAvatar(
                          child: Text(store.code.characters.take(2).toString()),
                        ),
                        title: Text(
                          store.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            store.code,
                            store.address,
                            store.phone,
                          ].where((value) => value.isNotEmpty).join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (store.id == session.store.id)
                              const Chip(label: Text('Current')),
                            const SizedBox(width: 8),
                            Chip(
                              label: Text(
                                store.isActive ? 'Active' : 'Inactive',
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _edit(context, ref, store: store),
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

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    Store? store,
  }) async {
    final name = TextEditingController(text: store?.name ?? '');
    final code = TextEditingController(text: store?.code ?? '');
    final address = TextEditingController(text: store?.address ?? '');
    final phone = TextEditingController(text: store?.phone ?? '');
    var active = store?.isActive ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(store == null ? 'New store' : 'Edit store'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Store name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Code'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                if (store != null)
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
    if (saved != true || !context.mounted) return;
    final session = ref.read(activeSessionProvider)!;
    if (store == null) {
      await ref
          .read(storeRepositoryProvider)
          .create(
            session: session,
            name: name.text,
            code: code.text,
            address: address.text,
            phone: phone.text,
          );
    } else {
      await ref
          .read(storeRepositoryProvider)
          .updateStore(
            session: session,
            store: store,
            name: name.text,
            code: code.text,
            address: address.text,
            phone: phone.text,
            isActive: active,
          );
    }
  }
}
