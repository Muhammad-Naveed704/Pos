import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/ui/ui_kit.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/permissions.dart';
import '../data/category_repository.dart';

/// Active products per category id.
final _productCountsProvider = StreamProvider.autoDispose<Map<String, int>>((
  ref,
) {
  final database = ref.watch(databaseProvider);
  return database
      .customSelect(
        'SELECT category_id, COUNT(*) AS n FROM products '
        'WHERE category_id IS NOT NULL AND is_active = 1 GROUP BY category_id',
        readsFrom: {database.products},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            row.read<String>('category_id'): row.read<int>('n'),
        },
      );
});

/// Categories (main groups such as Grocery) and their sub-categories (Rice,
/// Oil). Main categories are listed on the left; the selected one's
/// sub-categories on the right.
class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});
  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  String _search = '';
  String? _selectedId;

  Future<void> _editor({
    required List<Category> all,
    Category? category,
    bool sub = false,
    String? parentId,
  }) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryEditor(
        all: all,
        category: category,
        sub: sub || category?.parentId != null,
        initialParentId: parentId ?? category?.parentId,
      ),
    );
    if (id == null || !mounted) return;
    // Select the main category that was created or received a child.
    final saved = await ref
        .read(categoryRepositoryProvider)
        .watch()
        .first
        .then((list) => list.where((c) => c.id == id).firstOrNull);
    if (saved != null && mounted) {
      setState(() => _selectedId = saved.parentId ?? saved.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(categoryRepositoryProvider);
    final session = ref.watch(activeSessionProvider)!;
    final canCreate = session.can(Permissions.productsCreate);
    final canEdit = session.can(Permissions.productsEdit);
    final counts = ref.watch(_productCountsProvider).value ?? const {};
    return Padding(
      padding: const EdgeInsets.all(24),
      child: CachedStreamBuilder<List<Category>>(
        create: repository.watch,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Category>[];
          final mains = all.where((c) => c.parentId == null).toList();
          List<Category> childrenOf(String id) =>
              all.where((c) => c.parentId == id).toList();
          int productsOf(Category main) =>
              (counts[main.id] ?? 0) +
              childrenOf(main.id)
                  .fold(0, (sum, c) => sum + (counts[c.id] ?? 0));
          final term = _search.trim().toLowerCase();
          final visible = term.isEmpty
              ? mains
              : mains
                    .where(
                      (m) =>
                          m.name.toLowerCase().contains(term) ||
                          m.code.toLowerCase().contains(term) ||
                          childrenOf(m.id)
                              .any((c) => c.name.toLowerCase().contains(term)),
                    )
                    .toList();
          final selected =
              visible.where((m) => m.id == _selectedId).firstOrNull ??
              visible.firstOrNull;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Categories',
                subtitle: 'Main categories (e.g. Grocery) and their sub-categories (Rice, Oil).',
                actions: [
                  if (canCreate)
                    OutlinedButton.icon(
                      onPressed: mains.isEmpty
                          ? null
                          : () => _editor(
                              all: all,
                              sub: true,
                              parentId: selected?.id,
                            ),
                      icon: const Icon(Icons.subdirectory_arrow_right_rounded),
                      label: const Text('New sub-category'),
                    ),
                  if (canCreate)
                    FilledButton.icon(
                      onPressed: () => _editor(all: all),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New category'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: snapshot.hasError
                    ? Card(
                        child: EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: 'Categories could not be loaded',
                          message: friendlyError(snapshot.error!),
                        ),
                      )
                    : !snapshot.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : mains.isEmpty
                    ? Card(
                        child: Center(
                          child: _FirstCategory(
                            onCreate: canCreate
                                ? () => _editor(all: all)
                                : null,
                          ),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 330,
                            child: _MainList(
                              mains: visible,
                              selectedId: selected?.id,
                              subCount: (m) => childrenOf(m.id).length,
                              productCount: productsOf,
                              onSearch: (value) =>
                                  setState(() => _search = value),
                              onSelect: (m) =>
                                  setState(() => _selectedId = m.id),
                              onCreate: canCreate
                                  ? () => _editor(all: all)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: selected == null
                                ? const Card(
                                    child: EmptyState(
                                      icon: Icons.search_off_rounded,
                                      title: 'No category matches',
                                    ),
                                  )
                                : _MainDetail(
                                    main: selected,
                                    children: childrenOf(selected.id),
                                    counts: counts,
                                    totalProducts: productsOf(selected),
                                    canCreate: canCreate,
                                    canEdit: canEdit,
                                    onEdit: (c) =>
                                        _editor(all: all, category: c),
                                    onAddChild: () => _editor(
                                      all: all,
                                      sub: true,
                                      parentId: selected.id,
                                    ),
                                  ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MainList extends StatelessWidget {
  const _MainList({
    required this.mains,
    required this.selectedId,
    required this.subCount,
    required this.productCount,
    required this.onSearch,
    required this.onSelect,
    this.onCreate,
  });
  final List<Category> mains;
  final String? selectedId;
  final int Function(Category) subCount;
  final int Function(Category) productCount;
  final ValueChanged<String> onSearch;
  final ValueChanged<Category> onSelect;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: SearchField(hint: 'Search categories', onChanged: onSearch),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
          child: Text(
            'MAIN CATEGORIES · ${mains.length}',
            style: context.text.labelSmall?.copyWith(
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: mains.length,
            itemBuilder: (context, index) {
              final main = mains[index];
              final selected = main.id == selectedId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: ListTile(
                  selected: selected,
                  selectedTileColor: context.colors.primaryContainer.withValues(
                    alpha: 0.7,
                  ),
                  onTap: () => onSelect(main),
                  leading: ProductThumb(name: main.name, size: 38),
                  title: Text(
                    main.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${subCount(main)} sub · ${productCount(main)} products',
                    style: context.text.bodySmall,
                  ),
                  trailing: main.isActive
                      ? const Icon(Icons.chevron_right_rounded)
                      : const StatusPill('Inactive'),
                ),
              );
            },
          ),
        ),
        if (onCreate != null) ...[
          const Divider(height: 1),
          TextButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New category'),
          ),
        ],
      ],
    ),
  );
}

class _MainDetail extends StatelessWidget {
  const _MainDetail({
    required this.main,
    required this.children,
    required this.counts,
    required this.totalProducts,
    required this.canCreate,
    required this.canEdit,
    required this.onEdit,
    required this.onAddChild,
  });
  final Category main;
  final List<Category> children;
  final Map<String, int> counts;
  final int totalProducts;
  final bool canCreate;
  final bool canEdit;
  final ValueChanged<Category> onEdit;
  final VoidCallback onAddChild;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              ProductThumb(name: main.name, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            main.name,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        StatusPill(main.code, tone: PillTone.info),
                        const SizedBox(width: 6),
                        main.isActive
                            ? const StatusPill(
                                'Active',
                                tone: PillTone.success,
                                icon: Icons.circle,
                              )
                            : const StatusPill('Inactive', icon: Icons.circle),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Main category · ${children.length} sub-categor${children.length == 1 ? 'y' : 'ies'} · '
                      '$totalProducts products · sort ${main.sortOrder}',
                      style: TextStyle(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                OutlinedButton.icon(
                  onPressed: () => onEdit(main),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              if (canCreate) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onAddChild,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add sub-category'),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Expanded(
        child: AppTable(
          columns: const [
            AppColumn('Sub-category', flex: 4),
            AppColumn('Code', flex: 2),
            AppColumn('Products', flex: 2, center: true),
            AppColumn('Sort', flex: 1, center: true),
            AppColumn('Status', flex: 2),
            AppColumn('Actions', width: 90, center: true),
          ],
          rowCount: children.length,
          onTap: canEdit ? (index) => onEdit(children[index]) : null,
          empty: EmptyState(
            compact: true,
            icon: Icons.subdirectory_arrow_right_rounded,
            title: 'No sub-categories in ${main.name} yet',
            message: 'Sub-categories make large catalogs easier to browse.',
            action: canCreate
                ? FilledButton.tonalIcon(
                    onPressed: onAddChild,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add sub-category'),
                  )
                : null,
          ),
          footer: Text(
            '${children.length} sub-categor${children.length == 1 ? 'y' : 'ies'} in ${main.name}',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          cells: (context, index) {
            final child = children[index];
            return [
              Row(
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 18,
                    color: context.colors.outline,
                  ),
                  const SizedBox(width: 8),
                  ProductThumb(name: child.name, size: 34),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      child.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              Text(child.code),
              Text(
                '${counts[child.id] ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text('${child.sortOrder}'),
              child.isActive
                  ? const StatusPill(
                      'Active',
                      tone: PillTone.success,
                      icon: Icons.circle,
                    )
                  : const StatusPill('Inactive', icon: Icons.circle),
              canEdit
                  ? IconButton.outlined(
                      tooltip: 'Edit',
                      onPressed: () => onEdit(child),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    )
                  : const SizedBox.shrink(),
            ];
          },
        ),
      ),
    ],
  );
}

class _FirstCategory extends StatelessWidget {
  const _FirstCategory({this.onCreate});
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                primary.withValues(alpha: 0.16),
                primary.withValues(alpha: 0.02),
              ],
            ),
          ),
          child: Icon(Icons.category_rounded, size: 64, color: primary),
        ),
        const SizedBox(height: 18),
        Text(
          'No categories yet',
          style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Create main categories first (e.g. Grocery, Pharmacy), then add '
          'sub-categories inside them.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.onSurfaceVariant),
        ),
        if (onCreate != null) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create first category'),
          ),
        ],
      ],
    );
  }
}

/// Creates or edits a main category ([sub] false) or a sub-category.
/// Pops with the saved id.
class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({
    required this.all,
    this.category,
    this.sub = false,
    this.initialParentId,
  });
  final List<Category> all;
  final Category? category;
  final bool sub;
  final String? initialParentId;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late final _code = TextEditingController(text: widget.category?.code ?? '');
  late final _sort = TextEditingController(
    text: '${widget.category?.sortOrder ?? 0}',
  );
  late String? _parentId = widget.initialParentId;
  late bool _active = widget.category?.isActive ?? true;
  late bool _codeTouched = widget.category != null;
  late final List<Category> _all = [...widget.all];
  bool _busy = false;
  String? _error;

  bool get _editing => widget.category != null;

  List<Category> get _mains => _all
      .where((c) => c.parentId == null && c.id != widget.category?.id)
      .toList();

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _sort.dispose();
    super.dispose();
  }

  /// Suggests a short unique code from the name until the user edits it.
  void _nameChanged(String value) {
    setState(() => _error = null);
    if (_codeTouched) return;
    final base = value
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.length > 4 ? w.substring(0, 4) : w)
        .join('-');
    var code = base.length > 16 ? base.substring(0, 16) : base;
    final used = _all
        .where((c) => c.id != widget.category?.id)
        .map((c) => c.code.toUpperCase())
        .toSet();
    final stem = code;
    for (var n = 2; code.isNotEmpty && used.contains(code); n++) {
      code = '$stem-$n';
    }
    _code.text = code;
  }

  Future<void> _newMain() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryEditor(all: _all),
    );
    if (id == null || !mounted) return;
    final created = await ref
        .read(categoryRepositoryProvider)
        .watch()
        .first
        .then((list) => list.where((c) => c.id == id).firstOrNull);
    if (created == null || !mounted) return;
    setState(() {
      _all.add(created);
      _parentId = id;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (widget.sub && _parentId == null) {
      setState(() => _error = 'Choose the main category.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(categoryRepositoryProvider)
          .save(
            session: ref.read(activeSessionProvider)!,
            id: widget.category?.id,
            name: _name.text,
            code: _code.text,
            parentId: widget.sub ? _parentId : null,
            isActive: _active,
            sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
          );
      if (mounted) Navigator.pop(context, id);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.sub
        ? (_editing ? 'Edit sub-category' : 'New sub-category')
        : (_editing ? 'Edit category' : 'New category');
    final mains = _mains;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      },
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                widget.sub
                    ? Icons.subdirectory_arrow_right_rounded
                    : Icons.category_rounded,
                color: context.colors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  Text(
                    widget.sub
                        ? 'A sub-category sits inside a main category, e.g. Grocery › Rice.'
                        : 'A main category groups products, e.g. Grocery or Pharmacy.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.sub) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppSelect<String?>(
                        label: 'Main category *',
                        icon: Icons.category_outlined,
                        searchable: mains.length > 6,
                        hint: 'Choose where this belongs',
                        items: [
                          for (final main in mains)
                            SelectItem(
                              main.id,
                              main.name,
                              icon: Icons.category_outlined,
                            ),
                        ],
                        value: _parentId,
                        onChanged: (value) => setState(() {
                          _parentId = value;
                          _error = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _newMain,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _name,
                autofocus: !widget.sub || _parentId != null,
                onChanged: _nameChanged,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: widget.sub ? 'Sub-category name *' : 'Name *',
                  hintText: widget.sub ? 'e.g. Rice' : 'e.g. Grocery',
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _code,
                      onChanged: (_) => setState(() {
                        _codeTouched = true;
                        _error = null;
                      }),
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Code *',
                        prefixIcon: Icon(Icons.tag_rounded),
                        helperText: 'Short and unique, filled in for you',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _sort,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Sort order',
                        prefixIcon: Icon(Icons.sort_rounded),
                        helperText: 'Lower shows first',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Material (not a coloured Container) so the tile's ink and
              // background paint correctly.
              Material(
                color: context.colors.surfaceContainerLow,
                borderRadius: context.tokens.borderRadius,
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                  title: const Text('Active'),
                  subtitle: const Text('Shown on the POS and in product forms'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.errorContainer,
                    borderRadius: context.tokens.borderRadius,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: context.colors.onErrorContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: context.colors.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_editing ? 'Save changes' : 'Create'),
          ),
        ],
      ),
    );
  }
}
