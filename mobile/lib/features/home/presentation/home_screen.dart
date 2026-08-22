// THESIS: A posição financeira do Lar é uma leitura contínua, não um mosaico de métricas.
// OWN-WORLD: Grafite esverdeado, marfim, divisores finos, champanhe restrito e verde mineral.
// STORY: O casal confirma freshness, escolhe o responsável, lê posição, compromissos e origem.
// FIRST VIEWPORT: Sync e privacidade precedem o seletor; saldo domina sem card hero genérico.
// FORM: Operate, Casa de Valores code-first, referência aprovada em 13/08/2026.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/adaptive_shell.dart';
import '../../../app/app_lifecycle.dart';
import '../../../app/value_visibility_controller.dart';
import '../../../core/sync/sync_state.dart';
import '../../../design_system/components/owner_selector.dart';
import '../../../design_system/components/sync_status.dart';
import '../../../design_system/lar_spacing.dart';
import '../application/home_controller.dart';
import '../domain/home_snapshot.dart';
import 'widgets/attention_list.dart';
import 'widgets/balance_header.dart';
import 'widgets/commitments_summary.dart';
import 'widgets/recent_transactions.dart';

final class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.controller,
    this.visibilityController,
    super.key,
  });

  final HomeController controller;
  final ValueVisibilityController? visibilityController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState extends State<HomeScreen> {
  bool _valuesHidden = false;
  ValueListenable<int>? _resumeListenable;
  final FocusNode _privacyFocusNode = FocusNode(debugLabel: 'privacy-toggle');
  final FocusNode _retryFocusNode = FocusNode(debugLabel: 'sync-retry');

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.visibilityController?.addListener(_refresh);
    unawaited(widget.controller.start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AppResumeScope.listenableOf(context);
    if (identical(next, _resumeListenable)) return;
    _resumeListenable?.removeListener(_handleAppResume);
    _resumeListenable = next;
    _resumeListenable?.addListener(_handleAppResume);
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
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
    _resumeListenable?.removeListener(_handleAppResume);
    widget.controller.removeListener(_refresh);
    widget.visibilityController?.removeListener(_refresh);
    _privacyFocusNode.dispose();
    _retryFocusNode.dispose();
    super.dispose();
  }

  void _handleAppResume() => unawaited(widget.controller.refreshProjection());

  void _refresh() {
    if (mounted) setState(() {});
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
                child: _StatusAndPrivacy(
                  syncData: syncData,
                  hidden: hidden,
                  privacyFocusNode: _privacyFocusNode,
                  onToggleHidden: () => unawaited(_toggleValues()),
                ),
              ),
              const SizedBox(height: LarSpacing.xl),
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: OwnerSelector(
                  key: const Key('owner-selector'),
                  selected: _scopeIndex(state.selectedKind),
                  onSelected: controller.select,
                ),
              ),
              const SizedBox(height: LarSpacing.xxl),
              if (state.isLoading && snapshot == null)
                const _LoadingState()
              else
                _SnapshotContent(
                  snapshot: snapshot,
                  error: state.error,
                  syncPhase: controller.syncPhase,
                  hidden: hidden,
                  monthLabel: DateFormat(
                    'MMMM',
                    'pt_BR',
                  ).format(controller.now).toLowerCase(),
                  desktop: desktop,
                  onRetry: controller.retrySync,
                  retryFocusNode: _retryFocusNode,
                ),
            ],
          ),
        ),
      ),
    );
    if (ios) {
      return SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: <Widget>[
            CupertinoSliverRefreshControl(onRefresh: controller.retrySync),
            SliverToBoxAdapter(child: body),
          ],
        ),
      );
    }
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: controller.retrySync,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: body,
        ),
      ),
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
        snackBarAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
      );
    }
  }
}

final class _StatusAndPrivacy extends StatelessWidget {
  const _StatusAndPrivacy({
    required this.syncData,
    required this.hidden,
    required this.onToggleHidden,
    required this.privacyFocusNode,
  });

  final SyncStatusData syncData;
  final bool hidden;
  final VoidCallback onToggleHidden;
  final FocusNode privacyFocusNode;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(child: SyncStatusView(data: syncData)),
      const SizedBox(width: LarSpacing.sm),
      IconButton(
        key: const Key('privacy-toggle'),
        focusNode: privacyFocusNode,
        tooltip: hidden ? 'Mostrar valores' : 'Ocultar valores',
        onPressed: onToggleHidden,
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ],
  );
}

final class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Carregando dados locais',
    child: Column(
      key: const Key('home-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Carregando dados locais',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: LarSpacing.md),
        const LinearProgressIndicator(),
      ],
    ),
  );
}

final class _SnapshotContent extends StatelessWidget {
  const _SnapshotContent({
    required this.snapshot,
    required this.error,
    required this.syncPhase,
    required this.hidden,
    required this.monthLabel,
    required this.desktop,
    required this.onRetry,
    required this.retryFocusNode,
  });

  final HomeSnapshot? snapshot;
  final Object? error;
  final SyncPhase syncPhase;
  final bool hidden;
  final String monthLabel;
  final bool desktop;
  final Future<void> Function() onRetry;
  final FocusNode retryFocusNode;

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    final hasCache = data?.lastSyncedAt != null;
    final messages = <String>[
      if (syncPhase == SyncPhase.offline && !hasCache)
        'Sem dados disponíveis offline',
      if (syncPhase == SyncPhase.offline && hasCache)
        'Dados salvos no dispositivo',
      if (syncPhase == SyncPhase.failed) 'Não foi possível sincronizar',
      if (error != null) 'Dados locais indisponíveis',
      if (hasCache && data?.hasAccountData == false)
        'Dados de contas indisponíveis',
    ];
    final available = hasCache && error == null;
    final financialData = available ? data : null;
    final recent = available
        ? data!.recentTransactions
        : const <HomeTransaction>[];
    final balance = BalanceHeader(
      balanceMinor: financialData?.hasAccountData == true
          ? financialData!.balanceMinor
          : null,
      hidden: hidden,
    );
    final commitments = CommitmentsSummary(
      commitmentMinor: financialData?.upcomingCommitmentMinor,
      monthExpenseMinor: financialData?.monthExpenseMinor,
      monthLabel: monthLabel,
      hidden: hidden,
    );
    final attention = _AttentionSection(
      messages: messages,
      showRetry:
          syncPhase == SyncPhase.offline || syncPhase == SyncPhase.failed,
      onRetry: onRetry,
      retryFocusNode: retryFocusNode,
    );
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        balance,
        const SizedBox(height: LarSpacing.lg),
        commitments,
        if (messages.isNotEmpty) ...[
          const SizedBox(height: LarSpacing.lg),
          attention,
        ],
      ],
    );
    if (desktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 5, child: balance),
              const SizedBox(width: LarSpacing.lg),
              Expanded(flex: 4, child: commitments),
            ],
          ),
          if (messages.isNotEmpty) ...[
            const SizedBox(height: LarSpacing.lg),
            attention,
          ],
          const SizedBox(height: LarSpacing.lg),
          RecentTransactions(transactions: recent, hidden: hidden),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        main,
        const SizedBox(height: LarSpacing.lg),
        RecentTransactions(transactions: recent, hidden: hidden),
      ],
    );
  }
}

final class _AttentionSection extends StatelessWidget {
  const _AttentionSection({
    required this.messages,
    required this.showRetry,
    required this.onRetry,
    required this.retryFocusNode,
  });

  final List<String> messages;
  final bool showRetry;
  final Future<void> Function() onRetry;
  final FocusNode retryFocusNode;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      AttentionList(messages: messages),
      if (showRetry)
        Align(
          alignment: Alignment.centerLeft,
          child: FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: TextButton.icon(
              key: const Key('sync-retry'),
              focusNode: retryFocusNode,
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ),
        ),
    ],
  );
}

int _scopeIndex(OwnerScopeKind kind) => switch (kind) {
  OwnerScopeKind.household => 0,
  OwnerScopeKind.selfOwner => 1,
  OwnerScopeKind.spouse => 2,
};

SyncVisualState _syncVisualState(SyncPhase phase) => switch (phase) {
  SyncPhase.current => SyncVisualState.current,
  SyncPhase.syncing => SyncVisualState.syncing,
  SyncPhase.failed => SyncVisualState.failed,
  SyncPhase.idle || SyncPhase.offline => SyncVisualState.offline,
};
