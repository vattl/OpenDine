import 'package:admin_panel_flutter/src/features/pos/data/pending_order_submission_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('相同指纹重试复用请求标识，指纹变更换新，清除后重新生成', () async {
    final store = MemoryPendingOrderSubmissionStore();
    var sequence = 0;
    String generate() => 'req-${sequence++}';

    final first = await store.resolve(
      scope: 'add-dishes-ORD40',
      fingerprint: 'cart-a',
      generate: generate,
    );
    // 同一逻辑加菜车的重试必须复用同一请求标识（幂等）。
    final retry = await store.resolve(
      scope: 'add-dishes-ORD40',
      fingerprint: 'cart-a',
      generate: generate,
    );
    expect(retry, first);

    // 购物车内容变更（新指纹）必须产生新请求标识。
    final changed = await store.resolve(
      scope: 'add-dishes-ORD40',
      fingerprint: 'cart-b',
      generate: generate,
    );
    expect(changed, isNot(first));

    // 明确成功后清除记录，下一轮加菜重新生成。
    await store.clear('add-dishes-ORD40');
    final nextRound = await store.resolve(
      scope: 'add-dishes-ORD40',
      fingerprint: 'cart-b',
      generate: generate,
    );
    expect(nextRound, isNot(changed));
  });

  test('不同订单作用域的待提交请求标识互不干扰', () async {
    final store = MemoryPendingOrderSubmissionStore();
    var sequence = 0;
    String generate() => 'req-${sequence++}';

    final orderA = await store.resolve(
      scope: 'add-dishes-A',
      fingerprint: 'same',
      generate: generate,
    );
    final orderB = await store.resolve(
      scope: 'add-dishes-B',
      fingerprint: 'same',
      generate: generate,
    );
    expect(orderA, isNot(orderB));
  });
}
