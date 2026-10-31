import 'package:admin_panel_flutter/src/features/mobile/presentation/payment_reconcile_page.dart';
import 'package:admin_panel_flutter/src/features/reconciliation/data/reconciliation_repository.dart';
import 'package:admin_panel_flutter/src/features/reconciliation/domain/reconciliation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MockReconciliationRepository implements ReconciliationRepository {
  MockReconciliationRepository({
    this.overview,
    this.cases = const [],
  });

  ReconciliationOverview? overview;
  List<ReconciliationCase> cases;

  bool importCalled = false;
  String? lastImportChannel;
  String? lastImportContent;

  bool resolveCalled = false;
  int? lastResolvedCaseId;
  String? lastResolvedStatus;

  @override
  Future<ReconciliationOverview> loadOverview({String? statDate, int? shopId}) async {
    return overview ??
        const ReconciliationOverview(
          businessDay: '2026-10-03',
          shopId: 1,
          shopName: '测试分店',
          hasChannelStatement: false,
          summaryStatus: 'UNIMPORTED',
          openCasesCount: 0,
          totalCasesCount: 0,
          batchesCount: 0,
          layer1: ReconciliationLayer1(
            layer: 1,
            name: '订单与内部台账核对',
            orderCount: 10,
            orderNetSalesFen: 100000,
            ledgerCount: 10,
            ledgerNetAmountFen: 100000,
            differenceFen: 0,
            balanced: true,
          ),
          layer2: ReconciliationLayer2(
            layer: 2,
            name: '内部台账与渠道账单核对',
            hasStatement: false,
            message: '未导入微信/支付宝官方渠道对账单',
            channelTradeCount: 0,
            channelTotalAmountFen: 0,
            matchedCount: 0,
            amountMismatchCount: 0,
            unmatchedInternalCount: 10,
            unmatchedChannelCount: 0,
            differenceFen: 100000,
          ),
          layer3: ReconciliationLayer3(
            layer: 3,
            name: '渠道账单与资金结算核对',
            channelGrossFen: 0,
            feeFen: 0,
            netSettlementFen: 0,
          ),
        );
  }

  @override
  Future<ChannelStatementBatch> importStatement({
    required String channel,
    required String fileName,
    required String content,
    int? shopId,
  }) async {
    importCalled = true;
    lastImportChannel = channel;
    lastImportContent = content;
    return ChannelStatementBatch(
      id: 1,
      batchNo: 'BAT-20261003-001',
      shopId: shopId ?? 1,
      channel: channel,
      statementDate: '2026-10-03',
      fileName: fileName,
      fileHashSha256: 'hash123',
      totalCount: 1,
      totalAmountFen: 5000,
      feeFen: 30,
      netAmountFen: 4970,
      status: 'PARSED',
    );
  }

  @override
  Future<List<ChannelStatementBatch>> loadBatches({String? statDate, String? channel, int? shopId}) async {
    return [];
  }

  @override
  Future<List<ReconciliationCase>> loadCases({String? statDate, String? status, String? discrepancyType, int? shopId}) async {
    return cases;
  }

  @override
  Future<ReconciliationCase> resolveCase({
    required int caseId,
    required String status,
    String? resolutionNote,
    String? responsiblePerson,
    int? shopId,
  }) async {
    resolveCalled = true;
    lastResolvedCaseId = caseId;
    lastResolvedStatus = status;
    return ReconciliationCase(
      id: caseId,
      caseNo: 'CASE-20261003-0001',
      shopId: shopId ?? 1,
      businessDay: '2026-10-03',
      channel: 'WECHAT',
      layer: 2,
      discrepancyType: 'CHANNEL_MISSING',
      status: status,
      internalAmountFen: 5000,
      channelAmountFen: 0,
      differenceFen: 5000,
      resolutionNote: resolutionNote,
      responsiblePerson: responsiblePerson,
    );
  }
}

void main() {
  group('Commercial Reconciliation & Channel Import (POS-SDC-401 & 402)', () {
    testWidgets('unimported channel statement strictly prevents "已对平" and shows "未导入"', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = MockReconciliationRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: PaymentReconcilePage(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('未导入外部渠道对账单'), findsOneWidget);
      expect(find.text('未导入 (内部汇总)'), findsOneWidget);
      expect(find.text('已对平'), findsNothing);
      expect(find.text('第 1 层：订单 vs 内部支付台账'), findsOneWidget);
      expect(find.text('第 2 层：内部台账 vs 渠道对账单'), findsOneWidget);
      expect(find.text('导入渠道对账单'), findsOneWidget);
    });

    testWidgets('displays discrepancy badge and supports resolving discrepancy case', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testCase = const ReconciliationCase(
        id: 99,
        caseNo: 'CASE-20261003-0099',
        shopId: 1,
        businessDay: '2026-10-03',
        channel: 'WECHAT',
        layer: 2,
        discrepancyType: 'INTERNAL_MISSING',
        status: 'OPEN',
        internalAmountFen: 0,
        channelAmountFen: 5000,
        differenceFen: -5000,
        reason: '渠道有账·内部漏单',
      );

      final repo = MockReconciliationRepository(
        overview: const ReconciliationOverview(
          businessDay: '2026-10-03',
          shopId: 1,
          shopName: '测试分店',
          hasChannelStatement: true,
          summaryStatus: 'DISCREPANCY',
          openCasesCount: 1,
          totalCasesCount: 1,
          batchesCount: 1,
          layer1: ReconciliationLayer1(
            layer: 1,
            name: '订单与内部台账核对',
            orderCount: 10,
            orderNetSalesFen: 100000,
            ledgerCount: 10,
            ledgerNetAmountFen: 100000,
            differenceFen: 0,
            balanced: true,
          ),
          layer2: ReconciliationLayer2(
            layer: 2,
            name: '内部台账与渠道账单核对',
            hasStatement: true,
            status: 'DISCREPANCY',
            channelTradeCount: 11,
            channelTotalAmountFen: 105000,
            matchedCount: 10,
            amountMismatchCount: 0,
            unmatchedInternalCount: 0,
            unmatchedChannelCount: 1,
            differenceFen: -5000,
          ),
          layer3: ReconciliationLayer3(
            layer: 3,
            name: '渠道账单与资金结算核对',
            channelGrossFen: 105000,
            feeFen: 630,
            netSettlementFen: 104370,
          ),
        ),
        cases: [testCase],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PaymentReconcilePage(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('对账存在差异'), findsOneWidget);
      expect(find.text('存在差异 (1)'), findsOneWidget);
      expect(find.textContaining('CASE-20261003-0099'), findsOneWidget);

      // Tap '去处理'
      final resolveBtn = find.text('去处理');
      expect(resolveBtn, findsOneWidget);
      await tester.tap(resolveBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('处置差异单: CASE-20261003-0099'), findsOneWidget);

      // Tap '确认平账'
      final submitBtn = find.text('确认平账');
      expect(submitBtn, findsOneWidget);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(repo.resolveCalled, isTrue);
      expect(repo.lastResolvedCaseId, 99);
      expect(repo.lastResolvedStatus, 'CLOSED');
    });

    testWidgets('import channel statement opens dialog and submits content', (tester) async {
      final repo = MockReconciliationRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: PaymentReconcilePage(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      final importBtn = find.text('导入渠道对账单');
      await tester.tap(importBtn);
      await tester.pumpAndSettle();

      expect(find.text('导入渠道对账单 (CSV/JSON)'), findsOneWidget);

      // Tap '填充微信对账测试样例'
      final fillSampleBtn = find.text('填充微信对账测试样例');
      await tester.tap(fillSampleBtn);
      await tester.pumpAndSettle();

      // Tap '确认导入'
      final confirmBtn = find.text('确认导入');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(repo.importCalled, isTrue);
      expect(repo.lastImportChannel, 'WECHAT');
      expect(repo.lastImportContent, isNotNull);
      expect(repo.lastImportContent, contains('trade_time'));
    });
  });
}
