import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../pos/data/pos_repository.dart';
import 'cart_storage.dart';

class PendingOrderReplayer {
  const PendingOrderReplayer(this._repository);

  final PosRepository _repository;

  Future<bool> call(PendingOrder order) async {
    try {
      await _repository.submitOrder(
        tableNumber: order.tableNumber,
        diners: order.diners,
        remark: order.remark,
        lines: order.lines,
        clientRequestId: order.clientRequestId,
      );
      // Outbox 只补建待支付订单，支付必须由收银员在前台核对后发起。
      return true;
    } catch (error) {
      if (_isNetworkError(error)) rethrow;
      return false;
    }
  }

  bool _isNetworkError(Object error) {
    final text = '$error';
    return text.contains('SocketException') ||
        text.contains('TimeoutException') ||
        text.contains('请求超时') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection');
  }
}

/// 弱网补单 Outbox worker：周期 flush 落盘的 PendingOrder 队列。
/// 使用有上限的指数退避（5s/10s/30s/60s/300s/900s）。
///
/// 发送逻辑由调用方注入（submit 回调），worker 只负责调度与退避。
class PendingOrderWorker {
  PendingOrderWorker(
    this._storage, {
    Duration interval = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _interval = interval,
       _clock = clock ?? DateTime.now;

  final CartStorage _storage;
  final Duration _interval;
  final DateTime Function() _clock;
  Timer? _timer;
  bool _flushing = false;

  /// 返回 true 表示该笔补单成功（从队列移除）。
  Future<bool> Function(PendingOrder order)? _submitter;

  void start({required Future<bool> Function(PendingOrder order) submitter}) {
    _submitter = submitter;
    _timer ??= Timer.periodic(_interval, (_) => unawaited(flushOnce()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void kick() => unawaited(flushOnce());

  Future<void> flushOnce() async {
    final submitter = _submitter;
    if (submitter == null || _flushing) return;
    _flushing = true;
    try {
      final orders = await _storage.readPending();
      if (orders.isEmpty) return;
      final remaining = <PendingOrder>[];
      var blocked = false;
      for (final order in orders) {
        if (blocked) {
          remaining.add(order);
          continue;
        }
        final now = _clock();
        final nextAttemptAt = order.nextAttemptAt;
        if (nextAttemptAt != null && now.isBefore(nextAttemptAt)) {
          remaining.add(order);
          blocked = true;
          continue;
        }
        try {
          final ok = await submitter(order);
          if (!ok) {
            // 后端拒绝（非网络错误）：持久化死信，供人工核对，不丢单。
            final rejected = await _storage.readRejected();
            await _storage.saveRejected([
              ...rejected.where(
                (item) => item.clientRequestId != order.clientRequestId,
              ),
              order.markRejected(reason: '后端拒绝请求，请人工核对订单与支付状态', now: now),
            ]);
            debugPrint('pending order ${order.clientRequestId} rejected');
            continue;
          }
        } catch (error) {
          debugPrint('pending order ${order.clientRequestId} retry: $error');
          final retried = order.copyWithRetry(
            now: now,
            delay: _retryDelay(order.retryCount),
          );
          remaining.add(retried);
          // 保持顺序：后续订单可能依赖这笔（同桌台）。
          blocked = true;
        }
      }
      await _storage.savePending(remaining);
    } finally {
      _flushing = false;
    }
  }

  Duration _retryDelay(int retryCount) {
    const delays = [
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
    ];
    return delays[retryCount.clamp(0, delays.length - 1)];
  }
}
