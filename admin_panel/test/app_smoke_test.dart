import 'dart:convert';

import 'package:admin_panel_flutter/src/app/admin_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  testWidgets('login renders legacy admin menu groups and entries', (
    tester,
  ) async {
    final transport = FakeHttpTransport({
      'POST /adminLogin': jsonEncode({
        'code': 200,
        'data': {'token': 'jwt-token', 'scope': 'HQ'},
      }),
      'GET /admin/me/permissions': jsonEncode({
        'code': 200,
        'data': {
          'scope': 'HQ',
          'permissions': [
            'statistics:view',
            'user:view',
            'order:view',
            'order:operate',
            'dish:manage',
            'table:manage',
            'kds:config',
            'shop:manage',
            'banner:manage',
            'coupon:manage',
            'daily:settle',
            'material:manage',
            'log:view',
            'admin:manage',
            'payment:config:read',
          ],
        },
      }),
      'GET /admin/me/shops': jsonEncode({
        'code': 200,
        'data': {
          'shops': [
            {'id': 1, 'code': 'HQ001', 'name': '总部店'},
          ],
        },
      }),
      'POST /admin/order/list': jsonEncode({
        'code': 200,
        'data': {'records': [], 'total': 0},
      }),
      'GET /admin/order/todayCount': jsonEncode({'code': 200, 'data': 0}),
    });

    await tester.pumpWidget(AdminPanelFlutterApp(transport: transport));
    await tester.pumpAndSettle();

    expect(find.text('登录并拉取权限'), findsOneWidget);
    expect(find.text('生产环境：https://www.laofei.com.cn'), findsOneWidget);
    expect(find.text('后端 API Base URL'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.text('登录并拉取权限'));
    await tester.pumpAndSettle();

    expect(find.text('收银营业'), findsOneWidget);
    expect(find.text('商品菜单'), findsOneWidget);
    expect(find.text('门店营销'), findsOneWidget);
    expect(find.text('数据财务'), findsOneWidget);
    expect(find.text('功能设置'), findsOneWidget);
    expect(find.text('订单管理'), findsWidgets);
  });
}
