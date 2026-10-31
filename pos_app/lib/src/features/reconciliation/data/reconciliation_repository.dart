import '../domain/reconciliation_models.dart';

abstract interface class ReconciliationRepository {
  /// 获取三层对账全景概览
  Future<ReconciliationOverview> loadOverview({
    String? statDate,
    int? shopId,
  });

  /// 导入渠道对账单（微信/支付宝 CSV 或 JSON）
  Future<ChannelStatementBatch> importStatement({
    required String channel,
    required String fileName,
    required String content,
    int? shopId,
  });

  /// 获取对账单导入批次列表
  Future<List<ChannelStatementBatch>> loadBatches({
    String? statDate,
    String? channel,
    int? shopId,
  });

  /// 获取对账差异处理单列表
  Future<List<ReconciliationCase>> loadCases({
    String? statDate,
    String? status,
    String? discrepancyType,
    int? shopId,
  });

  /// 解决/平账差异单
  Future<ReconciliationCase> resolveCase({
    required int caseId,
    required String status,
    String? resolutionNote,
    String? responsiblePerson,
    int? shopId,
  });
}
