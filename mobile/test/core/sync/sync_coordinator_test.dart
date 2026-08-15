import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/core/network/api_error.dart';
import 'package:lar_finance/core/network/dio_transport.dart';
import 'package:lar_finance/core/network/session_transport.dart';
import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/core/storage/local_ledger.dart';
import 'package:lar_finance/core/sync/sync_api.dart';
import 'package:lar_finance/core/sync/sync_coordinator.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/features/auth/domain/session.dart';

const _deviceUuid = '70000000-0000-4000-8000-000000000001';
const _sessionIdentity = 'synthetic-session-identity';

void main() {
  group('LedgerSyncCoordinator', () {
    late Directory temporaryDirectory;
    late AppDatabase database;
    late DriftLocalLedger ledger;
    late BootstrapPayload bootstrap;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'lar-finance-sync-',
      );
      database = AppDatabase(
        NativeDatabase(File('${temporaryDirectory.path}/ledger.sqlite')),
      );
      ledger = DriftLocalLedger(database);
      bootstrap = parseBootstrapPayload(await _fixture('bootstrap.json'));
    });

    tearDown(() async {
      await database.close();
      await temporaryDirectory.delete(recursive: true);
    });

    test('bootstraps the first valid local snapshot atomically', () async {
      final coordinator = _coordinator(
        ledger,
        _FakeSyncApi(bootstrap: bootstrap),
      );

      final result = await coordinator.synchronize();

      expect(result, SyncResult.updated);
      expect((await ledger.readSyncMetadata())?.cursor, bootstrap.cursor);
      expect(await database.select(database.transactions).get(), hasLength(3));
    });

    test('rolls back a bootstrap with a broken account reference', () async {
      final brokenJson = await _fixture('bootstrap.json');
      final transactions = brokenJson['transactions']! as List<Object?>;
      (transactions.first! as Map<String, Object?>)['account_uuid'] =
          '30000000-0000-4000-8000-000000000099';
      final coordinator = _coordinator(
        ledger,
        _FakeSyncApi(bootstrap: parseBootstrapPayload(brokenJson)),
      );

      final result = await coordinator.synchronize();

      expect(result, SyncResult.failed);
      expect(await database.select(database.transactions).get(), isEmpty);
      expect(await ledger.readSyncMetadata(), isNull);
    });

    test('reports offline explicitly when no valid cache exists', () async {
      final coordinator = _coordinator(
        ledger,
        _FakeSyncApi(bootstrapError: const OfflineFailure()),
      );

      final result = await coordinator.synchronize();

      expect(result, SyncResult.noCacheOffline);
      expect(await ledger.readSyncMetadata(), isNull);
      expect(await database.select(database.accounts).get(), isEmpty);
    });

    test(
      'session expiry invalidates authentication and preserves cache',
      () async {
        await _seedBootstrap(ledger, bootstrap);
        var expirations = 0;
        final coordinator = _coordinator(
          ledger,
          _FakeSyncApi(changeError: const SessionExpired()),
          onSessionExpired: () => expirations++,
        );

        final result = await coordinator.synchronize();

        expect(result, SyncResult.failed);
        expect(expirations, 1);
        expect(
          await database.select(database.transactions).get(),
          hasLength(3),
        );
        expect((await ledger.readSyncMetadata())?.cursor, bootstrap.cursor);
        expect(coordinator.lastSuccessfulSession, isNull);
      },
    );

    test(
      'preserves prior snapshot and cursor when replacement fails',
      () async {
        await ledger.replaceBootstrap(
          bootstrap,
          DateTime.utc(2026, 8, 14, 12),
          '70000000-0000-4000-8000-000000000099',
        );
        final brokenJson = await _fixture('bootstrap.json');
        final transactions = brokenJson['transactions']! as List<Object?>;
        (transactions.first! as Map<String, Object?>)['account_uuid'] =
            '30000000-0000-4000-8000-000000000099';
        final replacement = parseBootstrapPayload(brokenJson);
        final coordinator = _coordinator(
          ledger,
          _FakeSyncApi(bootstrap: replacement),
        );

        expect(await coordinator.synchronize(), SyncResult.failed);
        expect(
          await database.select(database.transactions).get(),
          hasLength(3),
        );
        expect((await ledger.readSyncMetadata())?.cursor, bootstrap.cursor);
      },
    );

    test(
      'applies create, update and tombstone from one delta transaction',
      () async {
        await _seedBootstrap(ledger, bootstrap);
        final delta = parseSyncPage(
          await _fixture('delta_create_update_delete.json'),
        );
        final coordinator = _coordinator(
          ledger,
          _FakeSyncApi(pages: <SyncPage>[delta]),
        );

        expect(await coordinator.synchronize(), SyncResult.updated);
        expect(
          await database.select(database.transactions).get(),
          hasLength(4),
        );
        expect(
          (await database.select(database.accounts).get())
              .singleWhere(
                (account) =>
                    account.uuid == '30000000-0000-4000-8000-000000000001',
              )
              .version,
          2,
        );
        expect(
          (await database.select(database.categories).get()).map(
            (category) => category.uuid,
          ),
          isNot(contains('40000000-0000-4000-8000-000000000002')),
        );
        expect((await ledger.readSyncMetadata())?.cursor, delta.cursor);
      },
    );

    test(
      'empty delta is current and commits its cursor and timestamp',
      () async {
        await _seedBootstrap(ledger, bootstrap);
        final syncedAt = DateTime.utc(2026, 8, 14, 14);
        final coordinator = _coordinator(
          ledger,
          _FakeSyncApi(
            pages: const <SyncPage>[
              SyncPage(changes: <SyncChangePayload>[], cursor: 'cursor-empty'),
            ],
          ),
        );

        expect(await coordinator.synchronize(), SyncResult.current);
        final metadata = await ledger.readSyncMetadata();
        expect(metadata?.cursor, 'cursor-empty');
        expect(metadata?.lastSuccessAt, syncedAt);
        expect(coordinator.state.phase, SyncPhase.current);
        expect(coordinator.state.timestamp, syncedAt);
      },
    );

    for (final versionCase in <({int localVersion, int incomingVersion})>[
      (localVersion: 1, incomingVersion: 1),
      (localVersion: 2, incomingVersion: 1),
    ]) {
      test(
        'rejects account version ${versionCase.incomingVersion} against local ${versionCase.localVersion}',
        () async {
          await _seedBootstrap(ledger, bootstrap);
          var expectedCursor = bootstrap.cursor;
          if (versionCase.localVersion == 2) {
            expectedCursor = 'cursor-local-v2';
            await ledger.applyDelta(
              SyncPage(
                changes: <SyncChangePayload>[
                  SyncChangePayload(
                    entityType: 'account',
                    entityUuid: '30000000-0000-4000-8000-000000000001',
                    entityVersion: 2,
                    operation: 'update',
                    payload: _accountPayload(version: 2),
                  ),
                ],
                cursor: expectedCursor,
              ),
              DateTime.utc(2026, 8, 14, 13),
            );
          }
          final page = SyncPage(
            changes: <SyncChangePayload>[
              SyncChangePayload(
                entityType: 'account',
                entityUuid: '30000000-0000-4000-8000-000000000001',
                entityVersion: versionCase.incomingVersion,
                operation: 'update',
                payload: _accountPayload(version: versionCase.incomingVersion),
              ),
            ],
            cursor: 'cursor-stale-${versionCase.incomingVersion}',
          );

          final result = await _coordinator(
            ledger,
            _FakeSyncApi(pages: <SyncPage>[page]),
          ).synchronize();

          expect(result, SyncResult.failed);
          expect((await ledger.readSyncMetadata())?.cursor, expectedCursor);
          expect(
            (await database.select(database.accounts).get()).first.version,
            versionCase.localVersion,
          );
        },
      );
    }

    test('accepts a strictly newer entity version', () async {
      await _seedBootstrap(ledger, bootstrap);
      final page = SyncPage(
        changes: <SyncChangePayload>[
          SyncChangePayload(
            entityType: 'account',
            entityUuid: '30000000-0000-4000-8000-000000000001',
            entityVersion: 2,
            operation: 'update',
            payload: _accountPayload(version: 2),
          ),
        ],
        cursor: 'cursor-newer',
      );

      expect(
        await _coordinator(
          ledger,
          _FakeSyncApi(pages: <SyncPage>[page]),
        ).synchronize(),
        SyncResult.updated,
      );
      expect((await database.select(database.accounts).get()).first.version, 2);
      expect((await ledger.readSyncMetadata())?.cursor, 'cursor-newer');
    });

    test(
      'rejects a repeated cursor on a non-empty page without applying it',
      () async {
        await _seedBootstrap(ledger, bootstrap);
        final repeated = SyncPage(
          changes: <SyncChangePayload>[_transactionChange(0)],
          cursor: bootstrap.cursor,
        );
        final api = _FakeSyncApi(pages: <SyncPage>[repeated]);

        expect(
          await _coordinator(ledger, api).synchronize(),
          SyncResult.failed,
        );
        expect(api.changeCursors, <String>[bootstrap.cursor]);
        expect(
          await database.select(database.transactions).get(),
          hasLength(3),
        );
        expect((await ledger.readSyncMetadata())?.cursor, bootstrap.cursor);
      },
    );

    test('shares one bootstrap chain between simultaneous callers', () async {
      final release = Completer<void>();
      final api = _FakeSyncApi(bootstrap: bootstrap, bootstrapRelease: release);
      final coordinator = _coordinator(ledger, api);

      final first = coordinator.synchronize();
      final second = coordinator.synchronize();
      expect(identical(first, second), isTrue);
      await _eventually(() => api.bootstrapCalls == 1);
      expect(api.maxConcurrentChains, 1);

      release.complete();
      expect(
        await Future.wait(<Future<SyncResult>>[first, second]),
        <SyncResult>[SyncResult.updated, SyncResult.updated],
      );
      expect(api.bootstrapCalls, 1);
      expect(api.maxConcurrentChains, 1);
    });

    test('shares one pull chain between simultaneous callers', () async {
      await _seedBootstrap(ledger, bootstrap);
      final release = Completer<void>();
      final api = _FakeSyncApi(
        pages: const <SyncPage>[
          SyncPage(
            changes: <SyncChangePayload>[],
            cursor: 'cursor-pull-current',
          ),
        ],
        changeRelease: release,
      );
      final coordinator = _coordinator(ledger, api);

      final first = coordinator.synchronize();
      final second = coordinator.synchronize();
      expect(identical(first, second), isTrue);
      await _eventually(() => api.changeCursors.length == 1);
      expect(api.maxConcurrentChains, 1);

      release.complete();
      expect(
        await Future.wait(<Future<SyncResult>>[first, second]),
        <SyncResult>[SyncResult.current, SyncResult.current],
      );
      expect(api.changeCursors, <String>[bootstrap.cursor]);
      expect(api.maxConcurrentChains, 1);
    });

    test('pulls 101 changes over exactly two ordered pages', () async {
      await _seedBootstrap(ledger, bootstrap);
      final firstPage = SyncPage(
        changes: List<SyncChangePayload>.generate(
          DjangoSyncApi.pageSize,
          _transactionChange,
        ),
        cursor: 'cursor-page-100',
      );
      final secondPage = SyncPage(
        changes: <SyncChangePayload>[_transactionChange(100)],
        cursor: 'cursor-page-101',
      );
      final api = _FakeSyncApi(pages: <SyncPage>[firstPage, secondPage]);

      expect(await _coordinator(ledger, api).synchronize(), SyncResult.updated);
      expect(api.changeCursors, <String>[bootstrap.cursor, 'cursor-page-100']);
      expect(
        await database.select(database.transactions).get(),
        hasLength(104),
      );
      expect((await ledger.readSyncMetadata())?.cursor, 'cursor-page-101');
    });

    test(
      'rejects an empty terminal page that regresses to an older cursor',
      () async {
        await _seedBootstrap(ledger, bootstrap);
        final before = await ledger.readSyncMetadata();
        final api = _FakeSyncApi(
          pages: <SyncPage>[
            SyncPage(
              changes: List<SyncChangePayload>.generate(
                DjangoSyncApi.pageSize,
                _transactionChange,
              ),
              cursor: 'cursor-page-b',
            ),
            SyncPage(
              changes: const <SyncChangePayload>[],
              cursor: bootstrap.cursor,
            ),
          ],
        );

        expect(
          await _coordinator(ledger, api).synchronize(),
          SyncResult.failed,
        );
        expect(api.changeCursors, <String>[bootstrap.cursor, 'cursor-page-b']);
        expect(
          await database.select(database.transactions).get(),
          hasLength(3),
        );
        final after = await ledger.readSyncMetadata();
        expect(after?.cursor, before?.cursor);
        expect(after?.lastSuccessAt, before?.lastSuccessAt);
      },
    );

    test(
      'second-page offline failure leaves the whole chain untouched',
      () async {
        await _seedBootstrap(ledger, bootstrap);
        final before = await ledger.readSyncMetadata();
        final api = _FakeSyncApi(
          pages: <SyncPage>[
            SyncPage(
              changes: List<SyncChangePayload>.generate(
                DjangoSyncApi.pageSize,
                _transactionChange,
              ),
              cursor: 'cursor-page-b',
            ),
          ],
          changeErrors: const <int, Object>{1: OfflineFailure()},
        );

        expect(
          await _coordinator(ledger, api).synchronize(),
          SyncResult.offlineWithCache,
        );
        expect(api.changeCursors, <String>[bootstrap.cursor, 'cursor-page-b']);
        expect(
          await database.select(database.transactions).get(),
          hasLength(3),
        );
        final after = await ledger.readSyncMetadata();
        expect(after?.cursor, before?.cursor);
        expect(after?.lastSuccessAt, before?.lastSuccessAt);
      },
    );

    test(
      'uses cache only when its device UUID matches the active session',
      () async {
        await ledger.replaceBootstrap(
          bootstrap,
          DateTime.utc(2026, 8, 14, 12),
          '70000000-0000-4000-8000-000000000099',
        );
        final api = _FakeSyncApi(bootstrap: bootstrap);
        final coordinator = _coordinator(ledger, api);

        expect(await coordinator.hasValidCache(), isFalse);
        expect(await coordinator.synchronize(), SyncResult.updated);
        expect(api.bootstrapCalls, 1);
        expect(
          (await ledger.readSyncMetadata())?.sessionDeviceUuid,
          _deviceUuid,
        );
        expect(await coordinator.hasValidCache(), isTrue);
      },
    );

    test('reports offline with cache without mutating metadata', () async {
      await _seedBootstrap(ledger, bootstrap);
      final before = await ledger.readSyncMetadata();
      final coordinator = _coordinator(
        ledger,
        _FakeSyncApi(changeError: const OfflineFailure()),
      );

      expect(await coordinator.synchronize(), SyncResult.offlineWithCache);
      final after = await ledger.readSyncMetadata();
      expect(after?.cursor, before?.cursor);
      expect(after?.lastSuccessAt, before?.lastSuccessAt);
      expect(coordinator.state.phase, SyncPhase.offline);
      expect(coordinator.state.timestamp, before?.lastSuccessAt);
      expect(await coordinator.state.retry(), SyncResult.offlineWithCache);
    });

    test(
      'same-value session in a new generation cannot commit stale pull work',
      () async {
        await _seedBootstrap(ledger, bootstrap);
        final before = await ledger.readSyncMetadata();
        final store = _MemoryTokenStore(_tokens());
        final authority = SessionAuthority.forStore(store);
        final expectedSession = await authority.snapshot();
        final release = Completer<void>();
        final api = _FakeSyncApi(
          pages: <SyncPage>[
            SyncPage(
              changes: <SyncChangePayload>[_transactionChange(500)],
              cursor: 'cursor-stale-session',
            ),
          ],
          changeRelease: release,
        );
        final coordinator = LedgerSyncCoordinator(
          api: api,
          ledger: ledger,
          sessionAuthority: authority,
          now: () => DateTime.utc(2026, 8, 14, 14),
        );

        final sync = coordinator.synchronize();
        await _eventually(() => api.changeCursors.length == 1);
        await authority.clear();
        final replacement = _tokens();
        await authority.write(replacement);
        expect(
          (await authority.snapshot())?.generation,
          greaterThan(expectedSession!.generation),
        );
        release.complete();

        expect(await sync, SyncResult.failed);
        expect(
          await database.select(database.transactions).get(),
          hasLength(3),
        );
        final after = await ledger.readSyncMetadata();
        expect(after?.cursor, before?.cursor);
        expect(after?.lastSuccessAt, before?.lastSuccessAt);
        expect(await coordinator.hasValidCache(), isFalse);
        _expectSameSessionValues(await store.read(), replacement);
      },
    );

    test(
      'session replacement during a Drift commit rolls back stale bootstrap',
      () async {
        final enteredCommit = Completer<void>();
        final releaseCommit = Completer<void>();
        final pausedLedger = DriftLocalLedger(
          database,
          beforeTransactionCommit: () async {
            enteredCommit.complete();
            await releaseCommit.future;
          },
        );
        final store = _MemoryTokenStore(_tokens());
        final authority = SessionAuthority.forStore(store);
        final expectedSession = await authority.snapshot();
        final coordinator = LedgerSyncCoordinator(
          api: _FakeSyncApi(bootstrap: bootstrap),
          ledger: pausedLedger,
          sessionAuthority: authority,
          now: () => DateTime.utc(2026, 8, 14, 14),
        );

        final sync = coordinator.synchronize();
        await enteredCommit.future;
        await authority.clear();
        final replacement = _tokens();
        await authority.write(replacement);
        expect(
          (await authority.snapshot())?.generation,
          greaterThan(expectedSession!.generation),
        );
        releaseCommit.complete();

        expect(await sync, SyncResult.failed);
        expect(await database.select(database.households).get(), isEmpty);
        expect(await database.select(database.transactions).get(), isEmpty);
        expect(await pausedLedger.readSyncMetadata(), isNull);
        expect(await coordinator.hasValidCache(), isFalse);
        expect(coordinator.lastSuccessfulSession, isNull);
        _expectSameSessionValues(await store.read(), replacement);
      },
    );

    test(
      'session replacement during a Drift delta commit rolls back the chain',
      () async {
        await _seedBootstrap(ledger, bootstrap);
        final before = await ledger.readSyncMetadata();
        final enteredCommit = Completer<void>();
        final releaseCommit = Completer<void>();
        final pausedLedger = DriftLocalLedger(
          database,
          beforeTransactionCommit: () async {
            enteredCommit.complete();
            await releaseCommit.future;
          },
        );
        final store = _MemoryTokenStore(_tokens());
        final authority = SessionAuthority.forStore(store);
        final coordinator = LedgerSyncCoordinator(
          api: _FakeSyncApi(
            pages: <SyncPage>[
              SyncPage(
                changes: <SyncChangePayload>[
                  SyncChangePayload(
                    entityType: 'account',
                    entityUuid: '30000000-0000-4000-8000-000000000001',
                    entityVersion: 2,
                    operation: 'update',
                    payload: _accountPayload(version: 2),
                  ),
                ],
                cursor: 'cursor-stale-delta',
              ),
            ],
          ),
          ledger: pausedLedger,
          sessionAuthority: authority,
          now: () => DateTime.utc(2026, 8, 14, 14),
        );

        final sync = coordinator.synchronize();
        await enteredCommit.future;
        await authority.clear();
        final replacement = _tokens();
        await authority.write(replacement);
        releaseCommit.complete();

        expect(await sync, SyncResult.failed);
        expect(
          (await database.select(database.accounts).get()).first.version,
          1,
        );
        final after = await pausedLedger.readSyncMetadata();
        expect(after?.cursor, before?.cursor);
        expect(after?.lastSuccessAt, before?.lastSuccessAt);
        expect(await coordinator.hasValidCache(), isFalse);
        expect(coordinator.lastSuccessfulSession, isNull);
        _expectSameSessionValues(await store.read(), replacement);
      },
    );

    test(
      'restart keeps a valid cache bound to the persisted session identity',
      () async {
        final file = File('${temporaryDirectory.path}/ledger.sqlite');
        final vault = _SharedTokenVault();
        final firstStore = _VaultTokenStore(vault);
        final firstAuthority = SessionAuthority.forStore(firstStore);
        await firstAuthority.write(_tokens());
        final firstSession = await firstAuthority.snapshot();
        final firstApi = _FakeSyncApi(bootstrap: bootstrap);
        final firstCoordinator = _coordinator(
          ledger,
          firstApi,
          sessionAuthority: firstAuthority,
        );

        expect(await firstCoordinator.synchronize(), SyncResult.updated);
        await database.close();

        final secondStore = _VaultTokenStore(vault);
        final secondAuthority = SessionAuthority.forStore(secondStore);
        final secondSession = await secondAuthority.snapshot();
        final secondDatabase = AppDatabase(NativeDatabase(file));
        addTearDown(secondDatabase.close);
        final secondApi = _FakeSyncApi(
          pages: const <SyncPage>[
            SyncPage(
              changes: <SyncChangePayload>[],
              cursor: 'cursor-after-restart',
            ),
          ],
        );
        final secondCoordinator = _coordinator(
          DriftLocalLedger(secondDatabase),
          secondApi,
          sessionAuthority: secondAuthority,
        );

        expect(secondSession?.sessionIdentity, firstSession?.sessionIdentity);
        expect(await secondCoordinator.hasValidCache(), isTrue);
        expect(await secondCoordinator.synchronize(), SyncResult.current);
        expect(secondApi.bootstrapCalls, 0);
        expect(secondApi.changeCursors, <String>[bootstrap.cursor]);
      },
    );
  });

  group('DjangoSyncApi', () {
    test(
      'maps bootstrap and the encoded cursor to the exact GET routes',
      () async {
        final bootstrapJson = await _fixture('bootstrap.json');
        final transport = _RecordingTransport(<String, Object?>{
          '/bootstrap/': bootstrapJson,
          '/sync/changes/?cursor=cursor+with%2Fslash&limit=100':
              <String, Object?>{
                'changes': <Object?>[],
                'cursor': 'cursor-next',
              },
        });
        final api = DjangoSyncApi(
          SessionTransport(transport: transport, tokenStore: _tokenStore()),
        );

        expect((await api.fetchBootstrap()).transactions, hasLength(3));
        expect(
          (await api.fetchChanges('cursor with/slash')).cursor,
          'cursor-next',
        );
        expect(transport.paths, <String>[
          '/bootstrap/',
          '/sync/changes/?cursor=cursor+with%2Fslash&limit=100',
        ]);
        expect(transport.methods, everyElement('GET'));
        expect(transport.paths, isNot(contains('/sync/push/')));
      },
    );

    test('rejects a malformed cursor response', () {
      expect(
        () => parseSyncPage(<String, Object?>{
          'changes': <Object?>[],
          'cursor': '',
        }),
        throwsFormatException,
      );
    });
  });
}

LedgerSyncCoordinator _coordinator(
  LocalLedger ledger,
  SyncApi api, {
  SessionAuthority? sessionAuthority,
  void Function()? onSessionExpired,
}) {
  return LedgerSyncCoordinator(
    api: api,
    ledger: ledger,
    sessionAuthority:
        sessionAuthority ??
        SessionAuthority.forStore(_MemoryTokenStore(_tokens())),
    onSessionExpired: onSessionExpired,
    now: () => DateTime.utc(2026, 8, 14, 14),
  );
}

Future<Map<String, Object?>> _fixture(String name) async {
  return (jsonDecode(await File('test/fixtures/$name').readAsString()) as Map)
      .cast<String, Object?>();
}

Future<void> _seedBootstrap(LocalLedger ledger, BootstrapPayload bootstrap) {
  return ledger.replaceBootstrap(
    bootstrap,
    DateTime.utc(2026, 8, 14, 12),
    _deviceUuid,
    sessionIdentity: _sessionIdentity,
  );
}

JsonObject _accountPayload({required int version}) => <String, Object?>{
  'uuid': '30000000-0000-4000-8000-000000000001',
  'version': version,
  'created_at': '2026-08-01T09:05:00Z',
  'updated_at': '2026-08-14T13:05:00Z',
  'household_uuid': '10000000-0000-4000-8000-000000000001',
  'financial_owner_uuid': '20000000-0000-4000-8000-000000000001',
  'name': 'Conta versão $version',
  'type': 'checking',
  'initial_balance': '1300.00',
  'currency': 'BRL',
};

SyncChangePayload _transactionChange(int index) {
  final suffix = (index + 1000).toRadixString(16).padLeft(12, '0');
  final uuid = '60000000-0000-4000-8000-$suffix';
  return SyncChangePayload(
    entityType: 'transaction',
    entityUuid: uuid,
    entityVersion: 1,
    operation: 'create',
    payload: <String, Object?>{
      'uuid': uuid,
      'version': 1,
      'created_at': '2026-08-14T13:00:00Z',
      'updated_at': '2026-08-14T13:00:00Z',
      'household_uuid': '10000000-0000-4000-8000-000000000001',
      'financial_owner_uuid': '20000000-0000-4000-8000-000000000001',
      'account_uuid': '30000000-0000-4000-8000-000000000001',
      'category_uuid': '40000000-0000-4000-8000-000000000001',
      'description': 'Transação sintética $index',
      'amount': '1.00',
      'date': '2026-08-14',
      'type': 'expense',
    },
  );
}

Future<void> _eventually(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

final class _FakeSyncApi implements SyncApi {
  _FakeSyncApi({
    this.bootstrap,
    this.bootstrapError,
    this.pages = const <SyncPage>[],
    this.changeError,
    this.changeErrors = const <int, Object>{},
    this.bootstrapRelease,
    this.changeRelease,
  });

  final BootstrapPayload? bootstrap;
  final Object? bootstrapError;
  final List<SyncPage> pages;
  final Object? changeError;
  final Map<int, Object> changeErrors;
  final Completer<void>? bootstrapRelease;
  final Completer<void>? changeRelease;
  final List<String> changeCursors = <String>[];
  int bootstrapCalls = 0;
  int _nextPage = 0;
  int _activeChains = 0;
  int maxConcurrentChains = 0;

  @override
  Future<BootstrapPayload> fetchBootstrap() async {
    bootstrapCalls++;
    _beginChain();
    try {
      await bootstrapRelease?.future;
      if (bootstrapError case final error?) throw error;
      return bootstrap!;
    } finally {
      _activeChains--;
    }
  }

  @override
  Future<SyncPage> fetchChanges(String cursor) async {
    final call = changeCursors.length;
    changeCursors.add(cursor);
    _beginChain();
    try {
      await changeRelease?.future;
      if (changeError case final error?) throw error;
      if (changeErrors[call] case final error?) throw error;
      if (_nextPage >= pages.length) {
        throw StateError('No fake sync page was queued.');
      }
      return pages[_nextPage++];
    } finally {
      _activeChains--;
    }
  }

  void _beginChain() {
    _activeChains++;
    if (_activeChains > maxConcurrentChains) {
      maxConcurrentChains = _activeChains;
    }
  }
}

final class _RecordingTransport implements ApiTransport {
  _RecordingTransport(this.responses);

  final Map<String, Object?> responses;
  final List<String> paths = <String>[];
  final List<String> methods = <String>[];

  @override
  Future<ApiResponse> request(
    String path, {
    required String method,
    Object? data,
    String? bearerToken,
  }) async {
    paths.add(path);
    methods.add(method);
    if (!responses.containsKey(path)) {
      throw StateError('Unexpected path: $path');
    }
    return ApiResponse(statusCode: 200, data: responses[path]);
  }
}

TokenStore _tokenStore() => _MemoryTokenStore(_tokens());

StoredTokens _tokens() => StoredTokens(
  accessToken: 'synthetic-access',
  accessExpiresAt: DateTime.utc(2030),
  refreshToken: 'synthetic-refresh',
  refreshExpiresAt: DateTime.utc(2031),
  deviceUuid: _deviceUuid,
  sessionIdentity: _sessionIdentity,
);

void _expectSameSessionValues(StoredTokens? actual, StoredTokens expected) {
  expect(actual?.accessToken, expected.accessToken);
  expect(actual?.accessExpiresAt, expected.accessExpiresAt);
  expect(actual?.refreshToken, expected.refreshToken);
  expect(actual?.refreshExpiresAt, expected.refreshExpiresAt);
  expect(actual?.deviceUuid, expected.deviceUuid);
  expect(actual?.sessionIdentity, isNotEmpty);
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

final class _SharedTokenVault {
  StoredTokens? value;
}

final class _VaultTokenStore implements TokenStore {
  _VaultTokenStore(this.vault);

  final _SharedTokenVault vault;

  @override
  Future<void> clear() async => vault.value = null;

  @override
  Future<StoredTokens?> read() async => vault.value;

  @override
  Future<void> write(StoredTokens tokens) async => vault.value = tokens;
}
