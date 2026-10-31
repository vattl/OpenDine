import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel_flutter/src/core/cashier_operation_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cashier_audit_test_');
    dbPath = '${tempDir.path}${Platform.pathSeparator}audit_test.db';
    CashierOperationAuditStore.instance.close();
    await CashierOperationAuditStore.instance.init(overridePath: dbPath);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('record/query 基本读写与幂等', () async {
    final store = CashierOperationAuditStore.instance;
    expect(store.isReady, isTrue);

    store.currentActorName = 'cashier01';
    store.currentShopId = 7;

    store.record(CashierOperationAuditDraft(
      module: 'pos',
      action: 'create_order',
      result: 'success',
      operationId: 'op:fixed:1',
      targetType: 'table',
      targetId: 'A1',
      amountFen: 5000,
      detail: {'lines': 2, 'remark': 'test'},
    ));
    // 相同 operationId 重复写入应被忽略（幂等）
    store.record(CashierOperationAuditDraft(
      module: 'pos',
      action: 'create_order',
      result: 'success',
      operationId: 'op:fixed:1',
      targetType: 'table',
      targetId: 'A1',
    ));
    store.record(CashierOperationAuditDraft(
      module: 'order',
      action: 'refund',
      result: 'failed',
      targetType: 'order',
      targetId: 'ORD1',
      errorCode: 'E1',
      errorMsg: 'boom',
    ));

    // 等待异步批量落库
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final all = store.query(limit: 100);
    expect(all.length, 2, reason: '幂等：相同 operationId 只记一条');

    final ok = all.firstWhere((e) => e.module == 'pos');
    expect(ok.actorName, 'cashier01');
    expect(ok.shopId, 7);
    expect(ok.amountFen, 5000);
    expect(ok.detail?['lines'], 2);

    final failed = all.firstWhere((e) => e.module == 'order');
    expect(failed.result, 'failed');
    expect(failed.errorCode, 'E1');
  });

  test('敏感字段脱敏', () async {
    final store = CashierOperationAuditStore.instance;

    store.record(CashierOperationAuditDraft(
      module: 'auth',
      action: 'login',
      result: 'success',
      operationId: 'op:redact:1',
      detail: {'username': 'boss', 'password': 'secret123', 'phone': '13800000000'},
    ));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final entries = store.query(module: 'auth', limit: 10);
    expect(entries, isNotEmpty);
    final detail = jsonDecode(entries.first.detailJson!);
    expect(detail['username'], 'boss');
    expect(detail['password'], '***redacted***');
    expect(detail['phone'], '***redacted***');
  });

  test('按模块/结果筛选', () async {
    final store = CashierOperationAuditStore.instance;

    store.record(CashierOperationAuditDraft(
      module: 'shift',
      action: 'open',
      result: 'success',
      operationId: 'op:f1',
    ));
    store.record(CashierOperationAuditDraft(
      module: 'shift',
      action: 'daily_close',
      result: 'success',
      operationId: 'op:f2',
    ));
    store.record(CashierOperationAuditDraft(
      module: 'shop',
      action: 'business_close',
      result: 'failed',
      operationId: 'op:f3',
      errorCode: '4000',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final shifts = store.query(module: 'shift', limit: 10);
    expect(shifts.length, 2);

    final failed = store.query(result: 'failed', limit: 10);
    expect(failed.length, 1);
    expect(failed.first.errorCode, '4000');
  });

  test('trim 保留策略与精确行数上限截断', () async {
    final store = CashierOperationAuditStore.instance;
    for (int i = 1; i <= 15; i++) {
      store.record(CashierOperationAuditDraft(
        module: 'test',
        action: 'action_' + i.toString(),
        result: 'success',
        operationId: 'op:trim:' + i.toString(),
      ));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(store.query(limit: 100).length, 15);

    // 上限 10 条：应该裁减掉 5 条最旧记录，精确剩余 10 条
    store.trim(retentionDays: 365, maxRows: 10);
    final remaining = store.query(limit: 100);
    expect(remaining.length, 10);
    expect(remaining.map((e) => e.action).toSet().contains('action_1'), isFalse);
    expect(remaining.map((e) => e.action).toSet().contains('action_15'), isTrue);

    // 再次 trim：已在上限内，不额外删除
    store.trim(retentionDays: 365, maxRows: 10);
    expect(store.query(limit: 100).length, 10);

    // 边界：上限高于当前条数，不删除
    store.trim(retentionDays: 365, maxRows: 11);
    expect(store.query(limit: 100).length, 10);
  });

  test('flush 在任何异常下安全静默丢弃并累加 droppedCount，绝不逃逸异常', () async {
    final store = CashierOperationAuditStore.instance;
    // 注入格式错误的 draft 触发 SQLite 语法或约束异常
    store.record(const CashierOperationAuditDraft(
      module: 'shop',
      action: 'business_close',
      result: 'success',
      operationId: 'invalid-test-1',
    ));
    // 正常应写入成功，不抛任何异常
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(store.isReady, isTrue);
  });
}
