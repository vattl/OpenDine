import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/reconciliation_models.dart';
import 'reconciliation_repository.dart';

class RealReconciliationRepository implements ReconciliationRepository {
  const RealReconciliationRepository(this.client);

  final AdminApiClient client;

  @override
  Future<ReconciliationOverview> loadOverview({
    String? statDate,
    int? shopId,
  }) async {
    final query = <String, dynamic>{
      if (statDate != null && statDate.isNotEmpty) 'stat_date': statDate,
    };
    final response = await client.copyWith(shopId: shopId).get(
      reconciliationOverviewEndpoint,
      query: query,
    );
    final map = _map(response);
    return ReconciliationOverview.fromJson(map);
  }

  @override
  Future<ChannelStatementBatch> importStatement({
    required String channel,
    required String fileName,
    required String content,
    int? shopId,
  }) async {
    final body = <String, dynamic>{
      'channel': channel,
      'file_name': fileName,
      'content': content,
    };
    final response = await client.copyWith(shopId: shopId).post(
      reconciliationImportEndpoint,
      body: body,
    );
    final map = _map(response);
    final batchRaw = map['batch'] as Map<String, dynamic>? ?? map;
    return ChannelStatementBatch.fromJson(batchRaw);
  }

  @override
  Future<List<ChannelStatementBatch>> loadBatches({
    String? statDate,
    String? channel,
    int? shopId,
  }) async {
    final query = <String, dynamic>{
      if (statDate != null && statDate.isNotEmpty) 'stat_date': statDate,
      if (channel != null && channel.isNotEmpty) 'channel': channel,
    };
    final response = await client.copyWith(shopId: shopId).get(
      reconciliationBatchesEndpoint,
      query: query,
    );
    final map = _map(response);
    final rawList = map['batches'] as List<dynamic>? ?? [];
    return rawList
        .map((e) => ChannelStatementBatch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ReconciliationCase>> loadCases({
    String? statDate,
    String? status,
    String? discrepancyType,
    int? shopId,
  }) async {
    final query = <String, dynamic>{
      if (statDate != null && statDate.isNotEmpty) 'stat_date': statDate,
      if (status != null && status.isNotEmpty) 'status': status,
      if (discrepancyType != null && discrepancyType.isNotEmpty)
        'discrepancy_type': discrepancyType,
    };
    final response = await client.copyWith(shopId: shopId).get(
      reconciliationCasesEndpoint,
      query: query,
    );
    final map = _map(response);
    final rawList = map['cases'] as List<dynamic>? ?? [];
    return rawList
        .map((e) => ReconciliationCase.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ReconciliationCase> resolveCase({
    required int caseId,
    required String status,
    String? resolutionNote,
    String? responsiblePerson,
    int? shopId,
  }) async {
    final endpoint = AdminEndpoint(
      method: reconciliationResolveCaseEndpoint.method,
      path: '/admin/reconciliation/cases/$caseId/resolve',
      permissionCode: reconciliationResolveCaseEndpoint.permissionCode,
    );
    final body = <String, dynamic>{
      'status': status,
      if (resolutionNote != null) 'resolution_note': resolutionNote,
      if (responsiblePerson != null) 'responsible_person': responsiblePerson,
    };
    final response = await client.copyWith(shopId: shopId).post(
      endpoint,
      body: body,
    );
    final map = _map(response);
    final caseRaw = map['case'] as Map<String, dynamic>? ?? map;
    return ReconciliationCase.fromJson(caseRaw);
  }

  Map<String, dynamic> _map(dynamic response) {
    if (response is Map<String, dynamic>) {
      if (response.containsKey('data') && response['data'] is Map<String, dynamic>) {
        return response['data'] as Map<String, dynamic>;
      }
      return response;
    }
    return <String, dynamic>{};
  }
}
