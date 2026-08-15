import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmark_home.dart';

void main() {
  test('builds the exact synthetic warm-cache benchmark volume', () {
    final dataset = buildBenchmarkDataset(DateTime.utc(2026, 8, 14));

    expect(dataset.payload.accounts, hasLength(20));
    expect(dataset.payload.categories, hasLength(50));
    expect(dataset.payload.transactions, hasLength(10000));
    expect(dataset.payload.owners, hasLength(3));
    expect(dataset.payload.household['name'], 'Lar sintético de benchmark');
    expect(
      dataset.payload.transactions.every(
        (transaction) =>
            (transaction['description'] as String).startsWith('Sintética '),
      ),
      isTrue,
    );
  });

  test('summarizes ten iterations with median and nearest-rank p95', () {
    final summary = summarizeBenchmark(<Duration>[
      const Duration(milliseconds: 100),
      const Duration(milliseconds: 200),
      const Duration(milliseconds: 300),
      const Duration(milliseconds: 400),
      const Duration(milliseconds: 500),
      const Duration(milliseconds: 600),
      const Duration(milliseconds: 700),
      const Duration(milliseconds: 800),
      const Duration(milliseconds: 900),
      const Duration(milliseconds: 1000),
    ]);

    expect(summary.iterations, 10);
    expect(summary.median, const Duration(milliseconds: 550));
    expect(summary.p95, const Duration(milliseconds: 1000));
    expect(summary.accepted, isTrue);
  });

  test('rejects benchmark results with fewer than ten iterations', () {
    expect(
      () => summarizeBenchmark(List<Duration>.filled(9, Duration.zero)),
      throwsArgumentError,
    );
  });
}
