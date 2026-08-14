import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/lar_spacing.dart';
import '../application/auth_controller.dart';

final class DeviceOwnerScreen extends ConsumerStatefulWidget {
  const DeviceOwnerScreen({super.key});

  @override
  ConsumerState<DeviceOwnerScreen> createState() => _DeviceOwnerScreenState();
}

final class _DeviceOwnerScreenState extends ConsumerState<DeviceOwnerScreen> {
  String? _selectedUuid;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(authControllerProvider);
    final state = controller.state;
    final owners = state.owners
        .where((owner) => owner.type == 'self' || owner.type == 'spouse')
        .toList(growable: false);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(LarSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Este dispositivo',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: LarSpacing.sm),
                  Text(
                    'Escolha quem usa este dispositivo para personalizar a experiência.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: LarSpacing.lg),
                  for (final owner in owners) ...<Widget>[
                    Semantics(
                      selected: _selectedUuid == owner.uuid,
                      button: true,
                      child: Card(
                        child: ListTile(
                          selected: _selectedUuid == owner.uuid,
                          leading: Icon(
                            _selectedUuid == owner.uuid
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: Text(owner.name),
                          subtitle: Text(
                            owner.type == 'self' ? 'Você' : 'Cônjuge',
                          ),
                          onTap: state.isSubmitting
                              ? null
                              : () =>
                                    setState(() => _selectedUuid = owner.uuid),
                        ),
                      ),
                    ),
                    const SizedBox(height: LarSpacing.sm),
                  ],
                  if (state.message case final message?) ...<Widget>[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: LarSpacing.md),
                  ],
                  FilledButton(
                    onPressed: _selectedUuid == null || state.isSubmitting
                        ? null
                        : () => controller.selectDeviceOwner(_selectedUuid!),
                    child: state.isSubmitting
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continuar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
