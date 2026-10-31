import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/shop_summary.dart';
import '../../../core/app_config.dart';
import '../../auth/domain/auth_models.dart';

class AuthState {
  const AuthState({
    this.token,
    this.scope = 'SHOP',
    this.permissions = const {},
    this.shops = const [],
    this.currentShopId,
    this.baseUrl = AppConfig.apiBaseUrl,
    this.restoring = true,
  });

  final String? token;
  final String scope;
  final Set<String> permissions;
  final List<ShopSummary> shops;
  final int? currentShopId;
  final String baseUrl;
  final bool restoring;

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

  /// 老板/管理层（HQ 或持有经营/授权类权限码）：可查看经营数据、报表、员工授权。
  bool get isBoss =>
      scope == 'HQ' ||
      hasPermission('admin:manage') ||
      hasPermission('statistics:view') ||
      hasPermission('report:view');

  /// 店长/可顶班收银（shop:manage）：拥有改价/优惠/班次等 order:config 能力。
  bool get isManager => hasPermission('shop:manage');

  /// 是否可管理员工（admin:manage，老板专属）。
  bool get canManageStaff => hasPermission('admin:manage');

  /// 角色展示名：老板 / 店长 / 员工。
  String get roleLabel {
    if (isBoss) return isManager ? '老板 · 店长' : '老板';
    if (isManager) return '店长';
    return '员工';
  }

  AuthState copyWith({
    Object? token = _sentinel,
    String? scope,
    Set<String>? permissions,
    List<ShopSummary>? shops,
    Object? currentShopId = _sentinel,
    String? baseUrl,
    bool? restoring,
  }) {
    return AuthState(
      token: identical(token, _sentinel) ? this.token : token as String?,
      scope: scope ?? this.scope,
      permissions: permissions ?? this.permissions,
      shops: shops ?? this.shops,
      currentShopId: identical(currentShopId, _sentinel)
          ? this.currentShopId
          : currentShopId as int?,
      baseUrl: baseUrl ?? this.baseUrl,
      restoring: restoring ?? this.restoring,
    );
  }
}

const _sentinel = Object();

abstract class AuthStorage {
  Future<String?> readToken();
  Future<void> saveSession(LoginSession session);
  Future<void> clear();
}

class SecureAuthStorage implements AuthStorage {
  SecureAuthStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'auth.token';
  static const _scopeKey = 'auth.scope';
  static const _permissionsKey = 'auth.permissions';
  static const _shopsKey = 'auth.shops';

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> saveSession(LoginSession session) async {
    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(key: _scopeKey, value: session.scope);
    await _storage.write(
      key: _permissionsKey,
      value: session.permissions.join(','),
    );
    await _storage.write(
      key: _shopsKey,
      value: jsonEncode(
        session.shops
            .map((s) => {'id': s.id, 'code': s.code, 'name': s.name})
            .toList(),
      ),
    );
  }

  Future<LoginSession?> readSession() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;
    final scope = await _storage.read(key: _scopeKey) ?? 'SHOP';
    final permissionsRaw = await _storage.read(key: _permissionsKey) ?? '';
    final shopsRaw = await _storage.read(key: _shopsKey) ?? '[]';
    final shops = (jsonDecode(shopsRaw) as List)
        .whereType<Map>()
        .map(
          (m) => ShopSummary(
            id: (m['id'] as num).toInt(),
            code: '${m['code']}',
            name: '${m['name']}',
          ),
        )
        .toList();
    return LoginSession(
      token: token,
      scope: scope,
      permissions: permissionsRaw.split(',').where((p) => p.isNotEmpty).toSet(),
      shops: shops,
    );
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _scopeKey);
    await _storage.delete(key: _permissionsKey);
    await _storage.delete(key: _shopsKey);
  }
}

final authStorageProvider = Provider<SecureAuthStorage>(
  (ref) => SecureAuthStorage(),
);

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore();
    return const AuthState();
  }

  SecureAuthStorage get _storage => ref.read(authStorageProvider);

  Future<void> _restore() async {
    try {
      final session = await _storage.readSession();
      if (session != null) {
        _setSession(session);
        return;
      }
    } catch (error) {
      debugPrint('restore session failed: $error');
    }
    state = state.copyWith(restoring: false);
  }

  Future<void> applySession(LoginSession session) async {
    await _storage.saveSession(session);
    _setSession(session);
  }

  void _setSession(LoginSession session) {
    state = AuthState(
      token: session.token,
      scope: session.scope,
      permissions: session.permissions,
      shops: session.shops,
      currentShopId: session.shops.isEmpty ? null : session.shops.first.id,
      baseUrl: state.baseUrl,
      restoring: false,
    );
  }

  void selectShop(int shopId) {
    if (!state.shops.any((shop) => shop.id == shopId)) {
      throw ArgumentError.value(shopId, 'shopId', '门店不在当前账号授权范围内');
    }
    state = state.copyWith(currentShopId: shopId);
  }

  Future<void> logout() async {
    await _storage.clear();
    state = AuthState(baseUrl: state.baseUrl, restoring: false);
  }
}
