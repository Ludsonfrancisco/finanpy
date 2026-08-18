import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../app/adaptive_shell.dart';
import '../../../app/value_visibility_controller.dart';
import '../../../core/sync/sync_state.dart';
import '../../../design_system/components/owner_selector.dart';
import '../../../design_system/components/sync_status.dart';
import '../../../design_system/lar_spacing.dart';
import '../application/accounts_controller.dart';
import '../domain/accounts_models.dart';
import 'widgets/account_card.dart';
import 'widgets/account_form_sheet.dart';
import 'widgets/accounts_summary_header.dart';

final class AccountsScreen extends StatefulWidget {
  const AccountsScreen({
    required this.controller,
    this.visibilityController,
    this.onOpenImport,
    super.key,
  });

  final AccountsController controller;
  final ValueVisibilityController? visibilityController;
  final VoidCallback? onOpenImport;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

final class _AccountsScreenState extends State<AccountsScreen> {
  bool _valuesHidden = false;
  final FocusNode _privacyFocusNode = FocusNode(
    debugLabel: 'accounts-privacy-toggle',
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.visibilityController?.addListener(_refresh);
    unawaited(widget.controller.start());
  }

  @override
  void didUpdateWidget(AccountsScreen oldWidget) {
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
    widget.controller.removeListener(_refresh);
    widget.visibilityController?.removeListener(_refresh);
    _privacyFocusNode.dispose();
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
                      key: const Key('accounts-header-new-button'),
                      onPressed: () => AccountFormSheet.show(
                        context,
                        repository: widget.controller.repository,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nova Conta'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: LarSpacing.xs),
                    IconButton(
                      key: const Key('accounts-privacy-toggle'),
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
                  key: const Key('accounts-owner-selector'),
                  selected: state.selectedScopeIndex,
                  onSelected: controller.select,
                ),
              ),
              const SizedBox(height: LarSpacing.xxl),
              if (state.isLoading && snapshot == null)
                const _AccountsLoadingState()
              else if (snapshot == null || !snapshot.hasAccountData)
                _AccountsEmptyState(
                  onOpenImport: widget.onOpenImport,
                  onNewAccount: () => AccountFormSheet.show(
                    context,
                    repository: widget.controller.repository,
                  ),
                )
              else
                _AccountsContent(
                  snapshot: snapshot,
                  hidden: hidden,
                  desktop: desktop,
                ),
            ],
          ),
        ),
      ),
    );

    final fab = FloatingActionButton.extended(
      key: const Key('accounts-new-button'),
      onPressed: () => AccountFormSheet.show(
        context,
        repository: widget.controller.repository,
      ),
      icon: const Icon(Icons.add),
      label: const Text('Nova Conta'),
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

final class _AccountsLoadingState extends StatelessWidget {
  const _AccountsLoadingState();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Carregando contas',
    child: Column(
      key: const Key('accounts-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Carregando contas locais',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: LarSpacing.md),
        const LinearProgressIndicator(),
      ],
    ),
  );
}

final class _AccountsEmptyState extends StatelessWidget {
  const _AccountsEmptyState({this.onOpenImport, this.onNewAccount});

  final VoidCallback? onOpenImport;
  final VoidCallback? onNewAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    return Semantics(
      container: true,
      label: 'Nenhuma conta cadastrada',
      child: Container(
        key: const Key('accounts-empty-state'),
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
              Icons.account_balance_outlined,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: LarSpacing.md),
            Text(
              'Nenhuma conta encontrada',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: LarSpacing.xs),
            Text(
              'Cadastre uma conta manual ou importe um extrato bancário OFX.',
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
                if (onNewAccount != null)
                  FilledButton.icon(
                    onPressed: onNewAccount,
                    icon: const Icon(Icons.add),
                    label: const Text('Criar conta'),
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

final class _AccountsContent extends StatelessWidget {
  const _AccountsContent({
    required this.snapshot,
    required this.hidden,
    required this.desktop,
  });

  final AccountsSnapshot snapshot;
  final bool hidden;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final accounts = snapshot.accounts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AccountsSummaryHeader(
          totalBalanceMinor: snapshot.totalBalanceMinor,
          accountCount: accounts.length,
          hidden: hidden,
        ),
        const SizedBox(height: LarSpacing.xxl),
        if (desktop)
          Wrap(
            spacing: LarSpacing.lg,
            runSpacing: LarSpacing.lg,
            children: accounts
                .map(
                  (account) => SizedBox(
                    width: 340,
                    child: AccountCard(account: account, hidden: hidden),
                  ),
                )
                .toList(growable: false),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: accounts.length,
            separatorBuilder: (_, _) => const SizedBox(height: LarSpacing.md),
            itemBuilder: (context, index) =>
                AccountCard(account: accounts[index], hidden: hidden),
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
