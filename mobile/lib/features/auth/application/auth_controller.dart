import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/network/api_error.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

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
  AuthController(this._repository, {SessionAuthority? sessionAuthority})
    : _sessionAuthority = sessionAuthority;

  final AuthGateway _repository;
  final SessionAuthority? _sessionAuthority;
  AuthState _state = const AuthState(phase: AuthPhase.checking);
  bool _disposed = false;
  Future<void>? _logoutInFlight;

  AuthState get state => _state;

  Future<void> initialize() async {
    try {
      final deviceName = await _repository.readDeviceName();
      final lastSyncAt = await _repository.readLastSyncAt();
      final session = await _repository.readSession();
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
        late List<DeviceOwnerOption> owners;
        try {
          owners = await _repository.loadOwners();
        } on OfflineFailure catch (error) {
          await _logoutUnownedSession();
          _emit(
            AuthState(
              phase: AuthPhase.signedOut,
              message: error.message,
              deviceName: deviceName,
              lastSyncAt: lastSyncAt,
            ),
          );
          return;
        }
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
      final syncedSessionIdentity = await _repository
          .readSyncedSessionIdentity();
      final sessionIdentity = session.sessionIdentity;
      _emit(
        AuthState(
          phase:
              lastSyncAt != null &&
                  syncedDeviceUuid == session.deviceUuid &&
                  sessionIdentity != null &&
                  sessionIdentity.isNotEmpty &&
                  syncedSessionIdentity == sessionIdentity
              ? AuthPhase.authenticated
              : AuthPhase.initialSync,
          deviceName: deviceName,
          lastSyncAt: lastSyncAt,
        ),
      );
    } on SessionExpired {
      _emit(const AuthState(phase: AuthPhase.signedOut));
    } on OfflineFailure catch (error) {
      _emit(AuthState(phase: AuthPhase.signedOut, message: error.message));
    } catch (_) {
      _emit(const AuthState(phase: AuthPhase.signedOut));
    }
  }

  Future<void> login({required String email, required String password}) async {
    final logoutInFlight = _logoutInFlight;
    if (logoutInFlight != null) await logoutInFlight;
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
      if (result.owners.isEmpty) throw const RequestFailure();
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

  Future<bool> completeInitialSync(
    SessionSnapshot expectedSession,
    DateTime? lastSuccessAt,
  ) async {
    final authority = _sessionAuthority;
    if (_state.phase != AuthPhase.initialSync ||
        authority == null ||
        !await authority.isCurrent(expectedSession) ||
        _state.phase != AuthPhase.initialSync) {
      return false;
    }
    _emit(
      AuthState(
        phase: AuthPhase.authenticated,
        deviceName: _state.deviceName,
        lastSyncAt: lastSuccessAt ?? _state.lastSyncAt,
      ),
    );
    return true;
  }

  void expireSession() {
    _emit(
      AuthState(
        phase: AuthPhase.signedOut,
        message: const SessionExpired().message,
        deviceName: _state.deviceName,
        lastSyncAt: _state.lastSyncAt,
      ),
    );
  }

  Future<void> logout() {
    final logoutInFlight = _logoutInFlight;
    if (logoutInFlight != null) return logoutInFlight;
    _emit(
      AuthState(
        phase: AuthPhase.signedOut,
        isSubmitting: true,
        deviceName: _state.deviceName,
        lastSyncAt: _state.lastSyncAt,
      ),
    );
    late final Future<void> operation;
    operation = _performLogout().whenComplete(() {
      if (!identical(_logoutInFlight, operation)) return;
      _logoutInFlight = null;
      if (_state.phase == AuthPhase.signedOut && _state.isSubmitting) {
        _emit(
          AuthState(
            phase: AuthPhase.signedOut,
            deviceName: _state.deviceName,
            lastSyncAt: _state.lastSyncAt,
          ),
        );
      }
    });
    _logoutInFlight = operation;
    return operation;
  }

  Future<void> _performLogout() async {
    try {
      await _repository.logout();
    } catch (_) {
      // A local logout remains authoritative.
    }
  }

  List<DeviceOwnerOption> _deviceOwners(List<DeviceOwnerOption> owners) =>
      List<DeviceOwnerOption>.unmodifiable(
        owners.where((owner) => owner.type == 'self' || owner.type == 'spouse'),
      );

  Future<void> _logoutUnownedSession() async {
    try {
      await _repository.logout();
    } catch (_) {
      // A local signed-out state is still safer than an unusable owner flow.
    }
  }

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
