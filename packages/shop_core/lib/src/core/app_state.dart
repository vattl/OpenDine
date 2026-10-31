import 'package:flutter/foundation.dart';

import '../shared/auth/domain/auth_models.dart';
import 'api_debug_log.dart';
import 'app_config.dart';
import 'shop_summary.dart';

class AppState extends ChangeNotifier {
  AppState({String initialBaseUrl = AppConfig.apiBaseUrl})
    : baseUrl = initialBaseUrl;

  int selectedIndex = 0;
  int? currentShopId;
  String scope = 'SHOP';
  String baseUrl;
  String? token;
  List<ShopSummary> shops = const [];
  Set<String> permissions = const {};

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

  void applySession(LoginSession session) {
    token = session.token;
    scope = session.scope;
    permissions = session.permissions;
    shops = session.shops;
    currentShopId = shops.isEmpty ? null : shops.first.id;
    selectedIndex = 0;
    notifyListeners();
  }

  void logout() {
    ApiDebugLogStore.instance.clear();
    token = null;
    permissions = const {};
    shops = const [];
    currentShopId = null;
    selectedIndex = 0;
    notifyListeners();
  }

  void selectPage(int index) {
    selectedIndex = index;
    notifyListeners();
  }

  void selectShop(int shopId) {
    if (!shops.any((shop) => shop.id == shopId)) {
      throw ArgumentError.value(shopId, 'shopId', '门店不在当前账号授权范围内');
    }
    currentShopId = shopId;
    notifyListeners();
  }
}
