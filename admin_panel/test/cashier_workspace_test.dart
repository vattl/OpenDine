import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/core/network_status_monitor.dart';
import 'package:admin_panel_flutter/src/core/shop_summary.dart';
import 'package:admin_panel_flutter/src/features/auth/data/cashier_account_storage.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_api_debug_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  testWidgets('routes authorized cashier sections through one workspace', (
    tester,
  ) async {
    _usePosViewport(tester);
    final transport = _transport();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierWorkspace(
          client: _client(transport),
          permissions: const {
            'cashier:operate',
            'order:view',
            'order:operate',
            'order:config',
            'user:view',
            'user:points',
            'dish:manage',
            'report:view',
            'coupon:manage',
            'activity:manage',
            'announcement:manage',
            'statistics:view',
            'admin:manage',
            'admin:password',
            'log:view',
            'payment:config:read',
            'payment:config:write',
          },
          shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
          currentShopId: 2,
          storeName: '松源海鲜街',
          onShopChanged: (_) {},
          onLogout: () {},
          onTableSelected: (_) async {},
          onPickupOrder: () async {},
          kdsAvailable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final section in const [
      'table',
      'ordering',
      'bills',
      'members',
      'dishStatus',
      'shift',
      'settings',
    ]) {
      expect(find.byKey(Key('cashier-nav-$section')), findsOneWidget);
    }
    // 「更多」入口已移除，接口调试迁入设置页
    expect(find.byKey(const Key('cashier-nav-more')), findsNothing);

    expect(find.byKey(const Key('cashier-business-switch')), findsOneWidget);
    expect(find.text('营业中'), findsOneWidget);
    final initialTableLoads = transport.requests
        .where((request) => request.uri.path == '/admin/table/status')
        .length;
    await tester.tap(find.byKey(const Key('cashier-nav-table')));
    await tester.pumpAndSettle();
    expect(
      transport.requests
          .where((request) => request.uri.path == '/admin/table/status')
          .length,
      greaterThan(initialTableLoads),
    );
    await tester.tap(find.byKey(const Key('cashier-business-switch')));
    await tester.pumpAndSettle();
    expect(find.text('关闭营业'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();
    final businessRequest = transport.requests.lastWhere(
      (request) => request.uri.path == '/cashier/shop/business',
    );
    expect(jsonDecode(businessRequest.body!), {'bus': '0'});
    expect(businessRequest.headers['X-Shop-Id'], '2');

    // 接口调试控制台已从接口工具页提取为设置首页独立入口
    await tester.tap(find.byKey(const Key('cashier-nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('接口调试').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-debug-clear')), findsOneWidget);
    expect(find.text('/admin/table/status'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('外卖管理').first);
    await tester.pumpAndSettle();
    expect(find.text('外卖平台'), findsWidgets);
    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cashier-nav-bills')));
    await tester.pumpAndSettle();

    // 顶栏副标题已随 UI006 移除，账单页加载以请求为准
    expect(
      transport.requests.map((request) => request.uri.path),
      contains('/cashier/order/today'),
    );

    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('绑定会员'));
    await tester.pumpAndSettle();

    // 新流程：账单详情直接弹手机号输入框绑定，不再跳转会员页
    expect(
      find.byKey(const Key('bill-bind-member-phone-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('bill-bind-member-confirm-button')),
      findsOneWidget,
    );
  });

  testWidgets(
    'business status refreshes after external change on section re-tap',
    (tester) async {
      _usePosViewport(tester);
      final transport = _MutableBusinessTransport(_transport().routes, true);

      await tester.pumpWidget(
        MaterialApp(
          home: CashierWorkspace(
            client: _client(transport),
            permissions: const {
              'cashier:operate',
              'order:view',
              'order:operate',
            },
            shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
            currentShopId: 2,
            storeName: '松源海鲜街',
            onShopChanged: (_) {},
            onLogout: () {},
            onTableSelected: (_) async {},
            onPickupOrder: () async {},
            kdsAvailable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始营业中
      expect(find.text('营业中'), findsOneWidget);

      // 后台/小程序/其他端将营业状态改为关闭
      transport.isOpen = false;

      // 重复点击当前 section 触发静默刷新，顶部状态应实时更新
      await tester.tap(find.byKey(const Key('cashier-nav-table')));
      await tester.pumpAndSettle();

      expect(find.text('已关闭营业'), findsOneWidget);
    },
  );

  testWidgets('business open blocked with 4001 offers force escape for admin', (
    tester,
  ) async {
    _usePosViewport(tester);
    final transport = _BlockingBusinessOpenTransport({
      'POST /admin/table/status': jsonEncode({
        'code': 200,
        'data': {'tableList': []},
      }),
      'POST /admin/order/list': jsonEncode({
        'code': 200,
        'data': {'records': [], 'total': 0},
      }),
      'GET /cashier/shift/current': jsonEncode({'code': 0, 'shift': null}),
      'POST /order/Business': jsonEncode({
        'code': 0,
        'business': false,
        'isReview': true,
        'shopId': 2,
      }),
      'POST /cashier/order/today': jsonEncode({'code': 0, 'list': []}),
      'GET /admin/orderDetail/list': jsonEncode({
        'code': 0,
        'order': null,
        'list': [],
      }),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CashierWorkspace(
          client: _client(transport),
          permissions: const {
            'cashier:operate',
            'order:view',
            'order:operate',
            'order:config',
            'admin:manage',
          },
          shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
          currentShopId: 2,
          storeName: '松源海鲜街',
          onShopChanged: (_) {},
          onLogout: () {},
          onTableSelected: (_) async {},
          onPickupOrder: () async {},
          kdsAvailable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 已关闭营业 → 尝试开门
    expect(find.text('已关闭营业'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cashier-business-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();

    // 4001 拦截 → 无法营业弹窗，老板可强制营业
    expect(find.text('无法开启营业：前一营业日尚未日结'), findsOneWidget);
    expect(find.byKey(const Key('daily-block-force-open-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('daily-block-force-open-button')));
    await tester.pumpAndSettle();

    // 逃生成功 → 营业中，force=1 已发送
    expect(find.text('营业中'), findsOneWidget);
    final forceRequest = transport.requests.lastWhere(
      (request) => request.uri.path == '/cashier/shop/business',
    );
    expect(jsonDecode(forceRequest.body!), {'bus': '1', 'force': '1'});
  });

  testWidgets(
    'business open blocked with 4001 hides force escape without admin:manage',
    (tester) async {
      _usePosViewport(tester);
      final transport = _BlockingBusinessOpenTransport({
        'POST /admin/table/status': jsonEncode({
          'code': 200,
          'data': {'tableList': []},
        }),
        'POST /admin/order/list': jsonEncode({
          'code': 200,
          'data': {'records': [], 'total': 0},
        }),
        'GET /cashier/shift/current': jsonEncode({'code': 0, 'shift': null}),
        'POST /order/Business': jsonEncode({
          'code': 0,
          'business': false,
          'isReview': true,
          'shopId': 2,
        }),
        'POST /cashier/order/today': jsonEncode({'code': 0, 'list': []}),
        'GET /admin/orderDetail/list': jsonEncode({
          'code': 0,
          'order': null,
          'list': [],
        }),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: CashierWorkspace(
            client: _client(transport),
            permissions: const {
              'cashier:operate',
              'order:view',
              'order:operate',
              'order:config',
            },
            shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
            currentShopId: 2,
            storeName: '松源海鲜街',
            onShopChanged: (_) {},
            onLogout: () {},
            onTableSelected: (_) async {},
            onPickupOrder: () async {},
            kdsAvailable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 已关闭营业 → 尝试开门 → 4001 拦截
      await tester.tap(find.byKey(const Key('cashier-business-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-notice-primary')));
      await tester.pumpAndSettle();

      // 无 admin:manage：仅提示引导，不提供直接强制营业按钮
      expect(find.text('无法开启营业：前一营业日尚未日结'), findsOneWidget);
      expect(find.text('强制营业'), findsNothing);
    },
  );

  testWidgets('switching back to a visited section silently refreshes it', (
    tester,
  ) async {
    _usePosViewport(tester);
    final transport = _transport();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierWorkspace(
          client: _client(transport),
          permissions: const {'cashier:operate', 'order:view', 'order:operate'},
          shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
          currentShopId: 2,
          storeName: '松源海鲜街',
          onShopChanged: (_) {},
          onLogout: () {},
          onTableSelected: (_) async {},
          onPickupOrder: () async {},
          kdsAvailable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    int billLoads() => transport.requests
        .where((request) => request.uri.path == '/cashier/order/today')
        .length;

    // 首次进入账单：initState 加载一次，首次激活不重复补偿
    await tester.tap(find.byKey(const Key('cashier-nav-bills')));
    await tester.pumpAndSettle();
    expect(billLoads(), 1);

    // 切走：停轮询，不再产生账单请求
    await tester.tap(find.byKey(const Key('cashier-nav-ordering')));
    await tester.pumpAndSettle();
    expect(billLoads(), 1);

    // 切回：立即静默补偿刷新一次
    await tester.tap(find.byKey(const Key('cashier-nav-bills')));
    await tester.pumpAndSettle();
    expect(billLoads(), 2);
  });

  testWidgets('hides privileged member and dish entries', (tester) async {
    _usePosViewport(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: CashierWorkspace(
          client: _client(_transport()),
          permissions: const {'cashier:operate'},
          shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
          currentShopId: 2,
          storeName: '松源海鲜街',
          onShopChanged: (_) {},
          onLogout: () {},
          onTableSelected: (_) async {},
          onPickupOrder: () async {},
          kdsAvailable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cashier-nav-members')), findsNothing);
    expect(find.byKey(const Key('cashier-nav-dishStatus')), findsNothing);
    expect(find.byKey(const Key('cashier-nav-bills')), findsOneWidget);
    expect(find.byKey(const Key('cashier-nav-shift')), findsOneWidget);
    expect(find.byKey(const Key('cashier-nav-settings')), findsNothing);
  });

  testWidgets('interface debug entry requires log view permission', (
    tester,
  ) async {
    _usePosViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: CashierApiDebugPage(
          client: _client(_transport()),
          permissions: const {'cashier:operate'},
          currentShopId: 2,
          storeName: '松源海鲜街',
        ),
      ),
    );

    expect(find.text('接口调试'), findsNothing);
    expect(find.text('当前账号暂无接口调试权限，请联系管理员授权。'), findsOneWidget);
  });

  testWidgets('offline banner stays visible until the network recovers', (
    tester,
  ) async {
    _usePosViewport(tester);
    final monitor = _FakeNetworkMonitor(online: false);

    await tester.pumpWidget(
      MaterialApp(
        home: CashierWorkspace(
          client: _client(_transport()),
          permissions: const {'cashier:operate'},
          shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
          currentShopId: 2,
          storeName: '松源海鲜街',
          onShopChanged: (_) {},
          onLogout: () {},
          onTableSelected: (_) async {},
          onPickupOrder: () async {},
          kdsAvailable: true,
          networkMonitor: monitor,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 断网：横幅常驻，顶栏显示云端离线
    expect(find.byKey(const Key('cashier-offline-banner')), findsOneWidget);
    expect(find.text('云端离线'), findsOneWidget);

    // 恢复网络：横幅消失，状态恢复云端在线 (12ms)
    monitor.setOnline(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cashier-offline-banner')), findsNothing);
    expect(find.text('云端在线 (12ms)'), findsOneWidget);
  });

  testWidgets('password change sends current and new password then re-logins', (
    tester,
  ) async {
    _usePosViewport(tester);
    final transport = _transport()
      ..routes['POST /admin/modifyPassword'] = jsonEncode({'code': 0});
    var loggedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CashierApiDebugPage(
          client: _client(transport),
          permissions: const {'admin:password'},
          currentShopId: 2,
          storeName: '松源海鲜街',
          onPasswordChanged: () => loggedOut = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('修改密码'));
    await tester.pumpAndSettle();
    // 安全加固后不再按用户名选目标，表单不再有「当前账号」字段
    expect(find.widgetWithText(TextFormField, '当前账号'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, '当前密码'),
      'old-secret',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '新密码'),
      'new-secret-1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '确认新密码'),
      'new-secret-1',
    );
    await tester.tap(find.text('确认修改'));
    await tester.pumpAndSettle();

    final request = transport.requests.singleWhere(
      (r) => r.uri.path == '/admin/modifyPassword',
    );
    final body = jsonDecode(request.body!) as Map<String, Object?>;
    expect(body['password'], 'old-secret');
    expect(body['newPassword'], 'new-secret-1');
    expect(body.containsKey('userName'), isFalse);
    // 服务端已使全部旧 Token 失效，客户端必须强制重新登录
    expect(loggedOut, isTrue);
  });

  testWidgets('password change from cashier identity capsule verifies current password and logs out', (
    tester,
  ) async {
    _usePosViewport(tester);
    final transport = _transport()
      ..routes['POST /admin/modifyPassword'] = jsonEncode({'code': 0});
    var loggedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CashierWorkspace(
          client: _client(transport),
          permissions: const {
            'cashier:operate',
            'order:view',
            'order:operate',
            'admin:password',
          },
          shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
          currentShopId: 2,
          currentDisplayName: '张三收银员',
          currentWorkNo: 'CW001',
          storeName: '松源海鲜街',
          onShopChanged: (_) {},
          onLogout: () => loggedOut = true,
          onTableSelected: (_) async {},
          onPickupOrder: () async {},
          kdsAvailable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 点击右上角身份胶囊打开员工个人档案
    await tester.tap(find.byKey(const Key('cashier-identity-capsule')));
    await tester.pumpAndSettle();

    expect(find.text('员工个人档案'), findsOneWidget);
    expect(find.byKey(const Key('cashier-profile-modify-password')), findsOneWidget);

    // 点击修改密码
    await tester.tap(find.byKey(const Key('cashier-profile-modify-password')));
    await tester.pumpAndSettle();

    expect(find.text('修改登录密码'), findsOneWidget);
    expect(find.text('账号：张三收银员'), findsOneWidget);

    // 填写原密码与新密码
    await tester.enterText(
      find.byKey(const Key('change-password-current')),
      'old-password-123',
    );
    await tester.enterText(
      find.byKey(const Key('change-password-new')),
      'new-password-789',
    );
    await tester.enterText(
      find.byKey(const Key('change-password-confirm')),
      'new-password-789',
    );

    // 提交
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();

    final request = transport.requests.singleWhere(
      (r) => r.uri.path == '/admin/modifyPassword',
    );
    final body = jsonDecode(request.body!) as Map<String, Object?>;
    expect(body['password'], 'old-password-123');
    expect(body['newPassword'], 'new-password-789');

    // 凭证吊销，触发登出
    expect(loggedOut, isTrue);
  });

  testWidgets('password change validates input and displays error when current password is wrong', (
    tester,
  ) async {
    _usePosViewport(tester);
    final transport = _transport()
      ..routes['POST /admin/modifyPassword'] = jsonEncode({
        'code': 1,
        'msg': '当前密码错误！',
      });
    var loggedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CashierWorkspace(
          client: _client(transport),
          permissions: const {
            'cashier:operate',
            'order:view',
            'order:operate',
            'admin:password',
          },
          shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
          currentShopId: 2,
          currentDisplayName: '李四收银员',
          currentWorkNo: 'CW002',
          storeName: '松源海鲜街',
          onShopChanged: (_) {},
          onLogout: () => loggedOut = true,
          onTableSelected: (_) async {},
          onPickupOrder: () async {},
          kdsAvailable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cashier-identity-capsule')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cashier-profile-modify-password')));
    await tester.pumpAndSettle();

    // 校验：空密码校验
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();
    expect(find.text('请输入当前密码（原始密码）'), findsOneWidget);
    expect(find.text('请输入新密码'), findsOneWidget);

    // 校验：新密码少于6位
    await tester.enterText(
      find.byKey(const Key('change-password-current')),
      'wrong-pass',
    );
    await tester.enterText(
      find.byKey(const Key('change-password-new')),
      '123',
    );
    await tester.enterText(
      find.byKey(const Key('change-password-confirm')),
      '123',
    );
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();
    expect(find.text('新密码长度不能少于 6 位'), findsOneWidget);

    // 校验：两次新密码不一致
    await tester.enterText(
      find.byKey(const Key('change-password-new')),
      '123456',
    );
    await tester.enterText(
      find.byKey(const Key('change-password-confirm')),
      '654321',
    );
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的新密码不一致'), findsOneWidget);

    // 输入正确格式，但原密码错误（服务端返回 1 当前密码错误！）
    await tester.enterText(
      find.byKey(const Key('change-password-confirm')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();

    expect(find.text('当前密码错误！'), findsOneWidget);
    expect(loggedOut, isFalse);
  });

  testWidgets('password change from cashier settings hub triggers modify password dialog and logs out', (
    tester,
  ) async {
    _usePosViewport(tester);
    final transport = _transport()
      ..routes['POST /admin/modifyPassword'] = jsonEncode({'code': 0});
    var loggedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CashierWorkspace(
          client: _client(transport),
          permissions: const {
            'cashier:operate',
            'order:view',
            'order:operate',
            'admin:password',
          },
          shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
          currentShopId: 2,
          currentDisplayName: '店长操作员',
          currentWorkNo: 'MGR001',
          storeName: '松源海鲜街',
          onShopChanged: (_) {},
          onLogout: () => loggedOut = true,
          onTableSelected: (_) async {},
          onPickupOrder: () async {},
          kdsAvailable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 切换到设置页
    await tester.tap(find.byKey(const Key('cashier-nav-settings')));
    await tester.pumpAndSettle();

    // 验证设置主页右上角存在「修改密码」按钮
    expect(find.byKey(const Key('settings-modify-password-button')), findsOneWidget);

    // 点击设置主页的修改密码按钮
    await tester.tap(find.byKey(const Key('settings-modify-password-button')));
    await tester.pumpAndSettle();

    expect(find.text('修改登录密码'), findsOneWidget);

    // 填写原密码与新密码
    await tester.enterText(
      find.byKey(const Key('change-password-current')),
      'mgr-old-pass',
    );
    await tester.enterText(
      find.byKey(const Key('change-password-new')),
      'mgr-new-pass-1',
    );
    await tester.enterText(
      find.byKey(const Key('change-password-confirm')),
      'mgr-new-pass-1',
    );

    // 提交
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();

    final request = transport.requests.singleWhere(
      (r) => r.uri.path == '/admin/modifyPassword',
    );
    final body = jsonDecode(request.body!) as Map<String, Object?>;
    expect(body['password'], 'mgr-old-pass');
    expect(body['newPassword'], 'mgr-new-pass-1');
    expect(loggedOut, isTrue);
  });


  testWidgets('切换门店原地刷新数据，不销毁工作区、不跳回首页', (tester) async {
    _usePosViewport(tester);
    final transport = _transport();
    await tester.pumpWidget(_ShopSwitchHost(transport: transport));
    await tester.pumpAndSettle();

    // 先切到账单页
    await tester.tap(find.byKey(const Key('cashier-nav-bills')));
    await tester.pumpAndSettle();
    final billsBefore = transport.requests
        .where((r) => r.uri.path == '/cashier/order/today')
        .length;
    expect(billsBefore, greaterThan(0));
    final tableBefore = transport.requests
        .where((r) => r.uri.path == '/admin/table/status')
        .length;

    // 顶部门店选择器：门店 2 → 3
    await tester.tap(find.byKey(const Key('cashier-shop-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('江门店').last);
    await tester.pumpAndSettle();

    // 仍停留在账单页：账单以新门店数据重新加载，且未跳回点餐页重新拉桌台
    final billsAfter = transport.requests
        .where((r) => r.uri.path == '/cashier/order/today')
        .length;
    expect(billsAfter, greaterThan(billsBefore), reason: '账单页应以新门店数据原地刷新');
    final tableAfter = transport.requests
        .where((r) => r.uri.path == '/admin/table/status')
        .length;
    expect(tableAfter, tableBefore, reason: '不应跳回点餐页重新加载桌台');
    // 刷新请求携带新门店标识
    final lastToday = transport.requests.lastWhere(
      (r) => r.uri.path == '/cashier/order/today',
    );
    expect(lastToday.headers['X-Shop-Id'], '3');
  });

  testWidgets('顶部门店选择器一体化展示，去重复且切换后同步品牌门店名', (tester) async {
    _usePosViewport(tester);
    final transport = _transport();
    await tester.pumpWidget(_ShopSwitchHost(transport: transport));
    await tester.pumpAndSettle();

    // 多门店时：门店选择器作为一体化标题展示，不出现静态门店名与下拉框重复并存
    expect(find.byKey(const Key('cashier-shop-picker')), findsOneWidget);
    expect(find.byKey(const Key('cashier-brand-store-name')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('cashier-brand-store-name'))).data,
      '松源海鲜街',
    );

    // 切换到江门店
    await tester.tap(find.byKey(const Key('cashier-shop-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('江门店').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cashier-brand-store-name')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('cashier-brand-store-name'))).data,
      '江门店',
    );
  });

  testWidgets('档案弹窗切换账号：选历史工号触发回调，不保存密码', (tester) async {
    _usePosViewport(tester);
    final memoryStore = MemoryAccountKeyValueStorage();
    await memoryStore.write(
      'saved_cashier_accounts',
      jsonEncode(['CW001', 'CW099']),
    );
    String? switchedTo;
    var loggedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CashierWorkspace(
          client: _client(_transport()),
          permissions: const {'cashier:operate', 'order:view', 'order:operate'},
          shops: const [ShopSummary(id: 2, code: 'SY', name: '松源海鲜街')],
          currentShopId: 2,
          storeName: '松源海鲜街',
          currentDisplayName: '张三收银员',
          currentWorkNo: 'CW001',
          onShopChanged: (_) {},
          onLogout: () => loggedOut = true,
          accountStorage: CashierAccountStorage(memoryStore),
          onSwitchAccount: (workNo) => switchedTo = workNo,
          onTableSelected: (_) async {},
          onPickupOrder: () async {},
          kdsAvailable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 打开员工个人档案 → 有「切换账号」入口
    await tester.tap(find.byKey(const Key('cashier-identity-capsule')));
    await tester.pumpAndSettle();
    expect(find.text('员工个人档案'), findsOneWidget);
    expect(
      find.byKey(const Key('cashier-profile-switch-account')),
      findsOneWidget,
    );

    // 点击切换账号 → 弹窗列出历史工号，当前工号带「当前」标记
    await tester.tap(
      find.byKey(const Key('cashier-profile-switch-account')),
    );
    await tester.pumpAndSettle();
    expect(find.text('CW099'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);

    // 选择 CW099 → 回调收到目标工号；不触发退出登录（退出由宿主统一处理）
    await tester.tap(find.byKey(const Key('switch-account-CW099')));
    await tester.pumpAndSettle();
    expect(switchedTo, 'CW099');
    expect(loggedOut, isFalse);
  });

  testWidgets('履约外卖红点严格按当前门店隔离，非点餐页切换门店时亦实时同步清除其他门店红点', (tester) async {
    _usePosViewport(tester);
    // 模拟后端返回混合了门店2与门店3的履约单：
    // 门店2（松源海鲜街）有 2 笔待处理外卖/自提单，门店3（江门店）为 0 笔待处理单（仅1笔已完成）
    final transport = FakeHttpTransport({
      ..._transport().routes,
      'POST /admin/order/list': jsonEncode({
        'code': 200,
        'orderList': [
          {
            'id': 201,
            'shop_id': 2,
            'order_no': 'TO-201',
            'order_type': '外卖',
            'receiving_status': 'rec_order',
            'transac_status': 'success',
            'pickup_code': 'B01',
          },
          {
            'id': 202,
            'shop_id': 2,
            'order_no': 'PK-202',
            'order_type': '自提',
            'receiving_status': 'rec_order',
            'transac_status': 'success',
            'pickup_code': 'A02',
          },
          {
            // 其他门店（门店99）的待处理外卖单，必须被门店隔离过滤掉
            'id': 991,
            'shop_id': 99,
            'order_no': 'TO-991',
            'order_type': '外卖',
            'receiving_status': 'rec_order',
            'transac_status': 'success',
            'pickup_code': 'B99',
          },
          {
            // 门店3仅有一笔已完成外卖单
            'id': 301,
            'shop_id': 3,
            'order_no': 'TO-301',
            'order_type': '外卖',
            'receiving_status': 'off_order',
            'transac_status': 'success',
            'pickup_code': 'B03',
          },
        ],
        'total': 4,
      }),
    });

    await tester.pumpWidget(_ShopSwitchHost(transport: transport));
    await tester.pumpAndSettle();

    final fulfillmentBtn = find.byKey(const Key('topbar-fulfillment-btn'));
    expect(fulfillmentBtn, findsOneWidget);
    // 门店2仅展示本门店的 2 笔待履约单红点，不混入门店99的订单
    expect(
      find.descendant(of: fulfillmentBtn, matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fulfillmentBtn, matching: find.text('3')),
      findsNothing,
    );

    // 切换到「账单」页面（非点餐页）后，再切换门店到「江门店」(shopId=3)
    await tester.tap(find.byKey(const Key('cashier-nav-bills')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cashier-shop-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('江门店').last);
    await tester.pumpAndSettle();

    // 门店3无待履约单，即使当前处于账单页，顶部常驻栏红点也必须立即清零，不残留门店2的红点
    expect(
      find.descendant(of: fulfillmentBtn, matching: find.text('2')),
      findsNothing,
    );
  });
}

class _ShopSwitchHost extends StatefulWidget {
  const _ShopSwitchHost({required this.transport});

  final FakeHttpTransport transport;

  @override
  State<_ShopSwitchHost> createState() => _ShopSwitchHostState();
}

class _ShopSwitchHostState extends State<_ShopSwitchHost> {
  int _shopId = 2;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CashierWorkspace(
        client: AdminApiClient(
          baseUrl: 'https://example.test',
          transport: widget.transport,
          token: 'token',
          shopId: _shopId,
        ),
        permissions: const {
          'cashier:operate',
          'order:view',
          'order:operate',
          'order:config',
          'user:view',
          'user:points',
          'dish:manage',
          'report:view',
          'coupon:manage',
          'activity:manage',
          'announcement:manage',
          'statistics:view',
          'admin:manage',
          'admin:password',
          'log:view',
          'payment:config:read',
          'payment:config:write',
        },
        shops: const [
          ShopSummary(id: 2, code: 'SY', name: '松源海鲜街'),
          ShopSummary(id: 3, code: 'JH', name: '江门店'),
        ],
        currentShopId: _shopId,
        storeName: _shopId == 2 ? '松源海鲜街' : '江门店',
        onShopChanged: (id) => setState(() => _shopId = id),
        onLogout: () {},
        onTableSelected: (_) async {},
        onPickupOrder: () async {},
        kdsAvailable: true,
      ),
    );
  }
}

class _FakeNetworkMonitor extends NetworkStatusMonitor {
  _FakeNetworkMonitor({required bool online})
    : _online = online,
      super(baseUrl: 'https://example.test', transport: FakeHttpTransport({}));

  bool _online;

  @override
  bool get online => _online;

  @override
  void start() {}

  @override
  Future<void> probeNow() async {}

  void setOnline(bool value) {
    _online = value;
    notifyListeners();
  }
}

AdminApiClient _client(FakeHttpTransport transport) => AdminApiClient(
  baseUrl: 'https://example.test',
  transport: transport,
  token: 'token',
  shopId: 2,
);

FakeHttpTransport _transport() => FakeHttpTransport({
  'GET /admin/table/status': jsonEncode({
    'code': 200,
    'data': {
      'tableList': [
        {'id': 1, 'number': '1', 'status': 0},
      ],
    },
  }),
  'GET /admin/settings/overview': jsonEncode({
    'code': 0,
    'shopId': 2,
    'modules': <Object?>[],
  }),
  'POST /admin/order/list': jsonEncode({
    'code': 200,
    'data': {'records': [], 'total': 0},
  }),
  'GET /cashier/shift/current': jsonEncode({'code': 0, 'shift': null}),
  'POST /order/Business': jsonEncode({
    'code': 0,
    'business': true,
    'isReview': true,
    'shopId': 2,
  }),
  'POST /cashier/shop/business': jsonEncode({'code': 0}),
  'GET /cashier/order/today': jsonEncode({
    'code': 0,
    'list': [
      {
        'id': 42,
        'order_no': 'ORD-42',
        'table_number': '1',
        'transac_status': 'unsettled',
      },
    ],
  }),
  'GET /admin/orderDetail/list': jsonEncode({
    'code': 0,
    'order': {
      'id': 42,
      'order_no': 'ORD-42',
      'table_number': '1',
      'transac_status': 'unsettled',
    },
    'list': [],
  }),
});

class _BlockingBusinessOpenTransport extends FakeHttpTransport {
  _BlockingBusinessOpenTransport(super.routes);

  bool serverOpen = false;

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    if (uri.path == '/order/Business') {
      requests.add(
        RecordedRequest(
          method: method,
          uri: uri,
          headers: Map.of(headers),
          body: body,
        ),
      );
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({
          'code': 0,
          'business': serverOpen,
          'isReview': true,
          'shopId': 2,
        }),
      );
    }
    if (uri.path == '/cashier/shop/business') {
      requests.add(
        RecordedRequest(
          method: method,
          uri: uri,
          headers: Map.of(headers),
          body: body,
        ),
      );
      final payload = jsonDecode(body ?? '{}') as Map<String, Object?>;
      if (payload['force'] == '1') {
        serverOpen = true;
        return HttpResponseData(statusCode: 200, body: jsonEncode({'code': 0}));
      }
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({
          'code': 4001,
          'msg': '未开班不得营业，请先开班（可带 force=1 由老板/店长强制跳过）',
        }),
      );
    }
    return super.send(method: method, uri: uri, headers: headers, body: body);
  }
}

class _MutableBusinessTransport extends FakeHttpTransport {
  _MutableBusinessTransport(super.routes, this.isOpen);

  bool isOpen;

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    if (uri.path == '/order/Business') {
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({
          'code': 0,
          'business': isOpen,
          'isReview': true,
          'shopId': 2,
        }),
      );
    }
    return super.send(method: method, uri: uri, headers: headers, body: body);
  }
}

void _usePosViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
