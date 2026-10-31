import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/auth/data/access_approval_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/data/cashier_bill_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/data/real_cashier_bill_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/domain/cashier_bill.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/presentation/cashier_bill_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/data/cashier_member_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/domain/cashier_member.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/receipt_preview_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

/// 审批中心测试桩：authorize 直接签发固定令牌，供敏感操作流程断言。
class _FakeAccessApprovalRepository implements AccessApprovalRepository {
  _FakeAccessApprovalRepository()
    : client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: FakeHttpTransport(const {}),
        token: 'fake-token',
      );

  @override
  final AdminApiClient client;

  String? lastAuthorizerAccount;
  String? lastCredential;

  @override
  Future<CashierApprovalGrant> authorize({
    required String permission,
    String? bizType,
    String? bizId,
    double? amount,
    String? reason,
    required String authorizerAccount,
    required String credential,
    String authMethod = 'PASSWORD',
    String? requestId,
    String? terminalId,
  }) async {
    lastAuthorizerAccount = authorizerAccount;
    lastCredential = credential;
    return CashierApprovalGrant(
      approvalNo: 'APP-2026-TEST',
      approvalToken: 'fake-approval-token',
      permission: permission,
      operatorId: 1,
      authorizerId: 9,
      authorizerName: authorizerAccount,
      shopId: 1,
      expireSeconds: 120,
    );
  }

  @override
  Future<AccessApprovalPage> listApprovals({
    int page = 1,
    int pageSize = 20,
    String? status,
    String? bizType,
    int? shopId,
  }) async {
    return const AccessApprovalPage();
  }

  @override
  Future<AccessApprovalRecord?> loadApprovalDetail(int id) async => null;

  @override
  Future<List<RecentAuthor>> loadRecentAuthors({int limit = 10}) async =>
      const [];

  @override
  Future<CashierQrApprovalRequest> createQrApproval({
    required String permission,
    String? bizType,
    String? bizId,
    double? amount,
    String? reason,
    String? requestId,
    String? terminalId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierQrApprovalStatus> pollQrApprovalStatus(
    String approvalCode,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierQrApprovalDetails> loadQrApprovalDetails(
    String approvalCode,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierQrApprovalConfirmResult> confirmQrApproval({
    required String approvalCode,
    required String action,
    String? rejectReason,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierAccessEvaluation> evaluate({
    required int userId,
    int? shopId,
    required String permission,
    Map<String, Object?>? context,
  }) async {
    return const CashierAccessEvaluation(
      allow: true,
      approvalRequired: false,
      outcome: AuthorizationOutcome.allow,
    );
  }
}


/// 账单详情操作按钮所需的权限集（测试用）。
const kBillActionPerms = {
  'order:operate:refund',
  'order:operate:reopen',
  'order:operate',
  'cashier:operate',
  'order:view',
  'user:view',
};

void main() {
  group('CashierBill model', () {
    test('safely parses order totals, channels, cashier and line details', () {
      final bill = CashierBill.fromJson({
        'id': '18',
        'order_no': 202607200018,
        'table_number': 8,
        'order_time': '2026-07-20 18:03:04',
        'cashier_id': '7',
        'cashier_name': '小林',
        'transac_status': 'success',
        'sett_amount': '128.50',
        'discount_amount': 8,
        'service_fee': '6.43',
        'refund_amount': '3.00',
        'pay_amount_gift': 2,
        'pay_amount_wechat': '71.93',
        'pay_amount_cash': 50,
        'checkout_cash_tender': '100',
        'checkout_change_amount': 50,
        'checkout_change_channel_label': '微信',
        'list': [
          {
            'id': 1,
            'name': '油边',
            'quantity': '2',
            'unit': '份',
            'unitprice': '24.50',
            'total_price': 49,
            'selectedSpicy': '{"辣度":"微辣"}',
          },
          {
            'id': 2,
            'dish_name': '酸梅汤',
            'count': 1,
            'totalPrice': '12',
            'line_status': 'refunded',
          },
        ],
      });

      expect(bill.id, 18);
      expect(bill.orderNo, '202607200018');
      expect(bill.tableNumber, '8');
      expect(bill.cashierName, '小林');
      expect(bill.status, CashierBillStatus.success);
      expect(bill.itemQuantity, 3);
      expect(bill.payableAmount, closeTo(121.93, .001));
      expect(bill.paidAmount, closeTo(121.93, .001));
      expect(bill.paymentChannels.map((item) => item.label), [
        '微信支付',
        '现金',
        '赠送金',
      ]);
      expect(bill.cashTender, 100);
      expect(bill.changeAmount, 50);
      expect(bill.changeChannelLabel, '微信');
      expect(bill.lines.first.specification, '辣度：微辣');
      expect(bill.lines.last.isRefunded, isTrue);
    });

    test('CashierBillLine parses KDS preparation status and respects refund status', () {
      final linePending = CashierBillLine.fromJson({
        'id': 1,
        'dish_name': '热干面',
        'quantity': 1,
        'total_price': 15,
        'kds_item_status': 0,
        'kds_status_text': '待制作',
        'kds_served_quantity': 0,
      });
      expect(linePending.kdsItemStatus, 0);
      expect(linePending.kdsStatusText, '待制作');
      expect(linePending.kdsServedQuantity, 0);
      expect(linePending.isRefunded, isFalse);

      final lineCooking = CashierBillLine.fromJson({
        'id': 2,
        'dish_name': '牛肉串',
        'quantity': 5,
        'total_price': 25,
        'kds_item_status': 1,
        'kds_status_text': '制作中',
      });
      expect(lineCooking.kdsItemStatus, 1);
      expect(lineCooking.kdsStatusText, '制作中');

      final lineServing = CashierBillLine.fromJson({
        'id': 3,
        'dish_name': '炒青菜',
        'quantity': 1,
        'total_price': 18,
        'kds_item_status': 1,
        'kds_status_text': '待传菜',
      });
      expect(lineServing.kdsStatusText, '待传菜');

      final lineDone = CashierBillLine.fromJson({
        'id': 4,
        'dish_name': '蛋炒饭',
        'quantity': 1,
        'total_price': 16,
        'kds_item_status': 2,
        'kds_status_text': '已完成',
        'kds_served_quantity': 1,
      });
      expect(lineDone.kdsItemStatus, 2);
      expect(lineDone.kdsStatusText, '已完成');

      final lineVoid = CashierBillLine.fromJson({
        'id': 5,
        'dish_name': '啤酒',
        'quantity': 1,
        'total_price': 8,
        'kds_item_status': 3,
        'kds_status_text': '已退菜',
      });
      expect(lineVoid.kdsItemStatus, 3);
      expect(lineVoid.isRefunded, isTrue);
    });

    test('accepts epoch time, numeric status and malformed money', () {
      final bill = CashierBill.fromJson({
        'id': 1,
        'transac_status': 0,
        'order_time': 1784541600000,
        'sett_amount': 'not-money',
        'goods_count': '4',
      });

      expect(bill.status, CashierBillStatus.unsettled);
      expect(bill.orderTime, isNotNull);
      expect(bill.payableAmount, 0);
      expect(bill.itemQuantity, 4);
    });

    test('parses unified payment channel and split fields', () {
      final splitBill = CashierBill.fromJson({
        'id': 2,
        'transac_status': 'success',
        'sett_amount': 88,
        'payment_channel_code': 'online_combined',
        'payment_split': {'wechat': 30, 'alipay': 18, 'cash': 40},
      });
      final singleChannelBill = CashierBill.fromJson({
        'id': 3,
        'transac_status': 'success',
        'sett_amount': 66,
        'paymentChannelCode': 'offline_wechat_qr',
      });

      expect(splitBill.paymentMethod, 'online_combined');
      expect(splitBill.paymentChannels.map((item) => item.label), [
        '微信支付',
        '支付宝',
        '现金',
      ]);
      expect(
        splitBill.paymentChannels.fold<double>(
          0,
          (sum, item) => sum + item.amount,
        ),
        88,
      );
      expect(singleChannelBill.paymentChannels.single.label, '微信收款码');
      expect(singleChannelBill.paymentChannels.single.amount, 66);
    });

    test('parses payment_method: 微信收款码, 支付宝收款码, 现金, 微信支付 accurately', () {
      final billQr = CashierBill.fromJson({
        'id': 11,
        'transac_status': 'success',
        'sett_amount': 98.0,
        'payment_method': '微信收款码',
      });
      final billAliQr = CashierBill.fromJson({
        'id': 12,
        'transac_status': 'success',
        'sett_amount': 150.0,
        'payment_method': '支付宝收款码',
      });
      final billWechat = CashierBill.fromJson({
        'id': 13,
        'transac_status': 'success',
        'sett_amount': 88.0,
        'payment_method': '微信支付',
      });

      expect(billQr.paymentMethod, '微信收款码');
      expect(billQr.paymentChannels.single.label, '微信收款码');
      expect(billQr.paymentChannels.single.amount, 98.0);

      expect(billAliQr.paymentMethod, '支付宝收款码');
      expect(billAliQr.paymentChannels.single.label, '支付宝收款码');
      expect(billAliQr.paymentChannels.single.amount, 150.0);

      expect(billWechat.paymentMethod, '微信支付');
      expect(billWechat.paymentChannels.single.label, '微信支付');
    });

    test('parses dineInOrTakeOut: 打包, 堂食, 外卖 and matches correctly', () {
      final billDineIn = CashierBill.fromJson({
        'id': 101,
        'dineInOrTakeOut': '堂食',
      });
      final billPack = CashierBill.fromJson({
        'id': 102,
        'dineInOrTakeOut': '打包',
      });
      final billTakeout = CashierBill.fromJson({
        'id': 103,
        'dineInOrTakeOut': '外卖',
      });

      expect(billDineIn.orderType, '堂食');
      expect(billPack.orderType, '打包');
      expect(billTakeout.orderType, '外卖');

      expect(CashierOrderType.dineIn.matches(billDineIn.orderType), isTrue);
      expect(CashierOrderType.dineIn.matches(billPack.orderType), isFalse);

      expect(CashierOrderType.pickup.matches(billPack.orderType), isTrue);
      expect(CashierOrderType.pickup.matches('自提'), isTrue);
      expect(CashierOrderType.pickup.matches(billDineIn.orderType), isFalse);

      expect(CashierOrderType.takeout.matches(billTakeout.orderType), isTrue);
      expect(CashierOrderType.takeout.matches(billDineIn.orderType), isFalse);
    });
  });

  group('RealCashierBillRepository', () {
    test(
      'loads today with shop and status through the cashier contract',
      () async {
        final transport = FakeHttpTransport({
          'GET /cashier/order/today': jsonEncode({
            'code': 200,
            'list': [
              {'id': 1, 'transac_status': 'unsettled'},
            ],
          }),
        });
        final repository = RealCashierBillRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 6,
          ),
        );

        final result = await repository.loadBills(
          const CashierBillQuery(status: CashierBillStatus.unsettled),
        );

        expect(result.bills.single.status, CashierBillStatus.unsettled);
        expect(result.total, 1);
        expect(transport.requests.single.method, 'GET');
        expect(transport.requests.single.uri.path, '/cashier/order/today');
        expect(transport.requests.single.uri.queryParameters, {
          'shopId': '6',
          'transac_status': 'unsettled',
        });
        expect(transport.requests.single.headers['X-Shop-Id'], '6');
      },
    );

    test(
      'search sends only documented filters and reads pagination wrapper',
      () async {
        final transport = FakeHttpTransport({
          'GET /cashier/order/search': jsonEncode({
            'code': 200,
            'data': {
              'rows': [
                {'id': 2, 'tableNumber': 'A08', 'transac_status': 'success'},
              ],
              'totalCount': '31',
            },
          }),
        });
        final repository = RealCashierBillRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            shopId: 6,
          ),
        );

        final result = await repository.loadBills(
          CashierBillQuery(
            tableNumber: ' A08 ',
            startTime: DateTime(2026, 7, 20, 10),
            endTime: DateTime(2026, 7, 20, 22, 30),
            cashierId: 9,
            pageNum: 2,
            pageSize: 15,
          ),
        );

        expect(result.total, 31);
        expect(result.bills.single.tableNumber, 'A08');
        expect(transport.requests.single.uri.path, '/cashier/order/search');
        expect(transport.requests.single.uri.queryParameters, {
          'shopId': '6',
          'tableNumber': 'A08',
          'startTime': '2026/07/20',
          'endTime': '2026/07/20',
          'cashierId': '9',
          'pageNum': '2',
          'pageSize': '15',
        });
      },
    );

    test('today search uses the current day window formatted as yyyy/MM/dd', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/order/search': jsonEncode({
          'code': 200,
          'data': {'rows': [], 'totalCount': 0},
        }),
      });
      final repository = RealCashierBillRepository(
        AdminApiClient(baseUrl: 'http://api.test', transport: transport),
      );
      final now = DateTime.now();
      final expectedDate = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

      await repository.loadBills(const CashierBillQuery(tableNumber: 'A08'));

      expect(
        transport.requests.single.uri.queryParameters['startTime'],
        expectedDate,
      );
      expect(
        transport.requests.single.uri.queryParameters['endTime'],
        expectedDate,
      );
    });

    test('detail merges order and common list wrapper', () async {
      final transport = FakeHttpTransport({
        'GET /admin/orderDetail/list': jsonEncode({
          'code': 200,
          'data': {
            'order': {
              'id': 3,
              'table_number': '12',
              'transac_status': 'success',
              'sett_amount': 36,
              'pay_amount_alipay': 36,
            },
            'orderDetailList': [
              {'id': 30, 'name': '牛肉串', 'quantity': 3, 'total_price': 36},
            ],
          },
        }),
      });
      final repository = RealCashierBillRepository(
        AdminApiClient(baseUrl: 'http://api.test', transport: transport),
      );

      final detail = await repository.loadBillDetail(
        CashierBill.fromJson({'id': 3}),
      );

      expect(detail.tableNumber, '12');
      expect(detail.lines.single.name, '牛肉串');
      expect(detail.paymentChannels.single.label, '支付宝');
      expect(transport.requests.single.uri.queryParameters, {'id': '3'});
    });

    test('uncheckout and kitchen reprint use cashier contracts', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/unCheckout': jsonEncode({'code': 200, 'data': {}}),
        'POST /cashier/print/dispatch': jsonEncode({'code': 200, 'data': {}}),
      });
      final repository = RealCashierBillRepository(
        AdminApiClient(baseUrl: 'http://api.test', transport: transport),
      );

      await repository.unCheckout(
        orderNo: 'ORD202607260001',
        reason: ' 支付方式选错 ',
      );
      await repository.printKitchen(
        orderNo: 'ORD202607260001',
        categoryIds: const [
          'a20260320122903000000010',
          'a20260330044440000000031',
        ],
      );

      final uncheckout = transport.requests.first;
      expect(uncheckout.uri.path, '/cashier/order/unCheckout');
      expect(jsonDecode(uncheckout.body!), {
        'order_no': 'ORD202607260001',
        'reason': '支付方式选错',
      });
      final print = transport.requests.last;
      expect(print.uri.path, '/cashier/print/dispatch');
      expect(jsonDecode(print.body!), {
        'order_no': 'ORD202607260001',
        'scenario': 'kitchen',
        'is_reprint': true,
        'cid_list': ['a20260320122903000000010', 'a20260330044440000000031'],
      });
    });

    test('deleteBill calls order delete endpoint', () async {
      final transport = FakeHttpTransport({
        'DELETE /order/delete/9': jsonEncode({'code': 200, 'msg': 'success'}),
      });
      final repository = RealCashierBillRepository(
        AdminApiClient(baseUrl: 'http://api.test', transport: transport),
      );

      await repository.deleteBill(
        CashierBill.fromJson({'id': 9, 'order_no': 'ORD202608180009'}),
        account: 'EMP1001',
        password: 'secretPassword',
      );

      final request = transport.requests.single;
      expect(request.method, 'DELETE');
      expect(request.uri.path, '/order/delete/9');
    });

    test('deleteBill with authorization credentials sends body', () async {
      final transport = FakeHttpTransport({
        'DELETE /order/delete/9': jsonEncode({'code': 200, 'msg': 'success'}),
      });
      final repository = RealCashierBillRepository(
        AdminApiClient(baseUrl: 'http://api.test', transport: transport),
      );

      await repository.deleteBill(
        CashierBill.fromJson({'id': 9, 'order_no': 'ORD202608180009'}),
        account: 'EMP1001',
        password: 'secretPassword',
      );

      final request = transport.requests.single;
      expect(request.method, 'DELETE');
      expect(request.uri.path, '/order/delete/9');
      final body = jsonDecode(request.body!) as Map<String, dynamic>;
      expect(body['authorization'], {
        'account': 'EMP1001',
        'password': 'secretPassword',
      });
    });

    test('verifyPassword posts to adminLoginEndpoint', () async {
      final transport = FakeHttpTransport({
        'POST /adminLogin': jsonEncode({'code': 200, 'msg': 'success'}),
      });
      final repository = RealCashierBillRepository(
        AdminApiClient(baseUrl: 'http://api.test', transport: transport),
      );

      await repository.verifyPassword(username: 'EMP1001', password: 'pw');
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/adminLogin');
      final body = jsonDecode(request.body!) as Map<String, dynamic>;
      expect(body['workNo'], 'EMP1001');
      expect(body['password'], 'pw');
    });

    test(
      'loadBillDetail resolves openid to member phone and profile',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/orderDetail/list': jsonEncode({
            'code': 200,
            'data': {
              'order': {
                'id': 5,
                'order_no': 'ORD202609010005',
                'openid': 'wx_user_openid_123',
                'transaction_id': '4200002130202609010005',
                'transac_status': 'success',
                'sett_amount': 98.0,
              },
              'list': [],
            },
          }),
          'POST /admin/order/getUserInfo': jsonEncode({
            'code': 200,
            'data': {
              'rows': [
                {
                  'id': 66,
                  'name': '老王',
                  'phone': '13812345678',
                  'balance': 520.0,
                },
              ],
              'total': 1,
            },
          }),
        });
        final repository = RealCashierBillRepository(
          AdminApiClient(baseUrl: 'http://api.test', transport: transport),
        );

        final detail = await repository.loadBillDetail(
          CashierBill.fromJson({'id': 5}),
        );

        expect(detail.transactionId, '4200002130202609010005');
        expect(detail.openid, 'wx_user_openid_123');
        expect(detail.memberPhone, '13812345678');
        expect(detail.memberName, '老王');
        expect(detail.memberBalance, 520.0);
      },
    );

    test('refundOrder posts to admin refund endpoint', () async {
      final transport = FakeHttpTransport({
        'POST /admin/order/refund': jsonEncode({
          'code': 0,
          'order_no': 'ORD202609010005',
          'refund_amount': '50.00',
        }),
      });
      final repository = RealCashierBillRepository(
        AdminApiClient(baseUrl: 'http://api.test', transport: transport),
      );

      await repository.refundOrder(
        orderNo: 'ORD202609010005',
        transactionId: '4200002130202609010005',
        refundAmount: 50.0,
        reason: '顾客协商退款',
        account: 'EMP1001',
        password: 'secretPassword',
      );

      final request = transport.requests.single;
      expect(request.uri.path, '/admin/order/refund');
      expect(jsonDecode(request.body!), {
        'orderNo': 'ORD202609010005',
        'transaction_id': '4200002130202609010005',
        'refundAmount': '50.00',
        'reason': '顾客协商退款',
        'authorization': {'account': 'EMP1001', 'password': 'secretPassword'},
      });
    });
  });

  group('CashierBillPage', () {
    testWidgets('renders top filter bar and table rows matching 1:1 design', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _FakeBillRepository([
        CashierBill.fromJson({
          'id': 1,
          'order_no': 'A00012122',
          'table_number': '40',
          'transac_status': 'success',
          'sett_amount': 400.0,
          'pay_amount_wechat': 400.0,
          'order_type': '堂食',
        }),
        CashierBill.fromJson({
          'id': 2,
          'order_no': 'A00012125',
          'table_number': '08',
          'transac_status': 'unsettled',
          'sett_amount': 520.0,
          'order_type': '外卖',
        }),
      ]);

      await tester.pumpWidget(
        MaterialApp(home: CashierBillPage(
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        )),
      );
      await tester.pumpAndSettle();

      // 验证顶部筛选条
      expect(find.text('全部'), findsNWidgets(2)); // 就餐方式全部 + 结账状态全部
      expect(find.text('堂食'), findsNWidgets(2)); // 筛选条堂食 + 表格行堂食
      expect(find.text('外卖'), findsNWidgets(2)); // 筛选条外卖 + 表格行外卖
      expect(find.text('自提'), findsOneWidget);
      expect(find.text('未结账'), findsNWidgets(2)); // 筛选条未结账 + 表格行未结账
      expect(find.text('已结账'), findsOneWidget);
      expect(find.text('已取消'), findsOneWidget);
      expect(find.text('搜索'), findsOneWidget);
      expect(find.byKey(const Key('cashier-bill-search')), findsOneWidget);

      // 验证深色表头
      expect(find.text('账单号'), findsOneWidget);
      expect(find.text('桌台'), findsOneWidget);
      expect(find.text('就餐方式'), findsOneWidget);
      expect(find.text('金额'), findsOneWidget);
      expect(find.text('支付方式'), findsOneWidget);
      expect(find.text('时间'), findsOneWidget);
      expect(find.text('操作'), findsOneWidget);

      // 验证数据行
      expect(find.text('A00012122'), findsOneWidget);
      expect(find.text('40号'), findsOneWidget);
      expect(find.text('¥ 400.00'), findsOneWidget);
      expect(find.text('微信支付'), findsOneWidget);

      expect(find.text('A00012125'), findsOneWidget);
      expect(find.text('08号'), findsOneWidget);
      expect(find.text('¥ 520.00'), findsOneWidget);

      expect(find.text('详情'), findsNWidgets(2));
    });

    testWidgets('detail action buttons hide entirely when permission missing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bill = CashierBill.fromJson({
        'id': 40,
        'order_no': 'ORD202607260004',
        'table_number': '8',
        'transac_status': 'settled',
        'actual_amount': 92.0,
        'member_name': '张三',
      });
      final repository = _FakeBillRepository([bill]);

      await tester.pumpWidget(
        // 不传 permissions：默认空集，操作按钮全部隐藏
        MaterialApp(home: CashierBillPage(
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        )),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      expect(find.text('账单详情'), findsOneWidget);
      expect(find.byKey(const Key('bill-detail-refund-button')), findsNothing);
      expect(
        find.byKey(const Key('bill-detail-print-receipt-button')),
        findsNothing,
      );
      expect(find.text('打印厨房票'), findsNothing);
      expect(find.text('删除订单'), findsNothing);
    });

    testWidgets(
      'shows 3-column detail view matching 1:1 design and performs actions',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final bill = CashierBill.fromJson({
          'id': 4,
          'order_no': 'ORD202607260004',
          'table_number': '20',
          'transac_status': 'success',
          'sett_amount': 100,
          'discount_amount': 15,
          'pay_amount_wechat': 92,
          'list': [
            {
              'id': 40,
              'name': '招牌油边王',
              'quantity': 2,
              'total_price': 56,
              'selectedSpicy': '大份 · 微辣',
            },
            {'id': 41, 'name': '海鲜炒饭', 'quantity': 1, 'total_price': 28},
            {
              'id': 42,
              'name': '柠檬茶',
              'quantity': 2,
              'total_price': 16,
              'selectedSpicy': '少冰',
            },
          ],
          'remark': '少辣，打包一份柠檬茶，12:45 前来取',
          'member_name': '张三',
          'member_phone': '13888888888',
          'member_balance': 256.0,
        });
        final repository = _FakeBillRepository([bill]);

        await tester.pumpWidget(
          MaterialApp(
            home: CashierBillPage(
              repository: repository,
                            approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
              isSuperAdmin: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('详情'));
        await tester.pumpAndSettle();

        // 验证标题与顶部单号
        expect(find.text('账单详情'), findsOneWidget);
        expect(find.text('返回'), findsOneWidget);
        expect(find.text('订单号 ORD202607260004'), findsOneWidget);

        // 左栏与右侧详情
        expect(find.text('已结账'), findsWidgets);
        expect(find.text('堂食'), findsWidgets);
        expect(find.text('订单明细'), findsOneWidget);
        expect(find.text('招牌油边王'), findsOneWidget);
        expect(find.text('海鲜炒饭'), findsOneWidget);
        expect(find.text('柠檬茶'), findsOneWidget);
        expect(find.textContaining('少辣，打包一份柠檬茶'), findsOneWidget);
        expect(find.text('金额明细'), findsOneWidget);
        expect(find.text('实收'), findsOneWidget);

        // 中栏
        expect(find.text('订单信息'), findsOneWidget);
        expect(find.text('消费统计'), findsOneWidget);
        expect(find.text('累计消费'), findsOneWidget);
        expect(find.text('到店频次'), findsOneWidget);
        expect(find.text('平均客单'), findsOneWidget);
        expect(find.text('口味偏好'), findsOneWidget);
        expect(find.text('历史订单'), findsOneWidget);

        // 右栏
        expect(find.text('用户信息'), findsOneWidget);
        expect(find.text('张三'), findsOneWidget);
        expect(find.text('138****8888'), findsOneWidget);
        expect(find.text('¥256.00'), findsOneWidget);
        expect(find.text('退款'), findsOneWidget);
        expect(find.text('打印结账单'), findsOneWidget);
        expect(find.text('打印厨房票'), findsNothing);
        expect(find.text('删除订单'), findsOneWidget);

        // 测试返回主列表
        await tester.tap(find.text('返回'));
        await tester.pumpAndSettle();
        expect(find.text('账单号'), findsOneWidget);
      },
    );

    testWidgets('未结账账单详情只显示打印预结单入口', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bill = CashierBill.fromJson({
        'id': 7,
        'order_no': 'ORD202607260007',
        'table_number': '21',
        'transac_status': 'unsettled',
        'sett_amount': 88,
        'list': [
          {'id': 50, 'name': '烤生蚝', 'quantity': 1, 'total_price': 88},
        ],
      });
      final repository = _FakeBillRepository([bill]);

      await tester.pumpWidget(
        MaterialApp(
          home: CashierBillPage(
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
            permissions: kBillActionPerms,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      // 未结账 → 只显示「打印预结单」，不显示结账单/厨房票
      expect(find.text('未结账'), findsWidgets);
      expect(find.text('打印预结单'), findsOneWidget);
      expect(find.text('打印结账单'), findsNothing);
      expect(find.text('打印厨房票'), findsNothing);
    });

    testWidgets('delete bill confirms and deletes through repository', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bill = CashierBill.fromJson({
        'id': 5,
        'order_no': 'ORD202608180005',
        'table_number': '15',
        'transac_status': 'cancelled',
        'sett_amount': 20,
      });
      final repository = _FakeBillRepository([bill]);

      await tester.pumpWidget(
        MaterialApp(
          home: CashierBillPage(
            repository: repository,
                        approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
            isSuperAdmin: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击详情进入详情页
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      // 触发删除订单
      expect(find.text('删除订单'), findsOneWidget);
      await tester.tap(find.text('删除订单'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('approval-account')),
        'manager',
      );
      await tester.enterText(
        find.byKey(const Key('approval-credential')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pumpAndSettle();

      expect(repository.deletedBills.map((b) => b.id), contains(5));
      expect(
        repository.deletedBillCalls.single.approvalToken,
        'fake-approval-token',
      );
    });

    testWidgets('delete bill auth cancel does not delete bill', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bill = CashierBill.fromJson({
        'id': 6,
        'order_no': 'ORD202608180006',
        'table_number': '16',
        'transac_status': 'cancelled',
        'sett_amount': 30,
      });
      final repository = _FakeBillRepository([bill]);

      await tester.pumpWidget(
        MaterialApp(
          home: CashierBillPage(
            repository: repository,
                        approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
            isSuperAdmin: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除订单'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('approval-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cashier-approval-dialog')), findsNothing);
      expect(repository.deletedBills, isEmpty);
    });

    testWidgets('delete bill auth shows error on empty password', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bill = CashierBill.fromJson({
        'id': 7,
        'order_no': 'ORD202608180007',
        'table_number': '17',
        'transac_status': 'cancelled',
        'sett_amount': 40,
      });
      final repository = _FakeBillRepository([bill]);

      await tester.pumpWidget(
        MaterialApp(
          home: CashierBillPage(
            repository: repository,
                        approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
            isSuperAdmin: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除订单'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
      // 直接点击授权（账号与凭证为空）
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pumpAndSettle();

      expect(find.text('请填写授权员工账号与密码'), findsOneWidget);
      expect(repository.deletedBills, isEmpty);
    });

    testWidgets('refund button is disabled when transactionId is empty', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeBillRepository([
        CashierBill.fromJson({
          'id': 7,
          'order_no': '202608310007',
          'table_number': '06',
          'transac_status': 'success',
          'sett_amount': 158.0,
          'transaction_id': '', // 空 transaction_id
        }),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierBillPage(
              repository: repository,
                            approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      // 退款按钮为不可点击状态
      final refundButtonFinder = find.byKey(
        const Key('bill-detail-refund-button'),
      );
      expect(refundButtonFinder, findsOneWidget);
      final outlinedBtn = tester.widget<OutlinedButton>(
        find.descendant(
          of: refundButtonFinder,
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(outlinedBtn.onPressed, isNull);
    });

    testWidgets(
      'refund dialog inputs refundable amount and calls refundOrder when transactionId is present',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repository = _FakeBillRepository([
          CashierBill.fromJson({
            'id': 8,
            'order_no': '202608310008',
            'table_number': '08',
            'transac_status': 'success',
            'sett_amount': 200.0,
            'pay_amount_wechat': 200.0,
            'transaction_id': '4200002130202609010008',
          }),
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CashierBillPage(
                repository: repository,
                                approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 打开详情
        await tester.tap(find.text('详情'));
        await tester.pumpAndSettle();

        // 点击退款按钮打开退款弹窗
        final refundButtonFinder = find.byKey(
          const Key('bill-detail-refund-button'),
        );
        expect(refundButtonFinder, findsOneWidget);
        await tester.tap(refundButtonFinder);
        await tester.pumpAndSettle();

        // 验证弹窗渲染订单号与 transaction_id
        expect(find.text('订单退款'), findsOneWidget);
        expect(find.text('4200002130202609010008'), findsOneWidget);
        expect(
          find.byKey(const Key('bill-refund-amount-input')),
          findsOneWidget,
        );

        // 输入退款金额与退款原因
        await tester.enterText(
          find.byKey(const Key('bill-refund-amount-input')),
          '88.50',
        );
        await tester.enterText(
          find.byKey(const Key('bill-refund-reason-input')),
          '菜品退款',
        );

        // 点击确定退款
        await tester.tap(find.byKey(const Key('bill-refund-confirm-button')));
        await tester.pumpAndSettle();

        // 现场授权弹窗
        expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('approval-account')),
          'manager',
        );
        await tester.enterText(
          find.byKey(const Key('approval-credential')),
          'pass123',
        );
        await tester.tap(find.byKey(const Key('approval-submit')));
        await tester.pumpAndSettle();

        expect(repository.refundedOrders.length, 1);
        final refundRecord = repository.refundedOrders.single;
        expect(refundRecord.orderNo, '202608310008');
        expect(refundRecord.transactionId, '4200002130202609010008');
        expect(refundRecord.amount, 88.50);
        expect(refundRecord.reason, '菜品退款');
        expect(refundRecord.approvalToken, 'fake-approval-token');

        // 退款成功后弹出成功提示
        expect(find.text('退款成功'), findsOneWidget);
      },
    );

    testWidgets('cash order refund routes to manualRefund endpoint', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeBillRepository([
        CashierBill.fromJson({
          'id': 88,
          'order_no': '202609010088',
          'table_number': '08',
          'transac_status': 'success',
          'sett_amount': 66.0,
          'pay_amount_cash': 66.0,
        }),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierBillPage(
              repository: repository,
                            approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 打开详情
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      // 点击退款按钮打开退款弹窗
      final refundButtonFinder = find.byKey(
        const Key('bill-detail-refund-button'),
      );
      expect(refundButtonFinder, findsOneWidget);
      await tester.tap(refundButtonFinder);
      await tester.pumpAndSettle();

      // 输入退款金额与退款原因
      await tester.enterText(
        find.byKey(const Key('bill-refund-amount-input')),
        '20.00',
      );
      await tester.enterText(
        find.byKey(const Key('bill-refund-reason-input')),
        '现金单人工退款',
      );

      // 点击确定退款
      await tester.tap(find.byKey(const Key('bill-refund-confirm-button')));
      await tester.pumpAndSettle();

      // 现场授权弹窗
      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('approval-account')),
        'manager',
      );
      await tester.enterText(
        find.byKey(const Key('approval-credential')),
        'pass123',
      );
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pumpAndSettle();

      // 现金单应走 manualRefund 而非在线退款
      expect(repository.refundedOrders.length, 0);
      expect(repository.manualRefunds.length, 1);
      final manualRecord = repository.manualRefunds.single;
      expect(manualRecord.orderNo, '202609010088');
      expect(manualRecord.amount, 20.00);
      expect(manualRecord.reason, '现金单人工退款');
      expect(manualRecord.approvalToken, 'fake-approval-token');

      // 退款成功后弹出成功提示
      expect(find.text('退款成功'), findsOneWidget);
    });

    testWidgets('refund button disabled when no refundable amount remains', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeBillRepository([
        CashierBill.fromJson({
          'id': 9,
          'order_no': '202608310009',
          'table_number': '09',
          'transac_status': 'success',
          'sett_amount': 100.0,
          // 已全额退款，无可退金额
          'refund_amount': 100.0,
          'pay_amount_wechat': 100.0,
          'transaction_id': '4200002130202609010009',
        }),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierBillPage(
              repository: repository,
                            approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      // 有交易单号但可退金额为 0：退款按钮仍不可点击
      final refundButtonFinder = find.byKey(
        const Key('bill-detail-refund-button'),
      );
      expect(refundButtonFinder, findsOneWidget);
      final outlinedBtn = tester.widget<OutlinedButton>(
        find.descendant(
          of: refundButtonFinder,
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(outlinedBtn.onPressed, isNull);
    });

    testWidgets('filters by order type, status, and keywords', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bill1 = CashierBill.fromJson({
        'id': 1,
        'order_no': 'A000101',
        'table_number': '10',
        'transac_status': 'success',
        'sett_amount': 100.0,
        'pay_amount_wechat': 100.0,
        'order_type': '堂食',
      });
      final bill2 = CashierBill.fromJson({
        'id': 2,
        'order_no': 'A000102',
        'table_number': '20',
        'transac_status': 'unsettled',
        'sett_amount': 200.0,
        'order_type': '外卖',
      });
      final repository = _FakeBillRepository([bill1, bill2]);

      await tester.pumpWidget(
        MaterialApp(
          home: CashierBillPage(
            repository: repository,
                        approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证筛选条组件渲染
      expect(find.text('全部'), findsNWidgets(2));
      expect(find.text('堂食'), findsNWidgets(2)); // 筛选条堂食 + 表格行堂食
      expect(find.text('外卖'), findsNWidgets(2)); // 筛选条外卖 + 表格行外卖
      expect(find.text('自提'), findsOneWidget);
      expect(find.text('已结账'), findsOneWidget);
      expect(find.text('未结账'), findsNWidgets(2)); // 筛选条未结账 + 表格行未结账
      expect(find.text('搜索'), findsOneWidget);

      // 点击「外卖」就餐方式
      await tester.tap(find.text('外卖').first);
      await tester.pumpAndSettle();
      expect(repository.lastQuery?.orderType, CashierOrderType.takeout);
      expect(find.text('A000102'), findsOneWidget);
      expect(find.text('A000101'), findsNothing);

      // 输入关键字搜索
      await tester.enterText(find.byType(TextField).first, '10');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      expect(repository.lastQuery?.keyword, '10');
    });

    testWidgets(
      'loads and renders real member profile and consumption history from memberRepository',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final bill = CashierBill.fromJson({
          'id': 101,
          'order_no': 'ORD202609010001',
          'table_number': '12',
          'transac_status': 'success',
          'sett_amount': 258.0,
          'discount_amount': 28.0,
          'pay_amount_wechat': 230.0,
          'member_phone': '13912345678',
          'list': [
            {'id': 1, 'name': '炭烤牛舌', 'quantity': 2, 'total_price': 136.0},
          ],
        });

        final memberRepo = _FakeMemberRepository(
          profiles: {
            '13912345678': const CashierMemberProfile(
              member: CashierMember(
                id: 88,
                name: '李老板',
                phone: '13912345678',
                balance: 1580.0,
              ),
              orderCount: 16,
              totalAmount: 4920.0,
              avgOrderValue: 307.5,
              tags: const ['特辣', '免葱', '常客'],
            ),
          },
          consumption: {
            '13912345678': [
              const MemberConsumptionRecord(
                id: 99,
                orderNo: 'ORD202608250002',
                amount: 320.0,
                paidAt: '2026-08-25 20:15',
                tableNumber: '06',
                paymentMethod: 'wechat',
              ),
            ],
          },
        );

        final repository = _FakeBillRepository([bill]);

        await tester.pumpWidget(
          MaterialApp(
            home: CashierBillPage(
              repository: repository,
                            approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
              memberRepository: memberRepo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('详情'));
        await tester.pumpAndSettle();

        // 验证真实会员名称与手机号、余额
        expect(find.text('李老板'), findsOneWidget);
        expect(find.text('139****5678'), findsOneWidget);
        expect(find.text('¥1580.00'), findsOneWidget);

        // 验证真实会员统计数据
        expect(find.text('¥4920.00'), findsOneWidget);
        expect(find.text('16 次'), findsOneWidget);
        expect(find.text('¥307.50'), findsOneWidget);
        expect(find.text('2026-08-25'), findsOneWidget);

        // 验证真实偏好标签
        expect(find.text('特辣'), findsOneWidget);
        expect(find.text('免葱'), findsOneWidget);
        expect(find.text('常客'), findsOneWidget);

        // 验证真实历史订单
        expect(find.text('订单号 ORD202608250002 · 06号桌'), findsOneWidget);
        expect(find.text('¥320.00'), findsOneWidget);
      },
    );

    testWidgets(
      'renders clean non-member / walk-in state when no member is bound',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final bill = CashierBill.fromJson({
          'id': 102,
          'order_no': 'ORD202609010002',
          'table_number': '02',
          'transac_status': 'unsettled',
          'sett_amount': 88.0,
          'list': [],
        });

        final repository = _FakeBillRepository([bill]);

        await tester.pumpWidget(
          MaterialApp(
            home: CashierBillPage(
              repository: repository,
                            approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('详情'));
        await tester.pumpAndSettle();

        // 散客无会员状态验证
        expect(find.text('散客 / 未绑定会员'), findsOneWidget);
        expect(find.text('无备注'), findsOneWidget);
        expect(find.text('暂无偏好标签'), findsOneWidget);
        expect(find.text('暂无历史订单记录'), findsOneWidget);
        expect(find.text('未结账'), findsWidgets);

        // 确保没有出现硬编码假数据
        expect(find.text('张三'), findsNothing);
        expect(find.text('138****8888'), findsNothing);
        expect(find.text('¥3286.00'), findsNothing);
        expect(find.text('28 次'), findsNothing);
      },
    );

    testWidgets(
      'bind member from bill detail opens phone dialog and binds by phone',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final bill = CashierBill.fromJson({
          'id': 103,
          'order_no': 'ORD202609010003',
          'table_number': '08',
          'transac_status': 'unsettled',
          'sett_amount': 66.0,
          'list': [],
        });

        final memberRepo = _FakeMemberRepository();
        final repository = _FakeBillRepository([bill]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CashierBillPage(
                repository: repository,
                                approvalRepository: _FakeAccessApprovalRepository(),
permissions: kBillActionPerms,
                memberRepository: memberRepo,
                canBindMember: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('详情'));
        await tester.pumpAndSettle();

        // 打开绑定会员弹窗（仅输入手机号）
        await tester.tap(find.text('绑定会员'));
        await tester.pumpAndSettle();
        expect(find.text('会员手机号'), findsOneWidget);
        expect(find.text('确认绑定'), findsOneWidget);

        // 无效手机号被拦截
        await tester.enterText(
          find.byKey(const Key('bill-bind-member-phone-input')),
          '123',
        );
        await tester.tap(
          find.byKey(const Key('bill-bind-member-confirm-button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('请输入 11 位有效手机号'), findsOneWidget);
        expect(memberRepo.boundOrders, isEmpty);

        // 有效手机号确认绑定
        await tester.enterText(
          find.byKey(const Key('bill-bind-member-phone-input')),
          '13800138000',
        );
        await tester.tap(
          find.byKey(const Key('bill-bind-member-confirm-button')),
        );
        await tester.pumpAndSettle();

        expect(memberRepo.boundOrders, hasLength(1));
        expect(memberRepo.boundOrders.single.orderId, 103);
        expect(memberRepo.boundOrders.single.phone, '13800138000');
        // 弹窗关闭并提示成功
        expect(find.text('会员手机号'), findsNothing);
        expect(find.text('会员绑定成功'), findsOneWidget);
      },
    );

    testWidgets(
      'strictly differentiates between refunded and cancelled bills in pills and badges',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final refundedBill = CashierBill.fromJson({
          'id': 201,
          'order_no': 'ORD_REFUNDED_01',
          'table_number': '12',
          'transac_status': 'cancelled',
          'refund_amount': 150.0,
          'sett_amount': 150.0,
          'paid_amount': 150.0,
          'number_of_diners': 3,
        });
        final cancelledBill = CashierBill.fromJson({
          'id': 202,
          'order_no': 'ORD_CANCELLED_02',
          'table_number': '15',
          'transac_status': 'cancelled',
          'refund_amount': 0.0,
          'sett_amount': 180.0,
          'number_of_diners': 2,
        });

        expect(refundedBill.status, CashierBillStatus.refunded);
        expect(refundedBill.isRefunded, isTrue);
        expect(refundedBill.isCancelled, isFalse);

        expect(cancelledBill.status, CashierBillStatus.cancelled);
        expect(cancelledBill.isCancelled, isTrue);
        expect(cancelledBill.isRefunded, isFalse);

        final repository = _FakeBillRepository([refundedBill, cancelledBill]);

        await tester.pumpWidget(
          MaterialApp(
            home: CashierBillPage(
              repository: repository,
              approvalRepository: _FakeAccessApprovalRepository(),
              permissions: kBillActionPerms,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 验证筛选药丸分离
        expect(find.text('已退款'), findsWidgets);
        expect(find.text('已取消'), findsWidgets);

        // 验证卡片徽章各自准确
        expect(find.text('ORD_REFUNDED_01'), findsOneWidget);
        expect(find.text('ORD_CANCELLED_02'), findsOneWidget);
        expect(find.text('桌 (3人)'), findsOneWidget);
        expect(find.text('桌 (2人)'), findsOneWidget);

        // 严禁存在捏造的虚假标签和指标
        expect(find.text('🔥 高频熟客 (月均4+次)'), findsNothing);
        expect(find.text('🥩 偏好招牌油边(精选微辣)'), findsNothing);
        expect(find.text('4200002138202610228392104820'), findsNothing);
        expect(find.text('费率 0.38%'), findsNothing);
      },
    );

    testWidgets(
      'CashierBillPage correctly displays distinct KDS dish preparation statuses instead of all completed',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final billWithKds = CashierBill.fromJson({
          'id': 301,
          'order_no': 'ORD_KDS_STATUS_01',
          'table_number': '6',
          'transac_status': 'unsettled',
          'sett_amount': 120.0,
          'number_of_diners': 2,
          'list': [
            {
              'id': 11,
              'dish_name': '秘制烤羊肉',
              'quantity': 2,
              'unit_price': 18.0,
              'total_price': 36.0,
              'kds_item_status': 0,
              'kds_status_text': '待制作',
            },
            {
              'id': 12,
              'dish_name': '烤五花肉',
              'quantity': 1,
              'unit_price': 22.0,
              'total_price': 22.0,
              'kds_item_status': 1,
              'kds_status_text': '制作中',
            },
            {
              'id': 13,
              'dish_name': '拍黄瓜',
              'quantity': 1,
              'unit_price': 12.0,
              'total_price': 12.0,
              'kds_item_status': 1,
              'kds_status_text': '待传菜',
            },
            {
              'id': 14,
              'dish_name': '鲜酿酸梅汤',
              'quantity': 2,
              'unit_price': 10.0,
              'total_price': 20.0,
              'kds_item_status': 2,
              'kds_status_text': '已完成',
            },
            {
              'id': 15,
              'dish_name': '原味花生',
              'quantity': 1,
              'unit_price': 8.0,
              'total_price': 8.0,
              'line_status': 'refunded',
              'kds_item_status': 3,
              'kds_status_text': '已退菜',
            },
          ],
        });

        final repository = _FakeBillRepository([billWithKds]);

        await tester.pumpWidget(
          MaterialApp(
            home: CashierBillPage(
              repository: repository,
              approvalRepository: _FakeAccessApprovalRepository(),
              permissions: kBillActionPerms,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('详情'));
        await tester.pumpAndSettle();

        // 验证各菜品制作状态按 KDS 实际状态独立渲染，而非全部显示已出菜上桌
        expect(find.text('待制作'), findsWidgets);
        expect(find.text('制作中'), findsWidgets);
        expect(find.text('待传菜'), findsWidgets);
        expect(find.text('已出菜上桌'), findsWidgets);
        expect(find.text('已退菜免除'), findsWidgets);

        // 验证明细头部概览真实准确（4道菜品中 1 道已出餐，3 道制作中，1 道退菜免除）
        expect(find.textContaining('共 4 道菜品（1 道已出餐 · 3 道制作中） · 1 道退菜免除'), findsOneWidget);
      },
    );

    test('CashierInvoiceDetails correctly parses all statuses and field aliases', () {
      final success = CashierInvoiceDetails.fromJson({
        'orderNo': 'ORD001',
        'hasInvoice': true,
        'invoiceStatus': 'SUCCESS',
        'invoiceAmount': 100.0,
        'buyerTitle': '公司名',
        'invoiceNo': 'INV001',
        'downloadUrl': 'https://download/url',
      });
      expect(success.isSuccess, isTrue);
      expect(success.statusLabel, '已开具');

      final pending = CashierInvoiceDetails.fromJson({
        'order_no': 'ORD002',
        'invoice_status': 'PENDING_SCAN',
        'invoice_qr_url': 'https://qr/url',
      });
      expect(pending.isPendingScan, isTrue);
      expect(pending.invoiceQrUrl, 'https://qr/url');
      expect(pending.statusLabel, '待顾客扫码');

      final failed = CashierInvoiceDetails.fromJson({
        'orderNo': 'ORD003',
        'invoiceStatus': 'FAILED',
        'failReason': '税控盘故障',
      });
      expect(failed.isFailed, isTrue);
      expect(failed.failReason, '税控盘故障');
      expect(failed.statusLabel, '开票失败');
    });

    testWidgets(
      'CashierBillPage electronic invoice lifecycle: displays issued invoice details and PDF button when already succeeded',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final bill = CashierBill.fromJson({
          'id': 101,
          'order_no': 'ORD_INV_001',
          'table_number': 'A08',
          'transac_status': 'settled',
          'sett_amount': 188.0,
          'number_of_diners': 2,
          'list': [],
        });
        final repository = _FakeBillRepository([bill]);
        repository.invoiceStatusToReturn = const CashierInvoiceDetails(
          orderNo: 'ORD_INV_001',
          hasInvoice: true,
          invoiceStatus: 'SUCCESS',
          invoiceAmount: 188.0,
          titleType: 'COMPANY',
          buyerTitle: '广州科技创新有限公司',
          buyerTaxNo: '91440101XXXXXXXX',
          invoiceNo: '244420000000998877',
          invoiceCode: '0440020001',
          downloadUrl: 'https://test/invoice.pdf',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: CashierBillPage(
              repository: repository,
              approvalRepository: _FakeAccessApprovalRepository(),
              permissions: kBillActionPerms,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('详情'));
        await tester.pumpAndSettle();

        final invoiceBtn = find.byKey(const Key('bill-detail-invoice-button'));
        expect(invoiceBtn, findsOneWidget);
        await tester.tap(invoiceBtn);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('invoice-issued-card')), findsOneWidget);
        expect(find.text('电子发票已成功开具'), findsOneWidget);
        expect(find.text('广州科技创新有限公司 (企业)'), findsOneWidget);
        expect(find.text('244420000000998877'), findsOneWidget);
        expect(find.byKey(const Key('invoice-open-pdf-btn')), findsOneWidget);
        expect(find.byKey(const Key('invoice-copy-url-btn')), findsOneWidget);
      },
    );

    testWidgets(
      'CashierBillPage electronic invoice lifecycle: generates QR code when status is NONE',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final bill = CashierBill.fromJson({
          'id': 102,
          'order_no': 'ORD_INV_002',
          'table_number': 'A08',
          'transac_status': 'settled',
          'sett_amount': 88.0,
          'number_of_diners': 2,
          'list': [],
        });
        final repository = _FakeBillRepository([bill]);
        repository.invoiceStatusToReturn = const CashierInvoiceDetails(
          orderNo: 'ORD_INV_002',
          hasInvoice: false,
          invoiceStatus: 'NONE',
          invoiceAmount: 0.0,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: CashierBillPage(
              repository: repository,
              approvalRepository: _FakeAccessApprovalRepository(),
              permissions: kBillActionPerms,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('详情'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('bill-detail-invoice-button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('invoice-qrcode-image')), findsOneWidget);
        expect(find.text('待顾客扫码'), findsOneWidget);
        expect(find.text('发票抬头与税号将由顾客自行填写并自动推送至税局'), findsOneWidget);
        expect(find.byKey(const Key('invoice-copy-url-btn')), findsOneWidget);

        // Close dialog to cancel periodic timer cleanly
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
      },
    );

  });
}

class _FakeBillRepository implements CashierBillRepository {
  _FakeBillRepository(this.bills);

  final List<CashierBill> bills;
  final List<CashierBill> deletedBills = [];
  final List<String> printedReceipts = [];
  final List<String> unCheckedOutOrders = [];
  CashierBillQuery? lastQuery;

  @override
  Future<CashierBillResult> loadBills(CashierBillQuery query) async {
    lastQuery = query;
    final filtered = bills.where((bill) {
      if (query.status != CashierBillStatus.all && bill.status != query.status)
        return false;
      if (query.orderType != CashierOrderType.all &&
          !query.orderType.matches(bill.orderType))
        return false;
      if (query.keyword.trim().isNotEmpty) {
        final kw = query.keyword.trim().toLowerCase();
        final matchOrderNo = bill.orderNo.toLowerCase().contains(kw);
        final matchTable = bill.tableNumber.toLowerCase().contains(kw);
        if (!matchOrderNo && !matchTable) return false;
      }
      return true;
    }).toList();
    return CashierBillResult(bills: filtered, total: filtered.length);
  }

  @override
  Future<CashierBillSummary> loadSummary() async {
    return const CashierBillSummary(
      todayRevenue: 2860.0,
      orderCount: 48,
      avgOrderPrice: 59.58,
      totalDiscount: 320.0,
    );
  }

  @override
  Future<CashierBill> loadBillDetail(CashierBill bill) async => bill;

  @override
  Future<void> printKitchen({
    required String orderNo,
    List<String> categoryIds = const [],
  }) async {}

  @override
  Future<void> printReceipt({
    required String orderNo,
    int? orderId,
    String scenario = 'checkout',
  }) async {
    printedReceipts.add(orderNo);
  }

  @override
  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'CHECKOUT',
    int? orderId,
    String? orderNo,
    String paperSize = '58mm',
  }) async {
    return PrintPreviewResult(
      scenario: scenario,
      scenarioName: '收银结账单',
      paperSize: paperSize,
      paperWidthMm: paperSize == '80mm' ? 80 : 58,
      paperWidthChars: paperSize == '80mm' ? 48 : 32,
      shopName: '测试烧烤店',
      totalTickets: 1,
      tickets: [
        const PrintTicket(
          ticketIndex: 1,
          title: '收银结账单',
          rawContent: '测试小票内容',
          plainText: '测试小票排版文本',
          elements: [
            PrintElement(
              type: PrintElementType.header,
              text: '老肥油边王 结账单',
              align: PrintElementAlign.center,
              size: PrintElementSize.large,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> unCheckout({
    required String orderNo,
    required String reason,
    String? approvalToken,
  }) async {
    unCheckedOutOrders.add(orderNo);
  }

  final List<
    ({
      String orderNo,
      String? transactionId,
      double? amount,
      String? reason,
      String? account,
      String? password,
      String? approvalToken,
    })
  >
  refundedOrders = [];

  @override
  Future<void> refundOrder({
    required String orderNo,
    String? transactionId,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  }) async {
    if (approvalToken == null && account == null) {
      throw const ApiException('敏感操作需要现场输入授权员工账号和密码');
    }
    refundedOrders.add((
      orderNo: orderNo,
      transactionId: transactionId,
      amount: refundAmount,
      reason: reason,
      account: account,
      password: password,
      approvalToken: approvalToken,
    ));
  }

  final List<
    ({
      String orderNo,
      double? amount,
      String? reason,
      String? account,
      String? password,
      String? approvalToken,
    })
  >
  manualRefunds = [];

  @override
  Future<void> manualRefund({
    required String orderNo,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  }) async {
    if (approvalToken == null && account == null) {
      throw const ApiException('敏感操作需要现场输入授权员工账号和密码');
    }
    manualRefunds.add((
      orderNo: orderNo,
      amount: refundAmount,
      reason: reason,
      account: account,
      password: password,
      approvalToken: approvalToken,
    ));
  }

  final List<({CashierBill bill, String? approvalToken})> deletedBillCalls = [];

  @override
  Future<void> deleteBill(
    CashierBill bill, {
    String? account,
    String? password,
    String? approvalToken,
  }) async {
    if (approvalToken == null && account == null) {
      throw const ApiException('敏感操作需要现场输入授权员工账号和密码');
    }
    deletedBills.add(bill);
    deletedBillCalls.add((bill: bill, approvalToken: approvalToken));
  }

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {}

  @override
  Future<CashierInvoiceResult> createInvoiceQrcode({
    required String orderNo,
    String? tableNumber,
    double? invoiceAmount,
    double? taxRate,
  }) async {
    return CashierInvoiceResult(
      orderNo: orderNo,
      invoiceStatus: 'PENDING_SCAN',
      invoiceQrUrl: 'https://test/invoice/$orderNo',
      invoiceAmount: invoiceAmount ?? 100.0,
      expireMinutes: 1440,
      notice: '请使用微信或支付宝扫描上方二维码开票',
    );
  }

  CashierInvoiceDetails? invoiceStatusToReturn;

  @override
  Future<CashierInvoiceDetails> loadInvoiceStatus(String orderNo) async {
    return invoiceStatusToReturn ??
        CashierInvoiceDetails(
          orderNo: orderNo,
          hasInvoice: false,
          invoiceStatus: 'NONE',
          invoiceAmount: 0.0,
        );
  }

  @override
  Future<CashierAuditTimeline> loadAuditTimeline(String orderNo) async {
    return CashierAuditTimeline(
      orderNo: orderNo,
      events: const [],
    );
  }
}

class _FakeMemberRepository implements CashierMemberRepository {
  _FakeMemberRepository({
    this.profiles = const {},
    this.consumption = const {},
  });

  final Map<String, CashierMemberProfile> profiles;
  final Map<String, List<MemberConsumptionRecord>> consumption;
  final List<({int orderId, String phone})> boundOrders = [];

  @override
  Future<CashierMemberProfile> loadProfile(String phone) async {
    final profile = profiles[phone];
    if (profile != null) return profile;
    throw const MemberNotFoundException();
  }

  @override
  Future<List<MemberConsumptionRecord>> loadConsumption(String phone) async {
    return consumption[phone] ?? const [];
  }

  @override
  Future<MemberConsumptionDetail> loadConsumptionDetail(
    MemberConsumptionRecord record,
  ) async {
    return MemberConsumptionDetail(record: record, lines: const []);
  }

  @override
  Future<List<MemberRechargeRecord>> loadRecharges(String phone) async {
    return const [];
  }

  @override
  Future<MemberRechargeResult> recharge({
    required String phone,
    required double amount,
    required double giftAmount,
  }) async {
    return const MemberRechargeResult(newBalance: 0);
  }

  @override
  Future<void> bindOrder({required int orderId, required String phone}) async {
    boundOrders.add((orderId: orderId, phone: phone));
  }

  @override
  Future<PagedCashierMembers> loadMembers({
    required int page,
    int pageSize = 20,
    String query = '',
    String phone = '',
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierMemberStats> loadStats() async {
    throw UnimplementedError();
  }

  @override
  Future<PagedRechargeLogs> loadRechargeLogs({
    int page = 1,
    int pageSize = 20,
    String phone = '',
    String startTime = '',
    String endTime = '',
  }) async {
    return const PagedRechargeLogs(rows: [], total: 0);
  }

  @override
  Future<List<CashierCoupon>> loadCoupons() async {
    throw UnimplementedError();
  }

  @override
  Future<int> batchSendCoupon({required int couponId}) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CashierPersonaTag>> loadPersonaTags({
    String? phone,
    int? memberId,
  }) async {
    return const [];
  }
}
