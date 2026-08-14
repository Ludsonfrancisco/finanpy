import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/sync/sync_coordinator.dart';

final class AppSyncLifecycle extends StatefulWidget {
  const AppSyncLifecycle({
    required this.coordinator,
    required this.isAuthenticated,
    required this.child,
    this.resumeThreshold = const Duration(minutes: 5),
    super.key,
  });

  final LedgerSyncCoordinator coordinator;
  final bool Function() isAuthenticated;
  final Duration resumeThreshold;
  final Widget child;

  @override
  State<AppSyncLifecycle> createState() => _AppSyncLifecycleState();
}

final class _AppSyncLifecycleState extends State<AppSyncLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isAuthenticated()) {
        unawaited(widget.coordinator.synchronize());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isAuthenticated()) {
      unawaited(widget.coordinator.synchronizeIfStale(widget.resumeThreshold));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
