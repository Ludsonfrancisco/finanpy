import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/sync/sync_coordinator.dart';

final class AppResumeScope extends InheritedNotifier<ValueNotifier<int>> {
  const AppResumeScope({
    required ValueNotifier<int> notifier,
    required super.child,
    super.key,
  }) : super(notifier: notifier);

  static ValueListenable<int>? listenableOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppResumeScope>()?.notifier;

  static int generationOf(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<AppResumeScope>()
          ?.notifier
          ?.value ??
      0;
}

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
  final ValueNotifier<int> _resumeGeneration = ValueNotifier<int>(0);

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
    if (state == AppLifecycleState.resumed) {
      _resumeGeneration.value += 1;
      if (widget.isAuthenticated()) {
        unawaited(
          widget.coordinator.synchronizeIfStale(widget.resumeThreshold),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeGeneration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AppResumeScope(notifier: _resumeGeneration, child: widget.child);
}
