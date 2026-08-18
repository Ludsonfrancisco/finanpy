import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../app/adaptive_shell.dart';
import '../../../core/sync/sync_state.dart';
import '../../../design_system/components/sync_status.dart';
import '../../../design_system/lar_spacing.dart';
import '../../transactions/domain/transactions_models.dart';
import '../application/categories_controller.dart';
import '../domain/categories_models.dart';
import 'widgets/category_card.dart';
import 'widgets/category_form_sheet.dart';

final class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({required this.controller, super.key});

  final CategoriesController controller;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

final class _CategoriesScreenState extends State<CategoriesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    unawaited(widget.controller.start());
  }

  @override
  void didUpdateWidget(CategoriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
      unawaited(widget.controller.start());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state;
    final snapshot = state.snapshot;
    final desktop = MediaQuery.sizeOf(context).width >= LarBreakpoints.desktop;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;

    final syncData = SyncStatusData(
      state: _syncVisualState(controller.syncPhase),
      lastSuccessAt: snapshot?.lastSyncedAt ?? controller.syncTimestamp,
    );

    final selectedType = state.filters.type;

    final body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? LarSpacing.xxl : LarSpacing.lg,
            vertical: desktop ? LarSpacing.xxl : LarSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Header
              Row(
                children: <Widget>[
                  Expanded(child: SyncStatusView(data: syncData)),
                  const SizedBox(width: LarSpacing.sm),
                  FilledButton.icon(
                    key: const Key('categories-header-new-button'),
                    onPressed: () => CategoryFormSheet.show(
                      context,
                      repository: widget.controller.repository,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nova Categoria'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LarSpacing.xl),

              // Barra de Busca e Filtros
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Buscar categorias...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  controller.setSearchQuery('');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (val) => controller.setSearchQuery(val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LarSpacing.md),

              // Segmented Button para Tipo (Todas / Despesas / Receitas)
              SegmentedButton<TransactionType?>(
                segments: const [
                  ButtonSegment<TransactionType?>(
                    value: null,
                    label: Text('Todas'),
                  ),
                  ButtonSegment<TransactionType?>(
                    value: TransactionType.expense,
                    label: Text('Despesas'),
                  ),
                  ButtonSegment<TransactionType?>(
                    value: TransactionType.income,
                    label: Text('Receitas'),
                  ),
                ],
                selected: {selectedType},
                onSelectionChanged: (set) =>
                    controller.setTypeFilter(set.first),
              ),
              const SizedBox(height: LarSpacing.xl),

              // Conteúdo
              if (state.isLoading && snapshot == null)
                const _CategoriesLoadingState()
              else if (snapshot == null || snapshot.isEmpty)
                _CategoriesEmptyState(
                  hasFilter: state.filters.hasActiveFilters,
                  onClearFilters: () {
                    _searchController.clear();
                    controller.updateFilters(const CategoryFilters());
                  },
                  onNewCategory: () => CategoryFormSheet.show(
                    context,
                    repository: widget.controller.repository,
                  ),
                )
              else
                _CategoriesList(
                  snapshot: snapshot,
                  desktop: desktop,
                  onEditCategory: (cat) => CategoryFormSheet.show(
                    context,
                    repository: widget.controller.repository,
                    initialItem: cat,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final fab = FloatingActionButton.extended(
      key: const Key('categories-new-button'),
      onPressed: () => CategoryFormSheet.show(
        context,
        repository: widget.controller.repository,
      ),
      icon: const Icon(Icons.add),
      label: const Text('Nova Categoria'),
    );

    if (ios) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: fab,
        body: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: <Widget>[
              CupertinoSliverRefreshControl(onRefresh: controller.retrySync),
              SliverToBoxAdapter(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: fab,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.retrySync,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: body,
          ),
        ),
      ),
    );
  }
}

SyncVisualState _syncVisualState(SyncPhase phase) => switch (phase) {
  SyncPhase.current => SyncVisualState.current,
  SyncPhase.syncing => SyncVisualState.syncing,
  SyncPhase.failed => SyncVisualState.failed,
  SyncPhase.idle || SyncPhase.offline => SyncVisualState.offline,
};

final class _CategoriesLoadingState extends StatelessWidget {
  const _CategoriesLoadingState();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Carregando categorias',
    child: Column(
      key: const Key('categories-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Carregando categorias locais',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: LarSpacing.md),
        const LinearProgressIndicator(),
      ],
    ),
  );
}

final class _CategoriesEmptyState extends StatelessWidget {
  const _CategoriesEmptyState({
    required this.hasFilter,
    required this.onClearFilters,
    required this.onNewCategory,
  });

  final bool hasFilter;
  final VoidCallback onClearFilters;
  final VoidCallback onNewCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    return Semantics(
      container: true,
      label: hasFilter
          ? 'Nenhuma categoria com os filtros aplicados'
          : 'Nenhuma categoria cadastrada',
      child: Container(
        key: const Key('categories-empty-state'),
        padding: const EdgeInsets.all(LarSpacing.xxl),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.category_outlined,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: LarSpacing.md),
            Text(
              hasFilter
                  ? 'Nenhuma categoria encontrada'
                  : 'Nenhuma categoria cadastrada',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: LarSpacing.xs),
            Text(
              hasFilter
                  ? 'Tente ajustar os filtros ou a busca para localizar a categoria desejada.'
                  : 'Crie categorias para classificar suas despesas e receitas.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: LarSpacing.lg),
            if (hasFilter)
              OutlinedButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Limpar filtros'),
              )
            else
              FilledButton.icon(
                onPressed: onNewCategory,
                icon: const Icon(Icons.add),
                label: const Text('Criar Categoria'),
              ),
          ],
        ),
      ),
    );
  }
}

final class _CategoriesList extends StatelessWidget {
  const _CategoriesList({
    required this.snapshot,
    required this.desktop,
    required this.onEditCategory,
  });

  final CategoriesSnapshot snapshot;
  final bool desktop;
  final void Function(CategoryItem) onEditCategory;

  @override
  Widget build(BuildContext context) {
    final categories = snapshot.categories;

    if (desktop) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: LarSpacing.md,
          mainAxisSpacing: LarSpacing.md,
          mainAxisExtent: 82,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          return CategoryCard(category: cat, onTap: () => onEditCategory(cat));
        },
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: LarSpacing.sm),
      itemBuilder: (context, index) {
        final cat = categories[index];
        return CategoryCard(category: cat, onTap: () => onEditCategory(cat));
      },
    );
  }
}
