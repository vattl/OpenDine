import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../cashier_shell/presentation/cashier_change_password_dialog.dart';
import '../../cashier_shell/presentation/cashier_components.dart';
import '../../common/presentation/api_module_page.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

/// 设置页「接口工具」目的地内容：历史调试模块
/// （外卖配送/门店营销/权限管理/操作日志）+ 修改密码。
/// 由「更多」页迁移而来（更多入口已移除）。
class CashierApiDebugPage extends StatelessWidget {
  const CashierApiDebugPage({
    super.key,
    required this.client,
    required this.permissions,
    required this.currentShopId,
    required this.storeName,
    this.onPasswordChanged,
  });

  final AdminApiClient? client;
  final Set<String> permissions;
  final int? currentShopId;
  final String storeName;

  /// 密码修改成功后的回调（服务端已使全部旧 Token 失效，应强制重新登录）。
  final VoidCallback? onPasswordChanged;

  @override
  Widget build(BuildContext context) {
    final apiClient = client;
    if (apiClient == null) {
      return const SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: _EmptyAccessCard(message: '当前账号暂无接口调试权限，请联系管理员授权。'),
      );
    }
    final modules = _modules
        .map(
          (module) => module.withAllowedActions(
            module.actions
                .where(
                  (action) =>
                      action.endpoint.permissionCode == 'public' ||
                      permissions.contains(action.endpoint.permissionCode),
                )
                .toList(growable: false),
          ),
        )
        .where((module) => module.actions.isNotEmpty)
        .toList(growable: false);
    final canChangePassword = permissions.contains(
      adminModifyPasswordEndpoint.permissionCode,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: modules.isEmpty && !canChangePassword
          ? const _EmptyAccessCard()
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1180
                    ? 3
                    : constraints.maxWidth >= 720
                    ? 2
                    : 1;
                const spacing = 16.0;
                final width =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final module in modules)
                      SizedBox(
                        width: width,
                        child: _ModuleCard(
                          module: module,
                          onTap: () => _openModule(context, module),
                        ),
                      ),
                    if (canChangePassword)
                      SizedBox(
                        width: width,
                        child: _ModuleCard(
                          module: _passwordModule,
                          onTap: () => _showPasswordForm(context),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  void _openModule(BuildContext context, _ApiDebugModule module) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: context.cashier.canvas,
          appBar: AppBar(
            title: Text(module.title),
            backgroundColor: Colors.white,
            foregroundColor: context.cashier.ink,
            surfaceTintColor: Colors.white,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ApiModulePage.scoped(
              title: module.title,
              description: module.description,
              currentShopId: currentShopId,
              storeName: storeName,
              client: client!,
              actions: module.actions,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPasswordForm(BuildContext context) async {
    final changed = await showCashierChangePasswordDialog(
      context: context,
      client: client!,
      currentShopId: currentShopId,
    );
    if (changed != true) return;
    // 服务端已递增 tokenVersion，旧 Token 全部失效，必须重新登录。
    onPasswordChanged?.call();
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.onTap});

  final _ApiDebugModule module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '打开${module.title}',
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.cashier.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.cashier.row,
        focusColor: context.cashier.row,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 190),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: context.cashier.selectedBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        module.icon,
                        color: context.cashier.ink,
                        size: 28,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: context.cashier.inkMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  module.title,
                  style: TextStyle(
                    color: context.cashier.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  module.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.cashier.inkMuted,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _EmptyAccessCard extends StatelessWidget {
  const _EmptyAccessCard({this.message = '当前账号暂无接口调试权限，请联系管理员授权。'});

  final String message;

  @override
  Widget build(BuildContext context) => CashierCard(
    child: Row(
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 32,
          color: context.cashier.inkMuted,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: context.cashier.inkMuted, fontSize: 17),
          ),
        ),
      ],
    ),
  );
}

class _ApiDebugModule {
  const _ApiDebugModule({
    required this.title,
    required this.description,
    required this.icon,
    required this.actions,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<ApiModuleAction> actions;

  _ApiDebugModule withAllowedActions(List<ApiModuleAction> allowedActions) {
    return _ApiDebugModule(
      title: title,
      description: description,
      icon: icon,
      actions: allowedActions,
    );
  }
}

const _passwordModule = _ApiDebugModule(
  title: '修改密码',
  description: '按管理员用户名更新登录密码',
  icon: Icons.password_rounded,
  actions: [],
);

const _modules = <_ApiDebugModule>[
  _ApiDebugModule(
    title: '外卖配送',
    description: '配送单、轨迹、状态与门店外卖配置',
    icon: Icons.delivery_dining_rounded,
    actions: [
      ApiModuleAction(label: '配送列表', endpoint: takeoutDeliveryListEndpoint),
      ApiModuleAction(
        label: '配送详情',
        endpoint: takeoutDeliveryDetailEndpoint,
        defaultQuery: {'order_no': ''},
      ),
      ApiModuleAction(
        label: '配送轨迹',
        endpoint: takeoutDeliveryTrackingEndpoint,
        defaultQuery: {'order_no': ''},
      ),
      ApiModuleAction(
        label: '更新配送状态',
        endpoint: takeoutDeliveryStatusEndpoint,
        defaultBody: {'orderId': 0, 'dispatch_status': 'accepted'},
      ),
      ApiModuleAction(
        label: '呼叫顺丰同城',
        endpoint: takeoutZsqDispatchEndpoint,
        defaultBody: {'orderId': 0},
      ),
      ApiModuleAction(
        label: '重新呼叫配送',
        endpoint: takeoutZsqRedispatchEndpoint,
        defaultBody: {'orderId': 0},
      ),
      ApiModuleAction(
        label: '同步配送状态',
        endpoint: takeoutZsqSyncEndpoint,
        defaultBody: {'orderId': 0},
      ),
      ApiModuleAction(label: '外卖配置', endpoint: takeoutConfigEndpoint),
      ApiModuleAction(
        label: '保存外卖配置',
        endpoint: takeoutConfigSaveEndpoint,
        defaultBody: {'enabled': true},
      ),
    ],
  ),
  _ApiDebugModule(
    title: '门店营销',
    description: '优惠券、活动、公告与营销分析',
    icon: Icons.campaign_rounded,
    actions: [
      ApiModuleAction(label: '优惠券列表', endpoint: couponListEndpoint),
      ApiModuleAction(
        label: '优惠券详情',
        endpoint: couponGetEndpoint,
        defaultQuery: {'id': ''},
      ),
      ApiModuleAction(
        label: '新增优惠券',
        endpoint: couponAddEndpoint,
        defaultBody: {'name': '', 'type': '', 'amount': 0},
      ),
      ApiModuleAction(
        label: '更新优惠券',
        endpoint: couponUpdateEndpoint,
        defaultBody: {'id': 0, 'name': '', 'type': '', 'amount': 0},
      ),
      ApiModuleAction(
        label: '删除优惠券',
        endpoint: couponDeleteEndpoint,
        defaultQuery: {'id': ''},
      ),
      ApiModuleAction(label: '活动列表', endpoint: activityListEndpoint),
      ApiModuleAction(
        label: '新增活动',
        endpoint: activityAddEndpoint,
        defaultBody: {'image': '', 'url': '', 'sort': 0},
      ),
      ApiModuleAction(label: '公告列表', endpoint: announcementListEndpoint),
      ApiModuleAction(
        label: '公告详情',
        endpoint: announcementGetEndpoint,
        defaultQuery: {'id': ''},
      ),
      ApiModuleAction(
        label: '新增公告',
        endpoint: announcementAddEndpoint,
        defaultBody: {'title': '', 'content': '', 'enabled': true},
      ),
      ApiModuleAction(
        label: '更新公告',
        endpoint: announcementUpdateEndpoint,
        defaultBody: {'id': 0, 'title': '', 'content': ''},
      ),
      ApiModuleAction(
        label: '删除公告',
        endpoint: announcementDeleteEndpoint,
        defaultQuery: {'id': ''},
      ),
      ApiModuleAction(label: '营销分析', endpoint: analyticsMarketingEndpoint),
    ],
  ),
  _ApiDebugModule(
    title: '权限管理',
    description: '角色、业务权限与 API 权限映射',
    icon: Icons.admin_panel_settings_rounded,
    actions: [
      ApiModuleAction(label: '角色列表', endpoint: rbacRolesEndpoint),
      ApiModuleAction(
        label: '保存角色',
        endpoint: rbacRolesSaveEndpoint,
        defaultBody: {'roleCode': '', 'roleName': ''},
      ),
      ApiModuleAction(label: '权限列表', endpoint: rbacPermissionsEndpoint),
      ApiModuleAction(
        label: '保存权限',
        endpoint: rbacPermissionsSaveEndpoint,
        defaultBody: {'permissionCode': '', 'permissionName': ''},
      ),
      ApiModuleAction(label: 'API 权限', endpoint: rbacApiPermissionsEndpoint),
      ApiModuleAction(
        label: '保存 API 权限',
        endpoint: rbacApiPermissionsSaveEndpoint,
        defaultBody: {'pathPattern': '', 'permissionCode': ''},
      ),
    ],
  ),
  _ApiDebugModule(
    title: '操作日志',
    description: '查询关键操作记录与订单日志',
    icon: Icons.receipt_long_rounded,
    actions: [
      ApiModuleAction(label: '操作日志', endpoint: operationLogEndpoint),
      ApiModuleAction(
        label: '订单日志',
        endpoint: orderLogEndpoint,
        defaultQuery: {'orderId': ''},
      ),
    ],
  ),
];
