import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/app/app_config.dart';
import 'package:lar_finance/app/router.dart';
import 'package:lar_finance/core/network/dio_transport.dart';
import 'package:lar_finance/core/network/session_transport.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/features/auth/application/auth_controller.dart';
import 'package:lar_finance/features/auth/data/auth_repository.dart';
import 'package:lar_finance/features/auth/domain/session.dart';

const _deviceUuid = '11111111-1111-4111-8111-111111111111';
const _householdUuid = '22222222-2222-4222-8222-222222222222';
const _ownerUuid = '33333333-3333-4333-8333-333333333333';

void main() {
  testWidgets(
    'v1 metadata without a session identity cannot restore Home after migration',
    (tester) async {
      late AuthController controller;
      await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp(
          'lar-finance-legacy-session-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File(
          '${directory.path}${Platform.pathSeparator}ledger.sqlite',
        );
        var database = AppDatabase(NativeDatabase(file));
        final syncedAt = DateTime.utc(2026, 8, 14, 12);
        await database
            .into(database.households)
            .insert(
              HouseholdsCompanion.insert(
                uuid: _householdUuid,
                name: 'Casa sintética',
                updatedAt: syncedAt,
              ),
            );
        await database
            .into(database.localSettings)
            .insert(
              LocalSettingsCompanion.insert(
                key: AuthRepository.selectedOwnerSettingKey,
                value: _ownerUuid,
              ),
            );
        await database
            .into(database.syncState)
            .insert(
              SyncStateCompanion.insert(
                cursor: 'cursor-legacy',
                householdUuid: _householdUuid,
                sessionDeviceUuid: _deviceUuid,
                sessionGeneration: const Value(0),
                lastSuccessAt: Value(syncedAt),
              ),
            );
        await database.close();
        database = AppDatabase(
          NativeDatabase(
            file,
            setup: (rawDatabase) {
              rawDatabase.execute(
                'ALTER TABLE sync_state DROP COLUMN session_identity',
              );
              rawDatabase.execute(
                'ALTER TABLE sync_state DROP COLUMN session_generation',
              );
              rawDatabase.execute('PRAGMA user_version = 1');
            },
          ),
        );
        addTearDown(database.close);
        final store = _MemoryTokenStore(
          StoredTokens(
            accessToken: 'synthetic-access',
            accessExpiresAt: DateTime.utc(2030),
            refreshToken: 'synthetic-refresh',
            refreshExpiresAt: DateTime.utc(2031),
            deviceUuid: _deviceUuid,
            sessionIdentity: 'active-session-identity',
          ),
        );
        final authority = SessionAuthority.forStore(store);
        final transport = SessionTransport(
          transport: _NoNetworkTransport(),
          tokenStore: store,
          sessionAuthority: authority,
        );
        final repository = AuthRepository(
          publicTransport: _NoNetworkTransport(),
          sessionTransport: transport,
          tokenStore: store,
          sessionAuthority: authority,
          database: database,
          platformName: 'windows',
          deviceName: 'Lar Finance no Windows',
        );
        controller = AuthController(repository, sessionAuthority: authority);
        await controller.initialize();
      });
      expect(controller.state.phase, AuthPhase.initialSync);
      final router = createAppRouter(
        const AppConfig(apiBaseUrl: 'https://example.test/api/v1'),
        controller,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => controller,
              disposeNotifier: false,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Preparando dados'), findsOneWidget);
      expect(find.text('CASA DE VALORES'), findsNothing);
    },
  );
}

final class _MemoryTokenStore implements TokenStore {
  _MemoryTokenStore(this.value);

  StoredTokens? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredTokens?> read() async => value;

  @override
  Future<void> write(StoredTokens tokens) async => value = tokens;
}

final class _NoNetworkTransport implements ApiTransport {
  @override
  Future<ApiResponse> request(
    String path, {
    required String method,
    Object? data,
    String? bearerToken,
  }) => throw StateError('Unexpected network request: $method $path');
}
