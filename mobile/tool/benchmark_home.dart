import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:lar_finance/core/storage/app_database.dart';
import 'package:lar_finance/core/storage/local_ledger.dart';
import 'package:lar_finance/core/sync/sync_models.dart';
import 'package:lar_finance/core/sync/sync_state.dart';
import 'package:lar_finance/design_system/lar_theme.dart';
import 'package:lar_finance/features/home/application/home_controller.dart';
import 'package:lar_finance/features/home/data/home_repository.dart';
import 'package:lar_finance/features/home/presentation/home_screen.dart';

const benchmarkAccountCount = 20;
const benchmarkCategoryCount = 50;
const benchmarkTransactionCount = 10000;
const benchmarkIterationCount = 10;
const benchmarkAcceptance = Duration(seconds: 2);

Future<void> main() async {
  final launchStopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    stderr.writeln(
      'The Home benchmark is valid only in a Windows profile or release build.',
    );
    exitCode = 64;
    return;
  }
  if (!Platform.isWindows) {
    stderr.writeln('The Sprint 4 reference benchmark must run on Windows.');
    exitCode = 64;
    return;
  }

  await initializeDateFormatting('pt_BR');
  final benchmarkDate = DateTime.now();
  final databaseFile = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'lar_finance_task9_benchmark.sqlite',
  );
  if (!databaseFile.existsSync()) {
    final dataset = buildBenchmarkDataset(benchmarkDate);
    await seedBenchmarkDatabase(databaseFile, dataset, benchmarkDate);
  }
  runApp(
    _BenchmarkApplication(
      databaseFile: databaseFile,
      benchmarkDate: benchmarkDate,
      launchStopwatch: launchStopwatch,
    ),
  );
}

final class BenchmarkDataset {
  const BenchmarkDataset({required this.payload});

  final BootstrapPayload payload;
}

final class BenchmarkSummary {
  const BenchmarkSummary({
    required this.iterations,
    required this.median,
    required this.p95,
    required this.accepted,
  });

  final int iterations;
  final Duration median;
  final Duration p95;
  final bool accepted;

  Map<String, Object?> toJson({required List<Duration> samples}) =>
      <String, Object?>{
        'iterations': iterations,
        'samples_us': samples
            .map((sample) => sample.inMicroseconds)
            .toList(growable: false),
        'median_us': median.inMicroseconds,
        'p95_us': p95.inMicroseconds,
        'accepted': accepted,
        'acceptance_us': benchmarkAcceptance.inMicroseconds,
      };
}

BenchmarkDataset buildBenchmarkDataset(DateTime benchmarkDate) {
  const householdUuid = '10000000-0000-4000-8000-000000000001';
  final timestamp = benchmarkDate.toUtc().toIso8601String();
  const ownerUuids = <String>[
    '20000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000003',
  ];
  const owners = <JsonObject>[
    <String, Object?>{
      'uuid': '20000000-0000-4000-8000-000000000001',
      'type': 'self',
      'name': 'Pessoa sintética A',
    },
    <String, Object?>{
      'uuid': '20000000-0000-4000-8000-000000000002',
      'type': 'spouse',
      'name': 'Pessoa sintética B',
    },
    <String, Object?>{
      'uuid': '20000000-0000-4000-8000-000000000003',
      'type': 'shared',
      'name': 'Conjunto sintético',
    },
  ];
  final accounts = List<JsonObject>.generate(benchmarkAccountCount, (index) {
    final ownerUuid = ownerUuids[index % ownerUuids.length];
    return <String, Object?>{
      'uuid': _syntheticUuid(3, index + 1),
      'household_uuid': householdUuid,
      'financial_owner_uuid': ownerUuid,
      'name': 'Conta sintética ${index + 1}',
      'type': index.isEven ? 'checking' : 'savings',
      'initial_balance': '${1000 + index}.00',
      'currency': 'BRL',
      'version': 1,
      'created_at': timestamp,
      'updated_at': timestamp,
    };
  }, growable: false);
  final categories = List<JsonObject>.generate(benchmarkCategoryCount, (index) {
    final income = index >= benchmarkCategoryCount - 5;
    return <String, Object?>{
      'uuid': _syntheticUuid(4, index + 1),
      'household_uuid': householdUuid,
      'name': 'Categoria sintética ${index + 1}',
      'type': income ? 'income' : 'expense',
      'color': income ? '#2F756A' : '#8B6F47',
      'icon': null,
      'version': 1,
      'created_at': timestamp,
      'updated_at': timestamp,
    };
  }, growable: false);
  final transactions = List<JsonObject>.generate(benchmarkTransactionCount, (
    index,
  ) {
    final accountIndex = index % accounts.length;
    final income = index % 20 == 0;
    final categoryIndex = income
        ? benchmarkCategoryCount - 1 - (index % 5)
        : index % (benchmarkCategoryCount - 5);
    final transactionDate = DateTime(
      benchmarkDate.year,
      benchmarkDate.month,
      1 + (index % 28),
    );
    return <String, Object?>{
      'uuid': _syntheticUuid(5, index + 1),
      'household_uuid': householdUuid,
      'financial_owner_uuid': accounts[accountIndex]['financial_owner_uuid'],
      'account_uuid': accounts[accountIndex]['uuid'],
      'category_uuid': categories[categoryIndex]['uuid'],
      'description': 'Sintética ${index + 1}',
      'amount': _minorUnitsAsDecimal(100 + (index % 100000)),
      'date': _dateOnly(transactionDate),
      'type': income ? 'income' : 'expense',
      'version': 1,
      'created_at': timestamp,
      'updated_at': timestamp,
    };
  }, growable: false);
  return BenchmarkDataset(
    payload: BootstrapPayload(
      household: <String, Object?>{
        'uuid': householdUuid,
        'name': 'Lar sintético de benchmark',
        'updated_at': timestamp,
      },
      owners: owners,
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      cursor: 'synthetic-benchmark-cursor',
    ),
  );
}

BenchmarkSummary summarizeBenchmark(List<Duration> samples) {
  if (samples.length < benchmarkIterationCount) {
    throw ArgumentError.value(
      samples.length,
      'samples.length',
      'at least $benchmarkIterationCount iterations are required',
    );
  }
  final sorted = List<Duration>.of(samples)
    ..sort((left, right) => left.compareTo(right));
  final middle = sorted.length ~/ 2;
  final median = sorted.length.isOdd
      ? sorted[middle]
      : Duration(
          microseconds:
              (sorted[middle - 1].inMicroseconds +
                  sorted[middle].inMicroseconds) ~/
              2,
        );
  final p95Index = math.max(0, (sorted.length * 0.95).ceil() - 1);
  final p95 = sorted[p95Index];
  return BenchmarkSummary(
    iterations: samples.length,
    median: median,
    p95: p95,
    accepted: median < benchmarkAcceptance,
  );
}

Future<void> seedBenchmarkDatabase(
  File databaseFile,
  BenchmarkDataset dataset,
  DateTime benchmarkDate,
) async {
  final database = AppDatabase(NativeDatabase(databaseFile));
  try {
    await DriftLocalLedger(database).replaceBootstrap(
      dataset.payload,
      benchmarkDate.toUtc(),
      '60000000-0000-4000-8000-000000000001',
      sessionGeneration: 1,
      sessionIdentity: 'synthetic-benchmark-session',
      isSessionCurrent: () => true,
    );
  } finally {
    await database.close();
  }
}

final class _BenchmarkApplication extends StatefulWidget {
  const _BenchmarkApplication({
    required this.databaseFile,
    required this.benchmarkDate,
    required this.launchStopwatch,
  });

  final File databaseFile;
  final DateTime benchmarkDate;
  final Stopwatch launchStopwatch;

  @override
  State<_BenchmarkApplication> createState() => _BenchmarkApplicationState();
}

final class _BenchmarkApplicationState extends State<_BenchmarkApplication> {
  Widget _home = const _BenchmarkProgress();
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lar Finance benchmark',
    theme: LarTheme.light,
    debugShowCheckedModeBanner: false,
    home: _home,
  );

  Future<void> _run() async {
    if (_started) return;
    _started = true;
    if (!mounted) return;
    final database = AppDatabase(NativeDatabase(widget.databaseFile));
    final syncState = SyncState(retry: () async => SyncResult.current)
      ..markCurrent(widget.benchmarkDate.toUtc());
    final controller = HomeController(
      repository: DriftHomeRepository(database),
      syncState: syncState,
      now: () => widget.benchmarkDate,
    );
    final populatedFrame = Completer<void>();
    var frameScheduled = false;
    void onHomeChanged() {
      if (frameScheduled || controller.state.snapshot == null) return;
      frameScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!populatedFrame.isCompleted) populatedFrame.complete();
      });
    }

    controller.addListener(onHomeChanged);
    setState(() => _home = HomeScreen(controller: controller));
    await populatedFrame.future.timeout(const Duration(seconds: 20));
    widget.launchStopwatch.stop();
    final marker = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'lar_finance_task9_benchmark.ready.json',
    );
    await marker.writeAsString(
      jsonEncode(<String, Object?>{
        'ready': true,
        'process_id': pid,
        'internal_us': widget.launchStopwatch.elapsedMicroseconds,
      }),
      flush: true,
    );
    controller.removeListener(onHomeChanged);
    controller.dispose();
    syncState.dispose();
    await database.close();
    exit(0);
  }
}

final class _BenchmarkProgress extends StatelessWidget {
  const _BenchmarkProgress();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('Preparando Home do benchmark')));
}

String _syntheticUuid(int family, int index) =>
    '${family.toString().padLeft(8, '0')}-0000-4000-8000-'
    '${index.toString().padLeft(12, '0')}';

String _minorUnitsAsDecimal(int minorUnits) {
  final whole = minorUnits ~/ 100;
  final fraction = (minorUnits % 100).toString().padLeft(2, '0');
  return '$whole.$fraction';
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
