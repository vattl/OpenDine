import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/app_state.dart';
import 'package:admin_panel_flutter/src/core/shop_summary.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/auth_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/domain/cashier_bill.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/domain/cashier_shift.dart';
import 'package:admin_panel_flutter/src/features/users/presentation/employee_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('Employee Management & Accountability Model Tests', () {
    test('LoginSession parses full employee identity and formats badges', () {
      final json = {
        'adminId': 10,
        'workNo': 'EMP1001',
        'realName': '张晓明',
        'jobTitle': '店长',
        'displayName': '张晓明',
        'userName': 'zhangxm',
        'token': 'test-token',
        'scope': 'SHOP',
        'permissions': ['admin:manage'],
        'shops': [
          {'id': 1, 'code': 'S001', 'name': '老肥烧烤总店'},
        ],
      };

      final session = LoginSession.fromLoginData(json);
      expect(session.adminId, 10);
      expect(session.workNo, 'EMP1001');
      expect(session.realName, '张晓明');
      expect(session.jobTitle, '店长');
      expect(session.displayName, '张晓明');
      expect(session.badgeText, '张晓明 [店长]');
      expect(session.fullIdentityText, '张晓明 (EMP1001) · 店长');
    });

    test('LoginSession backward compatible fallback when workNo/realName absent', () {
      final json = {
        'adminId': 2,
        'username': 'legacy_cashier',
        'token': 'legacy-token',
      };

      final session = LoginSession.fromLoginData(json);
      expect(session.adminId, 2);
      expect(session.workNo, '');
      expect(session.realName, '');
      expect(session.jobTitle, '');
      expect(session.displayName, 'legacy_cashier');
      expect(session.badgeText, 'legacy_cashier');
      expect(session.fullIdentityText, 'legacy_cashier · 员工');
    });

    test('CashierIdentity parses employee attributes and generates fullIdentityText', () {
      final identity = CashierIdentity.fromJson({
        'id': 15,
        'work_no': 'EMP1008',
        'real_name': '李芳',
        'job_title': '领班收银',
        'display_name': '李芳',
      });

      expect(identity.workNo, 'EMP1008');
      expect(identity.realName, '李芳');
      expect(identity.jobTitle, '领班收银');
      expect(identity.fullIdentityText, '李芳 (EMP1008 · 领班收银)');
    });

    test('CommercialZReport parses operator and reviewer names with fallback', () {
      final report = CommercialZReport.fromJson({
        'report_type': 'Z_REPORT',
        'is_closed': true,
        'shop_id': 1,
        'shop_name': '老肥烧烤总店',
        'business_day': '2026-10-04',
        'operator_name': '张晓明',
        'operator_work_no': 'EMP1001',
        'operator_job_title': '店长',
        'reviewer_name': '王强',
        'reviewer_job_title': '财务主管',
        'sales_summary': {
          'total_sales': 24580.0,
          'discount_amount': 1460.0,
          'refund_amount': 0.0,
          'net_sales': 23120.0,
          'order_count': 120,
        },
      });

      expect(report.operatorName, '张晓明');
      expect(report.operatorWorkNo, 'EMP1001');
      expect(report.operatorJobTitle, '店长');
      expect(report.reviewerName, '王强');
      expect(report.reviewerJobTitle, '财务主管');
    });

    test('CashierCashEvent parses operator real identity', () {
      final event = CashierCashEvent.fromJson({
        'event_id': 101,
        'type': 'PAY_IN',
        'amount_fen': 50000,
        'operator_name': '李芳',
        'work_no': 'EMP1008',
        'job_title': '领班收银',
      });

      expect(event.operatorName, '李芳');
      expect(event.operatorWorkNo, 'EMP1008');
      expect(event.operatorJobTitle, '领班收银');
    });

    test('CashierBill parses cashierName with display_name / real_name fallback', () {
      final bill = CashierBill.fromJson({
        'id': 'BILL-001',
        'bill_no': 'B20261004001',
        'display_name': '张晓明',
        'status': 'PAID',
        'total_amount': 188.0,
        'paid_amount': 188.0,
      });

      expect(bill.cashierName, '张晓明');
    });
  });

  group('EmployeeListView Widget Tests', () {
    late FakeHttpTransport transport;
    late AdminApiClient client;
    late AppState appState;

    setUp(() {
      transport = FakeHttpTransport({
        'GET /admin/administrator/list': jsonEncode({
          'code': 0,
          'data': {
            'list': [
              {
                'id': 10,
                'workNo': 'EMP1001',
                'realName': '张晓明',
                'jobTitle': '店长',
                'displayName': '张晓明',
                'userName': 'zhangxm',
                'roleIds': [1],
                'roles': [
                  {'id': 1, 'role_code': 'store_manager', 'role_name': '门店主管'},
                ],
                'scope': 'SHOP',
                'shopIds': [1],
                'shops': [
                  {'id': 1, 'code': 'S001', 'name': '老肥烧烤总店'},
                ],
              },
              {
                'id': 11,
                'workNo': 'EMP1008',
                'realName': '李芳',
                'jobTitle': '收银员',
                'displayName': '李芳',
                'userName': 'lifang',
                'roleIds': [2],
                'roles': [
                  {'id': 2, 'role_code': 'cashier', 'role_name': '前厅收银'},
                ],
                'scope': 'SHOP',
                'shopIds': [1],
                'shops': [
                  {'id': 1, 'code': 'S001', 'name': '老肥烧烤总店'},
                ],
              },
            ],
            'total': 2,
            'allRoles': [
              {'id': 1, 'role_code': 'store_manager', 'role_name': '门店主管'},
              {'id': 2, 'role_code': 'cashier', 'role_name': '前厅收银'},
            ],
          },
        }),
      });

      client = AdminApiClient(
        baseUrl: 'http://test',
        transport: transport,
        token: 'test-token',
        shopId: 1,
      );

      appState = AppState();
      appState.shops = [
        const ShopSummary(id: 1, code: 'S001', name: '老肥烧烤总店'),
      ];
      appState.currentShopId = 1;
    });

    testWidgets('renders employee table, searches, and opens create dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        MaterialApp(
          home: EmployeeListView(
            appState: appState,
            client: client,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 验证标题与新建按钮
      expect(find.text('员工管理与责任人档案'), findsOneWidget);
      expect(find.byKey(const Key('btn-create-employee')), findsOneWidget);

      // 验证表格内容
      expect(find.text('EMP1001'), findsOneWidget);
      expect(find.text('张晓明'), findsOneWidget);
      expect(find.text('店长'), findsOneWidget);
      expect(find.text('zhangxm'), findsOneWidget);
      expect(find.text('门店主管'), findsOneWidget);

      expect(find.text('EMP1008'), findsOneWidget);
      expect(find.text('李芳'), findsOneWidget);
      expect(find.text('收银员'), findsOneWidget);

      // 搜索筛选：搜索 "李芳"
      await tester.enterText(find.byKey(const Key('employee-search-input')), '李芳');
      await tester.tap(find.byKey(const Key('btn-employee-search')));
      await tester.pumpAndSettle();

      expect(find.text('EMP1008'), findsOneWidget);
      expect(find.text('EMP1001'), findsNothing);

      // 重置筛选
      await tester.tap(find.byKey(const Key('btn-employee-reset')));
      await tester.pumpAndSettle();

      expect(find.text('EMP1001'), findsOneWidget);
      expect(find.text('EMP1008'), findsOneWidget);

      // 点击新建员工账号
      await tester.tap(find.byKey(const Key('btn-create-employee')));
      await tester.pumpAndSettle();

      // 验证弹窗与各必填项
      expect(find.text('新建员工档案'), findsOneWidget);
      expect(find.byKey(const Key('input-work-no')), findsOneWidget);
      expect(find.byKey(const Key('input-real-name')), findsOneWidget);
      expect(find.byKey(const Key('input-job-title')), findsOneWidget);
      expect(find.byKey(const Key('input-user-name')), findsOneWidget);
      expect(find.byKey(const Key('input-password')), findsOneWidget);

      // 测试工号校验：非法字符校验
      await tester.enterText(find.byKey(const Key('input-work-no')), 'EMP 123#');
      await tester.enterText(find.byKey(const Key('input-real-name')), '王大拿');
      await tester.enterText(find.byKey(const Key('input-user-name')), 'wangdn');
      await tester.enterText(find.byKey(const Key('input-password')), '123456');
      await tester.tap(find.byKey(const Key('btn-submit-employee-form')));
      await tester.pumpAndSettle();

      expect(find.text('工号仅支持字母、数字、下划线及连字符'), findsOneWidget);

      // 取消弹窗
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('新建员工档案'), findsNothing);
    });
  });
}
