import '../domain/subscribe_template.dart';
import '../domain/cashier_settings.dart';
import '../domain/printing_template_models.dart';
import '../domain/receipt_preview_models.dart';
import '../../auth/domain/access_approval_models.dart';

abstract interface class CashierSettingsRepository {
  Future<CashierSettingsOverview> loadSettingsOverview();

  Future<CashierSettingsSectionData> loadSettingsSection({
    required String module,
    required String section,
    int page = 1,
    int pageSize = 20,
  });

  Future<CashierStoreSettings> loadStoreSettings();

  Future<CashierStoreSettings> saveStoreSettings({
    required int version,
    Map<String, Object?>? basic,
    List<Map<String, Object?>>? businessHours,
    List<int>? businessDays,
  });

  /// 上传线下微信/支付宝收款码原图（multipart）；服务端 ZXing 解码并自动写入门店字段。
  Future<void> uploadOfflineCollectQr({
    required bool isWechat,
    required List<int> bytes,
    required String filename,
  });

  Future<int> publishAnnouncement({
    int? id,
    required String title,
    required String content,
    required int status,
    int sort = 0,
    String? startTime,
    String? endTime,
  });

  Future<CashierStoreSettings> restoreStoreSettings({required int version});

  Future<CashierAccessEvaluation> evaluateAccess({
    required int userId,
    int? shopId,
    required String permission,
    Map<String, Object?>? context,
  });
  Future<PagedCashierAccessEmployees> loadAccessEmployees({
    String keyword = '',
    int page = 1,
    int pageSize = 20,
  });

  /// 覆盖式员工授权（敏感操作，confirm=true 必传）
  Future<void> assignAccessEmployee({
    required int adminId,
    required List<int> roleIds,
    required List<int> shopIds,
    required bool confirm,
  });

  /// 新建员工档案
  Future<void> createEmployee({
    required String userName,
    required String password,
    String? workNo,
    String? realName,
    String? jobTitle,
    List<int>? roleIds,
    List<int>? shopIds,
  });

  /// 更新员工档案
  Future<void> updateEmployee({
    required int adminId,
    String? workNo,
    String? realName,
    String? jobTitle,
    String? password,
    List<int>? roleIds,
    List<int>? shopIds,
  });

  /// 删除员工账号（敏感操作，confirm=true 必传）
  Future<void> deleteEmployee({required int adminId, required bool confirm});

  /// 变更员工账号状态（ACTIVE/DISABLED/RESIGNED/LOCKED），返回新状态与权限版本。
  Future<CashierEmployeeStatusResult> updateEmployeeStatus({
    required int adminId,
    required String status,
  });

  /// 强制下线指定员工全部活跃会话（令牌即刻全部作废）。
  Future<void> forceLogoutEmployee({required int adminId});

  /// 查询员工最终有效权限（角色命中 + ALLOW/DENY 覆盖）。
  Future<CashierEffectivePermissions> loadEffectivePermissions({
    required int adminId,
    int? shopId,
  });

  /// SoD 职责分离冲突预检（body: permissionCodes，返回命中规则）。
  Future<List<CashierAccessConflict>> checkAccessConflicts({
    required List<String> permissionCodes,
  });

  /// 权限策略列表（可按权限码过滤）。
  Future<List<CashierAccessPolicy>> loadAccessPolicies({
    String? permissionCode,
  });

  /// 创建权限策略（金额上限/折扣底线/显式覆盖等）。
  Future<CashierAccessPolicy> createAccessPolicy(CashierAccessPolicy policy);

  /// 修改权限策略。
  Future<CashierAccessPolicy> updateAccessPolicy({
    required int id,
    required CashierAccessPolicy policy,
  });

  /// 删除权限策略。
  Future<void> deleteAccessPolicy(int id);

  /// 绑定权限策略至角色（可指定门店范围，null 表示全局生效）。
  Future<void> assignAccessPolicy({
    required int roleId,
    required int policyId,
    int? shopId,
  });

  /// 审批记录详情（GET /admin/access/approvals/{id}）。
  Future<AccessApprovalRecord?> loadApprovalDetail(int id);

  Future<List<CashierAccessRole>> loadAccessRoles();

  Future<void> createAccessRole({
    required String roleCode,
    required String roleName,
    String remark = '',
    int sortOrder = 100,
    List<int>? permissionIds,
    String? forceReason,
  });

  Future<void> updateAccessRole({
    required int id,
    required int version,
    String? roleName,
    String? remark,
    int? sortOrder,
    List<int>? permissionIds,
    String? forceReason,
  });

  Future<void> deleteAccessRole({required int id, required bool confirm});

  Future<List<CashierPermissionCode>> loadPermissionCodes();

  Future<void> savePermissionCode({
    int? id,
    String? permissionCode,
    String? permissionName,
    String? module,
    String? remark,
    int? sortOrder,
  });

  Future<void> deletePermissionCode(int id);

  Future<List<CashierApiPermission>> loadApiPermissions();

  Future<void> saveApiPermission({
    int? id,
    required String method,
    required String pathPattern,
    required String permissionCode,
    String remark = '',
  });

  Future<void> deleteApiPermission(int id);

  Future<void> reloadApiPermissions();

  Future<List<CashierAccessAuditEntry>> loadAccessAudit({
    int page = 1,
    int pageSize = 20,
  });
  Future<List<CashierShopRef>> loadShopList({String keyword = ''});

  /// rbac 管理员全量列表（含角色与门店摘要，admin:manage 门控）。
  Future<PagedCashierAdministrators> loadAdministrators();

  Future<CashierBusinessSettings> loadBusinessSettings();

  Future<CashierBusinessSettings> changeBusinessStatus(
    bool isOpen, {
    bool force = false,
  });

  Future<CashierSettingsShift?> loadCurrentShift();

  Future<CashierPrinterDevice> savePrinterDevice(CashierPrinterDevice device);

  Future<bool> deletePrinterDevice(int id);

  Future<bool> testPrinterDevice(
    int id, {
    String? testType,
    String? customContent,
  });

  Future<CashierPrinterStatusProbe> probePrinterDeviceStatus(int id);

  Future<bool> clearPrinterQueue(int id);

  Future<bool> reprintPrintJob(int id);

  Future<bool> savePrintingRules({
    required int version,
    required List<Map<String, Object?>> rules,
  });

  Future<PrintingTemplateMeta> getPrintingTemplateMeta();

  Future<List<PrintingTemplate>> loadPrintingTemplates({
    String? scenario,
    String? paperSize,
  });

  Future<PrintingTemplate> getPrintingTemplate(int id);

  Future<PrintingTemplate> createPrintingTemplate({
    required String templateName,
    String? templateCode,
    required String scenario,
    String paperSize = '58mm',
    bool isDefault = false,
    String? templateJson,
    Map<String, Object?>? templateDsl,
  });

  Future<PrintingTemplate> updatePrintingTemplate({
    required int id,
    required int version,
    String? templateName,
    String? scenario,
    String? paperSize,
    bool? isDefault,
    String? templateJson,
    Map<String, Object?>? templateDsl,
  });

  Future<bool> deletePrintingTemplate(int id);

  Future<PrintingTemplate> setDefaultPrintingTemplate(int id);

  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'ORDER',
    int? orderId,
    String? orderNo,
    int? deviceId,
    String paperSize = '58mm',
    bool isAddDishes = false,
    List<String>? cidFilter,
    int? detailId,
    int? serveQty,
    int? shiftId,
    String? testType,
    String? customContent,
    int? templateId,
    String? templateJson,
    Map<String, Object?>? templateDsl,
    Map<String, Object?>? refundInfo,
    Map<String, Object?>? statistics,
  });

  Future<PrintPreviewResult> fetchExactPrintPreview({
    required String scenario,
    int? orderId,
    String? orderNo,
    int? shiftId,
    int? ruleId,
    int? deviceId,
    int? detailId,
    int? serveQty,
    List<String>? cidFilter,
  });
  Future<ShopTakeoutConfig> loadTakeoutConfig();

  Future<ShopTakeoutConfig> saveTakeoutConfig(ShopTakeoutConfig config);

  Future<ZsqAutoApiConfig> loadZsqAutoApi();

  Future<ZsqAutoApiConfig> saveZsqAutoApi(ZsqAutoApiConfig config);

  Future<PagedTakeoutDeliveries> loadTakeoutDeliveries({
    int page = 1,
    int pageSize = 20,
    String? dispatchStatus,
    DateTime? start,
    DateTime? end,
  });

  Future<TakeoutDeliveryDetail> loadTakeoutDeliveryDetail(int orderId);

  Future<ZsqRiderTracking> loadTakeoutTracking(int orderId);

  Future<TakeoutDeliveryDetail> updateTakeoutDeliveryStatus(
    int orderId,
    String dispatchStatus,
  );

  Future<TakeoutDeliveryDetail> zsqDispatch(
    int orderId, {
    bool redispatch = false,
  });

  Future<TakeoutDeliveryDetail> zsqSync(int orderId);

  Future<List<SubscribeSceneTemplate>> listSubscribeSceneTemplates();

  Future<bool> createSubscribeSceneTemplate(
    Map<String, dynamic> data,
  );

  Future<bool> updateSubscribeSceneTemplate(
    String sceneCode,
    Map<String, dynamic> data,
  );

  Future<bool> deleteSubscribeSceneTemplate(
    String sceneCode,
  );

  Future<List<SubscribeSendLog>> listSubscribeSendLogs({
    String? bizNo,
    String? openid,
    String? scene,
    String? status,
    int limit = 50,
  });
}
