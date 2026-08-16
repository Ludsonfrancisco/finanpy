// THESIS: Importar é decidir com evidência à vista, não confiar num arquivo.
// OWN-WORLD: Grafite esverdeado, marfim, divisores finos e verde mineral restrito.
// STORY: Escolher o arquivo, ler origem e período, conferir linha a linha, decidir.
// FIRST VIEWPORT: Origem e período antes de qualquer total; ações sempre alcançáveis.
// FORM: Operate, Casa de Valores code-first, mesma gramática da Home.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/adaptive_shell.dart';
import '../../../design_system/lar_spacing.dart';
import '../application/import_controller.dart';
import '../domain/import_preview.dart';
import 'widgets/import_actions.dart';
import 'widgets/import_record_list.dart';
import 'widgets/import_source_card.dart';
import 'widgets/import_summary.dart';

final class ImportScreen extends StatefulWidget {
  const ImportScreen({
    required this.state,
    required this.onSelect,
    required this.onConfirm,
    required this.onCancel,
    required this.onRetry,
    required this.onLoadMore,
    this.formatExpiry = formatLocalExpiry,
    super.key,
  });

  final ImportViewState state;
  final VoidCallback onSelect;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;

  /// Injected so a golden can render a wall clock that never moves.
  final String Function(DateTime expiresAt) formatExpiry;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

final class _ImportScreenState extends State<ImportScreen> {
  final FocusNode _retryFocusNode = FocusNode(debugLabel: 'import-retry');

  @override
  void dispose() {
    _retryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final preview = state.preview;
    final desktop = MediaQuery.sizeOf(context).width >= LarBreakpoints.desktop;
    final isReceipt = state.phase == ImportPhase.completed;
    final showConfirmation =
        preview != null &&
        (state.phase == ImportPhase.preview ||
            state.phase == ImportPhase.confirming);
    final canConfirm =
        showConfirmation &&
        state.phase == ImportPhase.preview &&
        preview.records.isNotEmpty &&
        !preview.isRepeatedFile &&
        !preview.hasMorePages;
    final canCancel = showConfirmation && state.phase == ImportPhase.preview;

    final actions = ImportActions(
      canConfirm: canConfirm,
      canCancel: canCancel,
      showConfirmation: showConfirmation,
      showSelect: !showConfirmation,
      selectLabel: isReceipt
          ? 'Importar outro arquivo'
          : 'Selecionar arquivo OFX',
      canSelect: !state.isBusy,
      showRetry: state.phase == ImportPhase.failure,
      onSelect: widget.onSelect,
      onConfirm: widget.onConfirm,
      onCancel: widget.onCancel,
      onRetry: widget.onRetry,
      retryFocusNode: _retryFocusNode,
    );

    final summary = preview == null
        ? null
        : ImportSummary(
            key: const Key('import-summary'),
            preview: preview,
            isReceipt: isReceipt,
            compact: !desktop,
          );
    final list = preview == null
        ? null
        : ImportRecordList(
            key: const Key('import-record-list'),
            records: preview.records,
            emptyMessage: preview.isRepeatedFile
                ? 'Este arquivo já foi confirmado antes.'
                : 'Nenhum lançamento no período',
          );

    final body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? LarSpacing.xxl : LarSpacing.lg,
            vertical: desktop ? LarSpacing.xl : LarSpacing.lg,
          ),
          child: desktop && preview != null
              ? _DesktopLayout(
                  header: _Header(state: state),
                  source: ImportSourceCard(
                    preview: preview,
                    formatExpiry: widget.formatExpiry,
                  ),
                  list: list!,
                  summary: summary!,
                  actions: actions,
                  loadMore: _loadMore(state),
                )
              : _MobileLayout(
                  header: _Header(state: state),
                  source: preview == null
                      ? null
                      : ImportSourceCard(
                          preview: preview,
                          formatExpiry: widget.formatExpiry,
                        ),
                  summary: summary,
                  list: list,
                  loadMore: _loadMore(state),
                ),
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (canCancel) widget.onCancel();
        },
      },
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(child: SingleChildScrollView(child: body)),
              if (!desktop || preview == null) ...<Widget>[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LarSpacing.lg,
                    LarSpacing.md,
                    LarSpacing.lg,
                    LarSpacing.md,
                  ),
                  child: Align(alignment: Alignment.centerLeft, child: actions),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget? _loadMore(ImportViewState state) {
    if (state.phase != ImportPhase.preview) return null;
    if (!(state.preview?.hasMorePages ?? false)) return null;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('import-load-more'),
        onPressed: widget.onLoadMore,
        icon: const Icon(Icons.expand_more),
        label: const Text('Carregar mais lançamentos'),
      ),
    );
  }
}

final class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.header,
    required this.source,
    required this.summary,
    required this.list,
    required this.loadMore,
  });

  final Widget header;
  final Widget? source;
  final Widget? summary;
  final Widget? list;
  final Widget? loadMore;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      header,
      if (source != null) ...<Widget>[
        const SizedBox(height: LarSpacing.xl),
        source!,
      ],
      if (summary != null) ...<Widget>[
        const SizedBox(height: LarSpacing.xl),
        summary!,
      ],
      if (list != null) ...<Widget>[
        const SizedBox(height: LarSpacing.xl),
        list!,
      ],
      if (loadMore != null) ...<Widget>[
        const SizedBox(height: LarSpacing.sm),
        loadMore!,
      ],
    ],
  );
}

final class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.header,
    required this.source,
    required this.list,
    required this.summary,
    required this.actions,
    required this.loadMore,
  });

  final Widget header;
  final Widget source;
  final Widget list;
  final Widget summary;
  final Widget actions;
  final Widget? loadMore;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      header,
      const SizedBox(height: LarSpacing.xl),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                source,
                const SizedBox(height: LarSpacing.xl),
                list,
                if (loadMore != null) ...<Widget>[
                  const SizedBox(height: LarSpacing.sm),
                  loadMore!,
                ],
              ],
            ),
          ),
          const SizedBox(width: LarSpacing.xxl),
          const SizedBox(height: 420, child: VerticalDivider(width: 1)),
          const SizedBox(width: LarSpacing.xxl),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                summary,
                const SizedBox(height: LarSpacing.xl),
                Align(alignment: Alignment.centerLeft, child: actions),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

final class _Header extends StatelessWidget {
  const _Header({required this.state});

  final ImportViewState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final notices = _notices(state);
    final busy =
        state.phase == ImportPhase.uploading ||
        state.phase == ImportPhase.picking;
    final animationsOff = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('CASA DE VALORES', style: text.labelLarge),
        const SizedBox(height: LarSpacing.xxs),
        Text('Importação OFX', style: text.headlineMedium),
        const SizedBox(height: LarSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(statusLabel(state), style: text.bodyLarge),
        ),
        if (busy && !animationsOff) ...<Widget>[
          const SizedBox(height: LarSpacing.md),
          const LinearProgressIndicator(key: Key('import-progress')),
        ],
        if (busy && animationsOff) ...<Widget>[
          const SizedBox(height: LarSpacing.md),
          const SizedBox(
            key: Key('import-progress'),
            height: LarSpacing.xxs,
            width: double.infinity,
            child: ColoredBox(color: Color(0x33000000)),
          ),
        ],
        for (final notice in notices) ...<Widget>[
          const SizedBox(height: LarSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(Icons.info_outline, size: 20),
              ),
              const SizedBox(width: LarSpacing.sm),
              Expanded(child: Text(notice)),
            ],
          ),
        ],
      ],
    );
  }
}

String statusLabel(ImportViewState state) => switch (state.phase) {
  ImportPhase.idle => 'Nenhum arquivo selecionado',
  ImportPhase.picking => 'Escolhendo arquivo',
  ImportPhase.uploading => 'Enviando arquivo',
  ImportPhase.preview => 'Confira antes de confirmar',
  ImportPhase.confirming => 'Confirmando',
  ImportPhase.completed => 'Importação concluída',
  ImportPhase.failure => 'Não foi possível concluir',
};

List<String> _notices(ImportViewState state) {
  final preview = state.preview;
  final failure = state.failure;
  return <String>[
    if (state.phase == ImportPhase.idle)
      'Selecione um extrato OFX de conta ou cartão. Nada é gravado antes da '
          'sua confirmação.',
    if (preview != null &&
        preview.isRepeatedFile &&
        state.phase != ImportPhase.completed)
      'Arquivo já importado antes',
    if (preview != null &&
        preview.isRepeatedFile &&
        state.phase != ImportPhase.completed)
      '${preview.duplicateCount} lançamentos já existem no Lar.',
    if (state.phase == ImportPhase.completed && state.hasPendingSync)
      'Dados gravados. A sincronização ainda está pendente.',
    if (failure != null) failureMessage(failure),
  ];
}

String failureMessage(ImportFailureKind kind) => switch (kind) {
  ImportFailureKind.expiredPreview =>
    'A prévia expirou. Selecione o arquivo novamente.',
  ImportFailureKind.busy => 'A importação está ocupada. Tente novamente.',
  ImportFailureKind.offline =>
    'Sem conexão. Confira sua internet e tente novamente.',
  ImportFailureKind.invalidFile => 'Não foi possível ler este arquivo OFX.',
  ImportFailureKind.unsupportedFile => 'Este arquivo não é um OFX compatível.',
  ImportFailureKind.fileTooLarge => 'O arquivo passa de 10 MiB.',
  ImportFailureKind.notFound => 'Esta prévia não está mais disponível.',
  ImportFailureKind.invalidState => 'Esta prévia não pode mais ser usada.',
  ImportFailureKind.unknown => 'Não foi possível concluir a importação.',
};
