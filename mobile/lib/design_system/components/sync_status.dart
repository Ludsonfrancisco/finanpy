import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../lar_colors.dart';

enum SyncVisualState { current, syncing, offline, failed }

final class SyncStatusData {
  const SyncStatusData({required this.state, required this.lastSuccessAt});
  final SyncVisualState state;
  final DateTime? lastSuccessAt;
}

final class SyncStatusView extends StatelessWidget {
  const SyncStatusView({required this.data, super.key});
  final SyncStatusData data;
  String get _label => switch (data.state) {
    SyncVisualState.current => 'Atualizado',
    SyncVisualState.syncing => 'Sincronizando',
    SyncVisualState.offline => 'Offline',
    SyncVisualState.failed => 'Sincronização indisponível',
  };
  IconData get _icon => switch (data.state) {
    SyncVisualState.current => Icons.check_circle_outline,
    SyncVisualState.syncing => Icons.sync,
    SyncVisualState.offline => Icons.cloud_off_outlined,
    SyncVisualState.failed => Icons.error_outline,
  };
  Color get _color => switch (data.state) {
    SyncVisualState.current || SyncVisualState.syncing => LarColors.mineral,
    SyncVisualState.offline => LarColors.amber,
    SyncVisualState.failed => LarColors.danger,
  };
  @override
  Widget build(BuildContext context) {
    final detail = data.lastSuccessAt == null
        ? null
        : 'Última sincronização ${DateFormat('dd/MM, HH:mm', 'pt_BR').format(data.lastSuccessAt!)}';
    return Semantics(
      label: detail == null ? _label : '$_label. $detail',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_icon, size: 18, color: _color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(detail == null ? _label : '$_label · $detail'),
            ),
          ],
        ),
      ),
    );
  }
}
