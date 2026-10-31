import '../domain/subscribe_template.dart';
import 'dart:convert';
import '../../../core/cashier_operation_audit.dart';
import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../auth/domain/access_approval_models.dart';
import '../domain/cashier_settings.dart';
import '../domain/printing_template_models.dart';
import '../domain/receipt_preview_models.dart';
import 'cashier_settings_repository.dart';

class RealCashierSettingsRepository implements CashierSettingsRepository {
  const RealCashierSettingsRepository(this.client);

  final AdminApiClient client;

  @override
  Future<CashierSettingsOverview> loadSettingsOverview() async {
    final response = await client.get(settingsOverviewEndpoint);
    return CashierSettingsOverview.fromJson(_objectMap(response));
  }

  @override
  Future<CashierSettingsSectionData> loadSettingsSection({
    required String module,
    required String section,
    int page = 1,
    int pageSize = 20,
  }) async {
    final request = _settingsSectionRequest(
      module: module,
      section: section,
      page: page,
      pageSize: pageSize,
    );
    final response = await client.request(
      request.endpoint,
      query: request.query,
      body: request.body,
    );
    return CashierSettingsSectionData.fromResponse(response);
  }

  @override
  Future<CashierStoreSettings> loadStoreSettings() async {
    final response = await client.get(settingsStoreEndpoint);
    return CashierStoreSettings.fromJson(_objectMap(response));
  }

  @override
  Future<CashierStoreSettings> saveStoreSettings({
    required int version,
    Map<String, Object?>? basic,
    List<Map<String, Object?>>? businessHours,
    List<int>? businessDays,
  }) async {
    final response = await client.request(
      settingsStoreSaveEndpoint,
      body: {
        'version': version,
        if (basic != null && basic.isNotEmpty) 'basic': basic,
        if (businessHours != null) 'businessHours': businessHours,
        if (businessDays != null) 'businessDays': businessDays,
      },
    );
    final result = CashierStoreSettings.fromJson(_objectMap(response));
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'settings',
        action: 'store_edit',
        result: 'success',
        detail: {
          'version': version,
          'updated_fields': basic?.keys.toList(),
          'has_business_hours': businessHours != null,
          'has_business_days': businessDays != null,
        },
      ),
    );
    return result;
  }

  @override
  Future<void> uploadOfflineCollectQr({
    required bool isWechat,
    required List<int> bytes,
    required String filename,
  }) async {
    await client.postMultipart(
      offlineCollectUploadEndpoint,
      files: {
        isWechat ? 'wechatQr' : 'alipayQr': (
          bytes: bytes,
          filename: filename,
          contentType: _imageContentType(filename),
        ),
      },
    );
  }

  @override
  Future<int> publishAnnouncement({
    int? id,
    required String title,
    required String content,
    required int status,
    int sort = 0,
    String? startTime,
    String? endTime,
  }) async {
    final endpoint = id == null || id <= 0
        ? announcementAddEndpoint
        : announcementUpdateEndpoint;
    final response = await client.request(
      endpoint,
      body: {
        if (id != null && id > 0) 'id': id,
        'title': title,
        'content': content,
        'status': status,
        'sortOrder': sort,
        if (startTime != null && startTime.isNotEmpty) 'startTime': startTime,
        if (endTime != null && endTime.isNotEmpty) 'endTime': endTime,
      },
    );
    final map = _objectMap(response);
    return int.tryParse('${map['id'] ?? 0}') ?? 0;
  }

  @override
  Future<CashierStoreSettings> restoreStoreSettings({
    required int version,
  }) async {
    final response = await client.request(
      settingsStoreOverrideEndpoint,
      query: {'module': 'store', 'version': version, 'confirm': true},
    );
    final result = CashierStoreSettings.fromJson(_objectMap(response));
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'settings',
        action: 'store_restore',
        result: 'success',
        detail: {'version': version},
      ),
    );
    return result;
  }

  @override
  Future<CashierAccessEvaluation> evaluateAccess({
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
    return CashierAccessEvaluation.fromJson(_objectMap(response));
  }

  @override
  Future<PagedCashierAccessEmployees> loadAccessEmployees({
    String keyword = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await client.get(
      settingsAccessEmployeesEndpoint,
      query: {
        if (keyword.isNotEmpty) 'keyword': keyword,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return PagedCashierAccessEmployees.fromJson(_objectMap(response));
  }

  @override
  Future<void> assignAccessEmployee({
    required int adminId,
    required List<int> roleIds,
    required List<int> shopIds,
    required bool confirm,
  }) async {
    await client.request(
      settingsAccessEmployeeCreateEndpoint,
      body: {
        'adminId': adminId,
        'roleIds': roleIds,
        'shopIds': shopIds,
        'confirm': confirm,
      },
    );
  }

  @override
  Future<void> createEmployee({
    required String userName,
    required String password,
    String? workNo,
    String? realName,
    String? jobTitle,
    List<int>? roleIds,
    List<int>? shopIds,
  }) async {
    final body = <String, Object?>{
      'userName': userName,
      'password': password,
      if (workNo != null && workNo.trim().isNotEmpty) 'workNo': workNo.trim(),
      if (realName != null && realName.trim().isNotEmpty)
        'realName': realName.trim(),
      if (jobTitle != null && jobTitle.trim().isNotEmpty)
        'jobTitle': jobTitle.trim(),
      if (roleIds != null) 'roleIds': roleIds,
      if (shopIds != null) 'shopIds': shopIds,
    };
    final res = await client.request(
      adminAdministratorCreateEndpoint,
      body: body,
    );
    final map = _objectMap(res);
    final rawId = map['id'];
    final newId = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    if (newId != null &&
        newId > 0 &&
        ((shopIds != null && shopIds.isNotEmpty) ||
            (roleIds != null && roleIds.isNotEmpty))) {
      try {
        await assignAccessEmployee(
          adminId: newId,
          roleIds: roleIds ?? const [],
          shopIds: shopIds ?? const [],
          confirm: true,
        );
      } catch (error) {
        throw EmployeeAssignmentException(newId, error);
      }
    }
  }

  @override
  Future<void> updateEmployee({
    required int adminId,
    String? workNo,
    String? realName,
    String? jobTitle,
    String? password,
    List<int>? roleIds,
    List<int>? shopIds,
  }) async {
    final body = <String, Object?>{
      'workNo': (workNo != null && workNo.trim().isNotEmpty)
          ? workNo.trim()
          : '',
      'realName': (realName != null && realName.trim().isNotEmpty)
          ? realName.trim()
          : '',
      'jobTitle': (jobTitle != null && jobTitle.trim().isNotEmpty)
          ? jobTitle.trim()
          : '',
      if (password != null && password.trim().isNotEmpty)
        'password': password.trim(),
    };
    await client.request(
      AdminEndpoint(
        method: 'PUT',
        path: '/admin/administrator/$adminId',
        permissionCode: 'admin:manage',
      ),
      body: body,
    );
    if (roleIds != null || shopIds != null) {
      await assignAccessEmployee(
        adminId: adminId,
        roleIds: roleIds ?? const [],
        shopIds: shopIds ?? const [],
        confirm: true,
      );
    }
  }

  @override
  Future<void> deleteEmployee({
    required int adminId,
    required bool confirm,
  }) async {
    await client.request(
      settingsAccessEmployeeDeleteEndpoint(adminId),
      query: {'confirm': confirm},
    );
  }

  @override
  Future<CashierEmployeeStatusResult> updateEmployeeStatus({
    required int adminId,
    required String status,
  }) async {
    final response = await client.request(
      settingsAccessEmployeeStatusEndpoint(adminId),
      body: {'status': status},
    );
    return CashierEmployeeStatusResult.fromJson(_objectMap(response));
  }

  @override
  Future<void> forceLogoutEmployee({required int adminId}) async {
    await client.request(settingsAccessEmployeeForceLogoutEndpoint(adminId));
  }

  @override
  Future<CashierEffectivePermissions> loadEffectivePermissions({
    required int adminId,
    int? shopId,
  }) async {
    final response = await client.get(
      settingsAccessEffectivePermissionsEndpoint(adminId),
      query: {
        if (shopId != null) 'shopId': shopId},
    );
    return CashierEffectivePermissions.fromJson(_objectMap(response));
  }

  @override
  Future<List<CashierAccessConflict>> checkAccessConflicts({
    required List<String> permissionCodes,
  }) async {
    final response = await client.post(
      settingsAccessConflictsCheckEndpoint,
      body: {'permissionCodes': permissionCodes},
    );
    final raw = _objectMap(response)['conflicts'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => CashierAccessConflict.fromJson(e.cast<String, Object?>()))
        .toList(growable: false);
  }

  @override
  Future<List<CashierAccessPolicy>> loadAccessPolicies({
    String? permissionCode,
  }) async {
    final response = await client.get(
      settingsAccessPoliciesEndpoint,
      query: {
        if (permissionCode != null && permissionCode.trim().isNotEmpty)
          'permissionCode': permissionCode.trim(),
      },
    );
    final raw = _objectMap(response)['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => CashierAccessPolicy.fromJson(e.cast<String, Object?>()))
        .toList(growable: false);
  }

  @override
  Future<CashierAccessPolicy> createAccessPolicy(
    CashierAccessPolicy policy,
  ) async {
    final response = await client.request(
      settingsAccessPolicyCreateEndpoint,
      body: policy.toJson(),
    );
    final map = _objectMap(response);
    final data = map['data'] is Map
        ? (map['data'] as Map).cast<String, Object?>()
        : map;
    return CashierAccessPolicy.fromJson(data);
  }

  @override
  Future<CashierAccessPolicy> updateAccessPolicy({
    required int id,
    required CashierAccessPolicy policy,
  }) async {
    final response = await client.request(
      settingsAccessPolicyUpdateEndpoint(id),
      body: policy.toJson(),
    );
    final map = _objectMap(response);
    final data = map['data'] is Map
        ? (map['data'] as Map).cast<String, Object?>()
        : map;
    return CashierAccessPolicy.fromJson(data);
  }

  @override
  Future<void> deleteAccessPolicy(int id) async {
    await client.request(settingsAccessPolicyDeleteEndpoint(id));
  }

  @override
  Future<void> assignAccessPolicy({
    required int roleId,
    required int policyId,
    int? shopId,
  }) async {
    await client.request(
      settingsAccessPolicyAssignEndpoint,
      body: {
        'roleId': roleId,
        'policyId': policyId,
        if (shopId != null) 'shopId': shopId,
      },
    );
  }

  @override
  Future<AccessApprovalRecord?> loadApprovalDetail(int id) async {
    final response = await client.get(adminAccessApprovalDetailEndpoint(id));
    final map = _objectMap(response);
    final data = map['data'];
    if (data is Map) return AccessApprovalRecord.fromJson(data.cast<String, Object?>());
    if (data == null) return null;
    return AccessApprovalRecord.fromJson(map);
  }

  @override
  Future<List<CashierAccessRole>> loadAccessRoles() async {
    final response = await client.get(settingsAccessRolesEndpoint);
    final map = _objectMap(response);
    final items = map['items'] is List
        ? (map['items'] as List)
              .whereType<Map>()
              .map((e) => e.cast<String, Object?>())
              .toList()
        : const <Map<String, Object?>>[];
    return items.map(CashierAccessRole.fromJson).toList(growable: false);
  }

  @override
  Future<void> createAccessRole({
    required String roleCode,
    required String roleName,
    String remark = '',
    int sortOrder = 100,
    List<int>? permissionIds,
    String? forceReason,
  }) async {
    await client.request(
      settingsAccessRoleCreateEndpoint,
      body: {
        'roleCode': roleCode,
        'roleName': roleName,
        'remark': remark,
        'sortOrder': sortOrder,
        if (permissionIds != null) 'permissionIds': permissionIds,
        if (forceReason != null && forceReason.trim().isNotEmpty)
          'forceReason': forceReason.trim(),
      },
    );
  }

  @override
  Future<void> updateAccessRole({
    required int id,
    required int version,
    String? roleName,
    String? remark,
    int? sortOrder,
    List<int>? permissionIds,
    String? forceReason,
  }) async {
    await client.request(
      settingsAccessRoleUpdateEndpoint(id),
      body: {
        'version': version,
        if (roleName != null) 'roleName': roleName,
        if (remark != null) 'remark': remark,
        if (sortOrder != null) 'sortOrder': sortOrder,
        if (permissionIds != null) 'permissionIds': permissionIds,
        if (forceReason != null && forceReason.trim().isNotEmpty)
          'forceReason': forceReason.trim(),
      },
    );
  }

  @override
  Future<void> deleteAccessRole({
    required int id,
    required bool confirm,
  }) async {
    await client.request(
      settingsAccessRoleDeleteEndpoint(id),
      query: {'confirm': confirm},
    );
  }

  @override
  Future<List<CashierPermissionCode>> loadPermissionCodes() async {
    final response = await client.get(rbacPermissionsEndpoint);
    final map = _objectMap(response);
    final data = map['data'] is Map ? _objectMap(map['data']) : map;
    final items = data['list'] is List
        ? (data['list'] as List)
              .whereType<Map>()
              .map((e) => e.cast<String, Object?>())
              .toList()
        : const <Map<String, Object?>>[];
    return items.map(CashierPermissionCode.fromJson).toList(growable: false);
  }

  @override
  Future<void> savePermissionCode({
    int? id,
    String? permissionCode,
    String? permissionName,
    String? module,
    String? remark,
    int? sortOrder,
  }) async {
    await client.request(
      rbacPermissionsSaveEndpoint,
      body: {
        if (id != null) 'id': id,
        if (permissionCode != null && permissionCode.isNotEmpty)
          'permission_code': permissionCode,
        if (permissionName != null && permissionName.isNotEmpty)
          'permission_name': permissionName,
        if (module != null) 'module': module,
        if (remark != null) 'remark': remark,
        if (sortOrder != null) 'sort_order': sortOrder,
      },
    );
  }

  @override
  Future<void> deletePermissionCode(int id) async {
    await client.request(rbacPermissionDeleteByIdEndpoint(id));
  }

  @override
  Future<List<CashierApiPermission>> loadApiPermissions() async {
    final response = await client.get(rbacApiPermissionsEndpoint);
    final map = _objectMap(response);
    final data = map['data'] is Map ? _objectMap(map['data']) : map;
    final items = data['list'] is List
        ? (data['list'] as List)
              .whereType<Map>()
              .map((e) => e.cast<String, Object?>())
              .toList()
        : const <Map<String, Object?>>[];
    return items.map(CashierApiPermission.fromJson).toList(growable: false);
  }

  @override
  Future<void> saveApiPermission({
    int? id,
    required String method,
    required String pathPattern,
    required String permissionCode,
    String remark = '',
  }) async {
    await client.request(
      rbacApiPermissionsSaveEndpoint,
      body: {
        if (id != null) 'id': id,
        'method': method,
        'path_pattern': pathPattern,
        'permission_code': permissionCode,
        'remark': remark,
      },
    );
  }

  @override
  Future<void> deleteApiPermission(int id) async {
    await client.request(rbacApiPermissionDeleteByIdEndpoint(id));
  }

  @override
  Future<void> reloadApiPermissions() async {
    await client.request(rbacApiPermissionsReloadEndpoint);
  }

  @override
  Future<List<CashierAccessAuditEntry>> loadAccessAudit({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await client.get(
      settingsLogsEndpoint,
      query: {'module': 'security', 'pageNum': page, 'pageSize': pageSize},
    );
    final map = _objectMap(response);
    final data = map['data'] is Map ? _objectMap(map['data']) : map;
    final items = data['list'] is List
        ? (data['list'] as List)
              .whereType<Map>()
              .map((e) => e.cast<String, Object?>())
              .toList()
        : const <Map<String, Object?>>[];
    return items.map(CashierAccessAuditEntry.fromJson).toList(growable: false);
  }

  @override
  Future<List<CashierShopRef>> loadShopList({String keyword = ''}) async {
    final response = await client.get(
      adminShopListEndpoint,
      query: {if (keyword.isNotEmpty) 'keyword': keyword},
    );
    final map = _objectMap(response);
    final items = map['list'] is List
        ? (map['list'] as List)
              .whereType<Map>()
              .map((e) => e.cast<String, Object?>())
              .toList()
        : const <Map<String, Object?>>[];
    return items.map(CashierShopRef.fromJson).toList(growable: false);
  }

  @override
  Future<PagedCashierAdministrators> loadAdministrators() async {
    final response = await client.get(adminAdministratorListEndpoint);
    return PagedCashierAdministrators.fromJson(_objectMap(response));
  }

  @override
  Future<CashierBusinessSettings> loadBusinessSettings() async {
    final response = await client.post(settingsBusinessEndpoint);
    return CashierBusinessSettings.fromJson(_objectMap(response));
  }

  @override
  Future<CashierBusinessSettings> changeBusinessStatus(
    bool isOpen, {
    bool force = false,
  }) async {
    await client.post(
      cashierShopBusinessEndpoint,
      body: {'bus': isOpen ? '1' : '0', if (force) 'force': '1'},
    );
    return loadBusinessSettings();
  }

  @override
  Future<CashierSettingsShift?> loadCurrentShift() async {
    final response = await client.get(cashierShiftCurrentEndpoint);
    if (response == null) return null;
    final root = _objectMap(response);
    final rawShift = root.containsKey('shift') ? root['shift'] : root;
    if (rawShift == null) return null;
    final shift = _objectMap(rawShift);
    if (shift.isEmpty) return null;
    return CashierSettingsShift.fromJson(shift);
  }

  @override
  Future<CashierPrinterDevice> savePrinterDevice(
    CashierPrinterDevice device,
  ) async {
    final body = device.toJson();
    final response = device.id != null && device.id! > 0
        ? await client.request(
            settingsPrintingDeviceUpdateEndpoint(device.id!),
            body: body,
          )
        : await client.request(
            settingsPrintingDeviceCreateEndpoint,
            body: body,
          );
    final map = _objectMap(response);
    if (map.isEmpty) {
      return device;
    }
    final deviceMap = map['device'] is Map
        ? _objectMap(map['device'])
        : (map['data'] is Map ? _objectMap(map['data']) : map);
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'kds',
        action: 'device_bind',
        result: 'success',
        targetType: 'printer',
        targetId: '${deviceMap['id'] ?? device.id}',
      ),
    );
    return CashierPrinterDevice.fromJson(deviceMap);
  }

  @override
  Future<bool> deletePrinterDevice(int id) async {
    await client.request(settingsPrintingDeviceDeleteEndpoint(id));
    return true;
  }

  @override
  Future<bool> testPrinterDevice(
    int id, {
    String? testType,
    String? customContent,
  }) async {
    await client.request(
      settingsPrintingDeviceTestEndpoint(id),
      body: {
        if (testType != null) 'testType': testType,
        if (customContent != null) 'customContent': customContent,
      },
    );
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'print',
        action: 'test',
        result: 'success',
        targetType: 'printer',
        targetId: '$id',
        detail: {'test_type': testType, 'custom_content': customContent},
      ),
    );
    return true;
  }

  @override
  Future<CashierPrinterStatusProbe> probePrinterDeviceStatus(int id) async {
    final response = await client.get(settingsPrintingDeviceStatusEndpoint(id));
    final map = _objectMap(response);
    final statusMap = map['data'] is Map ? _objectMap(map['data']) : map;
    return CashierPrinterStatusProbe.fromJson(statusMap);
  }

  @override
  Future<bool> clearPrinterQueue(int id) async {
    await client.request(settingsPrintingDeviceClearQueueEndpoint(id));
    return true;
  }

  @override
  Future<bool> reprintPrintJob(int id) async {
    await client.request(settingsPrintingJobReprintEndpoint(id));
    return true;
  }

  @override
  Future<bool> savePrintingRules({
    required int version,
    required List<Map<String, Object?>> rules,
  }) async {
    await client.request(
      settingsPrintingRulesSaveEndpoint,
      body: {'version': version, 'rules': rules},
    );
    return true;
  }

  @override
  Future<PrintingTemplateMeta> getPrintingTemplateMeta() async {
    final response = await client.request(
      settingsPrintingTemplatesMetaEndpoint,
    );
    if (response is Map<String, Object?>) {
      final data = response['data'] ?? response['meta'];
      if (data is Map) {
        return PrintingTemplateMeta.fromJson(data.cast<String, Object?>());
      }
      return PrintingTemplateMeta.fromJson(response);
    }
    return const PrintingTemplateMeta();
  }

  @override
  Future<List<PrintingTemplate>> loadPrintingTemplates({
    String? scenario,
    String? paperSize,
  }) async {
    final response = await client.request(
      settingsPrintingTemplatesEndpoint,
      query: {
        if (scenario != null && scenario.isNotEmpty && scenario != 'ALL')
          'scenario': scenario,
        if (paperSize != null && paperSize.isNotEmpty && paperSize != 'ALL')
          'paperSize': paperSize,
      },
    );
    final list = _extractTemplateList(response);
    return list.map((item) => PrintingTemplate.fromJson(item)).toList();
  }

  @override
  Future<PrintingTemplate> getPrintingTemplate(int id) async {
    final response = await client.request(
      settingsPrintingTemplateDetailEndpoint(id),
    );
    return PrintingTemplate.fromJson(_extractTemplateMap(response));
  }

  @override
  Future<PrintingTemplate> createPrintingTemplate({
    required String templateName,
    String? templateCode,
    required String scenario,
    String paperSize = '58mm',
    bool isDefault = false,
    String? templateJson,
    Map<String, Object?>? templateDsl,
  }) async {
    final response = await client.request(
      settingsPrintingTemplateCreateEndpoint,
      body: {
        'templateName': templateName,
        if (templateCode != null && templateCode.isNotEmpty)
          'templateCode': templateCode,
        'scenario': scenario,
        'paperSize': paperSize,
        'isDefault': isDefault,
        if (templateJson != null) 'templateJson': templateJson,
        if (templateDsl != null) 'templateDsl': templateDsl,
      },
    );
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'print',
        action: 'template',
        result: 'success',
        targetType: 'print_template',
        targetId: templateName,
        detail: {
          'op': 'create',
          'name': templateName,
          'scenario': scenario,
          'paper_size': paperSize,
        },
      ),
    );
    return PrintingTemplate.fromJson(_extractTemplateMap(response));
  }

  @override
  Future<PrintingTemplate> updatePrintingTemplate({
    required int id,
    required int version,
    String? templateName,
    String? scenario,
    String? paperSize,
    bool? isDefault,
    String? templateJson,
    Map<String, Object?>? templateDsl,
  }) async {
    final response = await client.request(
      settingsPrintingTemplateUpdateEndpoint(id),
      body: {
        'version': version,
        if (templateName != null) 'templateName': templateName,
        if (scenario != null && scenario.isNotEmpty) 'scenario': scenario,
        if (paperSize != null) 'paperSize': paperSize,
        if (isDefault != null) 'isDefault': isDefault,
        if (templateJson != null) 'templateJson': templateJson,
        if (templateDsl != null) 'templateDsl': templateDsl,
      },
    );
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'print',
        action: 'template',
        result: 'success',
        targetType: 'print_template',
        targetId: '$id',
        detail: {
          'op': 'update',
          'name': templateName,
          'scenario': scenario,
          'paper_size': paperSize,
        },
      ),
    );
    return PrintingTemplate.fromJson(_extractTemplateMap(response));
  }

  @override
  Future<bool> deletePrintingTemplate(int id) async {
    await client.request(settingsPrintingTemplateDeleteEndpoint(id));
    return true;
  }

  @override
  Future<PrintingTemplate> setDefaultPrintingTemplate(int id) async {
    final response = await client.request(
      settingsPrintingTemplateSetDefaultEndpoint(id),
    );
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'print',
        action: 'template',
        result: 'success',
        targetType: 'print_template',
        targetId: '$id',
        detail: {'op': 'set_default'},
      ),
    );
    return PrintingTemplate.fromJson(_extractTemplateMap(response));
  }

  @override
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
  }) async {
    final response = await client.request(
      settingsPrintingPreviewPostEndpoint,
      body: {
        'scenario': scenario,
        if (orderId != null) 'orderId': orderId,
        if (orderNo != null) 'orderNo': orderNo,
        if (deviceId != null) 'deviceId': deviceId,
        'paperSize': paperSize,
        'isAddDishes': isAddDishes,
        if (cidFilter != null) 'cidFilter': cidFilter,
        if (detailId != null) 'detailId': detailId,
        if (serveQty != null) 'serveQty': serveQty,
        if (shiftId != null) 'shiftId': shiftId,
        if (testType != null) 'testType': testType,
        if (customContent != null) 'customContent': customContent,
        if (templateId != null) 'templateId': templateId,
        if (templateJson != null) 'templateJson': templateJson,
        if (templateDsl != null) 'templateDsl': templateDsl,
        if (refundInfo != null) 'refundInfo': refundInfo,
        if (statistics != null) 'statistics': statistics,
      },
    );
    final map = _objectMap(response);
    final dataMap = map['data'] is Map ? _objectMap(map['data']) : map;
    return PrintPreviewResult.fromJson(dataMap);
  }

  @override
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
  }) async {
    final response = await client.request(
      settingsPrintingPreviewExactEndpoint,
      body: {
        'scenario': scenario,
        if (orderId != null) 'orderId': orderId,
        if (orderNo != null) 'orderNo': orderNo,
        if (shiftId != null) 'shiftId': shiftId,
        if (ruleId != null) 'ruleId': ruleId,
        if (deviceId != null) 'deviceId': deviceId,
        if (detailId != null) 'detailId': detailId,
        if (serveQty != null) 'serveQty': serveQty,
        if (cidFilter != null) 'cidFilter': cidFilter,
      },
    );
    final map = _objectMap(response);
    final dataMap = map['data'] is Map ? _objectMap(map['data']) : map;
    return PrintPreviewResult.fromJson(dataMap);
  }

  @override
  Future<ShopTakeoutConfig> loadTakeoutConfig() async {
    final response = await client.get(takeoutConfigEndpoint);
    final map = _objectMap(response);
    final config = map['config'] is Map ? _objectMap(map['config']) : map;
    return ShopTakeoutConfig.fromJson(config);
  }

  @override
  Future<ShopTakeoutConfig> saveTakeoutConfig(ShopTakeoutConfig config) async {
    final response = await client.request(
      takeoutConfigSaveEndpoint,
      body: {
        'enabled': config.enabled == 1,
        if (config.deliveryFee != null) 'deliveryFee': config.deliveryFee,
        if (config.minOrderAmount != null)
          'minOrderAmount': config.minOrderAmount,
        if (config.freeDeliveryThreshold != null)
          'freeDeliveryThreshold': config.freeDeliveryThreshold,
        if (config.maxDeliveryDistanceKm != null)
          'maxDeliveryDistanceKm': config.maxDeliveryDistanceKm,
        if (config.freeDeliveryMaxDistanceKm != null)
          'freeDeliveryMaxDistanceKm': config.freeDeliveryMaxDistanceKm,
        'deliveryFeeTiersJson': jsonEncode(
          config.tiers.map((tier) => tier.toJson()).toList(growable: false),
        ),
        if (config.leadTimeMinutes != null)
          'leadTimeMinutes': config.leadTimeMinutes,
        'remark': config.remark,
      },
    );
    final map = _objectMap(response);
    final saved = map['config'] is Map ? _objectMap(map['config']) : map;
    return ShopTakeoutConfig.fromJson(saved);
  }

  @override
  Future<ZsqAutoApiConfig> loadZsqAutoApi() async {
    final response = await client.get(zsqAutoApiEndpoint);
    return ZsqAutoApiConfig.fromJson(_objectMap(response));
  }

  @override
  Future<ZsqAutoApiConfig> saveZsqAutoApi(ZsqAutoApiConfig config) async {
    final response = await client.request(
      zsqAutoApiSaveEndpoint,
      body: {
        'shopId': config.shopId,
        'autoDispatchEnabled': config.autoDispatchEnabled,
        'takeoutSyncEnabled': config.takeoutSyncEnabled,
      },
    );
    return ZsqAutoApiConfig.fromJson(_objectMap(response));
  }

  @override
  Future<PagedTakeoutDeliveries> loadTakeoutDeliveries({
    int page = 1,
    int pageSize = 20,
    String? dispatchStatus,
    DateTime? start,
    DateTime? end,
  }) async {
    String fmtDate(DateTime t) =>
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final response = await client.post(
      settingsTakeoutDeliveryListEndpoint,
      body: {
        'pageNum': page,
        'pageSize': pageSize,
        if (dispatchStatus != null && dispatchStatus.isNotEmpty)
          'dispatch_status': dispatchStatus,
        // v1.2.279：时间筛选传年月日，未传时后端按门店营业日窗口补全。
        if (start != null) 'startTime': fmtDate(start),
        if (end != null) 'endTime': fmtDate(end),
      },
    );
    return PagedTakeoutDeliveries.fromJson(_objectMap(response));
  }

  @override
  Future<TakeoutDeliveryDetail> loadTakeoutDeliveryDetail(int orderId) async {
    final response = await client.get(
      takeoutDeliveryDetailEndpoint,
      query: {'orderId': orderId},
    );
    return TakeoutDeliveryDetail.fromJson(_objectMap(response));
  }

  @override
  Future<ZsqRiderTracking> loadTakeoutTracking(int orderId) async {
    final response = await client.get(
      takeoutDeliveryTrackingEndpoint,
      query: {'orderId': orderId},
    );
    final map = _objectMap(response);
    final code = (map['code'] as num?)?.toInt() ?? 0;
    final canRedispatch = code == 4091 || map['canRedispatch'] == true;
    final missing = (map['missingOpenOrderId'] as num?)?.toInt();
    return ZsqRiderTracking.fromJson(
      map,
      canRedispatch: canRedispatch,
      missingOpenOrderId: missing,
    );
  }

  @override
  Future<TakeoutDeliveryDetail> updateTakeoutDeliveryStatus(
    int orderId,
    String dispatchStatus,
  ) async {
    final response = await client.post(
      takeoutDeliveryStatusEndpoint,
      body: {'orderId': orderId, 'dispatch_status': dispatchStatus},
    );
    return TakeoutDeliveryDetail.fromJson(_objectMap(response));
  }

  @override
  Future<TakeoutDeliveryDetail> zsqDispatch(
    int orderId, {
    bool redispatch = false,
  }) async {
    final response = await client.post(
      redispatch ? takeoutZsqRedispatchEndpoint : takeoutZsqDispatchEndpoint,
      body: {'orderId': orderId},
    );
    return TakeoutDeliveryDetail.fromJson(_objectMap(response));
  }

  @override
  Future<TakeoutDeliveryDetail> zsqSync(int orderId) async {
    final response = await client.post(
      takeoutZsqSyncEndpoint,
      body: {'orderId': orderId},
    );
    return TakeoutDeliveryDetail.fromJson(_objectMap(response));
  }

  @override
  Future<List<SubscribeSceneTemplate>> listSubscribeSceneTemplates() async {
    final response = await client.get(adminSubscribeScenesGetEndpoint);
    List<dynamic> list = [];
    if (response is List) {
      list = response;
    } else if (response is Map) {
      final data = response['data'];
      if (data is List) {
        list = data;
      } else if (response['items'] is List) {
        list = response['items'] as List;
      } else if (response['list'] is List) {
        list = response['list'] as List;
      }
    }
    return list
        .whereType<Map>()
        .map((item) => SubscribeSceneTemplate.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<bool> createSubscribeSceneTemplate(
    Map<String, dynamic> data,
  ) async {
    final response = await client.post(
      adminSubscribeSceneCreateEndpoint,
      body: data,
    );
    if (response is Map) {
      return response['code'] == 0 || response['code'] == 200;
    }
    return true;
  }

  @override
  Future<bool> updateSubscribeSceneTemplate(
    String sceneCode,
    Map<String, dynamic> data,
  ) async {
    final endpoint = adminSubscribeScenePutEndpoint.withPathParams({'sceneCode': sceneCode});
    final response = await client.request(
      endpoint,
      body: data,
    );
    if (response is Map) {
      return response['code'] == 0 || response['code'] == 200;
    }
    return true;
  }

  @override
  Future<bool> deleteSubscribeSceneTemplate(
    String sceneCode,
  ) async {
    final endpoint = adminSubscribeSceneDeleteEndpoint.withPathParams({'sceneCode': sceneCode});
    final response = await client.request(endpoint);
    if (response is Map) {
      return response['code'] == 0 || response['code'] == 200;
    }
    return true;
  }

  @override
  Future<List<SubscribeSendLog>> listSubscribeSendLogs({
    String? bizNo,
    String? openid,
    String? scene,
    String? status,
    int limit = 50,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      if (bizNo != null && bizNo.isNotEmpty) 'bizNo': bizNo,
      if (openid != null && openid.isNotEmpty) 'openid': openid,
      if (scene != null && scene.isNotEmpty) 'scene': scene,
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final response = await client.get(
      adminSubscribeLogsGetEndpoint,
      query: query,
    );
    List<dynamic> list = [];
    if (response is List) {
      list = response;
    } else if (response is Map) {
      final data = response['data'];
      if (data is List) {
        list = data;
      } else if (response['items'] is List) {
        list = response['items'] as List;
      } else if (response['list'] is List) {
        list = response['list'] as List;
      }
    }
    return list
        .whereType<Map>()
        .map((item) => SubscribeSendLog.fromJson(item.cast<String, dynamic>()))
        .toList();
  }
}

String _imageContentType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/png';
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Map<String, Object?>> _extractTemplateList(Object? response) {
  if (response is List) {
    return response
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList();
  }
  if (response is Map) {
    final map = response.cast<String, Object?>();
    for (final key in const [
      'templates',
      'data',
      'items',
      'list',
      'records',
      'rows',
    ]) {
      final val = map[key];
      if (val is List) {
        return val
            .whereType<Map>()
            .map((e) => e.cast<String, Object?>())
            .toList();
      }
    }
  }
  return const [];
}

Map<String, Object?> _extractTemplateMap(Object? response) {
  if (response is Map<String, Object?>) {
    if (response['template'] is Map) {
      return (response['template'] as Map).cast<String, Object?>();
    }
    if (response['data'] is Map) {
      return (response['data'] as Map).cast<String, Object?>();
    }
    return response;
  }
  if (response is Map) {
    final map = response.cast<String, Object?>();
    if (map['template'] is Map) {
      return (map['template'] as Map).cast<String, Object?>();
    }
    if (map['data'] is Map) {
      return (map['data'] as Map).cast<String, Object?>();
    }
    return map;
  }
  return const {};
}

class _SettingsSectionRequest {
  const _SettingsSectionRequest(
    this.endpoint, {
    this.query = const {},
    this.body = const {},
  });

  final AdminEndpoint endpoint;
  final Map<String, Object?> query;
  final Map<String, Object?> body;
}

_SettingsSectionRequest _settingsSectionRequest({
  required String module,
  required String section,
  required int page,
  required int pageSize,
}) {
  final paged = <String, Object?>{'page': page, 'pageSize': pageSize};
  return switch ('$module:$section') {
    'store:profile' ||
    'store:business' ||
    'store:business-day' ||
    'store:inheritance' => const _SettingsSectionRequest(settingsStoreEndpoint),
    'store:notice' => _SettingsSectionRequest(
      announcementListEndpoint,
      query: paged,
    ),
    'printer:devices' || 'printer:test' => _SettingsSectionRequest(
      settingsPrintingDevicesEndpoint,
      query: paged,
    ),
    'printer:rules' || 'printer:templates' => const _SettingsSectionRequest(
      settingsPrintingRulesEndpoint,
    ),
    'printer:jobs' => _SettingsSectionRequest(
      settingsPrintingJobsEndpoint,
      query: paged,
    ),
    'payment:channels' => const _SettingsSectionRequest(
      paymentCapabilitiesEndpoint,
    ),
    'notification:rules' || 'notification:receivers' => _SettingsSectionRequest(
      settingsNotificationRulesEndpoint,
      query: paged,
    ),
    'notification:deliveries' => _SettingsSectionRequest(
      settingsNotificationDeliveriesEndpoint,
      query: paged,
    ),
    'marketing:campaigns' || 'marketing:eligibility' => _SettingsSectionRequest(
      settingsFirstOrderCampaignsEndpoint,
      query: paged,
    ),
    'marketing:redemptions' => _SettingsSectionRequest(
      settingsFirstOrderRedemptionsEndpoint,
      query: paged,
    ),
    'employee:employees' || 'employee:shops' || 'employee:changes' =>
      _SettingsSectionRequest(settingsAccessEmployeesEndpoint, query: paged),
    'employee:roles' || 'employee:matrix' => const _SettingsSectionRequest(
      settingsAccessRolesEndpoint,
    ),
    'inventory:materials' => _SettingsSectionRequest(
      materialListEndpoint,
      query: paged,
    ),
    'inventory:bom' => _SettingsSectionRequest(
      settingsInventoryBomsEndpoint,
      query: paged,
    ),
    'inventory:purchase' => _SettingsSectionRequest(
      settingsInventoryPurchasesEndpoint,
      query: paged,
    ),
    'inventory:suppliers' => _SettingsSectionRequest(
      settingsInventorySuppliersEndpoint,
      query: paged,
    ),
    'inventory:warehouses' => _SettingsSectionRequest(
      settingsInventoryWarehousesEndpoint,
      query: paged,
    ),
    'inventory:transfers' => _SettingsSectionRequest(
      settingsInventoryTransfersEndpoint,
      query: paged,
    ),
    'inventory:batches' => _SettingsSectionRequest(
      settingsInventoryBatchesEndpoint,
      query: paged,
    ),
    'inventory:ledger' => _SettingsSectionRequest(
      materialAlertEndpoint,
      query: paged,
    ),
    'delivery:platforms' ||
    'delivery:rules' => const _SettingsSectionRequest(takeoutConfigEndpoint),
    'delivery:zsq' => const _SettingsSectionRequest(zsqAutoApiEndpoint),
    'delivery:records' => _SettingsSectionRequest(
      settingsTakeoutDeliveryListEndpoint,
      body: paged,
    ),
    'report:catalog' => const _SettingsSectionRequest(reportDashboardEndpoint),
    'report:business-day' => const _SettingsSectionRequest(
      settingsStoreEndpoint,
    ),
    'report:exports' => _SettingsSectionRequest(
      settingsReportExportsEndpoint,
      query: paged,
    ),
    'log:operations' => _SettingsSectionRequest(
      settingsLogsEndpoint,
      query: {...paged, 'type': 'operation'},
    ),
    'log:devices' => _SettingsSectionRequest(
      settingsLogsEndpoint,
      query: {...paged, 'type': 'device'},
    ),
    'log:archive' || 'log:exports' => _SettingsSectionRequest(
      settingsLogsEndpoint,
      query: paged,
    ),
    _ => throw ArgumentError('不支持的系统设置页面：$module/$section'),
  };
}
