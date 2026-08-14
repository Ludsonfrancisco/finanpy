import 'dart:async';

import 'package:flutter/material.dart';

final class PrivacyShield extends StatefulWidget {
  const PrivacyShield({
    required this.child,
    this.onInactive,
    this.onResumed,
    super.key,
  });

  final Widget child;
  final VoidCallback? onInactive;
  final Future<void> Function()? onResumed;

  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

final class _PrivacyShieldState extends State<PrivacyShield>
    with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (!_covered) setState(() => _covered = true);
        widget.onInactive?.call();
      case AppLifecycleState.resumed:
        if (_covered) setState(() => _covered = false);
        final restore = widget.onResumed;
        if (restore != null) unawaited(restore());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_covered) return widget.child;
    return Semantics(
      container: true,
      label: 'Lar Finance protegido',
      child: ExcludeSemantics(
        child: ColoredBox(
          color: const Color(0xFF091311),
          child: Center(
            child: Text(
              'LAR FINANCE',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFFE8E3D8),
                letterSpacing: 1.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
