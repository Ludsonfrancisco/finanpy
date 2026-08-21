# Exact Flutter Money Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every monetary `double` in Flutter cards and bills with exact integer minor units while preserving the Django `Decimal` HTTP contract and the approved Casa de Valores interface.

**Architecture:** Extend the existing pure money boundary with exact API, pt-BR input, editable, and display conversions. Migrate cards first and bills second so each vertical slice compiles, has its own RED/GREEN cycle, and sends decimal strings only at the HTTP edge. Finish with source-boundary scans, backend cent-level contract tests, unchanged goldens, full builds, documentation, commit, push, and remote CI.

**Tech Stack:** Flutter 3.47.0, Dart 3.13.0, Django 5.2.13, `flutter_test`, `intl`, integer minor units, Django `Decimal`.

## Global Constraints

- The approved design is `docs/superpowers/specs/2026-08-20-exact-money-flutter-design.md`.
- Do not add a `Money` class or a decimal package.
- Monetary domain, repository, controller, and form values use `int` with a `Minor` suffix.
- API money remains a JSON string with exactly two decimal places.
- User input accepts `1234`, `1234,5`, `1234,56`, `1.234,56`, and optional `R$`; invalid grouping or more than two fractional digits is rejected.
- Never round silently and never use `double.parse`, `double.tryParse`, `toStringAsFixed`, or division by `100.0` for money.
- `double` remains allowed for percentages, animation, dimensions, and Flutter graphics APIs.
- Backend authorization, models, migrations, financial rules, and sync scope do not change.
- Web and Flutter remain Casa de Valores 2.0; never introduce purple.
- Work only inside roadmap item R1.3. Do not start R1.4.

---

### Task 1: Complete the exact money boundary

**Files:**
- Modify: `mobile/lib/core/money/minor_units.dart`
- Modify: `mobile/test/core/money/minor_units_test.dart`

**Interfaces:**
- Consumes: existing `int parseMinorUnits(String value)`.
- Produces: `int parseApiMinorUnits(Object? value)`, `int parsePtBrMinorUnits(String value)`, `String minorUnitsToApiDecimal(int value)`, `String minorUnitsToPtBrInput(int value)`, and `String formatBrlMinorUnits(int value)`.

- [ ] **Step 1: Write RED tests for the exact public boundary**

Append tests equivalent to:

```dart
test('requires API money to be a canonical two-place string', () {
  expect(parseApiMinorUnits('0.01'), 1);
  expect(parseApiMinorUnits('90071992547409.91'), 9007199254740991);
  expect(() => parseApiMinorUnits(null), throwsFormatException);
  expect(() => parseApiMinorUnits(1.01), throwsFormatException);
  expect(() => parseApiMinorUnits('1.0'), throwsFormatException);
  expect(() => parseApiMinorUnits('1e3'), throwsFormatException);
});

test('parses approved pt-BR input without rounding', () {
  expect(parsePtBrMinorUnits('1234'), 123400);
  expect(parsePtBrMinorUnits('1234,5'), 123450);
  expect(parsePtBrMinorUnits('1234,56'), 123456);
  expect(parsePtBrMinorUnits('1.234,56'), 123456);
  expect(parsePtBrMinorUnits(' R\$ 1.234,56 '), 123456);
});

test('rejects ambiguous or over-precise pt-BR input', () {
  for (final value in <String>[
    '',
    '-1,00',
    '1,234',
    '12.34,56',
    '1.23.4,56',
    '1e3',
    'R\$ texto',
  ]) {
    expect(() => parsePtBrMinorUnits(value), throwsFormatException);
  }
});

test('serializes and formats minor units exactly', () {
  expect(minorUnitsToApiDecimal(0), '0.00');
  expect(minorUnitsToApiDecimal(1), '0.01');
  expect(minorUnitsToApiDecimal(105), '1.05');
  expect(minorUnitsToApiDecimal(-1205), '-12.05');
  expect(minorUnitsToPtBrInput(123456), '1234,56');
  expect(formatBrlMinorUnits(123456), r'R$ 1.234,56');
  expect(formatBrlMinorUnits(-1205), r'-R$ 12,05');
});
```

- [ ] **Step 2: Run the focused test and record RED**

Run:

```powershell
cd mobile
flutter test test/core/money/minor_units_test.dart -r expanded
```

Expected: compile failure because the five new functions do not exist.

- [ ] **Step 3: Implement the pure integer conversions**

Keep `parseMinorUnits` and add this behavior without floating point:

```dart
final RegExp _ptBrMoneyPattern = RegExp(
  r'^(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?$',
);

int parseApiMinorUnits(Object? value) {
  if (value is! String) {
    throw const FormatException('Expected a decimal string.');
  }
  return parseMinorUnits(value);
}

int parsePtBrMinorUnits(String value) {
  var normalized = value.trim();
  if (normalized.startsWith(r'R$')) {
    normalized = normalized.substring(2).trimLeft();
  }
  final match = _ptBrMoneyPattern.firstMatch(normalized);
  if (match == null) {
    throw const FormatException('Expected a positive pt-BR money value.');
  }
  final whole = int.parse(match.group(1)!.replaceAll('.', ''));
  final rawFraction = match.group(2) ?? '';
  final fraction = rawFraction.isEmpty
      ? 0
      : int.parse(rawFraction.padRight(2, '0'));
  return whole * 100 + fraction;
}

String minorUnitsToApiDecimal(int value) {
  final negative = value < 0;
  final magnitude = value.abs();
  final whole = magnitude ~/ 100;
  final fraction = (magnitude % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$fraction';
}

String minorUnitsToPtBrInput(int value) =>
    minorUnitsToApiDecimal(value).replaceFirst('.', ',');

String formatBrlMinorUnits(int value) {
  final negative = value < 0;
  final magnitude = value.abs();
  final whole = _groupThousands((magnitude ~/ 100).toString());
  final fraction = (magnitude % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}R\$ $whole,$fraction';
}

String _groupThousands(String digits) {
  final firstGroup = digits.length % 3;
  final parts = <String>[];
  var index = 0;
  if (firstGroup != 0) {
    parts.add(digits.substring(0, firstGroup));
    index = firstGroup;
  }
  while (index < digits.length) {
    parts.add(digits.substring(index, index + 3));
    index += 3;
  }
  return parts.join('.');
}
```

- [ ] **Step 4: Run GREEN and core regressions**

Run:

```powershell
cd mobile
dart format lib/core/money test/core/money
flutter test test/core/money test/core/storage -r expanded
flutter analyze
```

Expected: all money/storage tests pass and analyze reports no issues.

- [ ] **Step 5: Review, commit, and push the boundary**

Run:

```powershell
git diff --check
git add mobile/lib/core/money/minor_units.dart mobile/test/core/money/minor_units_test.dart
git commit -m "feat(mobile): add exact money boundary"
git push origin main
```

Expected: only the two declared files are committed and `main...origin/main` is `0 0`.

---

### Task 2: Migrate cards from `double` to minor units

**Files:**
- Modify: `mobile/lib/features/cards/domain/cards_models.dart`
- Modify: `mobile/lib/features/cards/data/cards_repository.dart`
- Modify: `mobile/lib/features/cards/application/cards_controller.dart`
- Modify: `mobile/lib/features/cards/presentation/cards_screen.dart`
- Modify: `mobile/lib/features/cards/presentation/widgets/card_item_widget.dart`
- Modify: `mobile/lib/features/cards/presentation/widgets/card_form_sheet.dart`
- Modify: `mobile/lib/features/cards/presentation/widgets/card_expense_sheet.dart`
- Modify: `mobile/lib/features/cards/presentation/widgets/pay_invoice_sheet.dart`
- Create: `mobile/test/support/recording_session_transport.dart`
- Create: `mobile/test/features/cards/cards_exact_money_test.dart`
- Modify: `mobile/test/features/cards/cards_screen_test.dart`

**Interfaces:**
- Consumes: all five functions produced by Task 1.
- Produces: cards domain fields `limitMinor`, `availableLimitMinor`, `unpaidExpensesTotalMinor`, `currentInvoiceTotalMinor`, `amountMinor`, `totalAmountMinor`, `paidAmountMinor`, `totalLimitMinor`, `totalUsedMinor`, `totalAvailableMinor`, `totalCurrentInvoicesMinor`; repository/controller parameters with matching `Minor` names. `limitUsagePercent` remains `double`.

- [ ] **Step 1: Write RED domain tests for every card money field**

Create `cards_exact_money_test.dart` with fixtures that assert:

```dart
test('card JSON keeps every cent and percentage stays double', () {
  final card = CreditCardModel.fromJson(<String, dynamic>{
    'id': 1,
    'name': 'Casa',
    'limit': '10000.01',
    'available_limit': '9999.99',
    'unpaid_expenses_total': '0.02',
    'current_invoice_total': '0.01',
    'limit_usage_percent': 12.5,
    'closing_day': 10,
    'due_day': 17,
    'color': '#2F756A',
    'brand': 'visa',
    'brand_display': 'Visa',
    'last_digits': '1234',
    'is_active': true,
    'financial_owner_id': 1,
    'financial_owner_type': 'self',
    'financial_owner_name': 'Eu',
  });
  expect(card.limitMinor, 1000001);
  expect(card.availableLimitMinor, 999999);
  expect(card.unpaidExpensesTotalMinor, 2);
  expect(card.currentInvoiceTotalMinor, 1);
  expect(card.limitUsagePercent, 12.5);
});

test('expense invoice and summary JSON use minor units', () {
  expect(CardExpenseModel.fromJson(expenseJson('0.01')).amountMinor, 1);
  final invoice = CardInvoiceModel.fromJson(invoiceJson('10.01', '0.01'));
  expect(invoice.totalAmountMinor, 1001);
  expect(invoice.paidAmountMinor, 1);
  final summary = CardsSummaryModel.fromJson(summaryJson());
  expect(summary.totalLimitMinor, 1000001);
  expect(summary.totalUsedMinor, 2);
  expect(summary.totalAvailableMinor, 999999);
  expect(summary.totalCurrentInvoicesMinor, 1);
});

test('malformed card money never becomes zero', () {
  final json = validCardJson()..['limit'] = '1.001';
  expect(() => CreditCardModel.fromJson(json), throwsFormatException);
  final numeric = validCardJson()..['limit'] = 1.01;
  expect(() => CreditCardModel.fromJson(numeric), throwsFormatException);
});
```

Define the fixtures in the same file exactly as complete maps (the `Object?`
parameters are intentional so numeric-money rejection is exercised at runtime):

```dart
Map<String, dynamic> validCardJson({Object? limit = '10000.01'}) =>
    <String, dynamic>{
      'id': 1,
      'name': 'Casa',
      'limit': limit,
      'available_limit': '9999.99',
      'unpaid_expenses_total': '0.02',
      'current_invoice_total': '0.01',
      'limit_usage_percent': 12.5,
      'closing_day': 10,
      'due_day': 17,
      'color': '#2F756A',
      'brand': 'visa',
      'brand_display': 'Visa',
      'last_digits': '1234',
      'is_active': true,
      'financial_owner_id': 1,
      'financial_owner_type': 'self',
      'financial_owner_name': 'Eu',
    };

Map<String, dynamic> expenseJson(Object? amount) => <String, dynamic>{
  'id': 2,
  'card_id': 1,
  'card_name': 'Casa',
  'invoice_id': 3,
  'description': 'Teste',
  'amount': amount,
  'date': '2026-08-20',
  'category_id': 4,
  'category_name': 'Geral',
  'financial_owner_id': 1,
  'financial_owner_type': 'self',
  'financial_owner_name': 'Eu',
  'installments_count': 1,
  'installment_number': 1,
  'installment_group_id': '00000000-0000-4000-8000-000000000001',
};

Map<String, dynamic> invoiceJson(Object? total, Object? paid) =>
    <String, dynamic>{
      'id': 3,
      'card_id': 1,
      'card_name': 'Casa',
      'month': 8,
      'year': 2026,
      'closing_date': '2026-08-10',
      'due_date': '2026-08-17',
      'status': 'open',
      'status_display': 'Aberta',
      'total_amount': total,
      'paid_amount': paid,
      'paid_at': null,
      'payment_account_id': null,
      'payment_account_name': null,
      'expenses_count': 0,
      'expenses': <Object?>[],
    };

Map<String, dynamic> summaryJson() => <String, dynamic>{
  'month': 8,
  'year': 2026,
  'total_limit': '10000.01',
  'total_used': '0.02',
  'total_available': '9999.99',
  'total_current_invoices': '0.01',
  'limit_usage_percent': 12.5,
};
```

- [ ] **Step 2: Run the card domain tests and record RED**

Run:

```powershell
cd mobile
flutter test test/features/cards/cards_exact_money_test.dart -r expanded
```

Expected: compile failures because the `*Minor` fields do not exist.

- [ ] **Step 3: Migrate card models exactly**

In `cards_models.dart`:

- import `../../../core/money/minor_units.dart`;
- rename all monetary constructor parameters and fields to the `*Minor` names listed in **Interfaces**;
- parse each JSON monetary value with `parseApiMinorUnits(json['field'])`;
- keep `limitUsagePercent` as `(json['limit_usage_percent'] as num?)?.toDouble() ?? 0.0`;
- make `CardsSummaryModel.empty` use integer zeroes;
- do not accept a numeric JSON fallback or default malformed money to zero.

Run the focused test again. Expected: domain tests pass while repository/widget compilation still fails, proving consumers must migrate.

- [ ] **Step 4: Add deterministic transport support and write RED repository payload tests**

Create `mobile/test/support/recording_session_transport.dart` with this exact
test-only boundary, then use it from cards and later bills:

```dart
import 'package:lar_finance/core/network/dio_transport.dart';
import 'package:lar_finance/core/network/session_transport.dart';
import 'package:lar_finance/features/auth/domain/session.dart';

final class RecordedApiRequest {
  const RecordedApiRequest({
    required this.path,
    required this.method,
    required this.data,
  });
  final String path;
  final String method;
  final Object? data;
}

final class RecordingApiTransport implements ApiTransport {
  RecordingApiTransport(this.respond);
  final Future<ApiResponse> Function(RecordedApiRequest request) respond;
  final List<RecordedApiRequest> requests = <RecordedApiRequest>[];

  @override
  Future<ApiResponse> request(
    String path, {
    required String method,
    Object? data,
    String? bearerToken,
  }) {
    final request = RecordedApiRequest(
      path: path,
      method: method,
      data: data,
    );
    requests.add(request);
    return respond(request);
  }
}

final class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([StoredTokens? initial]) : value = initial ?? testTokens();
  StoredTokens? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<StoredTokens?> read() async => value;
  @override
  Future<void> write(StoredTokens tokens) async => value = tokens;
}

StoredTokens testTokens() => StoredTokens(
  accessToken: 'access-test',
  accessExpiresAt: DateTime.utc(2030, 1, 1),
  refreshToken: 'refresh-test',
  refreshExpiresAt: DateTime.utc(2030, 2, 1),
  deviceUuid: '11111111-1111-4111-8111-111111111111',
);

SessionTransport recordingSessionTransport(RecordingApiTransport transport) =>
    SessionTransport(transport: transport, tokenStore: MemoryTokenStore());
```

In `cards_exact_money_test.dart`, construct `HttpCardsRepository` from
`recordingSessionTransport`. The responder must return `validCardJson()` for
card endpoints, `<String, Object?>{'expenses': [expenseJson('0.03')]}` for
expense creation, and `invoiceJson('0.01', '0.01')` for invoice payment. Add
these four assertions:

```dart
await repository.createCard(
  name: 'Casa',
  limitMinor: 1000001,
  closingDay: 10,
  dueDay: 17,
);
expect(recording.singleData['limit'], '10000.01');

await repository.updateCard(1, limitMinor: 1);
expect(recording.singleData['limit'], '0.01');

await repository.createExpense(
  cardId: 1,
  description: 'Teste',
  amountMinor: 3,
  date: DateTime(2026, 8, 20),
  categoryId: 1,
  installmentsCount: 3,
);
expect(recording.singleData['amount'], '0.03');

await repository.payInvoice(
  1,
  accountId: 1,
  paidAmountMinor: 1,
  paymentDate: DateTime(2026, 8, 20),
);
expect(recording.singleData['paid_amount'], '0.01');
```

Each recording response must return a valid strict card/expense/invoice JSON fixture so parsing is also exercised.

- [ ] **Step 5: Run repository RED, then migrate repository and controller**

Run the new tests and confirm compile failure on `limitMinor`, `amountMinor`, and `paidAmountMinor`. Then:

- change `CardsRepository`, `HttpCardsRepository`, and `CardsController` create/update/pay signatures from monetary `double` to the exact `int ...Minor` names;
- serialize only with `minorUnitsToApiDecimal`;
- keep dates, IDs, installments, and `limitUsagePercent` unchanged;
- never place an integer, `double`, or formatted BRL string in an API money field.

Run:

```powershell
flutter test test/features/cards/cards_exact_money_test.dart -r expanded
```

Expected: domain and repository tests pass; widget tests still fail to compile until the presentation migration.

- [ ] **Step 6: Write RED widget tests for exact card entry and display**

Extend `cards_screen_test.dart` and/or `cards_exact_money_test.dart` to prove:

```dart
expect(find.text(r'R$ 10.000,01'), findsWidgets);
expect(find.text(r'R$ 0,01'), findsWidgets);
```

Pump each sheet, enter `R$ 1.234,56`, submit, and capture the callback/repository argument:

```dart
expect(capturedLimitMinor, 123456);
expect(capturedExpenseMinor, 123456);
expect(capturedPaidAmountMinor, 123456);
```

Enter `1,234` and assert the validator is shown and no repository call occurs.
Repeat with `0`, `0,00`, and `-1,00`; positive create, expense, and payment
forms must reject each value before calling the controller.

Add a controller regression with a repository fake that first returns a valid
`CardsSnapshot` and then throws `FormatException` while refreshing. Assert that
`CardsState.cards`, `summary`, and the selected card still reference the last
valid snapshot and that only the existing error state changes. This proves a
malformed API amount cannot silently replace cached UI values.

- [ ] **Step 7: Migrate card presentation and make widgets GREEN**

Apply these exact conversions:

- `CardFormSheet`: `_parsedLimitMinor` calls `parsePtBrMinorUnits`; initial text calls `minorUnitsToPtBrInput`; callbacks use `limitMinor`;
- `CardExpenseSheet`: `_parsedAmountMinor` calls `parsePtBrMinorUnits`; callback uses `amountMinor`;
- `PayInvoiceSheet`: initial text uses `invoice.totalAmountMinor`; parsed value and callback use `paidAmountMinor`;
- account balances already stored as `currentBalanceMinor`; display with `formatBrlMinorUnits` instead of `/ 100.0`;
- `CardsScreen` and `CardItemWidget`: replace money `NumberFormat.currency(...).format(double)` calls with `formatBrlMinorUnits(int)`;
- keep progress values and percent labels based on `limitUsagePercent` as `double`.

Run:

```powershell
dart format lib/features/cards test/features/cards
flutter test test/features/cards -r expanded
flutter analyze
```

Expected: all card tests pass and analyze reports no issues.

- [ ] **Step 8: Review, commit, and push cards**

Run:

```powershell
rg -n "double\.tryParse|toStringAsFixed|/ 100\.0" mobile/lib/features/cards
git diff --check
git add mobile/lib/features/cards mobile/test/features/cards mobile/test/support/recording_session_transport.dart
git commit -m "refactor(cards): use exact minor units"
git push origin main
```

Expected: `rg` returns no monetary conversion matches; `double.infinity` and `limitUsagePercent` remain valid and are not removed.

---

### Task 3: Migrate bills from `double` to minor units

**Files:**
- Modify: `mobile/lib/features/bills/domain/bills_models.dart`
- Modify: `mobile/lib/features/bills/data/bills_repository.dart`
- Modify: `mobile/lib/features/bills/application/bills_controller.dart`
- Modify: `mobile/lib/features/bills/presentation/bills_screen.dart`
- Modify: `mobile/lib/features/bills/presentation/widgets/bill_form_sheet.dart`
- Modify: `mobile/lib/features/bills/presentation/widgets/pay_bill_sheet.dart`
- Create: `mobile/test/features/bills/bills_exact_money_test.dart`
- Modify: `mobile/test/features/bills/bills_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 exact money functions.
- Produces: `BillInstanceModel.amountMinor`, `RecurringBillModel.amountMinor`, `BillsMetricsModel.pendingExpensesTotalMinor`, `paidExpensesTotalMinor`, `totalCommittedMinor`, `totalAccountBalanceMinor`, `freeCashBalanceMinor`; repository/controller arguments `amountMinor` and `paidAmountMinor`.

- [ ] **Step 1: Write RED domain tests for every bill money field**

Create `bills_exact_money_test.dart` with strict fixtures:

```dart
test('bill instance and recurring rule preserve one cent', () {
  expect(BillInstanceModel.fromJson(instanceJson('0.01')).amountMinor, 1);
  expect(RecurringBillModel.fromJson(ruleJson('10000.01')).amountMinor, 1000001);
});

test('bill metrics preserve all exact totals', () {
  final metrics = BillsMetricsModel.fromJson(<String, Object?>{
    'month': 8,
    'year': 2026,
    'pending_expenses_total': '0.01',
    'paid_expenses_total': '0.02',
    'total_committed': '0.03',
    'overdue_count': 1,
    'due_today_count': 2,
    'total_account_balance': '10000.01',
    'free_cash_balance': '9999.98',
  });
  expect(metrics.pendingExpensesTotalMinor, 1);
  expect(metrics.paidExpensesTotalMinor, 2);
  expect(metrics.totalCommittedMinor, 3);
  expect(metrics.totalAccountBalanceMinor, 1000001);
  expect(metrics.freeCashBalanceMinor, 999998);
});

test('malformed bill money never becomes zero', () {
  expect(
    () => RecurringBillModel.fromJson(ruleJson('1.001')),
    throwsFormatException,
  );
  expect(
    () => RecurringBillModel.fromJson(ruleJson(1.01)),
    throwsFormatException,
  );
});
```

Define both fixtures in the same file, with `Object?` money parameters so the
numeric rejection is a real runtime test:

```dart
Map<String, Object?> instanceJson(Object? amount) => <String, Object?>{
  'id': 1,
  'bill_id': 2,
  'name': 'Internet',
  'month': 8,
  'year': 2026,
  'due_date': '2026-08-10',
  'due_day': 10,
  'amount': amount,
  'status': 'pending',
  'paid_at': null,
  'type': 'expense',
  'category_name': 'Casa',
  'category_id': 3,
  'account_name': null,
  'account_id': null,
  'default_account_id': 4,
  'financial_owner_type': 'self',
  'financial_owner_name': 'Eu',
};

Map<String, Object?> ruleJson(Object? amount) => <String, Object?>{
  'id': 2,
  'name': 'Internet',
  'amount': amount,
  'due_day': 10,
  'type': 'expense',
  'category_id': 3,
  'category_name': 'Casa',
  'default_account_id': 4,
  'default_account_name': 'Conta',
  'financial_owner_type': 'self',
  'financial_owner_name': 'Eu',
  'is_active': true,
  'notes': '',
};
```

- [ ] **Step 2: Run domain RED, then migrate bill models**

Run:

```powershell
cd mobile
flutter test test/features/bills/bills_exact_money_test.dart -r expanded
```

Expected: compile failure for missing `*Minor` fields. Migrate the fields named in **Interfaces**, import the core helper, parse every API money field with `parseApiMinorUnits`, and set `BillsMetricsModel.empty` monetary values to integer zero.

Run again. Expected: domain tests pass and downstream code reports compile failures.

- [ ] **Step 3: Write RED repository payload tests**

Import `mobile/test/support/recording_session_transport.dart`. Construct the
repository with `recordingSessionTransport`; return `ruleJson('10000.01')` for
create/update and `instanceJson('0.01')` for payment. Assert:

```dart
await repository.createRecurringBill(
  name: 'Internet',
  amountMinor: 1000001,
  dueDay: 10,
  type: 'expense',
);
expect(recording.singleData['amount'], '10000.01');

await repository.updateRecurringBill(1, amountMinor: 1);
expect(recording.singleData['amount'], '0.01');

await repository.payBillInstance(
  1,
  accountId: 1,
  paidAmountMinor: 1,
  paidDate: DateTime(2026, 8, 20),
);
expect(recording.singleData['paid_amount'], '0.01');
```

Responses must be valid strict bill fixtures and assertions must also cover the unchanged ISO date fields.

- [ ] **Step 4: Run repository RED, then migrate repository and controller**

Confirm the new tests fail to compile on `amountMinor`/`paidAmountMinor`. Then rename all monetary signatures in `BillsRepository`, `HttpBillsRepository`, and `BillsController`, serializing only through `minorUnitsToApiDecimal`.

Run:

```powershell
flutter test test/features/bills/bills_exact_money_test.dart -r expanded
```

Expected: domain and repository tests pass.

- [ ] **Step 5: Write RED widget tests for exact bill entry and display**

Extend bill tests so they pump create/edit/pay flows and assert:

```dart
expect(find.text(r'R$ 10.000,01'), findsWidgets);
expect(find.text(r'R$ 0,01'), findsWidgets);
expect(capturedAmountMinor, 123456);
expect(capturedPaidAmountMinor, 123456);
```

Use `R$ 1.234,56` as entered text and prove `1,234` displays a validation error without invoking the callback.
Repeat with `0`, `0,00`, and `-1,00`; create and payment flows are positive and
must not invoke the controller for any of those values.

Add the matching controller regression: a fake repository returns a valid
`BillsDataSnapshot`, then throws `FormatException` on refresh. Assert that
`instances`, `recurringBills`, and `metrics` remain the last valid objects while
`isLoading` becomes false and `error` is populated.

- [ ] **Step 6: Migrate bill presentation and make widgets GREEN**

Apply these exact conversions:

- `BillFormSheet`: initial input through `minorUnitsToPtBrInput`; parsing through `parsePtBrMinorUnits`; callback key `amountMinor`;
- `PayBillSheet`: same parsing and editable formatting with callback `paidAmountMinor`;
- account balance labels use `formatBrlMinorUnits(acc.currentBalanceMinor)`;
- `BillsScreen` uses `formatBrlMinorUnits` for every metric, instance, and recurring rule;
- remove money `NumberFormat.currency` objects only when no non-money date/percentage formatter uses them.

Run:

```powershell
dart format lib/features/bills test/features/bills
flutter test test/features/bills -r expanded
flutter analyze
```

Expected: all bill tests pass and analyze reports no issues.

- [ ] **Step 7: Review, commit, and push bills**

Run:

```powershell
rg -n "double\.tryParse|toStringAsFixed|/ 100\.0" mobile/lib/features/bills
git diff --check
git add mobile/lib/features/bills mobile/test/features/bills
git commit -m "refactor(bills): use exact minor units"
git push origin main
```

Expected: the source scan has no monetary conversion matches and `main` is synchronized.

---

### Task 4: Prove the Decimal boundary, visual stability, and release gates

**Files:**
- Modify: `api/tests/test_cards_api.py`
- Modify: `api/tests/test_bills_api.py`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/data-model.md`
- Modify: `PRD.md`
- Inspect without expected modification: `mobile/test/goldens/*.png`
- Create ignored report: `.superpowers/sdd/r1-task-3-report.md`

**Interfaces:**
- Consumes: exact cards/bills slices from Tasks 1–3.
- Produces: executable proof that Django `Decimal` strings and Flutter minor units agree at one-cent boundaries; completed R1.3 documentation and CI evidence.

- [ ] **Step 1: Strengthen backend cent-level contract tests**

Change the existing API lifecycle fixtures to include exact cent cases without changing backend production code:

```python
# cards
'limit': '10000.01'
'amount': '0.03'  # 3 installments must serialize as 0.01 each
'paid_amount': '0.01'
self.assertEqual(data['selected_invoice']['total_amount'], '0.01')

# bills
'amount': '120.01'
'paid_amount': '120.01'
self.assertEqual(bill_data['amount'], '120.01')
self.assertEqual(metrics['paid_expenses_total'], '120.01')
```

Keep the existing lifecycle assertions for create/list/detail/pay/reopen/update/delete.

- [ ] **Step 2: Run the backend contract tests**

Run with an ephemeral secret and test SSL redirect disabled:

```powershell
$env:SECRET_KEY = python -c "import secrets; print(secrets.token_urlsafe(64))"
$env:SECURE_SSL_REDIRECT = 'False'
python manage.py test api.tests.test_cards_api api.tests.test_bills_api
```

Expected: both lifecycle tests pass and all asserted amounts are strings with exactly two places.

- [ ] **Step 3: Run source-boundary scans**

Run:

```powershell
rg -n "final double (amount|limit|availableLimit|paidAmount|totalAmount|pendingExpensesTotal|paidExpensesTotal|totalCommitted|totalAccountBalance|freeCashBalance)" mobile/lib/features/cards mobile/lib/features/bills
rg -n "double\.(tryParse|parse)|toStringAsFixed|/ 100\.0" mobile/lib/features/cards mobile/lib/features/bills
```

Expected: no results. Manually inspect any remaining `double` and retain it only when it is `limitUsagePercent`, `double.infinity`, an animation, a dimension, or a Flutter graphics argument.

- [ ] **Step 4: Prove goldens before changing any baseline**

Run:

```powershell
cd mobile
flutter test --tags=golden -r expanded
```

Expected: all existing goldens pass unchanged because string output and layout remain visually equivalent. If any fail, inspect master/test/isolated diff images; do not run `--update-goldens` unless the visual difference is intentional, documented, and approved.

- [ ] **Step 5: Run the complete local verification matrix**

Run Flutter:

```powershell
cd mobile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --exclude-tags=golden
flutter test --tags=golden
flutter build windows --release --dart-define=LAR_FINANCE_API_BASE_URL=https://financeiro.palmbook.online/api/v1
flutter build apk --release --dart-define=LAR_FINANCE_API_BASE_URL=https://financeiro.palmbook.online/api/v1
```

Run Django from the repository root with synthetic production variables for checks and `SECURE_SSL_REDIRECT=False` only for tests:

```powershell
$env:SECRET_KEY = python -c "import secrets; print(secrets.token_urlsafe(64))"
$env:DEBUG = 'False'
$env:ALLOWED_HOSTS = 'financeiro.palmbook.online'
$env:CSRF_TRUSTED_ORIGINS = 'https://financeiro.palmbook.online'
$env:SESSION_COOKIE_SECURE = 'True'
$env:CSRF_COOKIE_SECURE = 'True'
$env:SECURE_HSTS_SECONDS = '31536000'
$env:SECURE_HSTS_INCLUDE_SUBDOMAINS = 'True'
$env:SECURE_HSTS_PRELOAD = 'True'
$env:SECURE_SSL_REDIRECT = 'True'
python -m ruff check . --config pyproject.toml
python manage.py check
python manage.py check --deploy --fail-level WARNING
python manage.py makemigrations --check
$env:SECURE_SSL_REDIRECT = 'False'
python -Wd -m coverage run manage.py test
python -m coverage report --fail-under=90
git diff --check
```

Expected: every command exits 0, no deprecation warning is emitted, and coverage is at least 90%.

- [ ] **Step 6: Update current-truth documentation only after gates pass**

Apply these exact state changes:

- check every R1.3 checkbox in `docs/ROADMAP.md`;
- change `docs/data-model.md` from “cards/bills use double” debt to “cards/bills use integer minor units and serialize two-place decimal strings”;
- remove the high-risk cards/bills `double` row from `PRD.md` or mark it resolved with commit evidence;
- leave R1.4 and all later roadmap items open;
- write `.superpowers/sdd/r1-task-3-report.md` with RED/GREEN evidence, field inventory, scans, test counts, coverage, builds, golden result, commits, and remaining concerns.

- [ ] **Step 7: Review the complete change set**

Verify:

```powershell
git diff --stat
git diff --check
git status --short
```

Review every changed money field against the approved spec, verify no unrelated behavior or redesign entered the diff, and confirm no ignored failure image or generated secret is staged.

- [ ] **Step 8: Commit, push, and confirm remote CI**

Run:

```powershell
git add api/tests/test_cards_api.py api/tests/test_bills_api.py docs/ROADMAP.md docs/data-model.md PRD.md
git commit -m "test: prove exact money contracts"
git push origin main
$sha = git rev-parse HEAD
$run = gh run list --commit $sha --limit 1 --json databaseId | ConvertFrom-Json
if ($run.Count -ne 1) { throw "Expected exactly one CI run for $sha" }
gh run watch $run[0].databaseId --exit-status
```

Expected: all six CI jobs succeed, including Django tests/image, secret scan, Flutter checks, Windows/MSIX integration, Android APK, and iOS no-codesign IPA. Stop after reporting R1.3; do not start R1.4.

---

## Plan self-review

- Spec coverage: exact parsing, serialization, pt-BR input, domain migration, HTTP payloads, widgets, percentage exception, malformed response behavior, backend Decimal contract, goldens, full CI, and documentation are each assigned to a task.
- Type consistency: all money names use the `Minor` suffix end-to-end; HTTP conversion occurs only in repositories and display conversion only in presentation.
- Scope: cards and bills are separate vertical slices under the single authorized roadmap item R1.3; R1.4 is explicitly excluded.
- Placeholder scan: the plan contains no deferred behavior or undefined implementation requirement.
