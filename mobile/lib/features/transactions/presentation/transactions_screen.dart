import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../app/adaptive_shell.dart';
import '../../../app/value_visibility_controller.dart';
import '../../../core/sync/sync_state.dart';
import '../../../design_system/components/financial_amount.dart';
import '../../../design_system/components/owner_selector.dart';
import '../../../design_system/components/sync_status.dart';
import '../../../design_system/lar_colors.dart';
import '../../../design_system/lar_spacing.dart';
import '../application/transactions_controller.dart';
import '../domain/transactions_models.dart';
import 'widgets/transaction_detail_sheet.dart';
import 'widgets/transaction_filter_sheet.dart';
import 'widgets/transaction_form_sheet.dart';
import 'widgets/transaction_group_header.dart';
import 'widgets/transaction_list_item.dart';
import 'widgets/transactions_search_bar.dart';

final class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    required this.controller,
    this.visibilityController,
    this.onOpenImport,
    super.key,
  });

  final TransactionsController controller;
  final ValueVisibilityController? visibilityController;
  final VoidCallback? onOpenImport;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

final class _TransactionsScreenState extends State<TransactionsScreen> {
  bool _valuesHidden = false;
  final FocusNode _privacyFocusNode = FocusNode(
    debugLabel: 'transactions-privacy-toggle',
  );
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.controller.state.filters.searchQuery,
    );
    widget.controller.addListener(_refresh);
    widget.visibilityController?.addListener(_refresh);
    unawaited(widget.controller.start());
  }

  @override
  void didUpdateWidget(TransactionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
      unawaited(widget.controller.start());
    }
    if (oldWidget.visibilityController != widget.visibilityController) {
      oldWidget.visibilityController?.removeListener(_refresh);
      widget.visibilityController?.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    widget.controller.removeListener(_refresh);
    widget.visibilityController?.removeListener(_refresh);
    _privacyFocusNode.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      final currentFilterQuery = widget.controller.state.filters.searchQuery;
      if (_searchController.text != currentFilterQuery) {
        _searchController.text = currentFilterQuery;
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state;
    final snapshot = state.snapshot;
    final desktop = MediaQuery.sizeOf(context).width >= LarBreakpoints.desktop;
    final syncData = SyncStatusData(
      state: _syncVisualState(controller.syncPhase),
      lastSuccessAt: snapshot?.lastSyncedAt ?? controller.syncTimestamp,
    );
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final hidden = widget.visibilityController?.hidden ?? _valuesHidden;

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
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: Row(
                  children: <Widget>[
                    Expanded(child: SyncStatusView(data: syncData)),
                    const SizedBox(width: LarSpacing.sm),
                    FilledButton.icon(
                      key: const Key('transactions-header-new-button'),
                      onPressed: () => TransactionFormSheet.show(
                        context,
                        repository: widget.controller.repository,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Novo'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: LarSpacing.xs),
                    IconButton(
                      key: const Key('transactions-privacy-toggle'),
                      focusNode: _privacyFocusNode,
                      tooltip: hidden ? 'Mostrar valores' : 'Ocultar valores',
                      onPressed: () => unawaited(_toggleValues()),
                      icon: Icon(
                        hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LarSpacing.xl),
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: OwnerSelector(
                  key: const Key('transactions-owner-selector'),
                  selected: state.selectedScopeIndex,
                  onSelected: controller.select,
                ),
              ),
              const SizedBox(height: LarSpacing.lg),
              TransactionsSearchBar(
                searchController: _searchController,
                onChanged: controller.updateSearch,
                onClear: () {
                  _searchController.clear();
                  controller.updateSearch('');
                },
                onOpenFilters: () => _openFilterSheet(snapshot),
                hasActiveFilters: state.filters.hasActiveFilters,
              ),
              const SizedBox(height: LarSpacing.xl),
              if (state.isLoading && snapshot == null)
                const _TransactionsLoadingState()
              else if (snapshot == null || snapshot.isEmpty)
                state.filters.hasActiveFilters
                    ? _TransactionsFilteredEmptyState(
                        onClear: controller.clearFilters,
                      )
                    : _TransactionsEmptyState(
                        onOpenImport: widget.onOpenImport,
                        onNewTransaction: () => TransactionFormSheet.show(
                          context,
                          repository: widget.controller.repository,
                        ),
                      )
              else
                _TransactionsContent(
                  snapshot: snapshot,
                  hidden: hidden,
                  onItemTap: (item) => TransactionDetailSheet.show(
                    context,
                    item: item,
                    hidden: hidden,
                    repository: widget.controller.repository,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final fab = FloatingActionButton.extended(
      key: const Key('transactions-new-button'),
      onPressed: () => TransactionFormSheet.show(
        context,
        repository: widget.controller.repository,
      ),
      icon: const Icon(Icons.add),
      label: const Text('Novo Lançamento'),
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

  void _openFilterSheet(TransactionsSnapshot? snapshot) {
    TransactionFilterSheet.show(
      context,
      initialFilters: widget.controller.state.filters,
      availableAccounts: snapshot?.availableAccounts ?? const [],
      availableCategories: snapshot?.availableCategories ?? const [],
      onApply: widget.controller.updateFilters,
    );
  }

  Future<void> _toggleValues() async {
    final visibility = widget.visibilityController;
    if (visibility == null) {
      setState(() => _valuesHidden = !_valuesHidden);
      return;
    }
    try {
      await visibility.toggle();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar a privacidade'),
        ),
      );
    }
  }
}

final class _TransactionsLoadingState extends StatelessWidget {
  const _TransactionsLoadingState();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Carregando movimentações',
    child: Column(
      key: const Key('transactions-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Carregando extrato local',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: LarSpacing.md),
        const LinearProgressIndicator(),
      ],
    ),
  );
}

final class _TransactionsEmptyState extends StatelessWidget {
  const _TransactionsEmptyState({this.onOpenImport, this.onNewTransaction});

  final VoidCallback? onOpenImport;
  final VoidCallback? onNewTransaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    return Semantics(
      container: true,
      label: 'Nenhuma movimentação registrada',
      child: Container(
        key: const Key('transactions-empty-state'),
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
              Icons.receipt_long_outlined,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: LarSpacing.md),
            Text(
              'Nenhuma movimentação encontrada',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: LarSpacing.xs),
            Text(
              'Crie um lançamento manual ou importe extratos OFX para gerenciar seu extrato financeiro.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: LarSpacing.lg),
            Wrap(
              spacing: LarSpacing.md,
              runSpacing: LarSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                if (onNewTransaction != null)
                  FilledButton.icon(
                    onPressed: onNewTransaction,
                    icon: const Icon(Icons.add),
                    label: const Text('Novo lançamento'),
                  ),
                if (onOpenImport != null)
                  OutlinedButton.icon(
                    onPressed: onOpenImport,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Importar extrato OFX'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _TransactionsFilteredEmptyState extends StatelessWidget {
  const _TransactionsFilteredEmptyState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    return Container(
      key: const Key('transactions-filtered-empty-state'),
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
            Icons.filter_alt_off_outlined,
            size: 44,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: LarSpacing.md),
          Text(
            'Nenhum resultado para os filtros atuais',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: LarSpacing.xs),
          Text(
            'Tente alterar os termos de busca ou limpar os filtros aplicados.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: LarSpacing.lg),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.clear_all),
            label: const Text('Limpar filtros'),
          ),
        ],
      ),
    );
  }
}

final class _TransactionsContent extends StatelessWidget {
  const _TransactionsContent({
    required this.snapshot,
    required this.hidden,
    required this.onItemTap,
  });

  final TransactionsSnapshot snapshot;
  final bool hidden;
  final ValueChanged<TransactionItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final netPeriod = snapshot.totalIncomeMinor - snapshot.totalExpenseMinor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Summary Header Card
        Container(
          padding: const EdgeInsets.all(LarSpacing.lg),
          decoration: BoxDecoration(
            color: isDark ? LarColors.darkSurface : LarColors.lightSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _SummaryColumn(
                label: 'RECEITAS',
                amountMinor: snapshot.totalIncomeMinor,
                hidden: hidden,
                color: isDark ? LarColors.mineralOnDark : LarColors.mineral,
              ),
              Container(
                height: 36,
                width: 1,
                color: isDark ? Colors.white10 : Colors.black12,
              ),
              _SummaryColumn(
                label: 'DESPESAS',
                amountMinor: snapshot.totalExpenseMinor,
                hidden: hidden,
                color: isDark ? const Color(0xFFF28B82) : LarColors.danger,
              ),
              Container(
                height: 36,
                width: 1,
                color: isDark ? Colors.white10 : Colors.black12,
              ),
              _SummaryColumn(
                label: 'BALANÇO',
                amountMinor: netPeriod,
                hidden: hidden,
                showPositiveSign: true,
                color: netPeriod < 0
                    ? LarColors.danger
                    : (isDark ? LarColors.mineralOnDark : LarColors.mineral),
              ),
            ],
          ),
        ),
        const SizedBox(height: LarSpacing.lg),
        Text(
          '${snapshot.totalCount} ${snapshot.totalCount == 1 ? 'lançamento' : 'lançamentos'}',
          style: text.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: LarSpacing.sm),
        // Groups list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.groups.length,
          itemBuilder: (context, groupIndex) {
            final group = snapshot.groups[groupIndex];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TransactionGroupHeader(group: group, hidden: hidden),
                Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? LarColors.darkSurface
                        : LarColors.lightSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: group.transactions.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 64,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                    itemBuilder: (context, itemIndex) => TransactionListItem(
                      item: group.transactions[itemIndex],
                      hidden: hidden,
                      onTap: () => onItemTap(group.transactions[itemIndex]),
                    ),
                  ),
                ),
                const SizedBox(height: LarSpacing.md),
              ],
            );
          },
        ),
      ],
    );
  }
}

final class _SummaryColumn extends StatelessWidget {
  const _SummaryColumn({
    required this.label,
    required this.amountMinor,
    required this.hidden,
    required this.color,
    this.showPositiveSign = false,
  });

  final String label;
  final int amountMinor;
  final bool hidden;
  final Color color;
  final bool showPositiveSign;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        Text(
          label,
          style: text.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        FinancialAmount(
          minorUnits: amountMinor,
          hidden: hidden,
          showPositiveSign: showPositiveSign,
          style: text.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

SyncVisualState _syncVisualState(SyncPhase phase) => switch (phase) {
  SyncPhase.current => SyncVisualState.current,
  SyncPhase.syncing => SyncVisualState.syncing,
  SyncPhase.failed => SyncVisualState.failed,
  SyncPhase.idle || SyncPhase.offline => SyncVisualState.offline,
};
