import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_models.dart';
import '../../../design_system/lar_spacing.dart';
import '../domain/session.dart';

typedef InitialSyncReady =
    Future<bool> Function(
      SessionSnapshot expectedSession,
      DateTime? lastSuccessAt,
    );

final class InitialSyncScreen extends StatefulWidget {
  const InitialSyncScreen({
    required this.coordinator,
    required this.onReady,
    super.key,
  });

  final LedgerSyncCoordinator coordinator;
  final InitialSyncReady onReady;

  @override
  State<InitialSyncScreen> createState() => _InitialSyncScreenState();
}

final class _InitialSyncScreenState extends State<InitialSyncScreen> {
  SyncResult? _result;
  bool _readyDelivered = false;

  @override
  void initState() {
    super.initState();
    unawaited(_synchronize());
  }

  Future<void> _synchronize() async {
    if (mounted) setState(() => _result = null);
    final result = await widget.coordinator.synchronize();
    if (!mounted) return;
    if (result == SyncResult.updated ||
        result == SyncResult.current ||
        result == SyncResult.offlineWithCache) {
      final expectedSession = widget.coordinator.lastSuccessfulSession;
      if (expectedSession != null &&
          await widget.coordinator.hasValidCacheFor(expectedSession)) {
        if (!mounted || _readyDelivered) return;
        _readyDelivered = true;
        if (await widget.onReady(
          expectedSession,
          widget.coordinator.state.timestamp,
        )) {
          return;
        }
        _readyDelivered = false;
      }
    }
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final text = Theme.of(context).textTheme;
    final isOfflineWithoutCache = result == SyncResult.noCacheOffline;
    final message = isOfflineWithoutCache
        ? 'Sem conexão e sem dados salvos neste dispositivo.'
        : 'Não foi possível sincronizar seus dados. Tente novamente.';

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(LarSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  'Preparando seus dados',
                  style: text.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: LarSpacing.lg),
                if (result == null) ...<Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: LarSpacing.lg),
                  Text(
                    'Sincronizando o Lar com segurança.',
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ] else ...<Widget>[
                  Icon(
                    isOfflineWithoutCache
                        ? Icons.cloud_off_outlined
                        : Icons.error_outline,
                    size: 40,
                  ),
                  const SizedBox(height: LarSpacing.md),
                  Text(
                    message,
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: LarSpacing.lg),
                  FilledButton(
                    onPressed: _synchronize,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
