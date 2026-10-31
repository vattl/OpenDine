import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/data/cashier_shift_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/data/real_cashier_shift_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/domain/cashier_shift.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/presentation/cashier_shift_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/presentation/cashier_shift_workbench.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_app_theme.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  setUpAll(() async {
    final fontLoader = FontLoader('NotoSansSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-VF.ttf'));
    await fontLoader.load();
  });

  group('cashier shift models', () {
    test(
      'safely parses mixed numeric money fields and formats two decimals',
      () {
        final shift = CashierShift.fromJson({
          'id': '12',
          'admin_id': 7,
          'shop_id': '2',
          'start_time': '2026-07-20 09:30:00',
          'start_cash': '120.5',
          'order_count': '8',
          'total_amount': 368.2,
        });

        expect(shift.id, 12);
        expect(shift.startCash, 120.5);
        expect(shift.totalAmount, 368.2);
        expect(formatCashierMoney(shift.totalAmount), '368.20');
        expect(safeMoney('not-a-number'), 0);
        expect(safeMoney(double.nan), 0);
      },
    );

    test('parses businessDay and fixed pay-channel amounts', () {
      final report = CashierTodayReport.fromJson({
        'businessDay': {
          'startTime': '2026-07-19T16:00:00+08:00',
          'endTime': '2026-07-20T04:00:00+08:00',
          'todayRevenue': '12560.5',
          'todayPaidOrderCount': '168',
          'todayOrderCount': '186',
          'todayMemberRechargeAmount': '3200.5',
          'todayUnpaidAmount': 980,
          'todayUnpaidOrderCount': 12,
          'totalRefundAmount': '120.00',
          'revenueByPayChannel': [
            {
              'channelCode': 'wechat',
              'channelLabel': '微信支付',
              'amount': '9000.2',
            },
            {'channelCode': 'cash', 'channelLabel': '现金', 'amount': 560.3},
          ],
        },
      });

      expect(report.revenue, 12560.5);
      expect(report.paidOrderCount, 168);
      expect(report.totalOrderCount, 186);
      expect(report.memberRechargeAmount, 3200.5);
      expect(report.unpaidAmount, 980);
      expect(report.unpaidOrderCount, 12);
      expect(report.refundAmount, 120);
      expect(report.revenueByPayChannel, hasLength(2));
      expect(report.revenueByPayChannel.first.amount, 9000.2);
    });

    test(
      'parses member recharge summary with fen and amount keys (v1.2.281)',
      () {
        final fen = MemberRechargeSummary.fromJson({
          'success_count': 5,
          'principal_fen': 250000,
          'gift_fen': 50000,
          'credited_total_fen': 300000,
        });
        expect(fen.successCount, 5);
        expect(fen.principal, 2500);
        expect(fen.gift, 500);
        expect(fen.creditedTotal, 3000);

        final amount = MemberRechargeSummary.fromJson({
          'successCount': 3,
          'principal_amount': 1800.0,
          'gift_amount': 200.0,
          'credited_total_amount': 2000.0,
        });
        expect(amount.successCount, 3);
        expect(amount.principal, 1800);
        expect(amount.gift, 200);
        expect(amount.creditedTotal, 2000);

        expect(MemberRechargeSummary.empty().successCount, 0);
      },
    );

    test('shift report parses member_recharge_summary block', () {
      final report = ShiftSummaryReport.fromJson({
        'session_id': 9,
        'cash_summary': {},
        'member_recharge_summary': {
          'success_count': 4,
          'principal_amount': 1200.0,
          'gift_amount': 300.0,
        },
      });
      expect(report.memberRechargeSummary, isNotNull);
      expect(report.memberRechargeSummary!.successCount, 4);
      expect(report.memberRechargeSummary!.principal, 1200);
      expect(report.memberRechargeSummary!.creditedTotal, 1500);

      // 旧服务端缺省时为空，不崩溃。
      final legacy = ShiftSummaryReport.fromJson({
        'session_id': 10,
        'cash_summary': {},
      });
      expect(legacy.memberRechargeSummary, isNull);
    });

    test(
      'shift report parses order sales, change and dish operation details',
      () {
        final report = ShiftSummaryReport.fromJson({
          'session_id': 11,
          'cash_summary': {},
          'order_sales_summary': {
            'paid_order_count': 5,
            'gross_sales_fen': 150000,
            'discount_fen': 2000,
            'refund_fen': 1500,
            'gift_paid_fen': 800,
            'net_sales_fen': 145700,
          },
          'change_summary': {
            'total_change_fen': 4500,
            'by_channel': {'cash': 3500, 'wechat': 1000},
          },
          'dish_operations': {
            'refund_dish_count': 3,
            'refund_dish_amount_fen': 3600,
            'give_dish_count': 2,
            'give_dish_amount_fen': 0,
          },
        });
        final sales = report.orderSalesSummary!;
        expect(sales.paidOrderCount, 5);
        expect(sales.grossSales, 1500);
        expect(sales.discount, 20);
        expect(sales.refund, 15);
        expect(sales.giftPaid, 8);
        expect(sales.netSales, 1457);
        final change = report.changeSummary!;
        expect(change.totalChange, 45);
        expect(change.byChannel['cash'], 35);
        expect(change.byChannel['wechat'], 10);
        final dishes = report.dishOperations!;
        expect(dishes.refundDishCount, 3);
        expect(dishes.refundDishAmount, 36);
        expect(dishes.giveDishCount, 2);

        // 旧服务端缺省时三段均为空，不崩溃。
        final legacy = ShiftSummaryReport.fromJson({
          'session_id': 12,
          'cash_summary': {},
        });
        expect(legacy.orderSalesSummary, isNull);
        expect(legacy.changeSummary, isNull);
        expect(legacy.dishOperations, isNull);
      },
    );

    test('keeps online and collection QR channels distinct', () {
      final report = CashierTodayReport.fromJson({
        'businessDay': {
          'revenueByPayChannel': [
            {'channelCode': 'wechat', 'amount': 100},
            {'channelCode': 'wechat_qr', 'amount': 200},
            {'channelCode': 'alipay', 'amount': 300},
            {'channelCode': 'alipay_qr', 'amount': 400},
          ],
        },
      });

      expect(report.revenueByPayChannel.map((item) => item.label), [
        '微信支付',
        '微信收款码',
        '支付宝',
        '支付宝收款码',
      ]);
      expect(dailyChannelLabel('wechat_qr'), '微信收款码');
      expect(dailyChannelLabel('offline_wechat_qr'), '微信收款码');
      expect(dailyChannelLabel('alipay_qr'), '支付宝收款码');
      expect(dailyChannelLabel('offline_alipay_qr'), '支付宝收款码');
    });

    test('parses the UI013 workbench without exposing a hidden amount', () {
      final workbench = CashierShiftWorkbenchData.fromJson({
        'business_day': '2026-10-03',
        'operator': {'id': 31, 'display_name': '李敏'},
        'terminal': {'id': 'POS-01', 'display_name': '前台收银机'},
        'drawer': {
          'id': 1038,
          'session_id': 1038,
          'code': 'FRONT-A',
          'display_name': '前台 A',
        },
        'latest_cash_movement': {
          'event_id': 3384,
          'type': 'CASH_DROP',
          'amount_hidden': true,
          'occurred_at': '2026-10-03T13:42:07+08:00',
          'operator_name': '王店长',
        },
        'previous_shift': {
          'session_id': 1037,
          'closed_at': '2026-10-03T01:12:34+08:00',
          'balanced': true,
        },
        'close_readiness': {
          'open_drawer_count': 1,
          'unsettled_order_count': 2,
          'pending_payment_count': 0,
          'unapproved_variance_count': 1,
        },
      });

      expect(workbench.operator?.displayName, '李敏');
      expect(workbench.drawer?.sessionId, 1038);
      expect(workbench.latestCashMovement?.amount, isNull);
      expect(workbench.latestCashMovement?.amountHidden, isTrue);
      expect(workbench.previousShift?.sessionId, 1037);
      expect(workbench.closeReadiness.canSettle, isFalse);
    });

    test('parses nested shift report money, channels, audit and integrity', () {
      final report = ShiftSummaryReport.fromJson({
        'session_id': 1037,
        'operator_name': '张倩',
        'terminal_name': '前台收银机',
        'drawer_name': '前台 A',
        'duration_seconds': 3661,
        'approval_status': 'APPROVED',
        'approved_by_name': '王店长',
        'cash_summary': {
          'opening_float_fen': 20000,
          'cash_sale_yuan': 1362,
          'cash_refund_yuan': 20,
          'expected_cash_fen': 154200,
          'counted_cash_fen': 154000,
          'variance_fen': -200,
        },
        'channels': [
          {
            'code': 'wechat',
            'label': '微信支付',
            'transaction_count': 28,
            'refund_count': 1,
            'refund_amount_fen': 8650,
            'net_amount_fen': 321000,
          },
        ],
        'audit_events': [
          {
            'event_id': 3384,
            'event_type': 'CASH_DROP',
            'amount_fen': -100000,
            'reference_no': 'CM-3384',
          },
        ],
        'integrity': {
          'version': 3,
          'status': 'VERIFIED',
          'report_hash': 'abc123',
        },
      });

      expect(report.openingFloat, 200);
      expect(report.expectedCash, 1542);
      expect(report.variance, -2);
      expect(report.channels.single.amount, 3210);
      expect(report.channels.single.transactionCount, 28);
      expect(report.channels.single.refundAmount, 86.5);
      expect(report.auditEvents.single.referenceNo, 'CM-3384');
      expect(report.integrity['status'], 'VERIFIED');
    });

    test('parses structured precheck and Z report contracts', () {
      final precheck = DailyPrecheckResult.fromJson({
        'can_settle': true,
        'is_already_settled': false,
        'stat_date': '2026-10-03',
        'precheck_token': 'signed-token',
        'precheck_expires_at': '2026-10-04T01:05:00+08:00',
        'watermarks': {
          'payment_ledger_id': 8921,
          'cash_event_id': 3384,
          'order_id': 16820,
        },
        'preview': {
          'gross_sales_fen': 539900,
          'channels': [
            {
              'code': 'wechat',
              'label': '微信支付',
              'success_count': 28,
              'refund_count': 1,
              'net_amount_fen': 321000,
            },
          ],
        },
      });
      final zReport = CommercialZReport.fromJson({
        'report_type': 'Z_REPORT',
        'is_closed': true,
        'shop_id': 2,
        'business_day': '2026-10-03',
        'snapshot_hash': 'sha256',
        'watermarks': precheck.watermarks,
        'sales_summary': {
          'gross_sales_fen': 539900,
          'discount_amount_fen': 18600,
          'refund_amount_fen': 8650,
          'net_sales_fen': 512650,
          'order_count': 42,
        },
        'channels': precheck.preview['channels'],
        'total_cash_variance': 8,
        'total_adjustment': 0,
        'adjusted_net_sales': 5126.5,
      });

      expect(precheck.precheckExpiresAt, isNotNull);
      expect(precheck.watermarks['order_id'], 16820);
      expect(zReport.netSales, 5126.5);
      expect(zReport.channels['wechat'], 3210);
      expect(zReport.channelDetails.single.transactionCount, 28);
      expect(zReport.watermarks['cash_event_id'], 3384);
    });

    test(
      'parses precheck with voidable_pack_takeout and void result (WI-036)',
      () {
        final precheck = DailyPrecheckResult.fromJson({
          'can_settle': false,
          'is_already_settled': false,
          'stat_date': '2026-10-12',
          'blockers': [
            {
              'code': 'OPEN_ORDERS',
              'message': '存在 2 笔未完成打包单，禁止关账',
              'count': 2,
              'voidable_pack_takeout': {
                'count': 2,
                'amount': 48.0,
                'threshold_minutes': 30,
                'orders': [
                  {
                    'id': 101,
                    'order_no': 'ORD-101',
                    'created_at': '2026-10-12T19:00:00Z',
                    'sett_amount': 28.0,
                    'age_minutes': 45,
                    'dine_in_or_take_out': 'PACK',
                  },
                  {
                    'id': 102,
                    'order_no': 'ORD-102',
                    'created_at': '2026-10-12T19:10:00Z',
                    'sett_amount': 20.0,
                    'age_minutes': 35,
                    'dine_in_or_take_out': 'PACK',
                  },
                ],
              },
            },
          ],
          'voidable_stale_pack_takeout': {
            'count': 2,
            'amount': 48.0,
            'threshold_minutes': 30,
          },
        });

        expect(precheck.canSettle, isFalse);
        expect(precheck.blockers.single.code, 'OPEN_ORDERS');
        final voidable = precheck.blockers.single.voidablePackTakeout;
        expect(voidable, isNotNull);
        expect(voidable!.count, 2);
        expect(voidable.amount, 48.0);
        expect(voidable.orders.length, 2);
        expect(voidable.orders.first.orderNo, 'ORD-101');
        expect(voidable.orders.first.ageMinutes, 45);
        expect(voidable.orders.first.settAmount, 28.0);
        expect(precheck.voidableStalePackTakeout?.count, 2);

        final voidResult = VoidStaleTakeoutResult.fromJson({
          'voided_count': 2,
          'voided_amount': 48.0,
          'threshold_minutes': 30,
          'voided_order_nos': ['ORD-101', 'ORD-102'],
        });
        expect(voidResult.voidedCount, 2);
        expect(voidResult.voidedAmount, 48.0);
        expect(voidResult.voidedOrderNos, ['ORD-101', 'ORD-102']);
      },
    );
  });

  group('RealCashierShiftRepository', () {
    test('treats a null current shift as not started', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/shift/current': jsonEncode({'code': 0, 'shift': null}),
      });
      final repository = RealCashierShiftRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 2,
        ),
      );

      expect(await repository.loadCurrentShift(), isNull);
    });

    test(
      'starts a shift with optional shop_id then reloads current shift',
      () async {
        final transport = FakeHttpTransport({
          'POST /cashier/shift/start': jsonEncode({'code': 0, 'shiftId': 33}),
          'GET /cashier/shift/current': jsonEncode({
            'code': 0,
            'shift': {
              'id': 33,
              'shop_id': 2,
              'start_cash': '200.00',
              'order_count': 0,
              'total_amount': 0,
            },
          }),
        });
        final repository = RealCashierShiftRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 2,
          ),
        );

        final shift = await repository.startShift(startCash: 200, shopId: 2);

        expect(shift.id, 33);
        final body = jsonDecode(transport.requests.first.body!);
        expect(body, {
          'start_cash': 200.0,
          'openingFloatFen': 20000,
          'shop_id': 2,
        });
        expect(transport.requests.first.headers['X-Shop-Id'], '2');
      },
    );

    test('uses the backend handover summary as the result', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/shift/handover': jsonEncode({
          'code': 0,
          'order_count': '19',
          'total_amount': '688.35',
          'business_no': 1037,
          'report': {
            'session_id': 1037,
            'state': 'CLOSED',
            'approval_status': 'APPROVED',
            'cash_summary': {'counted_cash_fen': 70050, 'variance_fen': 1215},
          },
        }),
      });
      final repository = RealCashierShiftRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 2,
        ),
      );

      final result = await repository.handover(
        endCash: 700.5,
        shopId: 2,
        idempotencyKey: 'handover-1037',
      );

      expect(result.orderCount, 19);
      expect(result.totalAmount, 688.35);
      expect(result.sessionId, 1037);
      expect(result.countedCash, 700.5);
      expect(result.variance, 12.15);
      expect(result.varianceApproved, isTrue);
      final body = jsonDecode(transport.requests.single.body!);
      expect(body, {
        'end_cash': 700.5,
        'countedCashFen': 70050,
        'shop_id': 2,
        'idempotency_key': 'handover-1037',
      });
    });

    test(
      'loads dashboard with shop header only when explicitly requested',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/report/dashboard': jsonEncode({
            'code': 0,
            'data': {
              'businessDay': {'todayRevenue': 88.8, 'revenueByPayChannel': []},
            },
          }),
        });
        final repository = RealCashierShiftRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
          ),
        );

        final report = await repository.loadTodayReport(shopId: 2);

        expect(report.revenue, 88.8);
        expect(transport.requests.single.headers['X-Shop-Id'], '2');
      },
    );

    test(
      'omits stat_date query/body when null to let server resolve active shift window',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/daily/summary': jsonEncode({
            'code': 0,
            'summary': {
              'stat_date': '2026-09-11',
              'total_amount': 1880.0,
              'discount_amount': 50.0,
              'refund_amount': 0.0,
              'settled': false,
            },
          }),
          'GET /admin/daily/byChannel': jsonEncode({
            'code': 0,
            'channels': {'微信支付': 1000.0, '现金': 880.0},
          }),
          'POST /admin/daily/settle': jsonEncode({
            'code': 0,
            'dailyStat': {
              'stat_date': '2026-09-11',
              'total_amount': 1880.0,
              'discount_amount': 50.0,
              'refund_amount': 0.0,
              'settled_at': '2026-09-11 23:30:00',
            },
          }),
        });
        final repository = RealCashierShiftRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 3,
          ),
        );

        final summary = await repository.loadDailySummary();
        expect(summary.statDate, '2026-09-11');
        expect(summary.totalAmount, 1880.0);
        // Query should NOT contain stat_date
        expect(
          transport.requests[0].uri.queryParameters.containsKey('stat_date'),
          isFalse,
        );

        final channels = await repository.loadDailyChannels();
        expect(channels['微信支付'], 1000.0);
        expect(
          transport.requests[1].uri.queryParameters.containsKey('date'),
          isFalse,
        );

        final settleResult = await repository.settleDaily(shopId: 3);
        expect(settleResult.statDate, '2026-09-11');
        final settleBody = jsonDecode(transport.requests[2].body!);
        expect(settleBody.containsKey('stat_date'), isFalse);
        expect(settleBody['shop_id'], 3);
      },
    );

    test(
      'loads UI013 workbench, history, cash events and Z report history',
      () async {
        final transport = FakeHttpTransport({
          'GET /cashier/shift/workbench': jsonEncode({
            'code': 0,
            'business_day': '2026-10-03',
            'operator': {'id': 31, 'display_name': '李敏'},
            'close_readiness': {'open_drawer_count': 0},
          }),
          'GET /cashier/shift/reports': jsonEncode({
            'code': 0,
            'items': [
              {
                'session_id': 1037,
                'state': 'CLOSED',
                'cash_summary': {'counted_cash_fen': 136200},
              },
            ],
            'has_more': true,
            'next_cursor': 1037,
          }),
          'GET /cashier/shift/1037/cash-events': jsonEncode({
            'code': 0,
            'items': [
              {'event_id': 3384, 'type': 'CASH_DROP', 'amount_fen': -100000},
            ],
            'has_more': false,
          }),
          'GET /admin/daily/z-reports': jsonEncode({
            'code': 0,
            'items': [
              {
                'id': 7,
                'snapshot_no': 'Z-20261003-0007',
                'business_day': '2026-10-03',
                'net_sales_fen': 512650,
                'order_count': 42,
              },
            ],
            'has_more': false,
          }),
        });
        final repository = RealCashierShiftRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 2,
          ),
        );

        final workbench = await repository.loadWorkbench(shopId: 2);
        final reports = await repository.loadShiftReports(
          shopId: 2,
          cursor: 2000,
          limit: 10,
        );
        final events = await repository.loadCashEvents(1037, shopId: 2);
        final zReports = await repository.loadZReports(
          shopId: 2,
          dateFrom: '2026-10-01T00:00:00+08:00',
          dateTo: '2026-10-03',
        );

        expect(workbench.operator?.displayName, '李敏');
        expect(reports.items.single.countedCash, 1362);
        expect(reports.nextCursor, 1037);
        expect(events.items.single.amount, -1000);
        expect(zReports.items.single.netSales, 5126.5);
        expect(transport.requests[1].uri.queryParameters, {
          'cursor': '2000',
          'limit': '10',
        });
        expect(
          transport.requests[3].uri.queryParameters['date_from'],
          '2026-10-01',
        );
        expect(
          transport.requests[3].uri.queryParameters['date_to'],
          '2026-10-03',
        );
      },
    );

    test(
      'voidStaleTakeoutOrders posts to backend with stat_date and minutes (WI-036)',
      () async {
        final transport = FakeHttpTransport({
          'POST /admin/daily/void-stale-takeout-orders': jsonEncode({
            'code': 0,
            'voided_count': 2,
            'voided_amount': 48.0,
            'threshold_minutes': 30,
            'voided_order_nos': ['ORD-101', 'ORD-102'],
          }),
        });
        final repository = RealCashierShiftRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 2,
          ),
        );

        final result = await repository.voidStaleTakeoutOrders(
          statDate: '2026-10-12',
          shopId: 2,
          minutes: 30,
        );

        expect(result.voidedCount, 2);
        expect(result.voidedAmount, 48.0);
        expect(result.thresholdMinutes, 30);
        expect(result.voidedOrderNos, ['ORD-101', 'ORD-102']);

        final req = transport.requests.single;
        expect(req.method, 'POST');
        expect(req.uri.path, '/admin/daily/void-stale-takeout-orders');
        final body = jsonDecode(req.body!);
        expect(body['stat_date'], '2026-10-12');
        expect(body['minutes'], 30);
      },
    );
  });

  group('CashierShiftPage', () {
    testWidgets('shows centered start card when there is no active shift', (
      tester,
    ) async {
      final repository = _FakeCashierShiftRepository();
      await _pumpPage(tester, repository: repository, canViewReport: false);
      await tester.pumpAndSettle();

      expect(find.text('尚未开班'), findsOneWidget);
      expect(find.text('开班'), findsOneWidget);
      expect(find.text('暂无今日简报权限'), findsOneWidget);
      expect(repository.reportLoads, 0);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets(
      'renders real workbench summaries and opens closed-shift history',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          shift: CashierShift.fromJson({
            'id': 1038,
            'drawer_session_id': 1038,
            'start_cash': 200,
            'business_day': '2026-10-03',
          }),
        );
        repository.workbench = CashierShiftWorkbenchData.fromJson({
          'business_day': '2026-10-03',
          'operator': {'id': 31, 'display_name': '李敏'},
          'terminal': {'id': 'POS-01', 'display_name': '前台收银机'},
          'drawer': {
            'id': 1038,
            'session_id': 1038,
            'code': 'FRONT-A',
            'display_name': '前台 A',
          },
          'latest_cash_movement': {
            'event_id': 3384,
            'type': 'CASH_DROP',
            'amount_hidden': true,
            'occurred_at': '2026-10-03T13:42:07+08:00',
          },
          'previous_shift': {
            'session_id': 1037,
            'closed_at': '2026-10-03T01:12:34+08:00',
            'balanced': true,
          },
          'close_readiness': {
            'open_drawer_count': 1,
            'unsettled_order_count': 2,
            'pending_payment_count': 1,
            'unapproved_variance_count': 0,
          },
        });
        repository.shiftReports = const CashierShiftReportPage(
          items: [
            ShiftSummaryReport(
              sessionId: 1037,
              state: 'CLOSED',
              operatorName: '张倩',
              terminalName: '前台收银机',
              drawerName: '前台 A',
              businessDay: '2026-10-03',
            ),
          ],
        );

        await _pumpPage(
          tester,
          repository: repository,
          canViewReport: false,
          canSettleDaily: true,
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('李敏 · 终端 前台收银机'), findsOneWidget);
        expect(find.textContaining('大钞投库 · 金额按盲盘规则隐藏'), findsOneWidget);
        expect(find.textContaining('班次 #1037 · 已平账'), findsOneWidget);
        expect(find.text('未结桌台账单'), findsOneWidget);
        expect(find.text('2 笔挂账桌台 (需结清)'), findsOneWidget);
        expect(find.text('进行中线上支付'), findsOneWidget);
        expect(find.text('1 笔待确认 (需核对)'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const Key('shift-detail-open-button')),
        );
        await tester.tap(find.byKey(const Key('shift-detail-open-button')));
        await tester.pumpAndSettle();

        expect(find.byType(CashierShiftHistoryPage), findsOneWidget);
        expect(find.text('班次 #1037 · 张倩'), findsOneWidget);
        expect(find.text('现金流水'), findsOneWidget);
      },
    );

    testWidgets(
      'renders the approved workbench with one blind-handover entry',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          shift: CashierShift.fromJson({
            'id': 1,
            'start_cash': 100,
            'order_count': 3,
            'total_amount': 90.5,
          }),
          report: CashierTodayReport.fromJson({
            'businessDay': {
              'todayRevenue': 188.5,
              'todayPaidOrderCount': 4,
              'todayOrderCount': 6,
              'todayMemberRechargeAmount': 300,
              'todayUnpaidAmount': 25,
              'todayUnpaidOrderCount': 2,
              'totalDiscountAmount': 20,
              'revenueByPayChannel': [
                {'channelCode': 'cash', 'channelLabel': '现金', 'amount': 80},
                {
                  'channelCode': 'wechat_qr',
                  'channelLabel': '微信收款码',
                  'amount': 60,
                },
                {
                  'channelCode': 'alipay_qr',
                  'channelLabel': '支付宝收款码',
                  'amount': 48.5,
                },
              ],
            },
          }),
        );
        await _pumpPage(
          tester,
          repository: repository,
          canViewReport: true,
          canSettleDaily: true,
        );
        await tester.pumpAndSettle();

        expect(find.text('当前钱箱'), findsOneWidget);
        expect(find.text('营业日关账与日结治理'), findsOneWidget);
        expect(find.text('今日支付渠道概览'), findsOneWidget);
        expect(find.text('当班摘要'), findsNothing);
        expect(find.text('今日简报'), findsNothing);
        expect(find.text('会员充值'), findsOneWidget);
        expect(find.text('¥ 300.00'), findsOneWidget);
        expect(find.text('待支付'), findsOneWidget);
        expect(find.text('2 单 · ¥ 25.00'), findsOneWidget);
        expect(find.text('优惠金额'), findsOneWidget);
        expect(find.text('¥ 20.00'), findsOneWidget);
        expect(find.text('现金'), findsOneWidget);
        expect(find.text('¥ 80.00'), findsOneWidget);
        expect(find.text('微信收款码'), findsOneWidget);
        expect(find.text('¥ 60.00'), findsOneWidget);
        expect(find.text('支付宝收款码'), findsOneWidget);
        expect(find.text('¥ 48.50'), findsOneWidget);
        expect(find.text('本班订单'), findsOneWidget);
        expect(find.text('6 笔'), findsOneWidget);
        expect(find.byKey(const Key('shift-handover-button')), findsOneWidget);
        expect(find.text('盲盘交班'), findsOneWidget);
        expect(find.text('确认交班'), findsNothing);
        expect(repository.reportLoads, 1);
        expect(
          tester
              .getSize(find.byKey(const Key('cashier-shift-content-frame')))
              .width,
          1120,
        );
        _expectGovernanceCardsAligned(tester);
        await expectLater(
          find.byType(CashierShiftPage),
          matchesGoldenFile(
            '../design/visual-verification/UI013/production/workbench-1280.png',
          ),
        );
      },
    );

    testWidgets('expands page frames in wide cashier work areas', (
      tester,
    ) async {
      final repository = _FakeCashierShiftRepository(
        shift: CashierShift.fromJson({
          'id': 21,
          'start_time': '2026-10-03T16:43:00',
          'start_cash': 0,
          'order_count': 0,
          'total_amount': 0,
        }),
        dailySummary: const CashierDailySummary(
          statDate: '2026-10-03',
          totalAmount: 0,
          discountAmount: 0,
          refundAmount: 0,
          settled: true,
        ),
      );
      await _pumpPage(
        tester,
        repository: repository,
        canViewReport: true,
        canSettleDaily: true,
        surfaceSize: const Size(1684, 1024),
      );
      await tester.pumpAndSettle();

      final primaryFrame = find.byKey(const Key('cashier-shift-content-frame'));
      expect(tester.getSize(primaryFrame).width, 1360);
      expect(tester.getTopLeft(primaryFrame).dx, 162);
      _expectGovernanceCardsAligned(tester);
      await expectLater(
        find.byType(CashierShiftPage),
        matchesGoldenFile(
          '../design/visual-verification/UI013/production/workbench-wide-1684.png',
        ),
      );

      await tester.tap(find.byKey(const Key('daily-close-open-button')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(
              find.byKey(const Key('cashier-shift-secondary-content-frame')),
            )
            .width,
        1360,
      );
    });

    testWidgets(
      'keeps the approved 1120 content frame at 1440 reference viewport',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          shift: CashierShift.fromJson({
            'id': 1038,
            'start_time': '2026-10-03T16:43:00',
            'start_cash': 500,
            'order_count': 42,
            'total_amount': 5126.5,
            'terminal_id': 'POS-01',
            'drawer_session_id': 1038,
            'business_day': '2026-10-03',
          }),
          report: CashierTodayReport.fromJson({
            'businessDay': {
              'todayRevenue': 5213,
              'todayPaidOrderCount': 42,
              'todayOrderCount': 42,
              'todayMemberRechargeAmount': 520,
              'todayUnpaidAmount': 75,
              'todayUnpaidOrderCount': 3,
              'revenueByPayChannel': [
                {
                  'channelCode': 'wechat',
                  'channelLabel': '微信支付',
                  'amount': 3210,
                },
                {
                  'channelCode': 'alipay',
                  'channelLabel': '支付宝',
                  'amount': 1240,
                },
                {'channelCode': 'cash', 'channelLabel': '现金', 'amount': 563},
                {
                  'channelCode': 'balance',
                  'channelLabel': '会员余额',
                  'amount': 200,
                },
              ],
            },
          }),
          dailySummary: const CashierDailySummary(
            statDate: '2026-10-03',
            totalAmount: 5399,
            discountAmount: 186,
            refundAmount: 86.5,
            settled: false,
          ),
        );
        await _pumpPage(
          tester,
          repository: repository,
          canViewReport: true,
          canSettleDaily: true,
          surfaceSize: const Size(1440, 900),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .getSize(find.byKey(const Key('cashier-shift-content-frame')))
              .width,
          1120,
        );
        _expectGovernanceCardsAligned(tester);
        await expectLater(
          find.byType(CashierShiftPage),
          matchesGoldenFile(
            '../design/visual-verification/UI013/production/workbench-reference-1440.png',
          ),
        );
      },
    );

    testWidgets('stacks governance cards at equal full width below 920dp', (
      tester,
    ) async {
      final repository = _FakeCashierShiftRepository(
        shift: CashierShift.fromJson({
          'id': 31,
          'start_cash': 500,
          'order_count': 2,
          'total_amount': 180,
        }),
      );
      await _pumpPage(
        tester,
        repository: repository,
        canViewReport: true,
        canSettleDaily: true,
        surfaceSize: const Size(800, 1200),
      );
      await tester.pumpAndSettle();

      final drawer = tester.getRect(
        find.byKey(const Key('cashier-drawer-governance-card')),
      );
      final daily = tester.getRect(
        find.byKey(const Key('cashier-daily-close-governance-card')),
      );
      expect((drawer.width - daily.width).abs(), lessThan(0.01));
      expect((drawer.left - daily.left).abs(), lessThan(0.01));
      expect(daily.top, greaterThan(drawer.bottom));
    });

    testWidgets(
      'captures equal governance cards at the 1280x720 audit viewport',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          shift: CashierShift.fromJson({
            'id': 41,
            'start_cash': 500,
            'order_count': 42,
            'total_amount': 5126.5,
            'terminal_id': 'POS-01',
          }),
        );
        await _pumpPage(
          tester,
          repository: repository,
          canViewReport: true,
          canSettleDaily: true,
          surfaceSize: const Size(1280, 720),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -280));
        await tester.pumpAndSettle();

        _expectGovernanceCardsAligned(tester);
        await expectLater(
          find.byType(CashierShiftPage),
          matchesGoldenFile(
            '../design/visual-verification/UI013/production/workbench-equal-cards-1280x720.png',
          ),
        );
      },
    );

    testWidgets(
      'enforces blind cash count on handover without exposing system expected cash',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          shift: CashierShift.fromJson({
            'id': 1,
            'start_time': '2026-07-21T09:30:00',
            'start_cash': 100,
            'order_count': 7,
            'total_amount': 300,
          }),
          handoverResult: const CashierHandoverResult(
            sessionId: 10,
            drawerSessionId: 10,
            orderCount: 9,
            totalAmount: 321.45,
            countedCash: 350.0,
            variance: 0.0,
          ),
        );
        await _pumpPage(tester, repository: repository, canViewReport: false);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('shift-handover-button')));
        await tester.pumpAndSettle();

        // Blind cash count invariants: system expected cash and variance MUST NOT be shown
        expect(find.text('系统金额'), findsNothing);
        expect(find.text('差额'), findsNothing);
        expect(find.text('盲盘交班'), findsNWidgets(2));
        expect(find.text('订单数'), findsOneWidget);
        expect(find.text('7 笔'), findsNWidgets(2));
        expect(find.text('班次开始'), findsOneWidget);
        expect(find.text('07-21 09:30'), findsOneWidget);
        expect(find.text('班次截至'), findsOneWidget);
        expect(find.textContaining('盲盘机制'), findsOneWidget);
        await expectLater(
          find.byType(CashierDialogFrame),
          matchesGoldenFile(
            '../design/visual-verification/UI013/production/blind-count-dialog-1280.png',
          ),
        );

        // Denomination helper toggle
        expect(
          find.byKey(const Key('toggle-denominations-button')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('toggle-denominations-button')));
        await tester.pumpAndSettle();
        expect(find.text('面额快捷点钞（张/枚数）：'), findsOneWidget);
        expect(find.text('100元: '), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('shift-cash-input')),
          '350',
        );
        await tester.pump();

        expect(find.textContaining('¥ 350.00'), findsOneWidget);

        await tester.tap(find.byKey(const Key('shift-cash-submit-button')));
        await tester.pumpAndSettle();
        expect(find.text('确认提交交班'), findsOneWidget);
        await tester.tap(find.byKey(const Key('shift-cash-submit-button')));
        await tester.pumpAndSettle();

        expect(repository.handoverCalls, 1);
        expect(find.text('交班完成'), findsOneWidget);
        expect(find.text('9 笔'), findsOneWidget);
        expect(find.text('¥ 321.45'), findsOneWidget);
        expect(find.textContaining('¥ 350.00'), findsOneWidget);
        expect(
          find.byKey(const Key('handover-view-report-button')),
          findsOneWidget,
        );

        // Open shift report
        await tester.tap(find.byKey(const Key('handover-view-report-button')));
        await tester.pumpAndSettle();
        expect(find.textContaining('钱箱班次 #'), findsOneWidget);
        expect(find.text('现金恒等式'), findsOneWidget);
        expect(find.text('期初备用金'), findsOneWidget);
        expect(find.text('返回工作台'), findsOneWidget);
        await expectLater(
          find.byType(CashierShiftDetailPage),
          matchesGoldenFile(
            '../design/visual-verification/UI013/production/shift-detail-1280.png',
          ),
        );
        await tester.tap(find.text('返回工作台'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'shift report renders transaction detail sections (sales/change/dish ops)',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          shift: CashierShift.fromJson({
            'id': 1,
            'start_time': '2026-07-21T09:30:00',
            'start_cash': 100,
            'order_count': 7,
            'total_amount': 300,
          }),
          handoverResult: const CashierHandoverResult(
            sessionId: 10,
            drawerSessionId: 10,
            orderCount: 9,
            totalAmount: 321.45,
            countedCash: 350.0,
            variance: 0.0,
          ),
          shiftReport: const ShiftSummaryReport(
            sessionId: 10,
            state: 'CLOSED',
            operatorName: '李敏',
            openingFloat: 200,
            cashSales: 1000,
            variance: 0,
            orderSalesSummary: const ShiftOrderSalesSummary(
              paidOrderCount: 5,
              grossSales: 1500,
              discount: 20,
              refund: 15,
              giftPaid: 8,
              netSales: 1457,
            ),
            changeSummary: const ShiftChangeSummary(
              totalChange: 45,
              byChannel: {'cash': 35, 'wechat': 10},
            ),
            dishOperations: const ShiftDishOperations(
              refundDishCount: 3,
              refundDishAmount: 36,
              giveDishCount: 2,
            ),
          ),
        );
        await _pumpPage(tester, repository: repository, canViewReport: false);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('shift-handover-button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('shift-cash-input')),
          '350',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('shift-cash-submit-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('shift-cash-submit-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('handover-view-report-button')));
        await tester.pumpAndSettle();

        // 交易明细：订单销售汇总
        expect(find.text('交易明细'), findsOneWidget);
        expect(find.text('已结订单 5 单 · 总营收 ¥ 1500.00'), findsOneWidget);
        expect(find.text('总营收（订单原价）'), findsOneWidget);
        expect(find.text('¥ 1500.00'), findsOneWidget);
        expect(find.text('优惠金额'), findsOneWidget);
        expect(find.text('退款金额'), findsOneWidget);
        expect(find.text('赠送金实付'), findsOneWidget);
        expect(find.text('净营收'), findsOneWidget);
        // 现金找零
        expect(find.text('现金找零'), findsNWidgets(2)); // 区块标题 + 现金找零渠道行
        expect(find.text('找零合计'), findsOneWidget);
        expect(find.text('微信找零'), findsOneWidget);
        // 退菜/赠菜
        expect(find.text('退菜 / 赠菜'), findsOneWidget);
        expect(find.text('退菜'), findsOneWidget);
        expect(find.text('3 道'), findsOneWidget);
        expect(find.text('赠菜'), findsOneWidget);
        expect(find.text('2 道'), findsOneWidget);
      },
    );

    testWidgets(
      'cash movement dialog records CASH_IN, CASH_OUT, and CASH_DROP',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          shift: CashierShift.fromJson({
            'id': 1,
            'start_time': '2026-07-21T09:30:00',
            'start_cash': 100,
            'order_count': 2,
            'total_amount': 80,
          }),
        );
        await _pumpPage(tester, repository: repository, canViewReport: false);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('cash-movement-open-button')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('cash-movement-open-button')));
        await tester.pumpAndSettle();

        expect(find.text('记录钱箱现金动作'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('cash-movement-amount-input')),
          '100',
        );
        await tester.enterText(
          find.byKey(const Key('cash-movement-remark-input')),
          '补充找零',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('cash-movement-confirm-button')));
        await tester.pumpAndSettle();

        expect(repository.cashMovementCalls, 1);
        expect(
          repository.recordedCashMovements.single['movementType'],
          'CASH_IN',
        );
        expect(repository.recordedCashMovements.single['amount'], 100.0);
        expect(repository.recordedCashMovements.single['remark'], '补充找零');
      },
    );

    testWidgets(
      'handover with >50 variance prompts manager approval with reason and password',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          shift: CashierShift.fromJson({
            'id': 1,
            'start_time': '2026-07-21T09:30:00',
            'start_cash': 100,
            'order_count': 5,
            'total_amount': 200,
          }),
        );
        // First handover call throws variance exceeding limit without approval
        repository.handoverCalls = 0;
        // Override handover behavior in test
        int handoverSubmitCount = 0;
        await _pumpPage(
          tester,
          repository: _VarianceApprovalFakeRepository(
            baseRepo: repository,
            onHandoverAttempt: (endCash, varianceReasonCode, approvedBy) {
              handoverSubmitCount++;
              if (approvedBy == null) {
                throw Exception('长短款超过50元，需要店长审批授权并填写原因');
              }
            },
          ),
          canViewReport: false,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('shift-handover-button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('shift-cash-input')),
          '100',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('shift-cash-submit-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('shift-cash-submit-button')));
        await tester.pumpAndSettle();

        // Manager authorization dialog should pop up
        expect(find.text('店长长短款差异授权审批'), findsOneWidget);
        expect(
          find.byKey(const Key('variance-reason-dropdown')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('variance-note-input')),
          '晚班点钞少50元，店长确认短款',
        );
        await tester.enterText(
          find.byKey(const Key('variance-manager-password-input')),
          'admin123',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('variance-approve-button')));
        await tester.pumpAndSettle();

        expect(handoverSubmitCount, 2);
        expect(find.text('交班完成'), findsOneWidget);
      },
    );

    testWidgets('shows daily settle card and settles through confirm dialog', (
      tester,
    ) async {
      final repository = _FakeCashierShiftRepository(
        shift: CashierShift.fromJson({'id': 1, 'start_cash': 100}),
        dailySummary: const CashierDailySummary(
          statDate: '2026-09-09',
          totalAmount: 5213,
          discountAmount: 186,
          refundAmount: 86.5,
          settled: false,
        ),
        dailyChannels: const {'wechat': 3210, 'alipay': 1540, 'cash': 463},
      );
      await _pumpPage(
        tester,
        repository: repository,
        canViewReport: false,
        canSettleDaily: true,
      );
      await tester.pumpAndSettle();

      expect(find.text('营业日关账与日结治理'), findsOneWidget);
      expect(find.text('未日结'), findsOneWidget);
      expect(find.text('未结桌台账单'), findsOneWidget);
      expect(find.text('进行中线上支付'), findsOneWidget);
      expect(find.text('待支付 0 · 未审批差异 0'), findsNothing);
      expect(find.text('长短款差异风控'), findsOneWidget);
      expect(find.text('营业日日结'), findsOneWidget);
      expect(find.text('当日 Z 报表'), findsOneWidget);
      expect(find.text('归档'), findsOneWidget);
      expect(find.byKey(const Key('daily-close-open-button')), findsOneWidget);
      expect(repository.dailyLoads, 2);

      await tester.ensureVisible(
        find.byKey(const Key('daily-close-open-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('daily-close-open-button')));
      await tester.pumpAndSettle();

      expect(find.text('日结中心'), findsOneWidget);
      expect(find.text('支付渠道核对'), findsOneWidget);
      expect(find.text('微信支付'), findsOneWidget);
      expect(find.text('运行预检并日结'), findsOneWidget);
      await expectLater(
        find.byType(CashierDailyClosePage),
        matchesGoldenFile(
          '../design/visual-verification/UI013/production/daily-close-1280.png',
        ),
      );

      await tester.ensureVisible(find.text('运行预检并日结'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('运行预检并日结'));
      await tester.pumpAndSettle();
      expect(find.text('营业日日结关账执行确认'), findsOneWidget);
      expect(find.text('全日已结订单数'), findsOneWidget);
      expect(find.text('42 笔'), findsNWidgets(2));
      expect(find.text('全日全渠道净营收'), findsOneWidget);
      expect(find.text('¥ 5126.50'), findsNWidgets(2));
      expect(find.text('累计现金实收'), findsOneWidget);
      expect(find.text('¥ 1916.50'), findsNWidgets(2));
      expect(find.text('管理二次验证'), findsOneWidget);
      expect(find.text('确认关账并生成 Z 报表'), findsOneWidget);
      await expectLater(
        find.byType(CashierDialogFrame),
        matchesGoldenFile(
          '../design/visual-verification/UI013/production/daily-close-confirm-dialog-1280.png',
        ),
      );

      await tester.enterText(
        find.byKey(const Key('cashier-daily-settle-password-input')),
        'admin123',
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('cashier-daily-settle-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(repository.verifyPasswordCalls, 1);
      expect(repository.settleCalls, 1);
      expect(find.text('Z 报表'), findsOneWidget);
      expect(find.text('关账快照已锁定'), findsOneWidget);
      expect(find.byKey(const Key('print-z-report-button')), findsOneWidget);
      await expectLater(
        find.byType(CashierZReportPage),
        matchesGoldenFile(
          '../design/visual-verification/UI013/production/z-report-1280.png',
        ),
      );

      await tester.tap(find.text('返回日结中心'));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'daily settle blocks when precheck blockers exist and displays blockers dialog',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          dailySummary: const CashierDailySummary(
            statDate: '2026-09-09',
            totalAmount: 5213,
            discountAmount: 186,
            refundAmount: 86.5,
            settled: false,
          ),
          dailyChannels: const {'wechat': 3210, 'alipay': 1540, 'cash': 463},
        );
        // Mock precheck having an unclosed drawer session blocker
        repository.precheckResult = const DailyPrecheckResult(
          canSettle: false,
          isAlreadySettled: false,
          statDate: '2026-09-09',
          blockers: [
            DailyPrecheckBlocker(
              code: 'OPEN_DRAWER_SESSIONS',
              message: '当前门店仍有 1 个钱箱处于开班状态，必须先完成交班关箱',
              count: 1,
            ),
          ],
        );

        await _pumpPage(
          tester,
          repository: repository,
          canViewReport: false,
          canSettleDaily: true,
          currentAccount: 'manager_lee',
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('daily-close-open-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('daily-close-open-button')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('运行预检并日结'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('运行预检并日结'));
        await tester.pumpAndSettle();

        expect(repository.precheckCalls, 2);
        expect(find.text('日结预检未通过'), findsOneWidget);
        expect(find.text('OPEN_DRAWER_SESSIONS'), findsNWidgets(2));
        expect(find.textContaining('必须先完成交班关箱'), findsNWidgets(2));
        expect(find.text('我知道了'), findsOneWidget);
        expect(repository.settleCalls, 0);

        await tester.tap(find.text('我知道了'));
        await tester.pumpAndSettle();
        expect(find.text('日结预检未通过'), findsNothing);
      },
    );

    testWidgets(
      'daily settle blocker dialog displays void stale takeout button and invokes voiding (WI-036)',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          dailySummary: const CashierDailySummary(
            statDate: '2026-09-09',
            totalAmount: 5213,
            discountAmount: 186,
            refundAmount: 86.5,
            settled: false,
          ),
          dailyChannels: const {'wechat': 3210, 'alipay': 1540, 'cash': 463},
        );
        repository.precheckResult = const DailyPrecheckResult(
          canSettle: false,
          isAlreadySettled: false,
          statDate: '2026-09-09',
          blockers: [
            DailyPrecheckBlocker(
              code: 'OPEN_ORDERS',
              message: '存在 2 笔未完成订单，禁止关账',
              count: 2,
              voidablePackTakeout: VoidableStalePackTakeoutSummary(
                count: 2,
                amount: 56.0,
                thresholdMinutes: 30,
                orders: [
                  VoidableStaleOrderInfo(
                    id: 101,
                    orderNo: 'ORD-1001',
                    orderTime: '2026-09-09 20:00:00',
                    settAmount: 30.0,
                    ageMinutes: 45,
                    dineInOrTakeOut: 'PACK',
                  ),
                  VoidableStaleOrderInfo(
                    id: 102,
                    orderNo: 'ORD-1002',
                    orderTime: '2026-09-09 20:10:00',
                    settAmount: 26.0,
                    ageMinutes: 35,
                    dineInOrTakeOut: 'PACK',
                  ),
                ],
              ),
            ),
          ],
        );

        await _pumpPage(
          tester,
          repository: repository,
          canViewReport: false,
          canSettleDaily: true,
          currentAccount: 'manager_lee',
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('daily-close-open-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('daily-close-open-button')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('运行预检并日结'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('运行预检并日结'));
        await tester.pumpAndSettle();

        // Check blockers dialog appears with voidable takeout section
        expect(find.text('日结预检未通过'), findsOneWidget);
        expect(find.textContaining('超时未支付打包/外卖单'), findsOneWidget);
        expect(find.textContaining('¥ 56.00'), findsWidgets);

        final voidButton = find.byKey(
          const Key('precheck-void-stale-takeout-button'),
        );
        expect(voidButton, findsOneWidget);

        // Click void button -> confirm dialog pops up
        await tester.tap(voidButton);
        await tester.pumpAndSettle();

        expect(find.text('作废超时打包外卖订单'), findsOneWidget);
        expect(find.text('确认全部作废'), findsOneWidget);

        // Confirm voiding
        await tester.tap(find.text('确认全部作废'));
        await tester.pumpAndSettle();

        expect(repository.voidStaleTakeoutCalls, 1);
      },
    );

    testWidgets(
      'daily settle blocks on wrong password and displays error message',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          dailySummary: const CashierDailySummary(
            statDate: '2026-09-09',
            totalAmount: 5213,
            discountAmount: 186,
            refundAmount: 86.5,
            settled: false,
          ),
          dailyChannels: const {'wechat': 3210, 'alipay': 1540, 'cash': 463},
        );
        await _pumpPage(
          tester,
          repository: repository,
          canViewReport: false,
          canSettleDaily: true,
          currentAccount: 'manager_lee',
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('daily-close-open-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('daily-close-open-button')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('运行预检并日结'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('运行预检并日结'));
        await tester.pumpAndSettle();

        expect(find.text('当前账号: manager_lee'), findsOneWidget);

        // 1. Empty password check
        await tester.tap(
          find.byKey(const Key('cashier-daily-settle-confirm-button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('请输入管理员密码'), findsOneWidget);
        expect(repository.verifyPasswordCalls, 0);
        expect(repository.settleCalls, 0);

        // 2. Wrong password check
        await tester.enterText(
          find.byKey(const Key('cashier-daily-settle-password-input')),
          'wrongpassword',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('cashier-daily-settle-confirm-button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('密码错误，请重新输入'), findsOneWidget);
        expect(repository.verifyPasswordCalls, 1);
        expect(repository.settleCalls, 0);
        expect(find.textContaining('确认日结'), findsWidgets);
      },
    );

    testWidgets(
      'daily settle displays active shift warning when a shift is currently open',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          shift: CashierShift.fromJson({
            'id': 101,
            'shop_id': 2,
            'cashier_name': '张三',
            'start_cash': 500.0,
          }),
          dailySummary: const CashierDailySummary(
            statDate: '2026-09-09',
            totalAmount: 5213,
            discountAmount: 186,
            refundAmount: 86.5,
            settled: false,
          ),
        );
        await _pumpPage(
          tester,
          repository: repository,
          canViewReport: false,
          canSettleDaily: true,
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('daily-close-open-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('daily-close-open-button')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('运行预检并日结'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('运行预检并日结'));
        await tester.pumpAndSettle();

        expect(find.textContaining('当前有正在当班的收银员（班次 #101'), findsOneWidget);
      },
    );

    testWidgets(
      'uses the dashboard business day date as the daily settlement date',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          report: CashierTodayReport.fromJson({
            'businessDay': {
              'businessDayDate': '2026-09-09',
              'startTime': '2026-09-09T16:00:00+08:00',
              'endTime': '2026-09-10T04:00:00+08:00',
            },
          }),
        );
        await _pumpPage(
          tester,
          repository: repository,
          canViewReport: true,
          canSettleDaily: true,
        );
        await tester.pumpAndSettle();

        expect(repository.dailyStatDates, ['2026-09-09', '2026-09-09']);
      },
    );

    testWidgets('hides daily settle card without permission', (tester) async {
      final repository = _FakeCashierShiftRepository();
      await _pumpPage(tester, repository: repository, canViewReport: false);
      await tester.pumpAndSettle();

      expect(find.text('营业日关账与日结治理'), findsNothing);
      expect(find.byKey(const Key('daily-close-open-button')), findsNothing);
      expect(repository.dailyLoads, 0);
    });

    testWidgets('shows error state and retries when loadTodayReport fails', (
      tester,
    ) async {
      final repository = _FakeCashierShiftRepository(
        shift: CashierShift.fromJson({
          'id': 1,
          'start_cash': 100,
          'order_count': 3,
          'total_amount': 90.5,
        }),
      );
      repository.reportError = Exception('网络超时，请检查服务');

      await _pumpPage(
        tester,
        repository: repository,
        canViewReport: true,
        canSettleDaily: false,
        surfaceSize: const Size(1280, 1000),
      );
      await tester.pumpAndSettle();

      expect(find.text('今日支付渠道概览'), findsOneWidget);
      expect(find.text('支付渠道概览加载失败'), findsOneWidget);
      expect(find.textContaining('网络超时'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('重试'), findsOneWidget);

      // Resolve error and click retry
      repository.reportError = null;
      repository.report = CashierTodayReport.fromJson({
        'businessDay': {
          'todayRevenue': 500,
          'todayPaidOrderCount': 2,
          'todayOrderCount': 2,
          'revenueByPayChannel': [
            {'channelCode': 'cash', 'channelLabel': '现金', 'amount': 123.45},
          ],
        },
      });

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('支付渠道概览加载失败'), findsNothing);
      expect(find.text('现金'), findsOneWidget);
      expect(find.text('¥ 123.45'), findsOneWidget);
    });

    testWidgets(
      'falls back to daily channels when report fails but daily summary is available',
      (tester) async {
        final repository = _FakeCashierShiftRepository(
          shift: CashierShift.fromJson({
            'id': 1,
            'start_cash': 100,
            'order_count': 3,
            'total_amount': 90.5,
          }),
          dailyChannels: {'wechat': 250.0, 'alipay': 150.0},
        );
        repository.reportError = Exception('看板服务500');

        await _pumpPage(
          tester,
          repository: repository,
          canViewReport: true,
          canSettleDaily: true,
        );
        await tester.pumpAndSettle();

        expect(find.text('今日支付渠道概览'), findsOneWidget);
        expect(find.textContaining('实时看板暂不可用，已自动切换至日结对账通道数据'), findsOneWidget);
        expect(find.text('微信支付'), findsOneWidget);
        expect(find.text('¥ 250.00'), findsOneWidget);
        expect(find.text('支付宝'), findsOneWidget);
        expect(find.text('¥ 150.00'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );
  });
}

void _expectGovernanceCardsAligned(WidgetTester tester) {
  final drawer = tester.getRect(
    find.byKey(const Key('cashier-drawer-governance-card')),
  );
  final daily = tester.getRect(
    find.byKey(const Key('cashier-daily-close-governance-card')),
  );
  expect((drawer.width - daily.width).abs(), lessThan(0.01));
  expect((drawer.height - daily.height).abs(), lessThan(0.01));
  expect((drawer.top - daily.top).abs(), lessThan(0.01));
  expect((drawer.bottom - daily.bottom).abs(), lessThan(0.01));
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required CashierShiftRepository repository,
  required bool canViewReport,
  bool canSettleDaily = false,
  String? currentAccount,
  Size surfaceSize = const Size(1280, 800),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: CashierAppTheme.light(),
      home: Scaffold(
        body: CashierShiftPage(
          repository: repository,
          canViewReport: canViewReport,
          canSettleDaily: canSettleDaily,
          shopId: 2,
          currentAccount: currentAccount,
          now: () => DateTime(2026, 10, 3, 17, 30),
        ),
      ),
    ),
  );
}

class _FakeCashierShiftRepository implements CashierShiftRepository {
  _FakeCashierShiftRepository({
    this.shift,
    this.report,
    this.shiftReport,
    this.handoverResult = const CashierHandoverResult(
      orderCount: 0,
      totalAmount: 0,
    ),
    this.dailySummary = const CashierDailySummary(
      statDate: '2026-09-09',
      totalAmount: 0,
      discountAmount: 0,
      refundAmount: 0,
      settled: false,
    ),
    this.dailyChannels = const {},
  });

  ShiftSummaryReport? shiftReport;

  CashierShift? shift;
  CashierTodayReport? report;
  CashierHandoverResult handoverResult;
  CashierDailySummary dailySummary = const CashierDailySummary(
    statDate: '2026-09-09',
    totalAmount: 0,
    discountAmount: 0,
    refundAmount: 0,
    settled: false,
  );
  Map<String, double> dailyChannels = const {};
  int reportLoads = 0;
  Object? reportError;
  int handoverCalls = 0;
  int dailyLoads = 0;
  final List<String> dailyStatDates = [];
  int settleCalls = 0;
  String validPassword = 'admin123';
  int verifyPasswordCalls = 0;

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {
    verifyPasswordCalls++;
    if (password != validPassword) {
      throw Exception('密码错误，请重新输入');
    }
  }

  @override
  Future<CashierShift?> loadCurrentShift() async => shift;

  CashierShiftWorkbenchData workbench = const CashierShiftWorkbenchData(
    businessDay: '2026-09-09',
  );
  CashierShiftReportPage shiftReports = const CashierShiftReportPage();
  CashierCashEventPage cashEvents = const CashierCashEventPage();
  CashierZReportHistoryPage zReports = const CashierZReportHistoryPage();

  @override
  Future<CashierShiftWorkbenchData> loadWorkbench({int? shopId}) async =>
      workbench;

  @override
  Future<CashierTodayReport> loadTodayReport({int? shopId}) async {
    reportLoads++;
    if (reportError != null) {
      throw reportError!;
    }
    return report ?? const CashierTodayReport();
  }

  @override
  Future<CashierShift> startShift({
    required double startCash,
    int? shopId,
    String? idempotencyKey,
  }) async {
    return shift = CashierShift.fromJson({
      'id': 2,
      'shop_id': shopId,
      'start_cash': startCash,
    });
  }

  @override
  Future<CashierHandoverResult> handover({
    required double endCash,
    double? countedCash,
    String? varianceReasonCode,
    String? varianceNote,
    int? approvedBy,
    int? shopId,
    String? idempotencyKey,
  }) async {
    handoverCalls++;
    shift = null;
    return handoverResult;
  }

  int cashMovementCalls = 0;
  final List<Map<String, Object?>> recordedCashMovements = [];

  @override
  Future<void> recordCashMovement({
    required String movementType,
    required double amount,
    String? reasonCode,
    String? remark,
    int? approverId,
    int? shopId,
    String? idempotencyKey,
  }) async {
    cashMovementCalls++;
    recordedCashMovements.add({
      'movementType': movementType,
      'amount': amount,
      'reasonCode': reasonCode,
      'remark': remark,
      'approverId': approverId,
      'shopId': shopId,
    });
  }

  @override
  Future<ShiftSummaryReport> loadShiftReport(
    int sessionId, {
    int? shopId,
  }) async {
    if (shiftReport != null) return shiftReport!;
    return ShiftSummaryReport(
      sessionId: sessionId,
      state: 'CLOSED',
      operatorName: '李敏',
      terminalName: '前台收银机',
      drawerName: '前台 A',
      businessDay: '2026-09-09',
      openedAt: DateTime(2026, 9, 9, 9),
      closedAt: DateTime(2026, 9, 9, 17, 30),
      durationSeconds: 30600,
      openingFloat: 200,
      expectedCash: 800,
      countedCash: 800,
      variance: 0,
      approvalStatus: 'NOT_REQUIRED',
      integrity: const {
        'version': 3,
        'status': 'VERIFIED',
        'report_hash': '8b7d5b271f2a4c88',
      },
      auditEvents: [
        CashierCashEvent(
          eventId: 1,
          type: 'OPENING_FLOAT',
          amount: 200,
          occurredAt: DateTime(2026, 9, 9, 9),
          operatorName: '李敏',
          referenceNo: 'CM-0001',
        ),
      ],
    );
  }

  @override
  Future<CashierShiftReportPage> loadShiftReports({
    int? shopId,
    int? cursor,
    int limit = 20,
  }) async => shiftReports;

  @override
  Future<CashierCashEventPage> loadCashEvents(
    int sessionId, {
    int? shopId,
    int? cursor,
    int limit = 20,
  }) async => cashEvents;

  @override
  Future<CashierDailySummary> loadDailySummary({
    String? statDate,
    int? shopId,
  }) async {
    dailyLoads++;
    if (statDate != null) dailyStatDates.add(statDate);
    return dailySummary;
  }

  @override
  Future<Map<String, double>> loadDailyChannels({
    String? statDate,
    int? shopId,
  }) async {
    dailyLoads++;
    if (statDate != null) dailyStatDates.add(statDate);
    return dailyChannels;
  }

  DailyPrecheckResult precheckResult = DailyPrecheckResult(
    canSettle: true,
    isAlreadySettled: false,
    statDate: '2026-09-09',
    blockers: [],
    warnings: [],
    precheckToken: 'test-precheck-token',
    precheckExpiresAt: DateTime(2026, 9, 9, 18),
    watermarks: const {
      'payment_ledger_id': 8921,
      'cash_event_id': 3384,
      'order_id': 16820,
    },
    preview: const {
      'gross_sales_fen': 539900,
      'discount_amount_fen': 18600,
      'refund_amount_fen': 8650,
      'net_sales_fen': 512650,
      'order_count': 42,
      'cash_variance_fen': 800,
      'channels': [
        {
          'code': 'wechat',
          'label': '微信支付',
          'success_count': 28,
          'refund_count': 1,
          'net_amount_fen': 321000,
        },
        {
          'code': 'cash',
          'label': '现金',
          'success_count': 14,
          'refund_count': 0,
          'net_amount_fen': 191650,
        },
      ],
    },
  );
  int precheckCalls = 0;
  int zReportCalls = 0;

  @override
  Future<DailyPrecheckResult> loadDailyContext({
    String? statDate,
    int? shopId,
    int? minutes,
  }) => precheckDaily(statDate: statDate, shopId: shopId, minutes: minutes);

  @override
  Future<DailyPrecheckResult> precheckDaily({
    String? statDate,
    int? shopId,
    int? minutes,
  }) async {
    precheckCalls++;
    return precheckResult;
  }

  int voidStaleTakeoutCalls = 0;
  VoidStaleTakeoutResult voidStaleTakeoutResult = const VoidStaleTakeoutResult(
    voidedCount: 2,
    voidedAmount: 56.0,
    thresholdMinutes: 30,
    voidedOrderNos: ['ORD-1001', 'ORD-1002'],
  );

  @override
  Future<VoidStaleTakeoutResult> voidStaleTakeoutOrders({
    String? statDate,
    int? shopId,
    int? minutes,
  }) async {
    voidStaleTakeoutCalls++;
    return voidStaleTakeoutResult;
  }

  @override
  Future<CommercialZReport> loadZReport({String? statDate, int? shopId}) async {
    zReportCalls++;
    return CommercialZReport(
      reportType: 'Z_REPORT',
      isClosed: true,
      shopId: shopId ?? 1,
      shopName: '测试收银门店',
      businessDay: statDate ?? '2026-09-09',
      totalSales: 5399,
      discountAmount: 186,
      refundAmount: 86.5,
      netSales: 5213,
      orderCount: 42,
      channels: const {'cash': 560.3, 'wechat': 4652.7},
      totalCashVariance: 0,
      totalAdjustment: 0,
      adjustedNetSales: 5213,
      printableText: 'Z-REPORT TEST',
    );
  }

  @override
  Future<CashierZReportHistoryPage> loadZReports({
    int? shopId,
    String? dateFrom,
    String? dateTo,
    Object? cursor,
    int limit = 20,
  }) async => zReports;

  @override
  Future<Map<String, Object?>> reopenDaily({
    String? statDate,
    int? shopId,
    required String password,
    required String reason,
  }) async {
    dailySummary = CashierDailySummary(
      statDate: statDate ?? dailySummary.statDate,
      totalAmount: 5213,
      discountAmount: 186,
      refundAmount: 86.5,
      settled: false,
    );
    return {'reopened': true};
  }

  @override
  Future<CashierDailySettleResult> settleDaily({
    String? statDate,
    int? shopId,
    String? precheckToken,
    String? password,
    bool force = false,
    String? idempotencyKey,
  }) async {
    settleCalls++;
    final resolvedDate = statDate ?? dailySummary.statDate;
    dailySummary = CashierDailySummary(
      statDate: resolvedDate,
      totalAmount: 5213,
      discountAmount: 186,
      refundAmount: 86.5,
      settled: true,
      settledAt: DateTime(2026, 9, 10, 2, 5),
    );
    return CashierDailySettleResult(
      statDate: resolvedDate,
      totalAmount: 5213,
      discountAmount: 186,
      refundAmount: 86.5,
      settledAt: DateTime(2026, 9, 10, 2, 5),
    );
  }

  int? reprintedShiftId;

  @override
  Future<void> reprintShiftTicket(int shiftId) async {
    reprintedShiftId = shiftId;
  }
}

class _VarianceApprovalFakeRepository implements CashierShiftRepository {
  _VarianceApprovalFakeRepository({
    required this.baseRepo,
    required this.onHandoverAttempt,
  });

  final _FakeCashierShiftRepository baseRepo;
  final void Function(
    double endCash,
    String? varianceReasonCode,
    int? approvedBy,
  )
  onHandoverAttempt;

  @override
  Future<CashierShift?> loadCurrentShift() => baseRepo.loadCurrentShift();

  @override
  Future<CashierShiftWorkbenchData> loadWorkbench({int? shopId}) =>
      baseRepo.loadWorkbench(shopId: shopId);

  @override
  Future<CashierTodayReport> loadTodayReport({int? shopId}) =>
      baseRepo.loadTodayReport(shopId: shopId);

  @override
  Future<CashierShift> startShift({
    required double startCash,
    int? shopId,
    String? idempotencyKey,
  }) => baseRepo.startShift(
    startCash: startCash,
    shopId: shopId,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<CashierHandoverResult> handover({
    required double endCash,
    double? countedCash,
    String? varianceReasonCode,
    String? varianceNote,
    int? approvedBy,
    int? shopId,
    String? idempotencyKey,
  }) async {
    onHandoverAttempt(endCash, varianceReasonCode, approvedBy);
    return baseRepo.handover(
      endCash: endCash,
      countedCash: countedCash,
      varianceReasonCode: varianceReasonCode,
      varianceNote: varianceNote,
      approvedBy: approvedBy,
      shopId: shopId,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<void> recordCashMovement({
    required String movementType,
    required double amount,
    String? reasonCode,
    String? remark,
    int? approverId,
    int? shopId,
    String? idempotencyKey,
  }) => baseRepo.recordCashMovement(
    movementType: movementType,
    amount: amount,
    reasonCode: reasonCode,
    remark: remark,
    approverId: approverId,
    shopId: shopId,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<ShiftSummaryReport> loadShiftReport(int sessionId, {int? shopId}) =>
      baseRepo.loadShiftReport(sessionId, shopId: shopId);

  @override
  Future<CashierShiftReportPage> loadShiftReports({
    int? shopId,
    int? cursor,
    int limit = 20,
  }) => baseRepo.loadShiftReports(shopId: shopId, cursor: cursor, limit: limit);

  @override
  Future<CashierCashEventPage> loadCashEvents(
    int sessionId, {
    int? shopId,
    int? cursor,
    int limit = 20,
  }) => baseRepo.loadCashEvents(
    sessionId,
    shopId: shopId,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<CashierDailySummary> loadDailySummary({
    String? statDate,
    int? shopId,
  }) => baseRepo.loadDailySummary(statDate: statDate, shopId: shopId);

  @override
  Future<Map<String, double>> loadDailyChannels({
    String? statDate,
    int? shopId,
  }) => baseRepo.loadDailyChannels(statDate: statDate, shopId: shopId);

  @override
  Future<DailyPrecheckResult> loadDailyContext({
    String? statDate,
    int? shopId,
    int? minutes,
  }) => baseRepo.loadDailyContext(
    statDate: statDate,
    shopId: shopId,
    minutes: minutes,
  );

  @override
  Future<DailyPrecheckResult> precheckDaily({
    String? statDate,
    int? shopId,
    int? minutes,
  }) => baseRepo.precheckDaily(
    statDate: statDate,
    shopId: shopId,
    minutes: minutes,
  );

  @override
  Future<VoidStaleTakeoutResult> voidStaleTakeoutOrders({
    String? statDate,
    int? shopId,
    int? minutes,
  }) => baseRepo.voidStaleTakeoutOrders(
    statDate: statDate,
    shopId: shopId,
    minutes: minutes,
  );

  @override
  Future<CommercialZReport> loadZReport({String? statDate, int? shopId}) =>
      baseRepo.loadZReport(statDate: statDate, shopId: shopId);

  @override
  Future<CashierZReportHistoryPage> loadZReports({
    int? shopId,
    String? dateFrom,
    String? dateTo,
    Object? cursor,
    int limit = 20,
  }) => baseRepo.loadZReports(
    shopId: shopId,
    dateFrom: dateFrom,
    dateTo: dateTo,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<Map<String, Object?>> reopenDaily({
    String? statDate,
    int? shopId,
    required String password,
    required String reason,
  }) => baseRepo.reopenDaily(
    statDate: statDate,
    shopId: shopId,
    password: password,
    reason: reason,
  );

  @override
  Future<CashierDailySettleResult> settleDaily({
    String? statDate,
    int? shopId,
    String? precheckToken,
    String? password,
    bool force = false,
    String? idempotencyKey,
  }) => baseRepo.settleDaily(
    statDate: statDate,
    shopId: shopId,
    precheckToken: precheckToken,
    password: password,
    force: force,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) => baseRepo.verifyPassword(username: username, password: password);

  @override
  Future<void> reprintShiftTicket(int shiftId) =>
      baseRepo.reprintShiftTicket(shiftId);
}
