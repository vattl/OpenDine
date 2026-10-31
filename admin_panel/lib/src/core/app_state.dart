import 'package:flutter/foundation.dart';

import '../features/auth/domain/auth_models.dart';
import 'api_debug_log.dart';
import 'app_config.dart';
import 'cashier_operation_audit.dart';
import 'crash_log.dart';
import 'shop_summary.dart';

export 'shop_summary.dart';

class AppState extends ChangeNotifier {
  AppState({String initialBaseUrl = AppConfig.apiBaseUrl})
    : baseUrl = initialBaseUrl {
    CrashLog.instance.registerStateProvider(
      'auth',
      () => {
        'authenticated': isAuthenticated,
        'actor': _lastActorName,
        'shop_id': currentShopId,
        'shop_name': currentShop?.name,
        'permissions_count': permissions.length,
        'base_url': baseUrl,
      },
    );
  }

  int selectedIndex = 0;
  int? currentShopId;
  String scope = 'SHOP';
  String baseUrl;
  String? token;
  List<ShopSummary> shops = const [];
  Set<String> permissions = const {};
  LoginSession? session;
  String? _lastActorName;
  String? get currentActorName => _lastActorName;
  int get currentAdminId => session?.adminId ?? 0;
  bool get isSuperAdmin => session?.isSuperAdmin ?? false;
  String get currentWorkNo => session?.workNo ?? '';
  String get currentRealName => session?.realName ?? '';
  String get currentJobTitle => session?.jobTitle ?? '';
  String get currentDisplayName => session?.displayName.isNotEmpty == true
      ? session!.displayName
      : (_lastActorName ?? '');

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  ShopSummary? get currentShop {
    for (final shop in shops) {
      if (shop.id == currentShopId) return shop;
    }
    return null;
  }

  bool hasPermission(String code) {
    if (code == 'public') return true;
    return permissions.contains(code);
  }

  void applySession(LoginSession session, {int? preferredShopId}) {
    this.session = session;
    token = session.token;
    scope = session.scope;
    permissions = session.permissions;
    shops = session.shops;
    _lastActorName = session.displayName.isNotEmpty
        ? session.displayName
        : (session.realName.isNotEmpty
              ? session.realName
              : (session.actorName.isEmpty ? null : session.actorName));
    CashierOperationAuditStore.instance.currentActorName = _lastActorName;
    currentShopId =
        preferredShopId != null &&
            shops.any((shop) => shop.id == preferredShopId)
        ? preferredShopId
        : (shops.isEmpty ? null : shops.first.id);
    CashierOperationAuditStore.instance.currentShopId = currentShopId;
    selectedIndex = 0;
    CrashLog.instance.recordBreadcrumb(
      category: 'auth',
      message: '收银员登录成功: ${_lastActorName ?? "未知"}, 默认门店: $currentShopId',
      data: {
        'actor': _lastActorName,
        'shop_id': currentShopId,
        'shops_count': shops.length,
      },
    );
    notifyListeners();
  }

  /// 权限刷新：用服务端最新会话数据原地更新（保留当前门店与所在页面）。
  /// 用于 ACCESS_PERMISSION_CHANGED 后调用 /admin/me/permissions 刷新权限，
  /// 避免因权限版本不一致导致后续请求被拦截。
  void refreshFromSession(LoginSession session) {
    this.session = session;
    token = session.token;
    scope = session.scope;
    permissions = session.permissions;
    shops = session.shops;
    _lastActorName = session.displayName.isNotEmpty
        ? session.displayName
        : (session.realName.isNotEmpty
              ? session.realName
              : (session.actorName.isEmpty ? null : session.actorName));
    if (currentShopId == null ||
        !shops.any((shop) => shop.id == currentShopId)) {
      currentShopId = shops.isEmpty ? null : shops.first.id;
    }
    CashierOperationAuditStore.instance.currentActorName = _lastActorName;
    CashierOperationAuditStore.instance.currentShopId = currentShopId;
    CrashLog.instance.recordBreadcrumb(
      category: 'auth',
      message: '权限刷新完成: ${_lastActorName ?? "未知"}, 门店: $currentShopId, 权限数: ${permissions.length}',
      data: {
        'actor': _lastActorName,
        'shop_id': currentShopId,
        'permissions_count': permissions.length,
      },
    );
    notifyListeners();
  }

  void logout() {
    final lastActor = _lastActorName;
    final lastShop = currentShopId;
    CrashLog.instance.recordBreadcrumb(
      category: 'auth',
      message: '收银员退出登录: ${lastActor ?? "未知"}',
      data: {'actor': lastActor, 'shop_id': lastShop},
    );
    ApiDebugLogStore.instance.clear();
    session = null;
    token = null;
    permissions = const {};
    shops = const [];
    currentShopId = null;
    selectedIndex = 0;
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'auth',
        action: 'logout',
        result: 'success',
        actorId: lastActor,
        actorName: lastActor,
        shopId: lastShop,
      ),
    );
    CashierOperationAuditStore.instance.currentActorName = null;
    CashierOperationAuditStore.instance.currentShopId = null;
    notifyListeners();
  }

  void selectPage(int index) {
    selectedIndex = index;
    notifyListeners();
  }

  void selectShop(int shopId) {
    if (!shops.any((shop) => shop.id == shopId)) {
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'shop',
          action: 'switch',
          result: 'rejected',
          actorId: _lastActorName,
          actorName: _lastActorName,
          shopId: currentShopId,
          detail: {
            'target_shop_id': shopId,
            'reason': '门店不在当前账号授权范围内',
          },
        ),
      );
      throw ArgumentError.value(shopId, 'shopId', '门店不在当前账号授权范围内');
    }
    final previous = currentShopId;
    currentShopId = shopId;
    CrashLog.instance.recordBreadcrumb(
      category: 'auth',
      message: '切换门店: $previous -> $shopId',
      data: {'previous_shop_id': previous, 'new_shop_id': shopId},
    );
    CashierOperationAuditStore.instance.currentShopId = shopId;
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'shop',
        action: 'switch',
        result: 'success',
        actorId: _lastActorName,
        actorName: _lastActorName,
        shopId: shopId,
        detail: {'previous_shop_id': previous},
      ),
    );
    notifyListeners();
  }
}
