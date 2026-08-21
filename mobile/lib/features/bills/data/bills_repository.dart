import '../../../core/money/minor_units.dart';
import '../../../core/network/session_transport.dart';
import '../domain/bills_models.dart';

abstract interface class BillsRepository {
  Future<BillsDataSnapshot> fetchBillsData({
    int? month,
    int? year,
    String? owner,
  });

  Future<RecurringBillModel> createRecurringBill({
    required String name,
    required int amountMinor,
    required int dueDay,
    required String type,
    int? categoryId,
    int? defaultAccountId,
    String? financialOwnerType,
    bool isActive = true,
    String notes = '',
  });

  Future<RecurringBillModel> updateRecurringBill(
    int id, {
    String? name,
    int? amountMinor,
    int? dueDay,
    String? type,
    int? categoryId,
    int? defaultAccountId,
    String? financialOwnerType,
    bool? isActive,
    String? notes,
  });

  Future<void> deleteRecurringBill(int id);

  Future<BillInstanceModel> payBillInstance(
    int instanceId, {
    required int accountId,
    required int paidAmountMinor,
    required DateTime paidDate,
  });

  Future<BillInstanceModel> reopenBillInstance(int instanceId);

  Future<BillsMetricsModel> fetchMetrics({
    int? month,
    int? year,
    String? owner,
  });
}

final class BillsDataSnapshot {
  const BillsDataSnapshot({
    required this.instances,
    required this.recurringBills,
    required this.metrics,
  });

  final List<BillInstanceModel> instances;
  final List<RecurringBillModel> recurringBills;
  final BillsMetricsModel metrics;
}

final class HttpBillsRepository implements BillsRepository {
  const HttpBillsRepository(this._transport);

  final SessionTransport _transport;

  @override
  Future<BillsDataSnapshot> fetchBillsData({
    int? month,
    int? year,
    String? owner,
  }) async {
    final queryParams = <String, String>{};
    if (month != null) queryParams['month'] = month.toString();
    if (year != null) queryParams['year'] = year.toString();
    if (owner != null && owner != 'household') queryParams['owner'] = owner;

    final queryStr = queryParams.isEmpty
        ? ''
        : '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';

    final data = await _transport.getObject('/api/v1/bills/$queryStr');

    final instancesList = (data['instances'] as List<dynamic>? ?? [])
        .map((e) => BillInstanceModel.fromJson(e as Map<String, Object?>))
        .toList();

    final recurringList = (data['recurring_bills'] as List<dynamic>? ?? [])
        .map((e) => RecurringBillModel.fromJson(e as Map<String, Object?>))
        .toList();

    final metricsObj = data['metrics'] != null
        ? BillsMetricsModel.fromJson(data['metrics'] as Map<String, Object?>)
        : BillsMetricsModel.empty;

    return BillsDataSnapshot(
      instances: instancesList,
      recurringBills: recurringList,
      metrics: metricsObj,
    );
  }

  @override
  Future<RecurringBillModel> createRecurringBill({
    required String name,
    required int amountMinor,
    required int dueDay,
    required String type,
    int? categoryId,
    int? defaultAccountId,
    String? financialOwnerType,
    bool isActive = true,
    String notes = '',
  }) async {
    final payload = <String, Object?>{
      'name': name,
      'amount': minorUnitsToApiDecimal(amountMinor),
      'due_day': dueDay,
      'type': type,
      'is_active': isActive,
      'notes': notes,
    };
    if (categoryId != null) payload['category_id'] = categoryId;
    if (defaultAccountId != null) {
      payload['default_account_id'] = defaultAccountId;
    }
    if (financialOwnerType != null) {
      payload['financial_owner_type'] = financialOwnerType;
    }

    final data = await _transport.postObject('/api/v1/bills/', data: payload);
    return RecurringBillModel.fromJson(data);
  }

  @override
  Future<RecurringBillModel> updateRecurringBill(
    int id, {
    String? name,
    int? amountMinor,
    int? dueDay,
    String? type,
    int? categoryId,
    int? defaultAccountId,
    String? financialOwnerType,
    bool? isActive,
    String? notes,
  }) async {
    final payload = <String, Object?>{};
    if (name != null) payload['name'] = name;
    if (amountMinor != null) {
      payload['amount'] = minorUnitsToApiDecimal(amountMinor);
    }
    if (dueDay != null) payload['due_day'] = dueDay;
    if (type != null) payload['type'] = type;
    if (categoryId != null) payload['category_id'] = categoryId;
    if (defaultAccountId != null) {
      payload['default_account_id'] = defaultAccountId;
    }
    if (financialOwnerType != null) {
      payload['financial_owner_type'] = financialOwnerType;
    }
    if (isActive != null) payload['is_active'] = isActive;
    if (notes != null) payload['notes'] = notes;

    final data = await _transport.patchObject('/api/v1/bills/$id/', payload);
    return RecurringBillModel.fromJson(data);
  }

  @override
  Future<void> deleteRecurringBill(int id) async {
    await _transport.deleteObject('/api/v1/bills/$id/');
  }

  @override
  Future<BillInstanceModel> payBillInstance(
    int instanceId, {
    required int accountId,
    required int paidAmountMinor,
    required DateTime paidDate,
  }) async {
    final payload = <String, Object?>{
      'account_id': accountId,
      'paid_amount': minorUnitsToApiDecimal(paidAmountMinor),
      'paid_date': paidDate.toIso8601String().substring(0, 10),
    };
    final data = await _transport.postObject(
      '/api/v1/bills/instances/$instanceId/pay/',
      data: payload,
    );
    return BillInstanceModel.fromJson(data);
  }

  @override
  Future<BillInstanceModel> reopenBillInstance(int instanceId) async {
    final data = await _transport.postObject(
      '/api/v1/bills/instances/$instanceId/reopen/',
    );
    return BillInstanceModel.fromJson(data);
  }

  @override
  Future<BillsMetricsModel> fetchMetrics({
    int? month,
    int? year,
    String? owner,
  }) async {
    final queryParams = <String, String>{};
    if (month != null) queryParams['month'] = month.toString();
    if (year != null) queryParams['year'] = year.toString();
    if (owner != null && owner != 'household') queryParams['owner'] = owner;

    final queryStr = queryParams.isEmpty
        ? ''
        : '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';

    final data = await _transport.getObject('/api/v1/bills/metrics/$queryStr');
    return BillsMetricsModel.fromJson(data);
  }
}
