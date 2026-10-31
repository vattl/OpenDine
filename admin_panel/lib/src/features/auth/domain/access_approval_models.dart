import 'package:flutter/foundation.dart';

import '../../../core/admin_api_client.dart';

/// 决策结果三态语义（对齐 POST /admin/access/evaluate 的 data.outcome，WI-062）。
enum AuthorizationOutcome {
  /// 拥有权限且策略通过，可直接提交动作。
  allow,

  /// 具有审批发起资格，需打开现场授权/扫码授权，获得 approvalToken 后重试。
  requireApproval,

  /// 硬拒绝（无权限或策略硬阻断），展示 reasonCode/explanation，禁止自动重试。
  deny,
}

/// 解析服务端评估响应的三态决策结果。
/// 优先读取 data['outcome']；若缺失则依据升级窗口兼容旧服务端的布尔字段降级推断。
AuthorizationOutcome parseOutcome(Map<String, Object?> data) {
  final outcomeRaw = data['outcome'] ?? data['verdict'];
  switch ('$outcomeRaw'.trim().toUpperCase()) {
    case 'ALLOW':
      return AuthorizationOutcome.allow;
    case 'REQUIRE_APPROVAL':
      return AuthorizationOutcome.requireApproval;
    case 'DENY':
      return AuthorizationOutcome.deny;
    default:
      // 兼容旧服务端，升级窗口内才使用；后续删除。
      if (data['allow'] == true || '${data['allow']}'.toLowerCase() == 'true') {
        return AuthorizationOutcome.allow;
      }
      if (data['approvalRequired'] == true ||
          '${data['approvalRequired']}'.toLowerCase() == 'true') {
        return AuthorizationOutcome.requireApproval;
      }
      return AuthorizationOutcome.deny;
  }
}

typedef AccessOutcome = AuthorizationOutcome;

/// 业务操作拦截模型（WI-063），用于统一封装高危业务动作返回的决策结果与错误详情。
@immutable
class ActionAccessFailure {
  const ActionAccessFailure({
    required this.code,
    required this.message,
    required this.outcome,
    this.reasonCode,
    this.approvalPermission,
    this.approval,
  });

  final int code;
  final String message;
  final AuthorizationOutcome outcome;
  final String? reasonCode;
  final String? approvalPermission;
  final Map<String, Object?>? approval;

  factory ActionAccessFailure.fromApiException(ApiException e) {
    AuthorizationOutcome outcome;
    if (e.outcome != null) {
      switch (e.outcome!.toUpperCase()) {
        case 'ALLOW':
          outcome = AuthorizationOutcome.allow;
          break;
        case 'REQUIRE_APPROVAL':
          outcome = AuthorizationOutcome.requireApproval;
          break;
        case 'DENY':
        default:
          outcome = AuthorizationOutcome.deny;
          break;
      }
    } else {
      if (e.isRequireApproval) {
        outcome = AuthorizationOutcome.requireApproval;
      } else {
        outcome = AuthorizationOutcome.deny;
      }
    }

    return ActionAccessFailure(
      code: e.code ?? e.statusCode ?? -1,
      message: e.message,
      outcome: outcome,
      reasonCode: e.reasonCode,
      approvalPermission: e.approvalPermission,
      approval: e.approval,
    );
  }

  @override
  String toString() =>
      'ActionAccessFailure(code: $code, outcome: $outcome, reasonCode: $reasonCode, message: $message)';
}

/// 敏感操作精确执行权限码常量（WI-062 §4）。
/// 前端不得把 cashier:operate 当作敏感动作执行权限，也不得自行拼接宽泛的 order:operate。
const String refundPermission = 'order:operate:refund';
const String changePricePermission = 'order:operate:changePrice';
const String discountPermission = 'order:operate:discount';
const String reopenPermission = 'order:operate:reopen';

/// 店长现场授权签发结果（POST /cashier/access/authorize）。
/// 收银端对高风险/超限操作发起审批后，由授权人凭密码或 PIN 验证通过，
/// 服务端签发短时（默认 120 秒）一次性审批令牌。
@immutable
class CashierApprovalGrant {
  const CashierApprovalGrant({
    required this.approvalNo,
    required this.approvalToken,
    required this.permission,
    required this.operatorId,
    required this.authorizerId,
    required this.authorizerName,
    required this.shopId,
    this.expiresAt,
    this.expireSeconds = 120,
    this.bindingVersion = 2,
    this.legacyBinding = false,
    this.requiredApprovalPermission,
  });

  /// 审批唯一流水号。
  final String approvalNo;

  /// 短时一次性审批令牌：随敏感操作请求体 approvalToken 提交，后端原子核销。
  final String approvalToken;

  /// 本次授权的目标权限码（如 order:operate:refund）。
  final String permission;

  /// 发起授权的操作者（收银员）ID。
  final int operatorId;

  /// 授权人（店长/管理员）ID。
  final int authorizerId;

  /// 授权人姓名/账号（用于界面展示与审计）。
  final String authorizerName;

  /// 授权门店 ID。
  final int shopId;

  /// 令牌失效时间（null 表示未返回）。
  final DateTime? expiresAt;

  /// 有效时长（秒）。
  final int expireSeconds;

  /// 绑定策略版本（2=严格上下文绑定；1=兼容绑定）。
  final int bindingVersion;

  /// 是否为兼容降级绑定（true 表示安全策略应阻止使用）。
  final bool legacyBinding;

  /// 授权所需的精确审批权限码（如 order:operate:refund:approve）。
  final String? requiredApprovalPermission;

  bool get isExpired {
    final time = expiresAt;
    if (time == null) return false;
    return !time.isAfter(DateTime.now());
  }

  factory CashierApprovalGrant.fromJson(Map<String, Object?> json) {
    Object? pick(String camel, String snake) =>
        json[camel] ?? json[snake] ?? json[camel.toLowerCase()];
    final rawLegacy = pick('legacyBinding', 'legacy_binding');
    final isLegacy = rawLegacy == true || '$rawLegacy'.toLowerCase() == 'true';
    final rawRequired = pick('requiredApprovalPermission', 'required_approval_permission');
    return CashierApprovalGrant(
      approvalNo: '${pick('approvalNo', 'approval_no') ?? ''}',
      approvalToken: '${pick('approvalToken', 'approval_token') ?? ''}',
      permission: '${pick('permission', 'permission_code') ?? ''}',
      operatorId: _toInt(pick('operatorId', 'operator_id')) ?? 0,
      authorizerId: _toInt(pick('authorizerId', 'authorizer_id')) ?? 0,
      authorizerName: '${pick('authorizerName', 'authorizer_name') ?? ''}',
      shopId: _toInt(pick('shopId', 'shop_id')) ?? 0,
      expiresAt: _toDateTime(pick('expiresAt', 'expires_at')),
      expireSeconds: _toInt(pick('expireSeconds', 'expire_seconds')) ?? 120,
      bindingVersion: _toInt(pick('bindingVersion', 'binding_version')) ?? 1,
      legacyBinding: isLegacy,
      requiredApprovalPermission:
          rawRequired == null || '$rawRequired'.isEmpty ? null : '$rawRequired',
    );
  }
}

/// 方案A·收银端出码申请结果（POST /cashier/access/qr/create 响应）。
/// 收银端据此展示动态二维码（qrPayload 渲染），店长手机扫码无密审批。
@immutable
class CashierQrApprovalRequest {
  const CashierQrApprovalRequest({
    required this.approvalCode,
    required this.qrPayload,
    this.status = 'PENDING',
    this.expiresAt,
    this.expireSeconds = 120,
    this.bindingVersion,
    this.legacyBinding = false,
    this.requiredApprovalPermission,
  });

  /// 扫码授权流水标识（QAP_...）。
  final String approvalCode;

  /// 二维码短链/唤起协议串（如 bbq://approval?code=QAP_...），直接渲染为二维码。
  final String qrPayload;

  /// 申请状态（初始 PENDING）。
  final String status;

  /// 二维码失效时间。
  final DateTime? expiresAt;

  /// 有效时长（秒），默认 120。
  final int expireSeconds;

  /// 绑定策略版本（2=严格上下文绑定）。
  final int? bindingVersion;

  /// 是否为兼容降级绑定。
  final bool legacyBinding;

  /// 授权所需的精确审批权限码。
  final String? requiredApprovalPermission;

  /// 是否已过期。
  bool get isExpired {
    final time = expiresAt;
    if (time == null) return false;
    return !time.isAfter(DateTime.now());
  }

  factory CashierQrApprovalRequest.fromJson(Map<String, Object?> json) {
    Object? pick(String camel, String snake) =>
        json[camel] ?? json[snake] ?? json[camel.toLowerCase()];
    final rawLegacy = pick('legacyBinding', 'legacy_binding');
    final isLegacy = rawLegacy == true || '$rawLegacy'.toLowerCase() == 'true';
    final rawRequired = pick('requiredApprovalPermission', 'required_approval_permission');
    return CashierQrApprovalRequest(
      approvalCode: '${pick('approvalCode', 'approval_code') ?? ''}',
      qrPayload: '${pick('qrPayload', 'qr_payload') ?? ''}',
      status: '${pick('status', 'status') ?? 'PENDING'}',
      expiresAt: _toDateTime(pick('expiresAt', 'expires_at')),
      expireSeconds: _toInt(pick('expireSeconds', 'expire_seconds')) ?? 120,
      bindingVersion: _toInt(pick('bindingVersion', 'binding_version')),
      legacyBinding: isLegacy,
      requiredApprovalPermission:
          rawRequired == null || '$rawRequired'.isEmpty ? null : '$rawRequired',
    );
  }
}

/// 扫码审批状态取值（对齐服务端 t_access_approval.status）。
class CashierQrApprovalStatusValue {
  static const pending = 'PENDING';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const expired = 'EXPIRED';

  static String label(String? status) {
    switch (status) {
      case pending:
        return '等待店长扫码';
      case approved:
        return '已同意';
      case rejected:
        return '已驳回';
      case expired:
        return '已过期';
      default:
        return status == null || status.isEmpty ? '-' : status;
    }
  }
}

/// 方案A·收银端轮询结果（GET /cashier/access/qr/status 响应）。
@immutable
class CashierQrApprovalStatus {
  const CashierQrApprovalStatus({
    required this.approvalCode,
    required this.status,
    this.approvalToken,
    this.authorizerId,
    this.authorizerName,
    this.expiresAt,
    this.reason,
    this.bindingVersion,
    this.legacyBinding = false,
  });

  final String approvalCode;

  /// PENDING / APPROVED / REJECTED / EXPIRED。
  final String status;

  /// 店长同意后返回的短期单次令牌（仅 APPROVED 时非空）。
  final String? approvalToken;

  /// 审批人（店长）ID。
  final int? authorizerId;

  /// 审批人姓名/账号。
  final String? authorizerName;

  /// 令牌失效时间。
  final DateTime? expiresAt;

  /// 驳回原因（REJECTED 时由服务端返回）。
  final String? reason;

  /// 绑定策略版本。
  final int? bindingVersion;

  /// 是否为兼容降级绑定。
  final bool legacyBinding;

  bool get isApproved => status == CashierQrApprovalStatusValue.approved;
  bool get isRejected => status == CashierQrApprovalStatusValue.rejected;
  bool get isExpired => status == CashierQrApprovalStatusValue.expired;

  factory CashierQrApprovalStatus.fromJson(Map<String, Object?> json) {
    Object? pick(String camel, String snake) =>
        json[camel] ?? json[snake] ?? json[camel.toLowerCase()];
    final rawLegacy = pick('legacyBinding', 'legacy_binding');
    final isLegacy = rawLegacy == true || '$rawLegacy'.toLowerCase() == 'true';
    return CashierQrApprovalStatus(
      approvalCode: '${pick('approvalCode', 'approval_code') ?? ''}',
      status: '${pick('status', 'status') ?? 'PENDING'}',
      approvalToken: '${pick('approvalToken', 'approval_token') ?? ''}'.isEmpty
          ? null
          : '${pick('approvalToken', 'approval_token')}',
      authorizerId: _toInt(pick('authorizerId', 'authorizer_id')),
      authorizerName: '${pick('authorizerName', 'authorizer_name') ?? ''}'
              .isEmpty
          ? null
          : '${pick('authorizerName', 'authorizer_name')}',
      expiresAt: _toDateTime(pick('expiresAt', 'expires_at')),
      reason: '${pick('reason', 'reason') ?? ''}'.isEmpty
          ? null
          : '${pick('reason', 'reason')}',
      bindingVersion: _toInt(pick('bindingVersion', 'binding_version')),
      legacyBinding: isLegacy,
    );
  }
}

/// 方案A·店长移动端待审批详情（GET /admin/access/qr/details 响应）。
@immutable
class CashierQrApprovalDetails {
  const CashierQrApprovalDetails({
    required this.approvalCode,
    this.shopId,
    this.permission,
    this.bizType,
    this.bizId,
    this.amount,
    this.reason,
    this.operatorId,
    this.operatorName,
    this.operatorWorkNo,
    this.status,
    this.createdAt,
    this.expiresAt,
    this.bindingVersion,
    this.legacyBinding = false,
    this.requiredApprovalPermission,
  });

  final String approvalCode;
  final int? shopId;
  final String? permission;
  final String? bizType;
  final String? bizId;
  final double? amount;
  final String? reason;
  final int? operatorId;
  final String? operatorName;
  final String? operatorWorkNo;
  final String? status;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final int? bindingVersion;
  final bool legacyBinding;
  final String? requiredApprovalPermission;

  /// 是否已过期（按服务端返回的 expiresAt 判定）。
  bool get isExpired {
    final time = expiresAt;
    if (time == null) return false;
    return !time.isAfter(DateTime.now());
  }

  factory CashierQrApprovalDetails.fromJson(Map<String, Object?> json) {
    Object? pick(String camel, String snake) =>
        json[camel] ?? json[snake] ?? json[camel.toLowerCase()];
    final rawLegacy = pick('legacyBinding', 'legacy_binding');
    final isLegacy = rawLegacy == true || '$rawLegacy'.toLowerCase() == 'true';
    final rawRequired = pick('requiredApprovalPermission', 'required_approval_permission');
    return CashierQrApprovalDetails(
      approvalCode: '${pick('approvalCode', 'approval_code') ?? ''}',
      shopId: _toInt(pick('shopId', 'shop_id')),
      permission: '${pick('permission', 'permission_code') ?? ''}'.isEmpty
          ? null
          : '${pick('permission', 'permission_code')}',
      bizType: '${pick('bizType', 'biz_type') ?? ''}'.isEmpty
          ? null
          : '${pick('bizType', 'biz_type')}',
      bizId: '${pick('bizId', 'biz_id') ?? ''}'.isEmpty
          ? null
          : '${pick('bizId', 'biz_id')}',
      amount: _toDouble(pick('amount', 'amount')),
      reason: '${pick('reason', 'reason') ?? ''}'.isEmpty
          ? null
          : '${pick('reason', 'reason')}',
      operatorId: _toInt(pick('operatorId', 'operator_id')),
      operatorName: '${pick('operatorName', 'operator_name') ?? ''}'.isEmpty
          ? null
          : '${pick('operatorName', 'operator_name')}',
      operatorWorkNo: '${pick('operatorWorkNo', 'operator_work_no') ?? ''}'
              .isEmpty
          ? null
          : '${pick('operatorWorkNo', 'operator_work_no')}',
      status: '${pick('status', 'status') ?? ''}'.isEmpty
          ? null
          : '${pick('status', 'status')}',
      createdAt: _toDateTime(pick('createdAt', 'created_at')),
      expiresAt: _toDateTime(pick('expiresAt', 'expires_at')),
      bindingVersion: _toInt(pick('bindingVersion', 'binding_version')),
      legacyBinding: isLegacy,
      requiredApprovalPermission:
          rawRequired == null || '$rawRequired'.isEmpty ? null : '$rawRequired',
    );
  }
}

/// 审批权限中文人类可读名称映射助手。
class ApprovalPermissionHelper {
  static const Map<String, String> _labels = {
    'order:operate:refund:approve': '退款审批',
    'order:operate:changePrice:approve': '改价审批',
    'order:operate:discount:approve': '折扣审批',
    'order:operate:reopen:approve': '反结账审批',
    'order:operate:refund': '退款/退菜',
    'order:operate:changePrice': '改价/赠菜',
    'order:operate:discount': '整单优惠/折扣',
    'order:operate:reopen': '反结账',
    'order:delete': '删除订单',
    'admin:manage': '主管管理',
  };

  /// 将精确审批权限码转换为人类可读名称，若未匹配则返回原权限码。
  static String readableName(String? permissionCode) {
    if (permissionCode == null || permissionCode.trim().isEmpty) return '-';
    final clean = permissionCode.trim();
    return _labels[clean] ?? clean;
  }

  /// 检查是否为已知审批权限。
  static bool isApprovalPermission(String? permissionCode) {
    return permissionCode != null && permissionCode.endsWith(':approve');
  }
}

/// 方案A·店长移动端确认/驳回结果（POST /admin/access/qr/confirm 响应）。
@immutable
class CashierQrApprovalConfirmResult {
  const CashierQrApprovalConfirmResult({
    required this.approvalCode,
    required this.status,
    this.authorizerId,
    this.authorizerName,
  });

  final String approvalCode;

  /// 审批后最终状态：APPROVED / REJECTED。
  final String status;

  /// 审批人（店长）ID。
  final int? authorizerId;

  /// 审批人姓名/账号。
  final String? authorizerName;

  factory CashierQrApprovalConfirmResult.fromJson(Map<String, Object?> json) {
    Object? pick(String camel, String snake) =>
        json[camel] ?? json[snake] ?? json[camel.toLowerCase()];
    return CashierQrApprovalConfirmResult(
      approvalCode: '${pick('approvalCode', 'approval_code') ?? ''}',
      status: '${pick('status', 'status') ?? ''}',
      authorizerId: _toInt(pick('authorizerId', 'authorizer_id')),
      authorizerName: '${pick('authorizerName', 'authorizer_name') ?? ''}'
              .isEmpty
          ? null
          : '${pick('authorizerName', 'authorizer_name')}',
    );
  }
}

/// 审批记录状态（对齐服务端 t_access_approval.status）。
class AccessApprovalStatus {  static const pending = 'PENDING';
  static const approved = 'APPROVED';
  static const consumed = 'CONSUMED';
  static const expired = 'EXPIRED';
  static const revoked = 'REVOKED';
  static const rejected = 'REJECTED';

  static String label(String? status) {
    switch (status) {
      case pending:
        return '待使用';
      case approved:
        return '已签发';
      case consumed:
        return '已核销';
      case expired:
        return '已过期';
      case revoked:
        return '已撤销';
      case rejected:
        return '已拒绝';
      default:
        return status == null || status.isEmpty ? '-' : status;
    }
  }
}

/// 审批方式（对齐服务端 auth_method：PASSWORD / PIN / SESSION）。
class AccessApprovalAuthMethod {
  static const password = 'PASSWORD';
  static const pin = 'PIN';
  static const session = 'SESSION';

  static String label(String? method) {
    switch (method) {
      case password:
        return '账号密码';
      case pin:
        return 'PIN 码';
      case session:
        return '登录会话';
      default:
        return method == null || method.isEmpty ? '-' : method;
    }
  }
}

/// 权限中心审批流水（GET /admin/access/approvals 的 items）。
@immutable
class AccessApprovalRecord {
  const AccessApprovalRecord({
    required this.id,
    required this.approvalNo,
    required this.permissionCode,
    this.operatorId,
    this.authorizerId,
    this.operatorName,
    this.operatorWorkNo,
    this.authorizerName,
    this.authorizerWorkNo,
    this.shopId,
    this.bizType,
    this.bizId,
    this.amount,
    this.reason,
    this.authMethod,
    this.status,
    this.maxAmount,
    this.expiresAt,
    this.consumedAt,
    this.createdAt,
  });

  final int id;
  final String approvalNo;
  final String permissionCode;
  final int? operatorId;
  final int? authorizerId;

  /// 操作人（发起敏感操作的收银员）姓名与工号，服务端审批流水增强后返回。
  final String? operatorName;
  final String? operatorWorkNo;

  /// 授权人（现场授权/扫码审批的店长、管理员）姓名与工号。
  final String? authorizerName;
  final String? authorizerWorkNo;

  final int? shopId;
  final String? bizType;
  final String? bizId;
  final double? amount;
  final String? reason;
  final String? authMethod;
  final String? status;
  final double? maxAmount;
  final DateTime? expiresAt;
  final DateTime? consumedAt;
  final DateTime? createdAt;

  factory AccessApprovalRecord.fromJson(Map<String, Object?> json) {
    Object? pick(String camel, String snake) =>
        json[camel] ?? json[snake] ?? json[camel.toLowerCase()];
    String? textOf(Object? raw) =>
        raw == null ? null : '$raw'.isEmpty ? null : '$raw';
    return AccessApprovalRecord(
      id: _toInt(pick('id', 'id')) ?? 0,
      approvalNo: '${pick('approvalNo', 'approval_no') ?? ''}',
      permissionCode: '${pick('permissionCode', 'permission_code') ?? ''}',
      operatorId: _toInt(pick('operatorId', 'operator_id')),
      authorizerId: _toInt(pick('authorizerId', 'authorizer_id')),
      operatorName: textOf(pick('operatorName', 'operator_name')),
      operatorWorkNo: textOf(pick('operatorWorkNo', 'operator_work_no')),
      authorizerName: textOf(pick('authorizerName', 'authorizer_name')),
      authorizerWorkNo:
          textOf(pick('authorizerWorkNo', 'authorizer_work_no')),
      shopId: _toInt(pick('shopId', 'shop_id')),
      bizType: '${pick('bizType', 'biz_type') ?? ''}'.isEmpty
          ? null
          : '${pick('bizType', 'biz_type')}',
      bizId: '${pick('bizId', 'biz_id') ?? ''}'.isEmpty
          ? null
          : '${pick('bizId', 'biz_id')}',
      amount: _toDouble(pick('amount', 'amount')),
      reason: '${pick('reason', 'reason') ?? ''}'.isEmpty
          ? null
          : '${pick('reason', 'reason')}',
      authMethod: '${pick('authMethod', 'auth_method') ?? ''}'.isEmpty
          ? null
          : '${pick('authMethod', 'auth_method')}',
      status: '${pick('status', 'status') ?? ''}'.isEmpty
          ? null
          : '${pick('status', 'status')}',
      maxAmount: _toDouble(pick('maxAmount', 'max_amount')),
      expiresAt: _toDateTime(pick('expiresAt', 'expires_at')),
      consumedAt: _toDateTime(pick('consumedAt', 'consumed_at')),
      createdAt: _toDateTime(pick('createdAt', 'created_at')),
    );
  }
}

/// 本门店最近授权人（GET /cashier/access/recent-authors 的列表项），
/// 供收银端授权弹窗快捷选择历史账号/工号。
@immutable
class RecentAuthor {
  const RecentAuthor({
    this.authorizerId,
    this.authorizerName,
    this.authorizerWorkNo,
    this.lastApprovalAt,
  });

  final int? authorizerId;
  final String? authorizerName;
  final String? authorizerWorkNo;
  final DateTime? lastApprovalAt;

  /// 快捷选择展示文案：姓名（有）或用户名，如「王店长 · 1001」。
  String get displayLabel {
    final name = authorizerName != null && authorizerName!.isNotEmpty
        ? authorizerName!
        : '店长';
    final no = authorizerWorkNo != null && authorizerWorkNo!.isNotEmpty
        ? authorizerWorkNo!
        : (authorizerId != null ? '#$authorizerId' : '');
    return no.isEmpty ? name : '$name · $no';
  }

  factory RecentAuthor.fromJson(Map<String, Object?> json) {
    Object? pick(String camel, String snake) =>
        json[camel] ?? json[snake] ?? json[camel.toLowerCase()];
    String? textOf(Object? raw) =>
        raw == null ? null : '$raw'.isEmpty ? null : '$raw';
    return RecentAuthor(
      authorizerId: _toInt(pick('authorizerId', 'authorizer_id')),
      authorizerName: textOf(pick('authorizerName', 'authorizer_name')),
      authorizerWorkNo: textOf(pick('authorizerWorkNo', 'authorizer_work_no')),
      lastApprovalAt: _toDateTime(pick('lastApprovalAt', 'last_approval_at')),
    );
  }
}

/// 审批记录分页结果（对齐服务端 pageResult：page/pageSize/total/items）。
@immutable
class AccessApprovalPage {
  const AccessApprovalPage({
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.items = const [],
  });

  final int page;
  final int pageSize;
  final int total;
  final List<AccessApprovalRecord> items;

  bool get hasMore => page * pageSize < total;

  factory AccessApprovalPage.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    final items = <AccessApprovalRecord>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map<String, Object?>) {
          items.add(AccessApprovalRecord.fromJson(raw));
        } else if (raw is Map) {
          items.add(
            AccessApprovalRecord.fromJson(
              raw.map((key, value) => MapEntry('$key', value)),
            ),
          );
        }
      }
    }
    return AccessApprovalPage(
      page: _toInt(json['page']) ?? 1,
      pageSize: _toInt(json['pageSize']) ?? 20,
      total: _toInt(json['total']) ?? 0,
      items: items,
    );
  }
}

int? _toInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

DateTime? _toDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final parsed = DateTime.tryParse('$value');
  return parsed;
}
