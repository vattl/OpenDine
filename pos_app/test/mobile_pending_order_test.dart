import 'package:admin_panel_flutter/src/features/mobile/data/cart_storage.dart';
import 'package:admin_panel_flutter/src/features/mobile/data/pending_order_worker.dart';
import 'package:admin_panel_flutter/src/features/pos/data/pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PendingOrderWorker', () {
    test('successful submit removes order from queue', () async {
      final storage = _MemoryCartStorage();
      await storage.savePending([_order('k1'), _order('k2')]);
      final worker = PendingOrderWorker(storage);
      worker.start(submitter: (_) async => true);
      await worker.flushOnce();
      expect(await storage.readPending(), isEmpty);
      worker.stop();
    });

    test(
      'network error keeps order and blocks later ones (ordering)',
      () async {
        final storage = _MemoryCartStorage();
        await storage.savePending([_order('k1'), _order('k2')]);
        final worker = PendingOrderWorker(storage);
        var calls = 0;
        worker.start(
          submitter: (order) async {
            calls++;
            throw Exception('SocketException: failed');
          },
        );
        await worker.flushOnce();
        final remaining = await storage.readPending();
        // k1 网络失败 → 保留并退避；k2 因顺序阻塞未尝试。
        expect(remaining, hasLength(2));
        expect(remaining.first.retryCount, 1);
        expect(calls, 1);
        worker.stop();
      },
    );

    test('backend rejection is persisted as a dead letter', () async {
      final storage = _MemoryCartStorage();
      await storage.savePending([_order('k1'), _order('k2')]);
      final worker = PendingOrderWorker(storage);
      worker.start(submitter: (order) async => order.clientRequestId != 'k1');
      await worker.flushOnce();
      final remaining = await storage.readPending();
      final rejected = await storage.readRejected();
      // k1 被拒 → 持久化死信；k2 成功 → 从待发送队列移除。
      expect(remaining, isEmpty);
      expect(rejected, hasLength(1));
      expect(rejected.single.clientRequestId, 'k1');
      expect(rejected.single.rejectionReason, isNotEmpty);
      worker.stop();
    });

    test('retry backoff prevents an immediate duplicate request', () async {
      final storage = _MemoryCartStorage();
      await storage.savePending([_order('k1')]);
      var now = DateTime(2026, 8, 1, 12);
      final worker = PendingOrderWorker(storage, clock: () => now);
      var calls = 0;
      worker.start(
        submitter: (_) async {
          calls++;
          throw Exception('SocketException: failed');
        },
      );

      await worker.flushOnce();
      await worker.flushOnce();
      expect(calls, 1);

      now = now.add(const Duration(seconds: 5));
      await worker.flushOnce();
      expect(calls, 2);
      worker.stop();
    });

    test('checkout outbox preserves the original idempotency key', () {
      final pending = PendingOrder.forCheckout(
        clientRequestId: 'original-key',
        tableNumber: 'A01',
        diners: 2,
        remark: '',
        lines: const [],
        paymentMethod: '现金',
        createdAt: DateTime(2026, 8, 1),
      );

      expect(pending.clientRequestId, 'original-key');
    });

    test(
      'outbox replay creates an unpaid order without automatic checkout',
      () async {
        final repository = _RecordingPosRepository();
        final replayer = PendingOrderReplayer(repository);

        final accepted = await replayer(_order('k1'));

        expect(accepted, isTrue);
        expect(repository.submittedRequestIds, ['k1']);
        expect(repository.checkoutCalls, 0);
      },
    );
  });
}

PendingOrder _order(String id) => PendingOrder(
  clientRequestId: id,
  tableNumber: 'A01',
  diners: 2,
  remark: '',
  lines: const [],
  paymentMethod: '现金',
  createdAt: DateTime(2026, 8, 1),
);

class _MemoryCartStorage extends CartStorage {
  _MemoryCartStorage() : super(_FakeSecureStorage());

  List<PendingOrder> pending = [];
  List<PendingOrder> rejected = [];

  @override
  Future<List<PendingOrder>> readPending() async => pending;

  @override
  Future<void> savePending(List<PendingOrder> orders) async {
    pending = orders;
  }

  @override
  Future<List<PendingOrder>> readRejected() async => rejected;

  @override
  Future<void> saveRejected(List<PendingOrder> orders) async {
    rejected = orders;
  }
}

class _FakeSecureStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingPosRepository extends PosRepository {
  final submittedRequestIds = <String>[];
  int checkoutCalls = 0;

  @override
  Future<PosSubmissionResult> submitOrder({
    required String tableNumber,
    required int diners,
    required String remark,
    required List<PosCartLine> lines,
    String? clientRequestId,
  }) async {
    submittedRequestIds.add(clientRequestId!);
    return const PosSubmissionResult(id: 1, orderNo: 'O1');
  }

  @override
  Future<void> checkout({
    required String orderNo,
    required String paymentMethod,
    double? cashAmount,
    String collectionSessionId = '',
    bool force = false,
    String? approvalToken,
  }) async {
    checkoutCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
