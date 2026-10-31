import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/data/cashier_member_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/data/real_cashier_member_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/domain/cashier_member.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/presentation/cashier_member_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/presentation/member_consumption_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('CashierMember models', () {
    test('parses profile.user, metrics, and nested tags', () {
      final profile = CashierMemberProfile.fromJson({
        'profile': {
          'user': {
            'id': 7,
            'name': '王女士',
            'phone': '13800138000',
            'openid': 'wx-7',
            'user_type': 1,
            'birthday': '1990-01-02',
            'level': 2,
            'points': 88,
            'balance': 268.5,
          },
          'orderCount': 12,
          'totalAmount': 1234.56,
          'avgOrderValue': 102.88,
          'consume_amount': 2380.5,
          'last_consume_time': '2026-08-02 12:30:00',
          'invite_registered_count': 5,
          'available_coupon_count': 2,
          'basicTags': {'gender': '女', 'hasPhone': '是'},
          'behaviorTags': {'consumeFrequency': '每月2-3次'},
          'dishTags': {
            'preferredCategories': ['烤串类', '酒水饮料'],
          },
          'valueTier': '高价值会员（重点维护）',
        },
      });

      expect(profile.member.id, 7);
      expect(profile.member.level, 2);
      expect(profile.member.balance, 268.5);
      expect(profile.orderCount, 12);
      expect(profile.totalAmount, 1234.56);
      expect(profile.avgOrderValue, 102.88);
      expect(profile.consumeAmount, 2380.5);
      expect(profile.lastConsumeTime, '2026-08-02 12:30:00');
      expect(profile.inviteRegisteredCount, 5);
      expect(profile.availableCouponCount, 2);
      expect(
        profile.tags,
        containsAll(['女', '是', '每月2-3次', '烤串类', '高价值会员（重点维护）']),
      );
    });

    test('parses consumption and recharge record snake_case fields', () {
      final consumption = MemberConsumptionRecord.fromJson({
        'id': 2,
        'order_no': 'ORD-2',
        'sett_amount': 88.8,
        'pay_time': '2026-07-20 12:30:00',
        'table_number': 'A08',
        'payment_method': 'wechat',
        'dineInOrTakeOut': '堂食',
      });
      final recharge = MemberRechargeRecord.fromJson({
        'id': 3,
        'order_no': 'RCH-3',
        'recharge_amount': 100,
        'gift_amount': 10,
        'total_amount': 110,
        'channel': 'admin',
        'status': 'success',
        'created_at': '2026-07-20 13:00:00',
      });

      expect(consumption.orderNo, 'ORD-2');
      expect(consumption.amount, 88.8);
      expect(consumption.orderType, '堂食');
      expect(recharge.principalAmount, 100);
      expect(recharge.giftAmount, 10);
      expect(recharge.totalAmount, 110);
    });

    test('calculates historical net consumption from order amount fields', () {
      final consumption = MemberConsumptionRecord.fromJson({
        'id': 4,
        'order_no': 'ORD-4',
        'sett_amount': 100,
        'discount_amount': 10,
        'service_fee': 5,
        'refund_amount': 2,
        'pay_amount_gift': 3,
      });

      expect(consumption.amount, 90);
    });

    test('parses member row with level, balance and last consume time', () {
      final row = CashierMemberRow.fromJson({
        'id': 7,
        'name': '张晓雯',
        'phone': '13800138000',
        'level': 2,
        'user_type': 1,
        'points': 3200,
        'balance': 520.5,
        'consume_amount': 2380,
        'last_consume_time': '2026-08-02 12:30:00',
      });

      expect(row.id, 7);
      expect(row.name, '张晓雯');
      expect(row.level, 2);
      expect(row.points, 3200);
      expect(row.balance, 520.5);
      expect(row.consumeAmount, 2380);
      expect(row.lastConsumeTime, '2026-08-02 12:30:00');
    });

    test('parses member stats and coupon template', () {
      final stats = CashierMemberStats.fromJson({
        'memberCount': 1286,
        'todayNewCount': 12,
        'totalBalance': 86400,
        'totalPoints': 42860,
      });
      final coupon = CashierCoupon.fromJson({
        'id': 9,
        'coupon_name': '满100减20',
        'coupon_type': 'full_reduction',
        'discount_value': 20,
        'min_amount': 100,
        'end_time': '2026-09-30 23:59:59',
        'status': 1,
      });

      expect(stats.memberCount, 1286);
      expect(stats.todayNewCount, 12);
      expect(stats.totalBalance, 86400);
      expect(stats.totalPoints, 42860);
      expect(coupon.isUsable, isTrue);
      expect(coupon.summary, '满100减20');
    });

    test('masks phones and maps level labels to the design tiers', () {
      expect(maskedPhone('13800138000'), '138****8000');
      expect(maskedPhone('13800'), '13800');
      expect(memberLevelLabel(0), '普通会员');
      expect(memberLevelLabel(1), '白银会员');
      expect(memberLevelLabel(2), '黄金会员');
      expect(memberLevelLabel(3), '铂金会员');
      expect(memberLevelLabel(null), '—');
      expect(memberLevelLabel(99), '—');
    });
  });

  group('RealCashierMemberRepository', () {
    late FakeHttpTransport transport;
    late RealCashierMemberRepository repository;

    setUp(() {
      transport = FakeHttpTransport({
        'GET /admin/member/profile': jsonEncode({
          'code': 0,
          'profile': {
            'user': {
              'id': 7,
              'name': '王女士',
              'phone': '13800138000',
              'openid': 'wx-7',
              'level': 2,
              'points': 88,
              'balance': 268.5,
            },
            'orderCount': 12,
            'totalAmount': 1234.56,
            'avgOrderValue': 102.88,
            'valueTier': '高价值会员（重点维护）',
          },
        }),
        'GET /admin/member/consumption': jsonEncode({
          'code': 0,
          'list': [
            {
              'id': 2,
              'order_no': 'ORD-2',
              'sett_amount': 88.8,
              'dineInOrTakeOut': '堂食',
            },
          ],
        }),
        'GET /admin/orderDetail/list': jsonEncode({
          'code': 0,
          'data': {
            'orderDetailList': [
              {
                'id': 21,
                'name': '油边王',
                'quantity': '2',
                'unit': '份',
                'selectedSpicy': '微辣',
                'total_price': 30,
              },
            ],
          },
        }),
        'GET /admin/member/recharge/list': jsonEncode({
          'code': 0,
          'list': [
            {
              'id': 3,
              'order_no': 'RCH-3',
              'recharge_amount': 100,
              'gift_amount': 10,
              'total_amount': 110,
              'status': 'success',
            },
          ],
        }),
        'POST /admin/member/recharge': jsonEncode({
          'code': 0,
          'balance': 378.5,
        }),
        'POST /admin/order/reassignOpenidByPhone': jsonEncode({'code': 0}),
        'POST /admin/order/getUserInfo': jsonEncode({
          'code': 0,
          'user': [
            {
              'id': 7,
              'name': '张晓雯',
              'phone': '13800138000',
              'level': 2,
              'points': 3200,
              'balance': 520.5,
              'consume_amount': 2380,
              'last_consume_time': '2026-08-02 12:30:00',
            },
          ],
          'total': 25,
        }),
        'GET /admin/member/stats': jsonEncode({
          'code': 0,
          'memberCount': 1286,
          'todayNewCount': 12,
          'totalBalance': 86400,
          'totalPoints': 42860,
        }),
        'GET /admin/coupon/list': jsonEncode({
          'code': 0,
          'list': [
            {
              'id': 9,
              'coupon_name': '满100减20',
              'coupon_type': 'full_reduction',
              'discount_value': 20,
              'min_amount': 100,
              'end_time': '2026-09-30 23:59:59',
              'status': 1,
            },
          ],
          'total': 1,
        }),
        'POST /admin/coupon/batch-send': jsonEncode({
          'code': 0,
          'couponId': 9,
          'candidateUserCount': 1286,
          'openidReadyCount': 1200,
          'consumeMatchedCount': 1200,
          'targetUserCount': 1200,
          'grantedCount': 42,
        }),
      });
      repository = RealCashierMemberRepository(
        AdminApiClient(
          baseUrl: 'https://example.test',
          transport: transport,
          shopId: 9,
        ),
      );
    });

    test('loads profile and both histories using phone query', () async {
      final profile = await repository.loadProfile('13800138000');
      final consumption = await repository.loadConsumption('13800138000');
      final recharges = await repository.loadRecharges('13800138000');

      expect(profile.member.name, '王女士');
      expect(profile.member.level, 2);
      expect(consumption.single.orderNo, 'ORD-2');
      expect(recharges.single.orderNo, 'RCH-3');
      for (final request in transport.requests) {
        expect(request.uri.queryParameters['phone'], '13800138000');
        expect(request.uri.queryParameters, isNot(contains('openid')));
      }
    });

    test('loads the selected consumption order details by order id', () async {
      final record = (await repository.loadConsumption('13800138000')).single;

      final detail = await repository.loadConsumptionDetail(record);

      expect(detail.record.orderNo, 'ORD-2');
      expect(detail.lines.single.name, '油边王');
      expect(detail.lines.single.quantity, 2);
      expect(detail.lines.single.unitPrice, 15);
      final request = transport.requests.singleWhere(
        (item) => item.uri.path == '/admin/orderDetail/list',
      );
      expect(request.uri.queryParameters['id'], '2');
    });

    test('rejects principal below 50 without sending a request', () async {
      await expectLater(
        repository.recharge(phone: '13800138000', amount: 49.99, giftAmount: 0),
        throwsArgumentError,
      );

      expect(transport.requests, isEmpty);
    });

    test('posts exact recharge and order binding contract fields', () async {
      final result = await repository.recharge(
        phone: '13800138000',
        amount: 100,
        giftAmount: 10,
      );
      await repository.bindOrder(orderId: 42, phone: '13800138000');

      expect(result.newBalance, 378.5);
      expect(jsonDecode(transport.requests[0].body!), {
        'phone': '13800138000',
        'amount': 100.0,
        'gift_amount': 10.0,
      });
      expect(jsonDecode(transport.requests[1].body!), {
        'id': 42,
        'phone': '13800138000',
      });
    });

    test('loads paged member rows and total from getUserInfo', () async {
      final page = await repository.loadMembers(
        page: 1,
        pageSize: 20,
        query: '张',
      );

      expect(page.total, 25);
      expect(page.rows.single.name, '张晓雯');
      expect(page.rows.single.level, 2);
      expect(page.rows.single.lastConsumeTime, '2026-08-02 12:30:00');
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/admin/order/getUserInfo');
      expect(jsonDecode(request.body!), {
        'pageNum': 1,
        'pageSize': 20,
        'query': '张',
      });
    });

    test('loads member stats from /admin/member/stats', () async {
      final stats = await repository.loadStats();

      expect(stats.memberCount, 1286);
      expect(stats.todayNewCount, 12);
      expect(stats.totalBalance, 86400);
      expect(stats.totalPoints, 42860);
      final request = transport.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/admin/member/stats');
    });

    test('loads coupons and batch-sends the selected coupon', () async {
      final coupons = await repository.loadCoupons();

      expect(coupons.single.id, 9);
      expect(coupons.single.name, '满100减20');
      expect(coupons.single.isUsable, isTrue);

      final granted = await repository.batchSendCoupon(couponId: 9);

      expect(granted, 42);
      final sendRequest = transport.requests.last;
      expect(sendRequest.method, 'POST');
      expect(sendRequest.uri.path, '/admin/coupon/batch-send');
      expect(jsonDecode(sendRequest.body!), {'couponId': 9});
    });
  });

  group('CashierMemberPage', () {
    testWidgets('renders stats, member table, toolbar and pagination', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final repository = _FakeMemberRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: CashierMemberPage(
            repository: repository,
            permissions: const {'coupon:manage'},
            canRecharge: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 统计卡（真实接口数据）
      expect(find.text('会员总数'), findsOneWidget);
      expect(find.text('1,286'), findsOneWidget);
      expect(find.text('今日新增'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('储值总额'), findsOneWidget);
      expect(find.text('¥86,400.00'), findsOneWidget);
      expect(find.text('积分发放'), findsOneWidget);
      expect(find.text('42,860'), findsOneWidget);

      // 表格列头与行数据
      for (final header in ['姓名', '手机号', '等级', '储值余额', '积分', '操作']) {
        expect(find.text(header), findsOneWidget);
      }
      expect(find.text('张晓雯'), findsOneWidget);
      expect(find.text('138****8000'), findsOneWidget);
      expect(find.text('黄金会员'), findsOneWidget);
      expect(find.text('3,200'), findsOneWidget);

      // 工具栏按钮
      expect(find.byKey(const Key('member-search-button')), findsOneWidget);
      expect(find.byKey(const Key('member-batch-coupon-button')), findsOneWidget);
      expect(find.byKey(const Key('member-recharge-button')), findsOneWidget);
      expect(find.byKey(const Key('member-create-button')), findsOneWidget);

      // 分页
      expect(find.text('共 25 位会员 · 第 1/2 页'), findsOneWidget);
    });

    testWidgets('opens member detail and returns to the list', (tester) async {
      _useDesktopViewport(tester);
      final repository = _FakeMemberRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: CashierMemberPage(
            repository: repository,
            permissions: const {'coupon:manage'},
            canRecharge: true,
            canBindOrder: true,
            currentOrderId: 42,
            currentOrderNo: 'ORD-42',
            currentTableNumber: 'A08',
            currentOrderStatus: 'unsettled',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member-row-detail-7')));
      await tester.pumpAndSettle();

      // 图2 详情布局
      expect(find.text('会员详情'), findsOneWidget);
      expect(find.text('会员编号 VIP-7'), findsOneWidget);
      // 档案横幅（原「会员信息」卡升级为横幅，key 保留）
      expect(find.byKey(const Key('member-info-card')), findsOneWidget);
      expect(find.text('王女士'), findsOneWidget);
      expect(find.text('等级权益'), findsOneWidget);
      // 等级徽章（横幅）+ 等级权益指标卡 各一处
      expect(find.text('黄金会员'), findsNWidgets(2));
      expect(find.text('可用积分'), findsOneWidget);
      expect(find.text('88分'), findsOneWidget);
      // D023 消费统计卡（后端画像接口后期补齐字段，前端已就位）
      expect(find.byKey(const Key('member-stats-card')), findsOneWidget);
      expect(find.text('消费统计'), findsOneWidget);
      expect(find.text('累计消费'), findsOneWidget);
      expect(find.text('¥2,380.50'), findsOneWidget);
      expect(find.text('最近消费'), findsOneWidget);
      expect(find.text('2026-08-02'), findsOneWidget);
      expect(find.text('邀请注册'), findsOneWidget);
      expect(find.text('可用券'), findsOneWidget);
      expect(find.text('消费记录'), findsOneWidget);
      expect(find.text('充值记录'), findsOneWidget);
      // 消费/充值表实际列（时间/金额/支付方式/积分变动/余额变动；时间/充值金额/到账金额/当前余额）
      expect(find.text('¥88.80'), findsOneWidget);
      expect(find.text('+89'), findsOneWidget);
      expect(find.text('¥110.00'), findsOneWidget);
      // 指标卡「储值余额」+ 充值记录表首行「当前余额」各一处
      expect(find.text('¥268.50'), findsNWidgets(2));
      expect(find.text('2026-07-20'), findsNWidgets(2));
      // 保留能力：绑定当前订单 / 储值
      expect(find.text('绑定当前订单'), findsOneWidget);

      await tester.tap(find.byKey(const Key('member-back-button')));
      await tester.pumpAndSettle();

      expect(find.text('会员总数'), findsOneWidget);
      expect(repository.detailOpens, greaterThanOrEqualTo(1));
    });

    testWidgets('detail failure keeps back button and returns to list', (tester) async {
      _useDesktopViewport(tester);
      final repository = _FakeMemberRepository(missing: true);
      await tester.pumpWidget(
        MaterialApp(home: CashierMemberPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member-row-detail-7')));
      await tester.pumpAndSettle();

      // 服务器处理失败：错误态可见，且返回按钮仍可用
      expect(find.text('未找到该手机号对应的会员'), findsOneWidget);
      expect(find.byKey(const Key('member-back-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('member-back-button')));
      await tester.pumpAndSettle();
      expect(find.text('会员总数'), findsOneWidget);
    });

    testWidgets('hides coupon and recharge actions without permissions', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: CashierMemberPage(repository: _FakeMemberRepository()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('member-batch-coupon-button')), findsNothing);
      expect(find.byKey(const Key('member-recharge-button')), findsNothing);
      expect(find.byKey(const Key('member-search-button')), findsOneWidget);
      expect(find.byKey(const Key('member-create-button')), findsOneWidget);
    });

    testWidgets('searches members by keyword and paginates', (tester) async {
      _useDesktopViewport(tester);
      final repository = _FakeMemberRepository();
      await tester.pumpWidget(
        MaterialApp(home: CashierMemberPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('member-search-input')),
        '张',
      );
      await tester.tap(find.byKey(const Key('member-search-button')));
      await tester.pumpAndSettle();
      expect(repository.lastMemberQuery, '张');

      await tester.tap(find.byKey(const Key('member-next-page')));
      await tester.pumpAndSettle();
      expect(repository.lastMemberPage, 2);
    });

    testWidgets('late page response does not overwrite newer load', (tester) async {
      _useDesktopViewport(tester);
      final repository = _FakeMemberRepository();
      repository.delayPages[2] = const Duration(milliseconds: 300);
      await tester.pumpWidget(
        MaterialApp(home: CashierMemberPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      // 翻到第 2 页（慢请求）
      await tester.tap(find.byKey(const Key('member-next-page')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.lastMemberPage, 2);

      // 搜索抢占（新请求 page=1，快）
      await tester.enterText(
        find.byKey(const Key('member-search-input')),
        '张',
      );
      await tester.tap(find.byKey(const Key('member-search-button')));
      await tester.pumpAndSettle();
      expect(repository.lastMemberPage, 1);
      expect(find.textContaining('第 1/'), findsOneWidget);

      // 慢的第 2 页响应返回：修复前会覆盖回第 2 页，修复后被请求序号守卫丢弃
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repository.lastMemberPage, 1);
      expect(find.textContaining('第 1/'), findsOneWidget);
    });

    testWidgets('recharges by phone via the toolbar action', (tester) async {
      _useDesktopViewport(tester);
      final repository = _FakeMemberRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: CashierMemberPage(
            repository: repository,
            canRecharge: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member-recharge-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recharge-phone-input')),
        '13800138000',
      );
      await tester.tap(find.byKey(const Key('recharge-phone-resolve')));
      await tester.pumpAndSettle();

      expect(find.textContaining('王女士'), findsOneWidget);
      expect(find.textContaining('当前余额'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('recharge-amount-input')),
        '100',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认充值'));
      await tester.pumpAndSettle();

      expect(find.text('充值成功'), findsOneWidget);
      expect(find.text('最新余额'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(repository.lastRechargePhone, '13800138000');
    });

    testWidgets('batch-sends a selected coupon', (tester) async {
      _useDesktopViewport(tester);
      final repository = _FakeMemberRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: CashierMemberPage(
            repository: repository,
            permissions: const {'coupon:manage'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member-batch-coupon-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coupon-send-list')), findsOneWidget);
      expect(find.text('满100减20'), findsOneWidget);

      await tester.tap(find.byKey(const Key('coupon-send-select-9')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认发放'));
      await tester.pumpAndSettle();

      expect(find.text('成功发放 42 张'), findsOneWidget);
      expect(repository.batchSentCouponId, 9);
    });

    testWidgets('shows the backend gap notice for create member', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      await tester.pumpWidget(
        MaterialApp(home: CashierMemberPage(repository: _FakeMemberRepository())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member-create-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('暂未提供「新增会员」能力'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
    });
  });

  group('MemberConsumptionDialog', () {
    testWidgets('shows an empty state when the member has no paid orders', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: MemberConsumptionDialog(
            phone: '13800138000',
            repository: _FakeMemberRepository(emptyConsumption: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('暂无消费记录'), findsOneWidget);
      expect(find.byKey(const Key('member-consumption-list')), findsNothing);
    });

    testWidgets('supports retrying a failed consumption request', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final repository = _FakeMemberRepository(failConsumptionOnce: true);
      await tester.pumpWidget(
        MaterialApp(
          home: MemberConsumptionDialog(
            phone: '13800138000',
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('消费记录加载失败'), findsOneWidget);
      await tester.tap(find.byKey(const Key('member-consumption-retry')));
      await tester.pumpAndSettle();

      expect(repository.consumptionCalls, 2);
      expect(find.text('ORD-2'), findsOneWidget);
    });

    testWidgets('opens the selected consumption order details', (tester) async {
      _useDesktopViewport(tester);
      final repository = _FakeMemberRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: MemberConsumptionDialog(
            phone: '13800138000',
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member-consumption-row-2')));
      await tester.pumpAndSettle();

      expect(repository.detailCalls, 1);
      expect(
        find.byKey(const Key('member-consumption-order-detail-dialog')),
        findsOneWidget,
      );
      expect(find.text('订单明细'), findsOneWidget);
      expect(find.text('油边王'), findsOneWidget);
      expect(find.text('堂食'), findsOneWidget);
      expect(find.text('微辣 / 少盐'), findsOneWidget);
      expect(find.textContaining('辣度：'), findsNothing);
      expect(find.textContaining('其他：'), findsNothing);
      expect(find.text('¥15.00'), findsOneWidget);
      expect(find.text('¥30.00'), findsOneWidget);
    });
  });
}

void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeMemberRepository implements CashierMemberRepository {
  _FakeMemberRepository({
    this.missing = false,
    this.emptyConsumption = false,
    this.failConsumptionOnce = false,
  });

  final bool missing;
  final bool emptyConsumption;
  final bool failConsumptionOnce;
  String? lastPhone;
  String? lastRechargePhone;
  String? lastMemberQuery;
  int? lastMemberPage;
  int? batchSentCouponId;
  final Map<int, Duration> delayPages = {};
  int consumptionCalls = 0;
  int detailCalls = 0;
  int detailOpens = 0;

  @override
  Future<void> bindOrder({required int orderId, required String phone}) async {}

  @override
  Future<List<MemberConsumptionRecord>> loadConsumption(String phone) async {
    consumptionCalls++;
    if (failConsumptionOnce && consumptionCalls == 1) {
      throw StateError('网络错误');
    }
    if (emptyConsumption) return const [];
    return [
      const MemberConsumptionRecord(
        id: 2,
        orderNo: 'ORD-2',
        amount: 88.8,
        paidAt: '2026-07-20 12:30',
        tableNumber: 'A08',
        paymentMethod: '微信',
        orderType: '堂食',
      ),
    ];
  }

  @override
  Future<MemberConsumptionDetail> loadConsumptionDetail(
    MemberConsumptionRecord record,
  ) async {
    detailCalls++;
    return MemberConsumptionDetail(
      record: record,
      lines: const [
        MemberConsumptionLine(
          id: 21,
          name: '油边王',
          quantity: 2,
          unit: '份',
          specification: '{"辣度":"微辣","其他":"少盐"}',
          unitPrice: 15,
          totalPrice: 30,
        ),
      ],
    );
  }

  @override
  Future<CashierMemberProfile> loadProfile(String phone) async {
    lastPhone = phone;
    detailOpens++;
    if (missing) throw const MemberNotFoundException();
    return const CashierMemberProfile(
      member: CashierMember(
        id: 7,
        name: '王女士',
        phone: '13800138000',
        openid: 'wx-7',
        level: 2,
        points: 88,
        balance: 268.5,
      ),
      orderCount: 12,
      totalAmount: 1234.56,
      avgOrderValue: 102.88,
      consumeAmount: 2380.5,
      lastConsumeTime: '2026-08-02 12:30:00',
      inviteRegisteredCount: 5,
      availableCouponCount: 2,
      tags: ['高价值会员'],
    );
  }

  @override
  Future<List<MemberRechargeRecord>> loadRecharges(String phone) async {
    return const [
      MemberRechargeRecord(
        id: 3,
        orderNo: 'RCH-3',
        principalAmount: 100,
        giftAmount: 10,
        totalAmount: 110,
        channel: 'admin',
        status: 'success',
        createdAt: '2026-07-20 13:00',
      ),
    ];
  }

  @override
  Future<MemberRechargeResult> recharge({
    required String phone,
    required double amount,
    required double giftAmount,
  }) async {
    lastRechargePhone = phone;
    return const MemberRechargeResult(newBalance: 378.5);
  }

  @override
  Future<PagedCashierMembers> loadMembers({
    required int page,
    int pageSize = 20,
    String query = '',
    String phone = '',
  }) async {
    lastMemberPage = page;
    lastMemberQuery = query;
    final delay = delayPages[page];
    if (delay != null) await Future<void>.delayed(delay);
    return const PagedCashierMembers(
      rows: [
        CashierMemberRow(
          id: 7,
          name: '张晓雯',
          phone: '13800138000',
          level: 2,
          points: 3200,
          balance: 520.5,
          consumeAmount: 2380,
          lastConsumeTime: '2026-08-02 12:30:00',
        ),
        CashierMemberRow(
          id: 8,
          name: '李伟强',
          phone: '13900139000',
          level: 1,
          points: 580,
          balance: 200,
          consumeAmount: 860,
          lastConsumeTime: '2026-08-01 19:20:00',
        ),
      ],
      total: 25,
    );
  }

  @override
  Future<CashierMemberStats> loadStats() async => const CashierMemberStats(
    memberCount: 1286,
    todayNewCount: 12,
    totalBalance: 86400,
    totalPoints: 42860,
  );

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
  Future<List<CashierCoupon>> loadCoupons() async => const [
    CashierCoupon(
      id: 9,
      name: '满100减20',
      type: 'full_reduction',
      discountValue: 20,
      minAmount: 100,
      endTime: '2026-09-30 23:59:59',
      status: 1,
    ),
  ];

  @override
  Future<int> batchSendCoupon({required int couponId}) async {
    batchSentCouponId = couponId;
    return 42;
  }

  @override
  Future<List<CashierPersonaTag>> loadPersonaTags({
    String? phone,
    int? memberId,
  }) async {
    return const [];
  }
}
