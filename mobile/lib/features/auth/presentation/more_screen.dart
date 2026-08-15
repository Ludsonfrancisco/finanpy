import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/lar_spacing.dart';
import '../application/auth_controller.dart';

final class MoreScreen extends ConsumerWidget {
  const MoreScreen({this.onOpenImport, super.key});

  /// Navigation is injected: this screen never builds its own transport.
  final VoidCallback? onOpenImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(authControllerProvider);
    final state = controller.state;
    final lastSync = state.lastSyncAt == null
        ? 'Ainda não sincronizado'
        : DateFormat('dd/MM/yyyy, HH:mm').format(state.lastSyncAt!);
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
                Text('Mais', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: LarSpacing.lg),
                Text(
                  'Dispositivo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: LarSpacing.sm),
                Text(state.deviceName),
                const SizedBox(height: LarSpacing.lg),
                Text(
                  'Última sincronização',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: LarSpacing.xs),
                Text(lastSync),
                if (onOpenImport != null) ...<Widget>[
                  const SizedBox(height: LarSpacing.xl),
                  Text(
                    'Importação',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: LarSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: onOpenImport,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Importar OFX'),
                  ),
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
}
