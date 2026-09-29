import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui_kit.dart';

import '../../../core/database/app_database.dart';
import '../../auth/application/session_controller.dart';
import '../data/category_repository.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});
  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(categoryRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Categories',
            subtitle: 'Group products for faster browsing at the counter.',
            actions: [
              FilledButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New category'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search categories',
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Card(
              child: StreamBuilder<List<Category>>(
                stream: repository.watch(search: _search),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final categories = snapshot.data!;
                  if (categories.isEmpty) {
                    return const Center(child: Text('No categories found.'));
                  }
                  return ListView.separated(
                    itemCount: categories.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = categories[index];
                      final parent = categories
                          .where((value) => value.id == item.parentId)
                          .firstOrNull;
                      return ListTile(
                        leading: const Icon(Icons.category_outlined),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${item.code}${parent == null ? '' : ' · under ${parent.name}'} · order ${item.sortOrder}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text(
                                item.isActive ? 'Active' : 'Inactive',
                              ),
                            ),
                            IconButton(
                              onPressed: () => _edit(
                                context,
                                category: item,
                                choices: categories,
                              ),
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
    BuildContext context, {
    Category? category,
    List<Category> choices = const [],
  }) async {
    final name = TextEditingController(text: category?.name ?? '');
    final code = TextEditingController(text: category?.code ?? '');
    final sort = TextEditingController(text: '${category?.sortOrder ?? 0}');
    String? parentId = category?.parentId;
    var active = category?.isActive ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(category == null ? 'New category' : 'Edit category'),
          content: SizedBox(
            width: 470,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Code'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: parentId,
                  decoration: const InputDecoration(labelText: 'Parent'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('No parent'),
                    ),
                    ...choices
                        .where((item) => item.id != category?.id)
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        ),
                  ],
                  onChanged: (value) => parentId = value,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sort order'),
                ),
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
    if (saved != true) return;
    await ref
        .read(categoryRepositoryProvider)
        .save(
          session: ref.read(activeSessionProvider)!,
          id: category?.id,
          name: name.text,
          code: code.text,
          parentId: parentId,
          isActive: active,
          sortOrder: int.tryParse(sort.text) ?? 0,
        );
  }
}
