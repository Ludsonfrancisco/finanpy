import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/sync/sync_state.dart';
import '../../../design_system/lar_spacing.dart';
import '../application/auth_controller.dart';

final class MoreScreen extends ConsumerWidget {
  const MoreScreen({
    this.syncState,
    this.buildLabel = 'development',
    this.serverHost = 'não configurado',
    this.onOpenBills,
    this.onOpenCards,
    this.onOpenImport,
    this.onOpenCategories,
    this.onOpenReports,
    super.key,
  });

  /// Navigation is injected: this screen never builds its own transport.
  final SyncState? syncState;
  final String buildLabel;
  final String serverHost;
  final VoidCallback? onOpenBills;
  final VoidCallback? onOpenCards;
  final VoidCallback? onOpenImport;
  final VoidCallback? onOpenCategories;
  final VoidCallback? onOpenReports;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(authControllerProvider);
    final liveState = syncState;
    Widget content() {
      final state = controller.state;
      final lastSyncAt = liveState?.timestamp ?? state.lastSyncAt;
      final lastSync = lastSyncAt == null
          ? 'Ainda não sincronizado'
          : DateFormat('dd/MM/yyyy, HH:mm').format(lastSyncAt.toLocal());
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(LarSpacing.xl),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Mais',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: LarSpacing.lg),
                  Text(
                    'Dispositivo',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: LarSpacing.sm),
                  Text(state.deviceName),
                  const SizedBox(height: LarSpacing.sm),
                  Text('Versão $buildLabel'),
                  const SizedBox(height: LarSpacing.xs),
                  Text(serverHost),
                  const SizedBox(height: LarSpacing.lg),
                  Text(
                    'Última sincronização',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: LarSpacing.xs),
                  Text(lastSync),
                  if (onOpenBills != null ||
                      onOpenCards != null ||
                      onOpenReports != null ||
                      onOpenCategories != null ||
                      onOpenImport != null) ...<Widget>[
                    const SizedBox(height: LarSpacing.xl),
                    Text(
                      'Cadastros & Ferramentas',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (onOpenCards != null) ...[
                      const SizedBox(height: LarSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: onOpenCards,
                        icon: const Icon(Icons.credit_card_outlined),
                        label: const Text('Cartões de Crédito & Faturas'),
                      ),
                    ],
                    if (onOpenBills != null) ...[
                      const SizedBox(height: LarSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: onOpenBills,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Contas Fixas & Vencimentos'),
                      ),
                    ],
                    if (onOpenReports != null) ...[
                      const SizedBox(height: LarSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: onOpenReports,
                        icon: const Icon(Icons.pie_chart_outline),
                        label: const Text('Relatórios & Gráficos'),
                      ),
                    ],
                    if (onOpenCategories != null) ...[
                      const SizedBox(height: LarSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: onOpenCategories,
                        icon: const Icon(Icons.category_outlined),
                        label: const Text('Categorias'),
                      ),
                    ],
                    if (onOpenImport != null) ...[
                      const SizedBox(height: LarSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: onOpenImport,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text('Importar OFX'),
                      ),
                    ],
                  ],
                  const SizedBox(height: LarSpacing.xl),
                  OutlinedButton.icon(
                    onPressed: state.isSubmitting ? null : controller.logout,
                    icon: state.isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout),
                    label: const Text('Sair'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (liveState == null) return content();
    return AnimatedBuilder(
      animation: liveState,
      builder: (context, _) => content(),
    );
  }
}
