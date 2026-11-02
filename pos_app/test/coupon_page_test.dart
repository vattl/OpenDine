import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_coupon_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'fake_http_transport.dart';

class _FakeSettingsRepository implements CashierSettingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('coupon settings page (M-J)', () {
    Widget build({
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
        home: Scaffold(
          body: CashierSettingsCouponPage(
            repository: _FakeSettingsRepository(),
            client: client,
            section: SettingsSectionSpec(
              sectionId,
              'section',
              Icons.confirmation_number_outlined,
            ),
          ),
        ),
      );
    }

    testWidgets('coupons section lists templates with status badge',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'coupon_type': 'full_reduction',
              'status': 1,
              'discount_value': 10,
              'min_amount': 50,
              'stock': 100,
              'granted_count': 12,
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      expect(find.text('满50减10'), findsOneWidget);
      expect(find.text('可用'), findsAtLeastNWidgets(1));
      // 新库存列：已发占比（已发 x/y），无限库存显示「无限」。
      expect(find.text('已发 12/100'), findsOneWidget);
      expect(find.text('共 1 条'), findsOneWidget);
    });

    testWidgets('redeem-codes section renders rows and qrcode dialog',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'status': 1,
              'stock': -1,
            },
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [
            {
              'id': 9,
              'coupon_id': 5,
              'redeem_code': 'LAOFEI-ABC',
              'status': 0,
              'create_time': '2026-08-01 00:00:00',
            },
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/qrcode': 'png',
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redeem-codes'),
      );
      await tester.pumpAndSettle();

      expect(find.text('LAOFEI-ABC'), findsOneWidget);
      expect(find.textContaining('未核销'), findsAtLeastNWidgets(1));

      await tester.tap(find.byIcon(Icons.qr_code_2_outlined));
      await tester.pumpAndSettle();
      expect(find.text('兑换码二维码'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('grant section renders coupon dropdown and upload path',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'status': 1,
              'stock': 100,
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'grant'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Excel 批量发券'), findsOneWidget);
      expect(
        find.byKey(const Key('coupon-grant-excel-path')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('coupon-grant-submit')),
        findsOneWidget,
      );
    });

    testWidgets('user-coupons section renders rows with actions',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'status': 1,
              'stock': -1,
            },
          ],
          'total': 1,
        }),
        'GET /admin/coupon/user-coupon/list': jsonEncode({
          'list': [
            {
              'id': 33,
              'user_openid': 'oX_2',
              'coupon_name': '满50减10',
              'status': 0,
              'get_time': '2026-08-02 10:00:00',
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'user-coupons'),
      );
      await tester.pumpAndSettle();

      expect(find.text('未使用'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const Key('coupon-user-coupon-void-33')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('coupon-user-coupon-unbind-33')),
        findsOneWidget,
      );
    });
    testWidgets('coupons section opens create form dialog', (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({'list': [], 'total': 0}),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-add-button')));
      await tester.pumpAndSettle();

      expect(find.text('新增优惠券'), findsAtLeastNWidgets(1));
      expect(find.byKey(const Key('coupon-form-name')), findsOneWidget);
      expect(find.byKey(const Key('coupon-form-submit')), findsOneWidget);
    });

    testWidgets('coupons section shows edit and delete actions per row',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'coupon_type': 'full_reduction',
              'status': 1,
              'discount_value': 10,
              'min_amount': 50,
              'stock': 100,
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coupon-edit-5')), findsOneWidget);
      expect(find.byKey(const Key('coupon-delete-5')), findsOneWidget);
      expect(find.byKey(const Key('coupon-detail-5')), findsOneWidget);
    });

    testWidgets('redeem-codes section opens create codes dialog',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': -1},
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [],
          'total': 0,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redeem-codes'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-redeem-code-create')));
      await tester.pumpAndSettle();

      expect(find.text('生成兑换码'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const Key('coupon-redeem-code-count')),
        findsOneWidget,
      );
    });

    testWidgets('grant section opens direct grant dialog', (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': 100},
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'grant'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-grant-direct')));
      await tester.pumpAndSettle();

      expect(find.text('定向发券'), findsOneWidget);
      expect(
        find.byKey(const Key('coupon-grant-direct-openid')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('coupon-grant-direct-phone')),
        findsOneWidget,
      );
    });

    testWidgets('coupons section shows value block and icon actions',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'coupon_type': 'full_reduction',
              'status': 1,
              'discount_value': 10,
              'min_amount': 50,
              'stock': 100,
              'granted_count': 12,
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      // 面值块突出显示。
      expect(find.text('¥10'), findsOneWidget);
      expect(find.text('满减'), findsAtLeastNWidgets(1));
      // 图标化操作按钮仍可定位。
      expect(find.byKey(const Key('coupon-detail-5')), findsOneWidget);
      expect(find.byKey(const Key('coupon-edit-5')), findsOneWidget);
      expect(find.byKey(const Key('coupon-delete-5')), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('redeem-codes rows show status badge and keyed qrcode button',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': -1},
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [
            {
              'id': 9,
              'coupon_id': 5,
              'redeem_code': 'LAOFEI-ABC',
              'status': 0,
              'create_time': '2026-08-01 00:00:00',
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redeem-codes'),
      );
      await tester.pumpAndSettle();

      expect(find.text('LAOFEI-ABC'), findsOneWidget);
      expect(find.text('未核销'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const Key('coupon-redeem-code-qrcode-9')),
        findsOneWidget,
      );
    });

    testWidgets('grant section exposes file picker button', (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': 100},
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'grant'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Excel 批量发券'), findsOneWidget);
      expect(
        find.byKey(const Key('coupon-grant-excel-pick')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('coupon-grant-submit')),
        findsOneWidget,
      );
    });

    testWidgets('coupons section shows down-shelf toggle for active coupon',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'coupon_type': 'full_reduction',
              'status': 1,
              'discount_value': 10,
              'min_amount': 50,
              'stock': 100,
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('coupon-status-toggle-5')),
        findsOneWidget,
      );
      expect(find.text('下架'), findsAtLeastNWidgets(1));
    });

    testWidgets('coupons section offers re-publish for disabled coupon',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'coupon_type': 'full_reduction',
              'status': 0,
              'discount_value': 10,
              'min_amount': 50,
              'stock': 100,
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('coupon-status-toggle-5')),
        findsOneWidget,
      );
      expect(find.text('上架'), findsAtLeastNWidgets(1));
    });

    testWidgets('redeem-codes section offers select all', (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': -1},
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [
            {
              'id': 9,
              'coupon_id': 5,
              'redeem_code': 'LAOFEI-ABC',
              'status': 0,
              'create_time': '2026-08-01 00:00:00',
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redeem-codes'),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('coupon-redeem-code-select-all')),
        findsOneWidget,
      );
    });

    testWidgets('redeem-codes qrcode dialog offers copy button',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': -1},
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [
            {
              'id': 9,
              'coupon_id': 5,
              'redeem_code': 'LAOFEI-ABC',
              'status': 0,
              'create_time': '2026-08-01 00:00:00',
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redeem-codes'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.qr_code_2_outlined));
      await tester.pumpAndSettle();

      expect(find.text('兑换码二维码'), findsOneWidget);
      expect(
        find.byKey(const Key('coupon-redeem-code-copy')),
        findsOneWidget,
      );
    });

    testWidgets('coupons add form opens as right drawer', (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'status': 1,
              'stock': 100,
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-add-button')));
      await tester.pumpAndSettle();

      expect(find.text('新增优惠券'), findsAtLeastNWidgets(1));
      expect(find.byKey(const Key('coupon-form-name')), findsOneWidget);
      expect(
        find.byKey(const Key('coupon-form-submit')),
        findsOneWidget,
      );
    });

    testWidgets('redeem-codes batch bar appears after selection',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'status': 1,
              'stock': -1,
            },
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [
            {
              'id': 9,
              'coupon_id': 5,
              'redeem_code': 'LAOFEI-ABC',
              'status': 0,
              'create_time': '2026-08-01 00:00:00',
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redeem-codes'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('已选'), findsNothing);

      await tester.tap(find.byKey(const Key('coupon-redeem-code-select-all')));
      await tester.pumpAndSettle();

      expect(find.text('已选 1 项'), findsOneWidget);
      expect(find.text('取消选择'), findsOneWidget);
      expect(
        find.byKey(const Key('coupon-redeem-code-delete')),
        findsOneWidget,
      );

      await tester.tap(find.text('取消选择'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已选'), findsNothing);
    });

    testWidgets('coupons dish picker selects dishes and previews JSON',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({'list': [], 'total': 0}),
        // 公开菜品端点：分组（allDish → dishList）。
        'GET /dish/listAll': jsonEncode({
          'allDish': [
            {
              'name': '堂食',
              'dishList': [
                {'id': 1, 'name': '烤鱼', 'unitprice': '88'},
                {'id': 2, 'name': '凉菜拼盘', 'unitprice': '32'},
              ],
            },
          ],
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-add-button')));
      await tester.pumpAndSettle();

      // 打开菜品选择器：分组复选框 + 搜索 + 已选计数。
      await tester.tap(find.text('选择菜品'));
      await tester.pumpAndSettle();
      expect(find.text('堂食'), findsOneWidget);
      expect(find.text('烤鱼'), findsOneWidget);
      expect(find.text('已选 0 项'), findsOneWidget);

      // 勾选两道菜品并确认。
      await tester.tap(find.text('烤鱼'));
      await tester.tap(find.text('凉菜拼盘'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('coupon-dish-picker-confirm')));
      await tester.pumpAndSettle();

      // 表单内：已选 chips + 客户端自动转 JSON 的实时预览。
      expect(
        find.byKey(const Key('coupon-form-dish-chip-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('coupon-form-dish-chip-2')),
        findsOneWidget,
      );
      expect(find.text('提交 JSON：[1,2]'), findsOneWidget);
    });

    testWidgets('coupons form submit shows real server id on create',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({'list': [], 'total': 0}),
        // 服务端真实返回新增 id=7（不再用本地假 ID 0）。
        'POST /admin/coupon/add': jsonEncode({'id': 7}),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-add-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('coupon-form-name')),
        '满30减5',
      );
      await tester.enterText(
        find.byKey(const Key('coupon-form-stock')),
        '50',
      );
      await tester.tap(find.byKey(const Key('coupon-form-submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('优惠券已创建（ID 7）'),
        findsOneWidget,
      );
    });

    testWidgets('coupons form submit failure keeps drawer with inline error',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({'list': [], 'total': 0}),
        'POST /admin/coupon/add': jsonEncode({'code': 500, 'msg': '库存不足'}),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-add-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('coupon-form-name')),
        '满30减5',
      );
      await tester.enterText(
        find.byKey(const Key('coupon-form-stock')),
        '50',
      );
      await tester.tap(find.byKey(const Key('coupon-form-submit')));
      await tester.pumpAndSettle();

      // 失败：内联错误条展示、表单未关闭、输入保留。
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(find.byKey(const Key('coupon-form-name')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('coupon-form-name')))
            .controller!
            .text,
        '满30减5',
      );
    });

    testWidgets('coupons detail opens with server detail and shows fields',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'coupon_type': 'full_reduction',
              'status': 1,
              'discount_value': 10,
              'min_amount': 50,
              'stock': 100,
              'granted_count': 12,
            },
          ],
          'total': 1,
        }),
        'GET /admin/coupon/get': jsonEncode({
          'coupon': {
            'id': 5,
            'coupon_name': '满50减10',
            'coupon_type': 'full_reduction',
            'status': 1,
            'discount_value': 10,
            'min_amount': 50,
            'stock': 100,
            'granted_count': 12,
            'apply_dish_ids': '[1,2]',
          },
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('coupon-detail-5')));
      await tester.tap(find.byKey(const Key('coupon-detail-5')));
      await tester.pumpAndSettle();

      expect(find.text('券模板详情：满50减10'), findsOneWidget);
      expect(find.text('[1,2]'), findsOneWidget);
    });

    testWidgets('coupons detail failure shows error state with retry',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'status': 1,
              'stock': 100,
            },
          ],
          'total': 1,
        }),
        'GET /admin/coupon/get': 'not-valid-json',
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('coupon-detail-5')));
      await tester.tap(find.byKey(const Key('coupon-detail-5')));
      await tester.pumpAndSettle();

      // 详情失败：错误态 + 重试按钮（不再静默回退列表行数据）。
      expect(find.textContaining('详情加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('redeem-codes row offers inline copy with feedback',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': -1},
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [
            {
              'id': 9,
              'coupon_id': 5,
              'redeem_code': 'LAOFEI-ABC',
              'status': 0,
              'create_time': '2026-08-01 00:00:00',
            },
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redeem-codes'),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('coupon-redeem-code-copy-9')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('coupon-redeem-code-copy-9')));
      await tester.pumpAndSettle();
      expect(find.text('兑换码已复制'), findsOneWidget);
    });

    testWidgets('redeem-codes create dialog submits with server result',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': -1},
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [],
          'total': 0,
        }),
        'POST /admin/coupon/redeem-code/create': jsonEncode({
          'codes': [
            {'id': 1, 'redeem_code': 'NEW-CODE-01', 'status': 0},
          ],
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redeem-codes'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-redeem-code-create')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('coupon-redeem-code-create-submit')),
      );
      await tester.pumpAndSettle();

      expect(find.text('已生成 1 个兑换码'), findsOneWidget);
    });

    testWidgets('coupons refresh button reloads the list', (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': 100},
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();
      expect(find.text('共 1 条'), findsOneWidget);

      transport.routes['GET /admin/coupon/list'] = jsonEncode({
        'list': [],
        'total': 0,
      });
      await tester.tap(find.byKey(const Key('coupon-coupons-refresh')));
      await tester.pumpAndSettle();

      expect(find.text('共 0 条'), findsOneWidget);
    });

    testWidgets('coupons filter chip sends status param to server',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': 100},
          ],
          'total': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, '可用'));
      await tester.pumpAndSettle();

      final listRequests = transport.requests
          .where((r) => r.uri.path == '/admin/coupon/list')
          .toList();
      expect(listRequests.length, greaterThanOrEqualTo(2));
      expect(listRequests.last.uri.queryParameters['status'], '1');
    });

    testWidgets('coupons edit submit calls update and shows saved',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'coupon_type': 'full_reduction',
              'status': 1,
              'discount_value': 10,
              'min_amount': 50,
              'stock': 100,
            },
          ],
          'total': 1,
        }),
        'POST /admin/coupon/update': '',
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'coupons'),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('coupon-edit-5')));
      await tester.tap(find.byKey(const Key('coupon-edit-5')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('coupon-form-name')),
        '满50减12',
      );
      await tester.tap(find.byKey(const Key('coupon-form-submit')));
      await tester.pumpAndSettle();

      expect(find.text('优惠券已更新'), findsOneWidget);
    });

    testWidgets('redeem-codes create dialog validates count range',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': -1},
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [],
          'total': 0,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redeem-codes'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-redeem-code-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('coupon-redeem-code-count')),
        '0',
      );
      await tester.tap(
        find.byKey(const Key('coupon-redeem-code-create-submit')),
      );
      await tester.pumpAndSettle();

      expect(find.text('数量需为 1~500 的整数'), findsOneWidget);
    });

    testWidgets('redeem-codes batch delete submits and shows deleted count',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': -1},
          ],
          'total': 1,
        }),
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [
            {
              'id': 9,
              'coupon_id': 5,
              'redeem_code': 'LAOFEI-ABC',
              'status': 0,
              'create_time': '2026-08-01 00:00:00',
            },
          ],
          'total': 1,
        }),
        'POST /admin/coupon/redeem-code/delete': jsonEncode({'deleted': 1}),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redeem-codes'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-redeem-code-select-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('coupon-redeem-code-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      expect(find.text('已删除 1 个兑换码'), findsOneWidget);
    });

    testWidgets('grant direct submit calls server and shows success',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': 100},
          ],
          'total': 1,
        }),
        'POST /admin/coupon/user-coupon/grant': '',
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'grant'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coupon-grant-direct')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('coupon-grant-direct-openid')),
        'oX_2',
      );
      await tester.tap(find.byKey(const Key('coupon-grant-direct-submit')));
      await tester.pumpAndSettle();

      expect(find.text('定向发券成功'), findsOneWidget);
    });

    testWidgets('user-coupons void row calls server and shows saved',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {'id': 5, 'coupon_name': '满50减10', 'status': 1, 'stock': -1},
          ],
          'total': 1,
        }),
        'GET /admin/coupon/user-coupon/list': jsonEncode({
          'list': [
            {
              'id': 33,
              'user_openid': 'oX_2',
              'coupon_name': '满50减10',
              'status': 0,
              'get_time': '2026-08-02 10:00:00',
            },
          ],
          'total': 1,
        }),
        'POST /admin/coupon/user-coupon/void': '',
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'user-coupons'),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('coupon-user-coupon-void-33')),
      );
      await tester.tap(find.byKey(const Key('coupon-user-coupon-void-33')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      expect(find.text('用户券已作废'), findsOneWidget);
    });

    testWidgets('coupons without client shows connection error state',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsCouponPage(
              repository: _FakeSettingsRepository(),
              client: null,
              section: const SettingsSectionSpec(
                'coupons',
                'section',
                Icons.confirmation_number_outlined,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 无接口客户端：整页错误态，不回退原型占位页。
      expect(find.textContaining('接口未连接'), findsOneWidget);
      expect(find.byType(SettingsErrorState), findsOneWidget);
    });
  });
}
