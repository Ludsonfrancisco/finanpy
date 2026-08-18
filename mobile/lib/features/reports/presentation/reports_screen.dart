import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../app/adaptive_shell.dart';
import '../../../core/sync/sync_state.dart';
import '../../../design_system/components/sync_status.dart';
import '../../../design_system/lar_spacing.dart';
import '../application/reports_controller.dart';
import '../domain/reports_models.dart';
import 'widgets/category_distribution_list.dart';
import 'widgets/donut_chart.dart';
import 'widgets/monthly_bar_chart.dart';
import 'widgets/reports_metrics_card.dart';

final class ReportsScreen extends StatefulWidget {
  const ReportsScreen({required this.controller, super.key});

  final ReportsController controller;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

final class _ReportsScreenState extends State<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    unawaited(widget.controller.start());
  }

  @override
  void didUpdateWidget(ReportsScreen oldWidget) {
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
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state;
    final summary = state.summary;
    final desktop = MediaQuery.sizeOf(context).width >= LarBreakpoints.desktop;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;

    final syncData = SyncStatusData(
      state: _syncVisualState(controller.syncPhase),
      lastSuccessAt: summary?.lastSyncedAt ?? controller.syncTimestamp,
    );

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
              // Header com SyncStatus
              Row(
                children: <Widget>[
                  Expanded(child: SyncStatusView(data: syncData)),
                ],
              ),
              const SizedBox(height: LarSpacing.lg),

              // Seletor de Titular Contábil (Lar / Eu / Esposa)
              if (state.ownerScopes != null) ...[
                _OwnerSelector(
                  selectedIndex: state.selectedScopeIndex,
                  onSelect: (idx) => controller.selectScope(idx),
                ),
                const SizedBox(height: LarSpacing.md),
              ],

              // Seletor de Período
              _PeriodSelector(
                selectedPeriod: state.selectedPeriod,
                onSelect: (period) => controller.selectPeriod(period),
              ),
              const SizedBox(height: LarSpacing.xl),

              // Conteúdo Analítico
              if (state.isLoading && summary == null)
                const _ReportsLoadingState()
              else if (summary == null || !summary.hasData)
                const _ReportsEmptyState()
              else
                _ReportsContent(summary: summary, desktop: desktop),
            ],
          ),
        ),
      ),
    );

    if (ios) {
      return Scaffold(
        backgroundColor: Colors.transparent,
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

final class _OwnerSelector extends StatelessWidget {
  const _OwnerSelector({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment<int>(value: 0, label: Text('Lar')),
        ButtonSegment<int>(value: 1, label: Text('Eu')),
        ButtonSegment<int>(value: 2, label: Text('Esposa')),
      ],
      selected: {selectedIndex},
      onSelectionChanged: (set) => onSelect(set.first),
    );
  }
}

final class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selectedPeriod, required this.onSelect});

  final ReportPeriod selectedPeriod;
  final void Function(ReportPeriod) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ReportPeriod.values.map((p) {
          final isSelected = p == selectedPeriod;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(p.label),
              selected: isSelected,
              onSelected: (_) => onSelect(p),
            ),
          );
        }).toList(),
      ),
    );
  }
}

final class _ReportsContent extends StatelessWidget {
  const _ReportsContent({required this.summary, required this.desktop});

  final ReportsSummary summary;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final donutCard = Container(
      padding: const EdgeInsets.all(LarSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2621) : const Color(0xFFF9F7F3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF31403A) : const Color(0xFFCBC5B9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Distribuição de Gastos',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: LarSpacing.md),
          DonutChartWidget(
            distributions: summary.categoryDistributions,
            totalExpenseMinor: summary.totalExpenseMinor,
          ),
        ],
      ),
    );

    final monthlyCard = Container(
      padding: const EdgeInsets.all(LarSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2621) : const Color(0xFFF9F7F3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF31403A) : const Color(0xFFCBC5B9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fluxo Mensal (6 Meses)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: LarSpacing.md),
          MonthlyBarChartWidget(monthlyFlows: summary.monthlyFlows),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Métricas Consolidadas
        ReportsMetricsCard(summary: summary),
        const SizedBox(height: LarSpacing.xl),

        // Gráficos (lado a lado no desktop, empilhados no mobile)
        if (desktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: donutCard),
              const SizedBox(width: LarSpacing.lg),
              Expanded(child: monthlyCard),
            ],
          )
        else ...[
          donutCard,
          const SizedBox(height: LarSpacing.lg),
          monthlyCard,
        ],
        const SizedBox(height: LarSpacing.xl),

        // Lista de Distribuição
        CategoryDistributionListWidget(
          distributions: summary.categoryDistributions,
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

final class _ReportsLoadingState extends StatelessWidget {
  const _ReportsLoadingState();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Calculando relatórios',
    child: Column(
      key: const Key('reports-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Calculando relatórios contábeis',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: LarSpacing.md),
        const LinearProgressIndicator(),
      ],
    ),
  );
}

final class _ReportsEmptyState extends StatelessWidget {
  const _ReportsEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    return Container(
      key: const Key('reports-empty-state'),
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
            Icons.pie_chart_outline,
            size: 48,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: LarSpacing.md),
          Text(
            'Sem dados no período selecionado',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: LarSpacing.xs),
          Text(
            'Adicione movimentações ou selecione outro período para visualizar os gráficos analíticos.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
