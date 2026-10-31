import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/auth/data/access_approval_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_access_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

class _FakeCrudCashierSettingsRepository implements CashierSettingsRepository {
  List<CashierAccessEmployee> accessEmployees = [
    const CashierAccessEmployee(
      adminId: 1,
      userName: 'zhang_manager',
      workNo: 'EMP1001',
      realName: '张店长',
      jobTitle: '店长',
      roles: [
        CashierAccessRoleRef(id: 1, roleCode: 'ROLE_STORE_MANAGER', roleName: '店长',
        ),
      ],
      shops: [1, 2],
    ),
    const CashierAccessEmployee(
      adminId: 2,
      userName: 'li_cashier',
      workNo: 'EMP1002',
      realName: '李收银',
      jobTitle: '收银员',
      roles: [
        CashierAccessRoleRef(id: 2, roleCode: 'ROLE_CASHIER', roleName: '收银员'),
      ],
      shops: [1],
    ),
  ];

  List<CashierAccessRole> accessRoles = const [
    CashierAccessRole(
      id: 1,
      roleCode: 'ROLE_STORE_MANAGER',
      roleName: '店长',
      sortOrder: 10,
    ),
    CashierAccessRole(
      id: 2,
      roleCode: 'ROLE_CASHIER',
      roleName: '收银员',
      sortOrder: 20,
    ),
  ];

  List<CashierShopRef> shopList = const [
    CashierShopRef(id: 1, name: '老肥烧烤西湖总店', code: 'S001'),
    CashierShopRef(id: 2, name: '老肥烧烤滨江分店', code: 'S002'),
  ];

  List<CashierAdministrator> administrators = const [
    CashierAdministrator(id: 1, userName: 'zhang_manager', roles: []),
    CashierAdministrator(id: 2, userName: 'li_cashier', roles: []),
  ];

  String? createdUserName;
  String? createdWorkNo;
  String? createdRealName;
  String? createdJobTitle;
  int? createdAdminCount;
  bool failAssignmentAfterCreate = false;
  int? retriedAssignmentAdminId;

  int? updatedAdminId;
  String? updatedWorkNo;
  String? updatedRealName;
  String? updatedJobTitle;

  int? deletedAdminId;
  bool? deletedConfirm;

  @override
  Future<PagedCashierAccessEmployees> loadAccessEmployees({
    String keyword = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    final filtered = accessEmployees.where((e) {
      if (keyword.isEmpty) return true;
      return e.userName.contains(keyword) ||
          e.realName.contains(keyword) ||
          e.workNo.contains(keyword);
    }).toList();
    return PagedCashierAccessEmployees(
      page: page,
      pageSize: pageSize,
      total: filtered.length,
      items: filtered,
    );
  }

  @override
  Future<List<CashierAccessRole>> loadAccessRoles() async => accessRoles;

  @override
  Future<List<CashierShopRef>> loadShopList({String keyword = ''}) async => shopList;

  @override
  Future<PagedCashierAdministrators> loadAdministrators() async {
    return PagedCashierAdministrators(
      total: administrators.length,
      items: administrators,
      allRoles: accessRoles
          .map((r) => CashierAccessRoleRef(
                id: r.id,
                roleCode: r.roleCode,
                roleName: r.roleName,
              ),
          )
          .toList(),
    );
  }

  @override
  Future<void> assignAccessEmployee({
    required int adminId,
    required List<int> roleIds,
    required List<int> shopIds,
    required bool confirm,
  }) async {
    retriedAssignmentAdminId = adminId;
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
    createdUserName = userName;
    createdWorkNo = workNo;
    createdRealName = realName;
    createdJobTitle = jobTitle;
    createdAdminCount = (createdAdminCount ?? 0) + 1;

    final newEmp = CashierAccessEmployee(
      adminId: 10 + createdAdminCount!,
      userName: userName,
      workNo: workNo ?? '',
      realName: realName ?? '',
      jobTitle: jobTitle ?? '',
      displayName: realName?.isNotEmpty == true ? realName! : userName,
      roles: (roleIds ?? [])
          .map((id) => CashierAccessRoleRef(id: id, roleName: '角色#$id'))
          .toList(),
      shops: shopIds ?? [],
    );
    accessEmployees = [...accessEmployees, newEmp];
    if (failAssignmentAfterCreate) {
      throw EmployeeAssignmentException(newEmp.adminId, StateError('授权失败'));
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
    updatedAdminId = adminId;
    updatedWorkNo = workNo;
    updatedRealName = realName;
    updatedJobTitle = jobTitle;

    accessEmployees = accessEmployees.map((e) {
      if (e.adminId == adminId) {
        return CashierAccessEmployee(
          adminId: adminId,
          userName: e.userName,
          workNo: workNo ?? e.workNo,
          realName: realName ?? e.realName,
          jobTitle: jobTitle ?? e.jobTitle,
          displayName: realName?.isNotEmpty == true ? realName! : e.displayName,
          roles: roleIds != null
              ? roleIds.map((id) => CashierAccessRoleRef(id: id, roleName: '角色#$id'),
                    ).toList()
              : e.roles,
          shops: shopIds ?? e.shops,
        );
      }
      return e;
    }).toList();
  }

  @override
  Future<void> deleteEmployee({
    required int adminId,
    required bool confirm,
  }) async {
    deletedAdminId = adminId;
    deletedConfirm = confirm;
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    accessEmployees = accessEmployees.where((e) => e.adminId != adminId).toList();
  }

  Object? deleteError;

  int? statusUpdatedAdminId;
  String? statusUpdatedValue;
  int? forceLogoutAdminId;
  int? effectivePermissionAdminId;
  List<String>? conflictCheckedCodes;
  CashierAccessPolicy? createdPolicy;
  CashierAccessPolicy? updatedPolicy;
  int? deletedPolicyId;
  ({int roleId, int policyId, int? shopId})? assignedPolicy;
  int? approvalDetailId;

  @override
  Future<CashierEmployeeStatusResult> updateEmployeeStatus({
    required int adminId,
    required String status,
  }) async {
    statusUpdatedAdminId = adminId;
    statusUpdatedValue = status;
    accessEmployees = accessEmployees.map((e) {
      if (e.adminId == adminId) {
        return CashierAccessEmployee(
          adminId: e.adminId,
          userName: e.userName,
          workNo: e.workNo,
          realName: e.realName,
          jobTitle: e.jobTitle,
          displayName: e.displayName,
          roles: e.roles,
          shops: e.shops,
          accountStatus: status,
          permissionVersion: e.permissionVersion + 1,
        );
      }
      return e;
    }).toList();
    return CashierEmployeeStatusResult(
      adminId: adminId,
      accountStatus: status,
      permissionVersion: 2,
    );
  }

  @override
  Future<void> forceLogoutEmployee({required int adminId}) async {
    forceLogoutAdminId = adminId;
  }

  @override
  Future<CashierEffectivePermissions> loadEffectivePermissions({
    required int adminId,
    int? shopId,
  }) async {
    effectivePermissionAdminId = adminId;
    return CashierEffectivePermissions(
      adminId: adminId,
      userName: 'zhang_manager',
      realName: '张店长',
      permissions: const ['cashier:operate', 'order:operate:refund'],
    );
  }

  @override
  Future<List<CashierAccessConflict>> checkAccessConflicts({
    required List<String> permissionCodes,
  }) async {
    conflictCheckedCodes = permissionCodes;
    return conflictsResult;
  }

  List<CashierAccessConflict> conflictsResult = const [];

  List<CashierPermissionCode> permissionCodes = const [
    CashierPermissionCode(
      id: 1,
      permissionCode: 'cash_drawer:cash_out',
      permissionName: '现金支出',
      module: '现金',
    ),
    CashierPermissionCode(
      id: 2,
      permissionCode: 'cash_drawer:variance_approve',
      permissionName: '长短款审批',
      module: '现金',
    ),
    CashierPermissionCode(
      id: 3,
      permissionCode: 'order:item_void',
      permissionName: '退菜',
      module: '订单',
    ),
  ];

  Object? roleSaveError;
  ({
    String? roleCode,
    String? roleName,
    List<int>? permissionIds,
    String? forceReason,
  })? createdRoleRecord;
  ({
    int? id,
    int? version,
    List<int>? permissionIds,
    String? forceReason})? updatedRoleRecord;

  @override
  Future<List<CashierPermissionCode>> loadPermissionCodes() async =>
      permissionCodes;

  @override
  Future<void> createAccessRole({
    required String roleCode,
    required String roleName,
    String remark = '',
    int sortOrder = 100,
    List<int>? permissionIds,
    String? forceReason,
  }) async {
    createdRoleRecord = (
      roleCode: roleCode,
      roleName: roleName,
      permissionIds: permissionIds,
      forceReason: forceReason,
    );
    // 模拟服务端豁免语义：携带合规原因后放行，否则 HARD 冲突 409 拦截。
    final error = roleSaveError;
    if (error != null && (forceReason == null || forceReason.trim().isEmpty)) {
      throw error;
    }
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
    updatedRoleRecord = (
      id: id,
      version: version,
      permissionIds: permissionIds,
      forceReason: forceReason,
    );
    final error = roleSaveError;
    if (error != null && (forceReason == null || forceReason.trim().isEmpty)) {
      throw error;
    }
  }

  @override
  Future<List<CashierAccessPolicy>> loadAccessPolicies({
    String? permissionCode,
  }) async =>
      policiesResult;

  List<CashierAccessPolicy> policiesResult = const [];

  @override
  Future<CashierAccessPolicy> createAccessPolicy(
    CashierAccessPolicy policy,
  ) async {
    createdPolicy = policy;
    return policy;
  }

  @override
  Future<CashierAccessPolicy> updateAccessPolicy({
    required int id,
    required CashierAccessPolicy policy,
  }) async {
    updatedPolicy = policy;
    return policy;
  }

  @override
  Future<void> deleteAccessPolicy(int id) async {
    deletedPolicyId = id;
  }

  @override
  Future<void> assignAccessPolicy({
    required int roleId,
    required int policyId,
    int? shopId,
  }) async {
    assignedPolicy = (roleId: roleId, policyId: policyId, shopId: shopId);
  }

  @override
  Future<AccessApprovalRecord?> loadApprovalDetail(int id) async {
    approvalDetailId = id;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Cashier Employee Access supports Create, Edit and Delete employee profiles', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeCrudCashierSettingsRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [CashierTokens.light]),
        home: Scaffold(
          body: CashierSettingsAccessEvaluatePage(
            repository: repository,
            section: const SettingsSectionSpec('employees', '员工', Icons.people_outline,
              ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Initial list verification
    expect(find.text('员工列表与授权管理'), findsOneWidget);
    expect(find.text('新建员工档案'), findsOneWidget);
    expect(find.text('张店长'), findsOneWidget);
    expect(find.text('李收银'), findsOneWidget);

    // 2. Test Create Employee Profile
    await tester.tap(find.byKey(const Key('access-employees-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('employee-form-work-no')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('employee-form-work-no')), 'EMP1003',
      );
    await tester.enterText(find.byKey(const Key('employee-form-real-name')), '王大厨',
      );
    await tester.enterText(find.byKey(const Key('employee-form-job-title')), '后厨主管',
      );
    await tester.enterText(find.byKey(const Key('employee-form-user-name')), 'wang_chef',
      );
    await tester.enterText(find.byKey(const Key('employee-form-password')), 'chef123456',
      );
    await tester.pumpAndSettle();

      repository.failAssignmentAfterCreate = true;
      await tester.tap(find.byKey(const Key('employee-form-submit')));
      await tester.pumpAndSettle();
      expect(find.text('重试角色与门店授权'), findsOneWidget);
      expect(repository.createdAdminCount, 1);

    await tester.tap(find.byKey(const Key('employee-form-submit')));
    await tester.pumpAndSettle();
      expect(repository.createdAdminCount, 1);
      expect(repository.retriedAssignmentAdminId, 11);

    expect(repository.createdUserName, 'wang_chef');
    expect(repository.createdWorkNo, 'EMP1003');
    expect(repository.createdRealName, '王大厨');
    expect(repository.createdJobTitle, '后厨主管');
    expect(find.text('王大厨'), findsOneWidget);

    // 3. Test Edit Employee Profile
    final editBtn = find.byKey(const Key('access-employee-profile-1'));
    expect(editBtn, findsOneWidget);
    await tester.tap(editBtn);
    await tester.pumpAndSettle();

    expect(find.text('编辑员工档案'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('employee-form-real-name')), '张明（高级店长）',
      );
    await tester.enterText(find.byKey(const Key('employee-form-job-title')), '大堂经理',
      );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('employee-form-submit')));
    await tester.pumpAndSettle();

    expect(repository.updatedAdminId, 1);
    expect(repository.updatedRealName, '张明（高级店长）');
    expect(repository.updatedJobTitle, '大堂经理');
    expect(find.text('张明（高级店长）'), findsOneWidget);

    // 4. Test Delete Employee Profile
    final deleteBtn = find.byKey(const Key('access-employee-delete-2'));
    expect(deleteBtn, findsOneWidget);
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    expect(find.text('注销并删除员工'), findsOneWidget);
    expect(find.textContaining('确定注销并删除员工账号「李收银」？'), findsOneWidget);

    await tester.tap(find.byKey(const Key('employee-delete-confirm-btn')));
    await tester.pumpAndSettle();

    expect(repository.deletedAdminId, 2);
    expect(repository.deletedConfirm, isTrue);
    expect(find.text('李收银'), findsNothing);
  },
  );

  testWidgets('Cashier Access employee lifecycle: status badge, status change, force logout and effective permissions', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeCrudCashierSettingsRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [CashierTokens.light]),
        home: Scaffold(
          body: CashierSettingsAccessEvaluatePage(
            repository: repository,
            section: const SettingsSectionSpec('employees', '员工', Icons.people_outline,
              ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. 状态徽标与权限版本展示：默认 ACTIVE 显示"在职"，权限 v1
    expect(find.text('在职'), findsNWidgets(2));
    expect(find.textContaining('权限 v1'), findsWidgets);

    // 2. 更多菜单 → 停用账号（确认弹窗 → 提交）
    await tester.tap(find.byKey(const Key('access-employee-more-1')));
    await tester.pumpAndSettle();
    expect(find.text('停用账号'), findsOneWidget);
    expect(find.text('强制下线'), findsOneWidget);
    expect(find.text('查看有效权限'), findsOneWidget);
    await tester.tap(find.text('停用账号'));
    await tester.pumpAndSettle();
    expect(find.textContaining('确定停用'), findsOneWidget);
    await tester.tap(find.byKey(const Key('employee-status-confirm-1')));
    await tester.pumpAndSettle();

    expect(repository.statusUpdatedAdminId, 1);
    expect(repository.statusUpdatedValue, 'DISABLED');
    expect(find.text('已停用'), findsOneWidget);

    // 3. 更多菜单 → 强制下线（确认弹窗 → 提交）
    await tester.tap(find.byKey(const Key('access-employee-more-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('强制下线'));
    await tester.pumpAndSettle();
    expect(find.textContaining('全部活跃会话'), findsOneWidget);
    await tester.tap(find.byKey(const Key('employee-force-logout-confirm')));
    await tester.pumpAndSettle();

    expect(repository.forceLogoutAdminId, 2);

    // 4. 更多菜单 → 查看有效权限（弹窗展示角色/权限码）
    await tester.tap(find.byKey(const Key('access-employee-more-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看有效权限'));
    await tester.pumpAndSettle();

    expect(find.text('有效权限'), findsOneWidget);
    expect(repository.effectivePermissionAdminId, 1);
    expect(find.text('cashier:operate'), findsOneWidget);
    expect(find.text('order:operate:refund'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  },
  );

  testWidgets('Cashier Access delete 409 guides to disable or resign', (tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeCrudCashierSettingsRepository();
    repository.deleteError = Exception(
      'ACCESS_EMPLOYEE_HAS_HISTORY 该员工已有业务记录，不能物理删除，可改为离职或停用',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [CashierTokens.light]),
        home: Scaffold(
          body: CashierSettingsAccessEvaluatePage(
            repository: repository,
            section: const SettingsSectionSpec('employees', '员工', Icons.people_outline,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 打开删除弹窗并确认 → 服务端 409 → 显示防误删引导
    await tester.tap(find.byKey(const Key('access-employee-delete-1')));
    await tester.pumpAndSettle();
    expect(find.text('注销并删除员工'), findsOneWidget);
    await tester.tap(find.byKey(const Key('employee-delete-confirm-btn')));
    await tester.pumpAndSettle();

    expect(repository.deletedAdminId, 1);
    expect(repository.deletedConfirm, isTrue);
    expect(find.textContaining('存在历史订单、收银当班、审计日志或审批流水'), findsOneWidget);
    expect(find.text('改为停用'), findsOneWidget);
    expect(find.text('标记离职'), findsOneWidget);

    // 点击"改为停用" → 调 updateEmployeeStatus(DISABLED)，弹窗关闭、列表徽标更新
    await tester.tap(find.byKey(const Key('employee-delete-guide-disable')));
    await tester.pumpAndSettle();

    expect(repository.statusUpdatedAdminId, 1);
    expect(repository.statusUpdatedValue, 'DISABLED');
    expect(find.text('注销并删除员工'), findsNothing);
    expect(find.text('已停用'), findsOneWidget);
  });

  testWidgets('Cashier Access role SoD conflict precheck and forceReason exemption', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeCrudCashierSettingsRepository();
    repository.conflictsResult = const [
      CashierAccessConflict(
        ruleId: 1,
        permissionA: 'cash_drawer:cash_out',
        permissionB: 'cash_drawer:variance_approve',
        severity: 'HARD',
        message: '现金支出与长短款审批冲突',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [CashierTokens.light]),
        home: Scaffold(
          body: CashierSettingsAccessEvaluatePage(
            repository: repository,
            section: const SettingsSectionSpec('roles', '角色', Icons.admin_panel_settings_outlined,
              ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 打开新增角色弹窗并填写
    await tester.tap(find.byKey(const Key('access-roles-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('access-role-name')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('access-role-name')), '测试冲突角色',
      );
    await tester.enterText(find.byKey(const Key('access-role-code')), 'ROLE_TEST_SOD',
      );
    await tester.pumpAndSettle();

    // 勾选两个 HARD 冲突权限码 → 防抖预检 → 显示严禁冲突警告
    await tester.tap(find.text('cash_drawer:cash_out'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('cash_drawer:variance_approve'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(repository.conflictCheckedCodes, isNotNull);
    expect(repository.conflictCheckedCodes!.length, 2);
    expect(find.textContaining('存在职责分离（SoD）严禁冲突'), findsOneWidget);

    // 保存遇 409 ACCESS_ROLE_CONFLICT → forceReason 二次确认
    repository.roleSaveError = Exception(
      'ACCESS_ROLE_CONFLICT 存在职责分离 (SoD) 严禁冲突，禁止同时授予冲突权限',
    );
    await tester.tap(find.byKey(const Key('access-role-submit')));
    await tester.pumpAndSettle();

    expect(find.text('职责分离冲突豁免'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('force-reason-input')),
      '临时业务需要，财务轮岗期间由店长兼任',
    );
    await tester.tap(find.byKey(const Key('force-reason-confirm')));
    await tester.pumpAndSettle();

    expect(repository.createdRoleRecord?.forceReason, '临时业务需要，财务轮岗期间由店长兼任');
    expect(find.byKey(const Key('access-role-name')), findsNothing);
  },
  );

  testWidgets('Cashier Access policy center: list, create, edit, assign and delete', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeCrudCashierSettingsRepository();
    repository.policiesResult = const [
      CashierAccessPolicy(
        id: 1,
        policyCode: 'MAX_AMOUNT_REFUND_50',
        policyName: '退款金额上限 50 元',
        permissionCode: 'order:operate:refund',
        policyType: CashierAccessPolicyType.maxAmount,
        effect: CashierAccessPolicyEffect.deny,
        priority: 10,
        enabled: 1,
        configJson: '{"maxAmount": 50}',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [CashierTokens.light]),
        home: Scaffold(
          body: CashierSettingsAccessEvaluatePage(
            repository: repository,
            section: const SettingsSectionSpec('policies', '策略中心', Icons.rule_outlined,
              ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 列表展示：名称、类型徽标、效果徽标、规则
    expect(find.text('退款金额上限 50 元'), findsOneWidget);
    expect(find.text('金额上限'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);
    expect(find.textContaining('{"maxAmount": 50}'), findsOneWidget);
    expect(find.text('2 个角色'), findsOneWidget);

    // 新建策略
    await tester.tap(find.byKey(const Key('access-policies-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('policy-form-code')),
      'MIN_DISCOUNT_RATE_8',
    );
    await tester.enterText(
      find.byKey(const Key('policy-form-name')),
      '整单折扣不低于 8 折',
    );
    await tester.enterText(
      find.byKey(const Key('policy-form-permission-code')),
      'order:operate:discount',
    );
    await tester.enterText(
      find.byKey(const Key('policy-form-config')),
      '{"minRate": 0.8}',
    );
    await tester.tap(find.byKey(const Key('policy-form-submit')));
    await tester.pumpAndSettle();

    expect(repository.createdPolicy?.policyCode, 'MIN_DISCOUNT_RATE_8');
    expect(repository.createdPolicy?.configJson, '{"minRate": 0.8}');
    expect(find.text('策略已创建'), findsOneWidget);

    // 编辑策略（改名称）
    await tester.tap(find.byKey(const Key('access-policy-more-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑策略'));
    await tester.pumpAndSettle();
      for (final key in ['policy-form-code', 'policy-form-permission-code']) {
        final field = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(TextField),
          ),
        );
        expect(field.readOnly, isTrue);
      }
      await tester.enterText(
      find.byKey(const Key('policy-form-name')),
      '退款上限调整为 100 元',
    );
    await tester.tap(find.byKey(const Key('policy-form-submit')));
    await tester.pumpAndSettle();
    expect(repository.updatedPolicy?.policyName, '退款上限调整为 100 元');

    // 绑定角色（全局）
    await tester.tap(find.byKey(const Key('access-policy-more-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('绑定角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy-assign-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收银员 (ROLE_CASHIER)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy-assign-confirm')));
    await tester.pumpAndSettle();
    expect(repository.assignedPolicy?.roleId, 2);
    expect(repository.assignedPolicy?.policyId, 1);
    expect(repository.assignedPolicy?.shopId, isNull);

    // 删除策略
    await tester.tap(find.byKey(const Key('access-policy-more-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除策略'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy-delete-confirm-1')));
    await tester.pumpAndSettle();
    expect(repository.deletedPolicyId, 1);
    expect(find.text('策略已删除'), findsOneWidget);
  },
  );

  testWidgets('Cashier Access approval detail dialog loads GET approvals/{id}', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = FakeHttpTransport({
      'GET /admin/access/approvals': jsonEncode({
        'data': {
          'items': [
            {
              'id': 5,
              'approval_no': 'APP-2026-0005',
              'permission_code': 'order:operate:refund',
              'operator_id': 2,
              'authorizer_id': 1,
              'shop_id': 1,
              'biz_type': 'REFUND',
              'biz_id': 'R-20261006-001',
              'amount': 60.0,
              'reason': '菜品质量问题退款',
              'auth_method': 'PIN',
              'status': 'CONSUMED',
              'max_amount': 50.0,
              'expires_at': '2026-10-06 12:02:00',
              'consumed_at': '2026-10-06 12:01:40',
              'created_at': '2026-10-06 12:00:00',
            },
          ],
          'total': 1,
          'page': 1,
          'pageSize': 20,
        },
      }),
      'GET /admin/access/approvals/5': jsonEncode({
        'data': {
          'id': 5,
          'approval_no': 'APP-2026-0005',
          'permission_code': 'order:operate:refund',
          'operator_id': 2,
          'authorizer_id': 1,
          'shop_id': 1,
          'biz_type': 'REFUND',
          'biz_id': 'R-20261006-001',
          'amount': 60.0,
          'reason': '菜品质量问题退款，店长现场 PIN 授权',
          'auth_method': 'PIN',
          'status': 'CONSUMED',
          'max_amount': 50.0,
          'expires_at': '2026-10-06 12:02:00',
          'consumed_at': '2026-10-06 12:01:40',
          'created_at': '2026-10-06 12:00:00',
        },
      }),
    });
    final client = AdminApiClient(
      baseUrl: 'http://fake',
      transport: transport,
      token: 'fake-token',
      shopId: 1,
      terminalId: 'TERM-TEST-01',
    );
    final approvalRepository = AccessApprovalRepository(client);

    // 解析层自检：列表分页结构与详情单条结构均按服务端 R 包装解包后解析。
    final page = await approvalRepository.listApprovals();
    expect(page.total, 1);
    expect(page.items.length, 1);
    expect(page.items.first.approvalNo, 'APP-2026-0005');
    final detail = await approvalRepository.loadApprovalDetail(5);
    expect(detail?.reason, '菜品质量问题退款，店长现场 PIN 授权');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [CashierTokens.light]),
        home: Scaffold(
          body: CashierSettingsAccessEvaluatePage(
            repository: _FakeCrudCashierSettingsRepository(),
            approvalRepository: approvalRepository,
            section: const SettingsSectionSpec('approvals', '审批记录', Icons.approval_outlined,
              ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 审批流水列表展示
    expect(find.text('APP-2026-0005'), findsOneWidget);
    expect(find.textContaining('order:operate:refund'), findsOneWidget);

    // 点击记录打开详情（GET /admin/access/approvals/5）
    await tester.tap(find.text('APP-2026-0005'));
    await tester.pumpAndSettle();

    expect(find.textContaining('审批详情'), findsOneWidget);
    expect(find.text('R-20261006-001'), findsOneWidget);
    expect(find.text('¥50.00'), findsOneWidget); // 最大允许金额
    expect(
      find.text('菜品质量问题退款，店长现场 PIN 授权'),
      findsOneWidget);
    expect(tester.takeException(), isNull);
  },
  );

  test('cashier authorize parses approvalToken after R unwrap (no missing token error)', () async {
    final transport = FakeHttpTransport({
      'POST /cashier/access/authorize': jsonEncode({
        'code': 200,
        'data': {
          'approvalNo': 'AP_1_20261006_1000',
          'approvalToken': 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
          'permission': 'order:operate:refund',
          'operatorId': 2,
          'authorizerId': 1,
          'authorizerName': '张店长',
          'shopId': 1,
          'bizType': 'REFUND',
          'bizId': 'R-20261006-001',
          'maxAmount': 100.0,
          'expireSeconds': 120,
          'bindingVersion': 2,
        },
      }),
    });
    final client = AdminApiClient(
      baseUrl: 'http://fake',
      transport: transport,
      token: 'fake-token',
      shopId: 1,
      terminalId: 'TERM-TEST-01',
    );
    final repository = AccessApprovalRepository(client);

    final grant = await repository.authorize(
      permission: 'order:operate:refund',
      bizType: 'REFUND',
      bizId: 'R-20261006-001',
      authorizerAccount: '10242',
      credential: 'secret',
    );

    expect(grant.approvalToken,
        'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
      );
    expect(grant.authorizerName, '张店长');
    expect(grant.expireSeconds, 120);
    expect(transport.requests.single.body, contains('10242'));
  },
  );
}
