import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel_flutter/src/features/mobile/presentation/payment_reconcile_page.dart';
import 'package:admin_panel_flutter/src/features/reconciliation/data/ledger_migration_repository.dart';
import 'package:admin_panel_flutter/src/features/reconciliation/data/reconciliation_repository.dart';
import 'package:admin_panel_flutter/src/features/reconciliation/domain/migration_models.dart';
import 'package:admin_panel_flutter/src/features/reconciliation/domain/reconciliation_models.dart';

class _FakeReconciliationRepository implements ReconciliationRepository {
  @override
  Future<ReconciliationOverview> loadOverview({String? statDate, int? shopId}) async {
    return const ReconciliationOverview(
      businessDay: '2026-10-03',
      shopId: 1,
      shopName: '测试分店',
      hasChannelStatement: true,
      summaryStatus: 'RECONCILED',
      openCasesCount: 0,
      totalCasesCount: 0,
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
        channelTradeCount: 10,
        channelTotalAmountFen: 100000,
        matchedCount: 10,
        amountMismatchCount: 0,
        unmatchedInternalCount: 0,
        unmatchedChannelCount: 0,
        differenceFen: 0,
      ),
      layer3: ReconciliationLayer3(
        layer: 3,
        name: '渠道账单与资金结算核对',
        channelGrossFen: 100000,
        feeFen: 60,
        netSettlementFen: 99940,
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
    throw UnimplementedError();
  }

  @override
  Future<List<ChannelStatementBatch>> loadBatches({String? statDate, String? channel, int? shopId}) async {
    return [];
  }

  @override
  Future<List<ReconciliationCase>> loadCases({String? statDate, String? status, String? discrepancyType, int? shopId}) async {
    return [];
  }

  @override
  Future<ReconciliationCase> resolveCase({
    required int caseId,
    required String status,
    String? resolutionNote,
    String? responsiblePerson,
    int? shopId,
  }) async {
    throw UnimplementedError();
  }
}

class _FakeLedgerMigrationRepository implements LedgerMigrationRepository {
  String currentSource = 'PAYMENT_LEDGER';

  @override
  Future<CutoverStatus> getStatus() async {
    return CutoverStatus(
      shopId: 1,
      currentReadSource: currentSource,
      isCutoverToLedger: currentSource == 'PAYMENT_LEDGER',
      totalLedgerRows: 120,
      nativeRows: 100,
      backfilledRows: 20,
    );
  }

  @override
  Future<BackfillReport> backfill({String? statDate, bool dryRun = false}) async {
    return BackfillReport(
      dryRun: dryRun,
      shopId: 1,
      statDate: statDate,
      totalOrdersScanned: 50,
      backfilledOrders: 48,
      skippedOrders: 2,
      totalRowsInserted: 52,
      totalAmountFen: 88800,
      channelTotalsFen: {'CASH': 30000, 'WECHAT': 58800},
      anomaliesCount: 0,
      anomalies: [],
      integrityHash: 'a1b2c3d4e5f67890abcdef1234567890',
      executedAt: '2026-10-03 15:30:00',
    );
  }

  @override
  Future<ShadowVerifyResult> shadowVerify({required String statDate}) async {
    return ShadowVerifyResult(
      shopId: 1,
      statDate: statDate,
      readyForCutover: true,
      netVarianceFen: 0,
      discrepancyCount: 0,
      discrepancies: [],
      legacyOrderSummary: {'net_revenue_fen': 10000},
      ledgerSummary: {'net_revenue_fen': 10000},
      channelVariances: {'net_variance_fen': 0},
    );
  }

  @override
  Future<Map<String, dynamic>> cutover({required String targetSource}) async {
    currentSource = targetSource;
    return {'shop_id': 1, 'current_read_source': targetSource};
  }
}

void main() {
  testWidgets('Migration cutover menu opens and shows status', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.resetPhysicalSize);

    final reconRepo = _FakeReconciliationRepository();
    final migRepo = _FakeLedgerMigrationRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentReconcilePage(
          repository: reconRepo,
          migrationRepository: migRepo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify migration button is present in AppBar
    final migrationButton = find.byKey(const Key('reconcile-migration-button'));
    expect(migrationButton, findsOneWidget);

    // Tap button to open dialog
    await tester.tap(migrationButton);
    await tester.pumpAndSettle();

    // Dialog title and read source check
    expect(find.text('历史账本回填与切读 (Phase 5)'), findsOneWidget);
    expect(find.textContaining('商业支付台账 (PAYMENT_LEDGER)'), findsOneWidget);
    expect(find.textContaining('总计 120 行'), findsOneWidget);

    // Click "执行历史订单回填"
    await tester.tap(find.text('执行历史订单回填 (POS-SDC-501)'));
    await tester.pumpAndSettle();

    expect(find.text('执行历史订单回填 (POS-SDC-501)'), findsOneWidget);
    expect(find.text('仅演练试算 (Dry-Run 模式)'), findsOneWidget);

    // Click run backfill
    final runButton = find.byKey(const Key('reconcile-run-backfill-button'));
    expect(runButton, findsOneWidget);
    await tester.tap(runButton);
    await tester.pumpAndSettle();

    // Verify report preview rendered
    expect(find.text('【演练预览结果】'), findsOneWidget);
    expect(find.textContaining('扫描订单: 50 笔'), findsOneWidget);
    expect(find.textContaining('回填金额: ¥888.00'), findsOneWidget);
  });

  testWidgets('Shadow verify and cutover read source work smoothly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.resetPhysicalSize);

    final reconRepo = _FakeReconciliationRepository();
    final migRepo = _FakeLedgerMigrationRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentReconcilePage(
          repository: reconRepo,
          migrationRepository: migRepo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open migration dialog
    await tester.tap(find.byKey(const Key('reconcile-migration-button')));
    await tester.pumpAndSettle();

    // Click "双写影子验证"
    await tester.tap(find.text('双写影子验证 (POS-SDC-502)'));
    await tester.pumpAndSettle();

    expect(find.text('双写影子验证 (POS-SDC-502)'), findsOneWidget);
    final runShadowButton = find.byKey(const Key('reconcile-run-shadow-button'));
    await tester.tap(runShadowButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('验证通过·账实零差异·可安全切读'), findsOneWidget);
    expect(find.textContaining('旧订单净收: ¥100.00'), findsOneWidget);
  });
}
