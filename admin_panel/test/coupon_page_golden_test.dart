import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_coupon_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

class _FakeSettingsRepository implements CashierSettingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 生产 UI 截图（accept 阶段保真对比证据）：
/// 以真实主题/真实字体渲染生产优惠券页面（1440×900，与原型同视口），
/// golden 输出到 design/prototypes/UI032-coupon-interaction-redesign/_shots/。
void main() {
  setUpAll(() async {
    final fontLoader = FontLoader('NotoSansSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-VF.ttf'));
    await fontLoader.load();
  });

  Widget buildPage({
    required FakeHttpTransport transport,
    required String sectionId,
  }) {
    final client = AdminApiClient(
      baseUrl: 'http://api.test',
      transport: transport,
      token: 'token',
      shopId: 8,
    );
    return MaterialApp(
      theme: CashierAppTheme.light(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: CashierSettingsCouponPage(
          repository: _FakeSettingsRepository(),
          client: client,
          section: SettingsSectionSpec(
            sectionId,
            'section',
            Icons.confirmation_number_outlined,
          ),
          // 固定「更新于」时钟，保证截图可复现。
          now: () => DateTime(2026, 10, 10, 9, 30),
        ),
      ),
    );
  }

  // 与原型桌面数据对应的券模板列表（含无限库存/已发占比/到期着色）。
  Map<String, Object?> couponRow(
    int id,
    String name,
    String type,
    int status,
    double discount,
    double minAmount,
    int stock,
    int granted,
    String end,
  ) => {
    'id': id,
    'coupon_name': name,
    'coupon_type': type,
    'status': status,
    'discount_value': discount,
    'min_amount': minAmount,
    'stock': stock,
    'granted_count': granted,
    'start_time': '2026-01-01 00:00:00',
    'end_time': end,
    'validity_time': 24,
    'description': '全场通用，买单时自动抵扣',
  };

  testWidgets('production coupons list at 1440x900', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = FakeHttpTransport({
      'GET /admin/coupon/list': jsonEncode({
        'list': [
          couponRow(5, '满50减10', 'full_reduction', 1, 10, 50, 100, 82,
              '2026-12-31 23:59:59'),
          couponRow(6, '新客立减5', 'direct_reduction', 0, 5, 0, -1, 0,
              '2026-12-31 23:59:59'),
          couponRow(7, '会员8折券', 'discount', 1, 8, 30, 300, 211,
              '2026-10-20 23:59:59'),
          couponRow(8, '夜宵满30减3', 'full_reduction', 2, 3, 30, 50, 31,
              '2026-09-30 23:59:59'),
          couponRow(9, '储值赠券', 'direct_reduction', 1, 20, 200, 20, 3,
              '2026-11-30 23:59:59'),
        ],
        'total': 5,
      }),
    });

    await tester.pumpWidget(buildPage(transport: transport, sectionId: 'coupons'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(CashierSettingsCouponPage),
      matchesGoldenFile(
        '../design/prototypes/UI032-coupon-interaction-redesign/_shots/production_coupons_1440.png',
      ),
    );
  });

  testWidgets('production form with dish picker dialog at 1440x900',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = FakeHttpTransport({
      'GET /admin/coupon/list': jsonEncode({'list': [], 'total': 0}),
      'GET /dish/listAll': jsonEncode({
        'allDish': [
          {
            'name': '招牌烤鱼',
            'dishList': [
              {'id': 1, 'name': '香辣烤鱼', 'unitprice': '88'},
              {'id': 2, 'name': '蒜香烤鱼', 'unitprice': '92'},
              {'id': 3, 'name': '豆豉烤鱼', 'unitprice': '98'},
            ],
          },
          {
            'name': '凉菜',
            'dishList': [
              {'id': 11, 'name': '凉菜拼盘', 'unitprice': '32'},
              {'id': 12, 'name': '拍黄瓜', 'unitprice': '12'},
            ],
          },
          {
            'name': '饮品',
            'dishList': [
              {'id': 21, 'name': '酸梅汤', 'unitprice': '8'},
            ],
          },
        ],
      }),
    });

    await tester.pumpWidget(buildPage(transport: transport, sectionId: 'coupons'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coupon-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择菜品'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../design/prototypes/UI032-coupon-interaction-redesign/_shots/production_form_dish_picker.png',
      ),
    );
  });
}
