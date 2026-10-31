import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/data/cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/data/real_cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/domain/cashier_payment_config.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/presentation/cashier_payment_config_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/presentation/cashier_routing_rule_dialog.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/presentation/cashier_routing_simulator_dialog.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/pos_auth_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

class _FakeCashierPaymentRepository implements CashierPaymentRepository {
  _FakeCashierPaymentRepository({
    List<PaymentRoutingRule>? rules,
  }) : currentRules = rules ?? [
          const PaymentRoutingRule(
            id: 101,
            ruleName: '三文鱼生鲜专线',
            priority: 150,
            enabled: true,
            targetMerchantKey: 'small_amount',
            matchMode: 'ALL',
            conditions: PaymentRoutingConditions(
              diningTypes: ['打包', '自提'],
              minPaidYuan: 50.0,
              maxPaidYuan: 200.0,
              goodsMatch: GoodsMatchCondition(
                goodsNameKeywords: ['三文鱼'],
                mode: 'CONTAINS_ANY',
              ),
              timeRange: TimeRangeCondition(
                startTime: '10:00',
                endTime: '22:00',
              ),
            ),
            targetMerchantPayReady: true,
          ),
        ];

  final CashierPaymentCapabilities initialCapabilities =
      const CashierPaymentCapabilities();
  List<PaymentRoutingRule> currentRules;
  int verifyPasswordCalls = 0;
  int deleteRuleCalls = 0;
  int saveRuleCalls = 0;
  int sortRuleCalls = 0;
  int simulateCalls = 0;

  @override
  Future<CashierPaymentCapabilities> loadCapabilities() async =>
      initialCapabilities;

  @override
  Future<CashierPaymentCapabilities> saveCapabilities(
    CashierPaymentCapabilities capabilities,
  ) async =>
      capabilities;

  @override
  Future<PaymentMerchantCollection> loadMerchants(PaymentChannel channel) async {
    return PaymentMerchantCollection(
      owned: [
        PaymentMerchant(
          id: 1,
          channel: channel,
          merchantKey: 'default',
          mchId: '10000001',
          payReady: true,
        ),
        PaymentMerchant(
          id: 2,
          channel: channel,
          merchantKey: 'small_amount',
          mchId: '10000002',
          payReady: true,
        ),
      ],
    );
  }

  @override
  Future<PaymentMerchantForm> loadEditForm(
    PaymentChannel channel, {
    required String merchantKey,
  }) async =>
      PaymentMerchantForm(channel: channel, merchantKey: merchantKey);

  @override
  Future<PaymentMerchantForm> loadMerchant(int id) async =>
      const PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
      );

  @override
  Future<PaymentMerchantForm> saveMerchant(PaymentMerchantForm form) async =>
      form;

  @override
  Future<PaymentMerchantDeleteResult> deleteMerchant(int id) async =>
      const PaymentMerchantDeleteResult(deletedId: 1, physicallyDeleted: true);

  @override
  Future<PaymentNotifyUrls> loadNotifyUrls() async => const PaymentNotifyUrls(
        wechatPayNotify: '',
        wechatRefundNotify: '',
        alipayPayNotify: '',
      );

  @override
  Future<PaymentPrivateKeyUploadResult> uploadWechatPrivateKey({
    required List<int> pemBytes,
    required String filename,
    String? merchantKey,
  }) async =>
      const PaymentPrivateKeyUploadResult(privateKeyRef: 'ref/pk.pem');

  @override
  Future<PaymentPlatformPublicKeyUploadResult> uploadWechatPlatformPublicKey({
    required List<int> pemBytes,
    required String filename,
    String? merchantKey,
  }) async =>
      const PaymentPlatformPublicKeyUploadResult(
        platformPubKeyRef: 'ref/cert.pem',
        materialType: 'CERTIFICATE',
      );

  @override
  Future<PaymentMerchantForm> uploadMerchantPrivateKey({
    required int merchantId,
    required List<int> pemBytes,
    required String filename,
  }) async =>
      const PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
      );

  @override
  Future<PaymentCertificateUploadResult> uploadCertificate({
    required List<int> bytes,
    required String filename,
    String? merchantKey,
    String type = 'AUTO',
  }) async =>
      PaymentCertificateUploadResult(
        certificateType: type,
        fileRef: 'ref/cert.crt',
        filename: filename,
        fileSize: bytes.length,
      );

  @override
  Future<PaymentMerchantForm> uploadMerchantCertificate({
    required int merchantId,
    required List<int> bytes,
    required String filename,
    String type = 'AUTO',
  }) async =>
      const PaymentMerchantForm(
        channel: PaymentChannel.wechat,
        merchantKey: 'default',
      );

  @override
  Future<PaymentRoutingRuleCollection> loadRoutingRules(
    PaymentChannel channel,
  ) async {
    return PaymentRoutingRuleCollection(
      channel: channel,
      rules: currentRules.where((r) => r.channel == channel).toList(),
    );
  }

  @override
  Future<PaymentRoutingRule> saveRoutingRule({
    int? id,
    required Map<String, Object?> data,
  }) async {
    saveRuleCalls++;
    final rule = PaymentRoutingRule(
      id: id ?? 999,
      ruleName: data['ruleName']?.toString() ?? '',
      priority: (data['priority'] as num?)?.toInt() ?? 100,
      enabled: data['enabled'] != false,
      targetMerchantKey: data['targetMerchantKey']?.toString() ?? 'default',
      matchMode: data['matchMode']?.toString() ?? 'ALL',
      targetMerchantPayReady: true,
    );
    if (id != null) {
      currentRules = currentRules.map((r) => r.id == id ? rule : r).toList();
    } else {
      currentRules = [...currentRules, rule];
    }
    return rule;
  }

  @override
  Future<bool> deleteRoutingRule(int id) async {
    deleteRuleCalls++;
    currentRules = currentRules.where((r) => r.id != id).toList();
    return true;
  }

  @override
  Future<bool> sortRoutingRules(
    PaymentChannel channel,
    List<int> ruleIds,
  ) async {
    sortRuleCalls++;
    return true;
  }

  @override
  Future<PaymentRoutingSimulationResult> simulateRouting(
    Map<String, Object?> context,
  ) async {
    simulateCalls++;
    return const PaymentRoutingSimulationResult(
      matched: true,
      matchedRuleId: 101,
      matchedRuleName: '三文鱼生鲜专线',
      targetMerchantKey: 'small_amount',
      targetMerchantPayReady: true,
      effectiveMerchantKey: 'small_amount',
      fallbackOccurred: false,
    );
  }

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {
    verifyPasswordCalls++;
    if (password != '123456') {
      throw Exception('密码错误');
    }
  }
}

void main() {
  group('Payment Routing Rules Domain & Model Tests', () {
    test('parses PaymentRoutingRule with nested conditions correctly', () {
      final json = {
        'id': 101,
        'shopId': 7,
        'channel': 'wechat',
        'ruleName': '三文鱼生鲜专线',
        'priority': 150,
        'enabled': 1,
        'targetMerchantKey': 'small_amount',
        'matchMode': 'ALL',
        'conditionsJson': jsonEncode({
          'diningTypes': ['打包', '自提'],
          'minPaidYuan': 50.0,
          'maxPaidYuan': 200.0,
          'goodsMatch': {
            'goodsNameKeywords': ['三文鱼'],
            'categoryIds': [10],
            'mode': 'CONTAINS_ANY',
          },
          'timeRange': {
            'startTime': '10:00',
            'endTime': '22:00',
          },
        }),
        'remark': '测试备注',
        'targetMerchantPayReady': true,
      };

      final rule = PaymentRoutingRule.fromJson(json);
      expect(rule.id, 101);
      expect(rule.ruleName, '三文鱼生鲜专线');
      expect(rule.priority, 150);
      expect(rule.enabled, isTrue);
      expect(rule.targetMerchantKey, 'small_amount');
      expect(rule.matchMode, 'ALL');
      expect(rule.conditions, isNotNull);
      expect(rule.conditions!.diningTypes, ['打包', '自提']);
      expect(rule.conditions!.minPaidYuan, 50.0);
      expect(rule.conditions!.maxPaidYuan, 200.0);
      expect(rule.conditions!.goodsMatch!.goodsNameKeywords, ['三文鱼']);
      expect(rule.conditions!.goodsMatch!.mode, 'CONTAINS_ANY');
      expect(rule.conditions!.timeRange!.startTime, '10:00');
      expect(rule.conditions!.timeRange!.endTime, '22:00');
      expect(rule.targetMerchantPayReady, isTrue);
    });

    test('serializes PaymentRoutingConditions to JSON properly', () {
      const cond = PaymentRoutingConditions(
        diningTypes: ['堂食'],
        minPaidYuan: 88.0,
        goodsMatch: GoodsMatchCondition(
          goodsNameKeywords: ['烤鸭'],
          mode: 'ONLY',
        ),
      );
      final json = cond.toJson();
      expect(json['diningTypes'], ['堂食']);
      expect(json['minPaidYuan'], 88.0);
      expect((json['goodsMatch'] as Map)['mode'], 'ONLY');
    });

    test('parses PaymentRoutingSimulationResult properly', () {
      final json = {
        'shopId': 7,
        'channel': 'wechat',
        'inputPaidYuan': 88.0,
        'inputDiningType': '打包',
        'matched': true,
        'matchedRuleId': 101,
        'matchedRuleName': '三文鱼专线',
        'targetMerchantKey': 'small_amount',
        'targetMerchantPayReady': true,
        'effectiveMerchantKey': 'small_amount',
        'fallbackOccurred': false,
      };
      final res = PaymentRoutingSimulationResult.fromJson(json);
      expect(res.matched, isTrue);
      expect(res.matchedRuleName, '三文鱼专线');
      expect(res.effectiveMerchantKey, 'small_amount');
      expect(res.fallbackOccurred, isFalse);
    });
  });

  group('RealCashierPaymentRepository Routing API Integration Tests', () {
    test('routes CRUD and simulate calls to correct endpoints', () async {
      final transport = FakeHttpTransport({
        'GET /admin/payment/routing-rules': jsonEncode({
          'code': 0,
          'data': {
            'targetShopId': 7,
            'channel': 'wechat',
            'rules': [
              {
                'id': 101,
                'ruleName': '专线1',
                'priority': 100,
                'targetMerchantKey': 'default',
              },
            ],
          },
        }),
        'POST /admin/payment/routing-rules': jsonEncode({
          'code': 0,
          'data': {
            'id': 102,
            'ruleName': '新规则',
            'priority': 120,
            'targetMerchantKey': 'small_amount',
          },
        }),
        'PUT /admin/payment/routing-rules/101': jsonEncode({
          'code': 0,
          'data': {
            'id': 101,
            'ruleName': '修改规则',
            'priority': 130,
            'targetMerchantKey': 'default',
          },
        }),
        'DELETE /admin/payment/routing-rules/101': jsonEncode({
          'code': 0,
          'data': {'deleted': true},
        }),
        'PUT /admin/payment/routing-rules/sort': jsonEncode({
          'code': 0,
          'data': {'sorted': true},
        }),
        'POST /admin/payment/routing-rules/simulate': jsonEncode({
          'code': 0,
          'data': {
            'matched': true,
            'matchedRuleName': '命中专线',
            'targetMerchantKey': 'small_amount',
            'effectiveMerchantKey': 'small_amount',
          },
        }),
        'POST /adminLogin': jsonEncode({
          'code': 0,
          'data': {'token': 'admin-token'},
        }),
      });

      final repo = RealCashierPaymentRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 7,
        ),
      );

      final rules = await repo.loadRoutingRules(PaymentChannel.wechat);
      expect(rules.rules.length, 1);

      final created = await repo.saveRoutingRule(
        data: {'ruleName': '新规则', 'priority': 120},
      );
      expect(created.id, 102);

      final updated = await repo.saveRoutingRule(
        id: 101,
        data: {'ruleName': '修改规则', 'priority': 130},
      );
      expect(updated.ruleName, '修改规则');

      final deleted = await repo.deleteRoutingRule(101);
      expect(deleted, isTrue);

      final sorted = await repo.sortRoutingRules(
        PaymentChannel.wechat,
        [102, 101],
      );
      expect(sorted, isTrue);

      final sim = await repo.simulateRouting({'paidYuan': 88.0});
      expect(sim.matched, isTrue);
      expect(sim.effectiveMerchantKey, 'small_amount');

      await repo.verifyPassword(username: 'admin', password: 'pw');

      expect(transport.requests.map((r) => '${r.method} ${r.uri.path}'), [
        'GET /admin/payment/routing-rules',
        'POST /admin/payment/routing-rules',
        'PUT /admin/payment/routing-rules/101',
        'DELETE /admin/payment/routing-rules/101',
        'PUT /admin/payment/routing-rules/sort',
        'POST /admin/payment/routing-rules/simulate',
        'POST /adminLogin',
      ]);
    });
  });

  group('CashierPaymentConfigPage Routing Rules Widget Tests', () {
    testWidgets(
      'renders card with locked badge, requires PosAuth on action, and unlocks',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _FakeCashierPaymentRepository();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CashierPaymentConfigPage(
                repository: repo,
                canEdit: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 验证卡片与初始锁定徽标
        expect(find.text('商户分流路由规则'), findsOneWidget);
        expect(find.text('🔒 店长/老板专享功能'), findsOneWidget);
        expect(find.text('三文鱼生鲜专线'), findsOneWidget);
        expect(find.text('目标: small_amount · 就绪'), findsOneWidget);

        // 未授权时点击「+ 新增规则」-> 弹出店长二次授权弹窗
        await tester.tap(find.byKey(const Key('cashier-routing-add-rule-btn')));
        await tester.pumpAndSettle();

        expect(find.byType(PosAuthDialog), findsOneWidget);
        expect(find.text('商户分流主管授权'), findsOneWidget);

        // 输入账号密码并确认
        await tester.enterText(
          find.byKey(const Key('pos-auth-account')),
          'admin',
        );
        await tester.enterText(
          find.byKey(const Key('pos-auth-password')),
          '123456',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('pos-auth-confirm')));
        await tester.pumpAndSettle();

        // 验证二次授权调用成功，且卡片状态变为 🟢「店长已授权 (免密操作中)」
        expect(repo.verifyPasswordCalls, 1);
        expect(find.text('🟢 店长已授权 (免密操作中)'), findsOneWidget);

        // 并且随后自动进入了新增规则弹窗 CashierRoutingRuleDialog
        expect(find.byType(CashierRoutingRuleDialog), findsOneWidget);
        expect(find.text('新增商户分流路由规则'), findsOneWidget);

        // 在弹窗中输入规则名称并保存
        await tester.enterText(
          find.byKey(const Key('cashier-routing-rule-name-input')),
          '自提小额进款',
        );
        await tester.tap(find.byKey(const Key('cashier-routing-rule-save-btn')));
        await tester.pumpAndSettle();

        expect(repo.saveRuleCalls, 1);
        expect(find.byType(CashierRoutingRuleDialog), findsNothing);
      },
    );

    testWidgets('opens simulation dialog and shows matched feedback', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _FakeCashierPaymentRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierPaymentConfigPage(
              repository: repo,
              canEdit: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击「🔍 模拟测算」
      await tester.tap(find.byKey(const Key('cashier-routing-simulator-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(CashierRoutingSimulatorDialog), findsOneWidget);
      expect(find.text('商户分流路由规则现场试算模拟器'), findsOneWidget);

      // 点击「开始模拟试算」
      await tester.tap(find.byKey(const Key('cashier-sim-run-btn')));
      await tester.pumpAndSettle();

      expect(repo.simulateCalls, 1);
      expect(find.byKey(const Key('cashier-sim-result-card')), findsOneWidget);
      expect(find.text('成功命中分流规则'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('cashier-sim-result-card')),
          matching: find.text('三文鱼生鲜专线'),
        ),
        findsOneWidget,
      );
      expect(find.text('small_amount'), findsWidgets);
    });
  });
}
