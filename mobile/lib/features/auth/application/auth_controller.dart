import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/network/api_error.dart';
import '../data/auth_repository.dart';

enum AuthPhase {
  checking,
  signedOut,
  choosingOwner,
  initialSync,
  authenticated,
}

final class AuthState {
  const AuthState({
    required this.phase,
    this.owners = const <DeviceOwnerOption>[],
    this.isSubmitting = false,
    this.message,
    this.deviceName = 'Lar Finance',
    this.lastSyncAt,
  });

  final AuthPhase phase;
  final List<DeviceOwnerOption> owners;
  final bool isSubmitting;
  final String? message;
  final String deviceName;
  final DateTime? lastSyncAt;
}

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  throw StateError('AuthController must be overridden at the app root.');
});

final class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final AuthGateway _repository;
  AuthState _state = const AuthState(phase: AuthPhase.checking);
  bool _disposed = false;

  AuthState get state => _state;

  Future<void> initialize() async {
    try {
      final session = await _repository.readSession();
      final deviceName = await _repository.readDeviceName();
      final lastSyncAt = await _repository.readLastSyncAt();
      if (session == null) {
        _emit(
          AuthState(
            phase: AuthPhase.signedOut,
            deviceName: deviceName,
            lastSyncAt: lastSyncAt,
          ),
        );
        return;
      }

      final selectedOwner = await _repository.readSelectedOwnerUuid();
      if (selectedOwner == null) {
        final owners = await _repository.loadOwners();
        _emit(
          AuthState(
            phase: AuthPhase.choosingOwner,
            owners: _deviceOwners(owners),
            deviceName: deviceName,
            lastSyncAt: lastSyncAt,
          ),
        );
        return;
      }

      final syncedDeviceUuid = await _repository.readSyncedDeviceUuid();
      _emit(
        AuthState(
          phase: lastSyncAt != null && syncedDeviceUuid == session.deviceUuid
              ? AuthPhase.authenticated
              : AuthPhase.initialSync,
          deviceName: deviceName,
          lastSyncAt: lastSyncAt,
        ),
      );
    } on SessionExpired {
      _emit(const AuthState(phase: AuthPhase.signedOut));
    } on OfflineFailure catch (error) {
      try {
        await _repository.logout();
      } catch (_) {
        // A local signed-out state is still safer than an unusable owner flow.
      }
      _emit(AuthState(phase: AuthPhase.signedOut, message: error.message));
    } catch (_) {
      _emit(const AuthState(phase: AuthPhase.signedOut));
    }
  }

  Future<void> login({required String email, required String password}) async {
    if (_state.isSubmitting) return;
    _emit(
      AuthState(
        phase: AuthPhase.signedOut,
        isSubmitting: true,
        deviceName: _state.deviceName,
        lastSyncAt: _state.lastSyncAt,
      ),
    );
    try {
      final result = await _repository.login(email: email, password: password);
      final deviceName = await _repository.readDeviceName();
      final lastSyncAt = await _repository.readLastSyncAt();
      _emit(
        AuthState(
          phase: AuthPhase.choosingOwner,
          owners: _deviceOwners(result.owners),
          deviceName: deviceName,
          lastSyncAt: lastSyncAt,
        ),
      );
    } on ApiError catch (error) {
      _emit(
        AuthState(
          phase: AuthPhase.signedOut,
          message: error.message,
          deviceName: _state.deviceName,
          lastSyncAt: _state.lastSyncAt,
        ),
      );
    } catch (_) {
      _emit(
        AuthState(
          phase: AuthPhase.signedOut,
          message: const RequestFailure().message,
          deviceName: _state.deviceName,
          lastSyncAt: _state.lastSyncAt,
        ),
      );
    }
  }

  Future<void> selectDeviceOwner(String uuid) async {
    if (_state.isSubmitting ||
        !_state.owners.any((owner) => owner.uuid == uuid)) {
      return;
    }
    _emit(
      AuthState(
        phase: AuthPhase.choosingOwner,
        owners: _state.owners,
        isSubmitting: true,
        deviceName: _state.deviceName,
        lastSyncAt: _state.lastSyncAt,
      ),
    );
    try {
      await _repository.selectDeviceOwner(uuid);
      _emit(
        AuthState(
          phase: AuthPhase.initialSync,
          deviceName: _state.deviceName,
          lastSyncAt: _state.lastSyncAt,
        ),
      );
    } on ApiError catch (error) {
      _emit(
        AuthState(
          phase: error is SessionExpired
              ? AuthPhase.signedOut
              : AuthPhase.choosingOwner,
          owners: _state.owners,
          message: error.message,
          deviceName: _state.deviceName,
          lastSyncAt: _state.lastSyncAt,
        ),
      );
    } catch (_) {
      _emit(
        AuthState(
          phase: AuthPhase.choosingOwner,
          owners: _state.owners,
          message: const RequestFailure().message,
          deviceName: _state.deviceName,
          lastSyncAt: _state.lastSyncAt,
        ),
      );
    }
  }

  Future<void> logout() async {
    if (_state.isSubmitting) return;
    _emit(
      AuthState(
        phase: _state.phase,
        owners: _state.owners,
        isSubmitting: true,
        deviceName: _state.deviceName,
        lastSyncAt: _state.lastSyncAt,
      ),
    );
    try {
      await _repository.logout();
    } catch (_) {
      // A local logout remains authoritative.
    }
    _emit(const AuthState(phase: AuthPhase.signedOut));
  }

  List<DeviceOwnerOption> _deviceOwners(List<DeviceOwnerOption> owners) =>
      List<DeviceOwnerOption>.unmodifiable(
        owners.where((owner) => owner.type == 'self' || owner.type == 'spouse'),
      );

  void _emit(AuthState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
