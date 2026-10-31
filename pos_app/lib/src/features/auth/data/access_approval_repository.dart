import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/crash_log.dart';
import '../../../core/terminal_device_service.dart';
import '../../cashier_settings/domain/cashier_settings.dart';
import '../domain/access_approval_models.dart';

/// 权限中心审批数据仓库：
/// 1) 店长现场授权（POST /cashier/access/authorize）→ 签发短时一次性审批令牌；
/// 2) 方案A扫码授权（POST /cashier/access/qr/create + GET /cashier/access/qr/status）→ 收银端出码、店长手机无密审批；
/// 3) 店长移动端扫码审批（GET /admin/access/qr/details + POST /admin/access/qr/confirm）；
/// 4) 审批记录分页查询（GET /admin/access/approvals，权限 access:view）。
class AccessApprovalRepository {
  const AccessApprovalRepository(this.client);

  final AdminApiClient client;

  /// 发起店长现场授权。
  ///
  /// [permission] 为目标权限码（如 order:operate:refund），
  /// [authorizerAccount] 为授权人（店长/管理员）工号或用户名，
  /// [credential] 为密码或 PIN，[authMethod] 取 PASSWORD / PIN。
  /// 成功返回审批令牌；授权人凭证错误、账号停用或无审批权限时抛 [ApiException]。
  Future<CashierApprovalGrant> authorize({
    required String permission,
    String? bizType,
    String? bizId,
    double? amount,
    String? reason,
    required String authorizerAccount,
    required String credential,
    String authMethod = 'PASSWORD',
    String? requestId,
    String? terminalId,
  }) async {
    final account = authorizerAccount.trim();
    if (account.isEmpty) {
      throw ArgumentError('授权人账号不能为空');
    }
    if (credential.isEmpty) {
      throw ArgumentError('授权凭证不能为空');
    }
    final effectiveTerminalId =
        (terminalId != null && terminalId.trim().isNotEmpty)
            ? terminalId.trim()
            : (client.terminalId ?? TerminalDeviceService.instance.currentTerminalId);
    if (effectiveTerminalId == null || effectiveTerminalId.isEmpty) {
      throw ArgumentError('未取得终端编号，无法发起现场授权');
    }
    final response = await client.post(
      cashierAccessAuthorizeEndpoint,
      headers: {
        'X-Terminal-Id': effectiveTerminalId,
        if (requestId != null && requestId.isNotEmpty)
          'X-Client-Request-Id': requestId,
      },
      body: {
        'bindingVersion': 2,
        'terminalId': effectiveTerminalId,
        'authorizerAccount': account,
        'credential': credential,
        'authMethod': authMethod == 'PIN' ? 'PIN' : 'PASSWORD',
        'permission': permission,
        if (bizType != null && bizType.isNotEmpty) 'bizType': bizType,
        if (bizId != null && bizId.isNotEmpty) 'bizId': bizId,
        if (amount != null && amount > 0) 'amount': amount,
        if (reason != null && reason.trim().isNotEmpty)
          'reason': reason.trim(),
      },
    );
    final map = response is Map<String, Object?>
        ? response
        : (response is Map ? response.cast<String, Object?>() : const {});
    // 响应已被 unwrapResponse 解包为 data 本体（含 approvalToken），
    // 兼容仍带 data 包装的响应：data 键存在时取 data，否则直接用 map。
    final data = map.containsKey('approvalToken') ||
            map.containsKey('approval_token') ||
            map.containsKey('approvalNo')
        ? map
        : (map['data'] is Map ? map['data'] : const {});
    final dataMap = data is Map<String, Object?>
        ? data
        : (data is Map ? data.cast<String, Object?>() : const <String, Object?>{});
    final grant = CashierApprovalGrant.fromJson(dataMap);
    if (grant.approvalToken.isEmpty) {
      throw const ApiException('授权接口返回异常：缺少审批令牌', code: -1);
    }
    if (grant.legacyBinding || grant.bindingVersion != 2) {
      CrashLog.instance.recordBreadcrumb(
        category: 'auth',
        message: '审批令牌为旧版降级绑定 (legacyBinding=${grant.legacyBinding}, version=${grant.bindingVersion})，安全策略阻止使用',
        level: 'error',
      );
      throw const ApiException('安全策略阻断：服务端返回了旧版兼容绑定令牌，已阻止使用', code: 403);
    }
    return grant;
  }

  /// 方案A·收银端发起扫码授权申请（POST /cashier/access/qr/create）。
  ///
  /// 生成动态二维码与短链（qrPayload），店长手机扫码后无密审批。
  /// [permission] 为目标权限码；成功返回申请信息（approvalCode + qrPayload）。
  Future<CashierQrApprovalRequest> createQrApproval({
    required String permission,
    String? bizType,
    String? bizId,
    double? amount,
    String? reason,
    String? requestId,
    String? terminalId,
  }) async {
    final effectiveTerminalId =
        (terminalId != null && terminalId.trim().isNotEmpty)
            ? terminalId.trim()
            : (client.terminalId ?? TerminalDeviceService.instance.currentTerminalId);
    if (effectiveTerminalId == null || effectiveTerminalId.isEmpty) {
      throw ArgumentError('未取得终端编号，无法发起扫码审批');
    }
    final response = await client.post(
      cashierAccessQrCreateEndpoint,
      headers: {
        'X-Terminal-Id': effectiveTerminalId,
        if (requestId != null && requestId.isNotEmpty)
          'X-Client-Request-Id': requestId,
      },
      body: {
        'bindingVersion': 2,
        'terminalId': effectiveTerminalId,
        'permission': permission,
        if (bizType != null && bizType.isNotEmpty) 'bizType': bizType,
        if (bizId != null && bizId.isNotEmpty) 'bizId': bizId,
        if (amount != null && amount > 0) 'amount': amount,
        if (reason != null && reason.trim().isNotEmpty)
          'reason': reason.trim(),
      },
    );
    final map = _asMap(response);
    // 响应已被 unwrapResponse 解包为 data 本体（含 approvalCode/qrPayload），
    // 兼容仍带 data 包装的响应。
    final data = map.containsKey('approvalCode') ||
            map.containsKey('approval_code') ||
            map.containsKey('qrPayload')
        ? map
        : (map['data'] is Map ? map['data'] : const {});
    final dataMap = _asMap(data);
    final request = CashierQrApprovalRequest.fromJson(dataMap);
    if (request.approvalCode.isEmpty || request.qrPayload.isEmpty) {
      throw const ApiException('出码接口返回异常：缺少授权码或二维码内容', code: -1);
    }
    return request;
  }

  /// 方案A·收银端轮询扫码授权审批状态（GET /cashier/access/qr/status）。
  ///
  /// PENDING 时继续轮询；APPROVED 时返回一次性 approvalToken；
  /// REJECTED/EXPIRED 时由 [CashierQrApprovalStatus] 状态标记承载。
  Future<CashierQrApprovalStatus> pollQrApprovalStatus(
    String approvalCode,
  ) async {
    final response = await client.get(
      cashierAccessQrStatusEndpoint,
      query: {'approvalCode': approvalCode},
    );
    final map = _asMap(response);
    final data = map.containsKey('approvalCode') ||
            map.containsKey('approval_code') ||
            map.containsKey('status')
        ? map
        : (map['data'] is Map ? map['data'] : const {});
    final status = CashierQrApprovalStatus.fromJson(_asMap(data));
    if (status.isApproved && status.approvalToken != null) {
      if (status.legacyBinding || (status.bindingVersion != null && status.bindingVersion != 2)) {
        CrashLog.instance.recordBreadcrumb(
          category: 'auth',
          message: '扫码审批令牌为旧版降级绑定 (legacyBinding=${status.legacyBinding}, version=${status.bindingVersion})，安全策略阻止使用',
          level: 'error',
        );
        throw const ApiException('安全策略阻断：服务端返回了旧版兼容绑定令牌，已阻止使用', code: 403);
      }
    }
    return status;
  }

  /// 方案A·店长移动端获取待审批详情（GET /admin/access/qr/details）。
  ///
  /// 扫码唤起后调用，展示申请门店、操作员、业务类型、金额与原因；
  /// 门店无管辖权限时抛 [ApiException]。
  Future<CashierQrApprovalDetails> loadQrApprovalDetails(
    String approvalCode,
  ) async {
    final response = await client.get(
      adminAccessQrDetailsEndpoint,
      query: {'approvalCode': approvalCode},
    );
    final map = _asMap(response);
    final data = map.containsKey('approvalCode') ||
            map.containsKey('approval_code') ||
            map.containsKey('shopId')
        ? map
        : (map['data'] is Map ? map['data'] : const {});
    final dataMap = _asMap(data);
    final details = CashierQrApprovalDetails.fromJson(dataMap);
    if (details.approvalCode.isEmpty) {
      throw const ApiException('审批详情接口返回异常', code: -1);
    }
    return details;
  }

  /// 方案A·店长移动端确认或驳回扫码审批（POST /admin/access/qr/confirm）。
  ///
  /// [action] 取 AGREE / REJECT；同意时服务端签发单次令牌，
  /// 返回核销结果（含最终 status 与审批人信息）。
  Future<CashierQrApprovalConfirmResult> confirmQrApproval({
    required String approvalCode,
    required String action,
    String? rejectReason,
  }) async {
    if (action != 'AGREE' && action != 'REJECT') {
      throw ArgumentError('审批动作必须是 AGREE 或 REJECT');
    }
    final response = await client.post(
      adminAccessQrConfirmEndpoint,
      body: {
        'approvalCode': approvalCode,
        'action': action,
        if (rejectReason != null && rejectReason.trim().isNotEmpty)
          'rejectReason': rejectReason.trim(),
      },
    );
    final map = _asMap(response);
    final data = map.containsKey('approvalCode') ||
            map.containsKey('approval_code') ||
            map.containsKey('status')
        ? map
        : (map['data'] is Map ? map['data'] : const {});
    return CashierQrApprovalConfirmResult.fromJson(_asMap(data));
  }

  /// 分页查询审批记录（默认按创建时间倒序）。
  Future<AccessApprovalPage> listApprovals({
    int page = 1,
    int pageSize = 20,
    String? status,
    String? bizType,
    int? shopId,
  }) async {
    final response = await client.request(
      adminAccessApprovalsEndpoint,
      query: {
        'page': page,
        'pageSize': pageSize,
        if (status != null && status.isNotEmpty) 'status': status,
        if (bizType != null && bizType.isNotEmpty) 'bizType': bizType,
        if (shopId != null && shopId > 0) 'shopId': shopId,
      },
    );
    final map = response is Map<String, Object?>
        ? response
        : (response is Map ? response.cast<String, Object?>() : const {});
    // 响应已被 unwrapResponse 解包：直接含 page/items 分页结构，或仍带 data 包装。
    final data = map.containsKey('items') || map.containsKey('page')
        ? map
        : (map['data'] is Map ? map['data'] : const {});
    final dataMap = data is Map<String, Object?>
        ? data
        : (data is Map ? data.cast<String, Object?>() : const <String, Object?>{});
    return AccessApprovalPage.fromJson(dataMap);
  }

  /// 本门店最近授权人（GET /cashier/access/recent-authors，权限 cashier:operate）。
  ///
  /// 返回最近成功授权（APPROVED/CONSUMED）的店长/管理员去重列表（倒序），
  /// 供授权弹窗「最近授权账号」快捷选择。加载失败时由调用方静默降级（不阻塞授权主流程）。
  Future<List<RecentAuthor>> loadRecentAuthors({int limit = 10}) async {
    final response = await client.get(
      cashierAccessRecentAuthorsEndpoint,
      query: {'limit': limit},
    );
    final list = response is List
        ? response
        : (response is Map ? response['data'] : null);
    final authors = <RecentAuthor>[];
    if (list is List) {
      for (final raw in list) {
        if (raw is Map<String, Object?>) {
          authors.add(RecentAuthor.fromJson(raw));
        } else if (raw is Map) {
          authors.add(
            RecentAuthor.fromJson(
              raw.map((key, value) => MapEntry('$key', value)),
            ),
          );
        }
      }
    }
    return authors;
  }

  /// 查询单条审批记录详情（GET /admin/access/approvals/{id}，权限 access:view）。
  Future<AccessApprovalRecord?> loadApprovalDetail(int id) async {
    final response = await client.get(adminAccessApprovalDetailEndpoint(id));
    final map = response is Map<String, Object?>
        ? response
        : (response is Map ? response.cast<String, Object?>() : const {});
    // 响应可能已被解包为记录本体，或仍带 data 包装。
    final data = map.containsKey('approvalNo') ||
            map.containsKey('approval_no') ||
            map.containsKey('id')
        ? map
        : (map['data'] is Map ? map['data'] : const {});
    final dataMap = data is Map<String, Object?>
        ? data
        : (data is Map ? data.cast<String, Object?>() : const <String, Object?>{});
    if (dataMap.isEmpty) return null;
    return AccessApprovalRecord.fromJson(dataMap);
  }

  /// 权限决策评估（POST /admin/access/evaluate，WI-062 三态评估）。
  Future<CashierAccessEvaluation> evaluate({
    required int userId,
    int? shopId,
    required String permission,
    Map<String, Object?>? context,
  }) async {
    final response = await client.post(
      settingsAccessEvaluateEndpoint,
      body: {
        'userId': userId,
        if (shopId != null) 'shopId': shopId,
        'permission': permission,
        if (context != null && context.isNotEmpty) 'context': context,
      },
    );
    final map = _asMap(response);
    final data = map.containsKey('outcome') || map.containsKey('allow')
        ? map
        : (map['data'] is Map ? _asMap(map['data']) : map);
    return CashierAccessEvaluation.fromJson(data);
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.map((key, v) => MapEntry('$key', v));
    return const {};
  }
}
