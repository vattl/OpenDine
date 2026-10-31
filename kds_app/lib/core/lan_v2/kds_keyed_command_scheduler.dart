import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kds_app/core/storage/kds_command_outbox_store.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';

/// 调度器指标快照，满足 Task 9 / Task 10 观测需求
@immutable
class KdsSchedulerMetrics {
  const KdsSchedulerMetrics({
    this.activeWorkers = 0,
    this.readyAggregates = 0,
    this.pausedAggregates = 0,
    this.totalPendingCommands = 0,
    this.unknownCommands = 0,
    this.oldestPendingAgeMs = 0,
    this.currentConcurrencyLimit = 4,
    this.totalExecutedCommands = 0,
  });

  final int activeWorkers;
  final int readyAggregates;
  final int pausedAggregates;
  final int totalPendingCommands;
  final int unknownCommands;
  final int oldestPendingAgeMs;
  final int currentConcurrencyLimit;
  final int totalExecutedCommands;

  @override
  String toString() =>
      'KdsSchedulerMetrics(workers=$activeWorkers/$currentConcurrencyLimit, '
      'ready=$readyAggregates, paused=$pausedAggregates, pending=$totalPendingCommands, '
      'unknown=$unknownCommands, oldestAge=${oldestPendingAgeMs}ms)';
}

/// 执行结果类型
enum KdsCommandExecutionOutcome {
  success,
  conflict,
  networkFailure,
  rateLimited,
  businessFailure,
}

/// 执行结果包装
class KdsCommandExecutionResult {
  const KdsCommandExecutionResult({
    required this.outcome,
    this.errorMessage,
    this.nextRecord,
  });

  final KdsCommandExecutionOutcome outcome;
  final String? errorMessage;

  /// 本次执行后应继续保留在队列中的最新记录。
  ///
  /// 网络结果不确定时，执行器会把记录推进为 UNKNOWN，并要求下一轮先按
  /// command_id 查权威账本。调度器必须替换旧副本，禁止直接重放旧命令。
  final KdsOutboxRecord? nextRecord;
}

typedef KdsCommandExecutor = Future<KdsCommandExecutionResult> Function(
  KdsOutboxRecord record,
  int generation,
);

typedef KdsAggregateKeyExtractor = String Function(KdsOutboxRecord record);

/// 按业务聚合键串行、跨聚合有界并发的安全调度器（CP3 核心）
///
/// 遵循 KDS-CA-1.3 标准：
/// - 同一 aggregate key 内严格 FIFO，同一时间最多 1 个在途写请求；
/// - 不同 aggregate key 并发执行，默认并发 4，配置上限 8，动态降速至 1；
/// - 单聚合 UNKNOWN 仅挂起所属聚合队列，不占用全局并发 Worker，不阻塞其他订单；
/// - 通道 Handover 时停止领取新命令，Generation fencing 防止旧代际迟到响应覆盖 UI；
/// - 429 或高延迟时自适应降速，成功恢复时逐步回升并发度。
class KdsKeyedCommandScheduler {
  KdsKeyedCommandScheduler({
    required this.executor,
    required this.aggregateKeyExtractor,
    int initialConcurrency = 4,
    this.maxConcurrency = 8,
    this.minConcurrency = 1,
    this.onMetricsUpdated,
  })  : assert(initialConcurrency >= minConcurrency &&
            initialConcurrency <= maxConcurrency),
        _concurrencyLimit = initialConcurrency;

  final KdsCommandExecutor executor;
  final KdsAggregateKeyExtractor aggregateKeyExtractor;
  final int maxConcurrency;
  final int minConcurrency;
  final ValueChanged<KdsSchedulerMetrics>? onMetricsUpdated;

  int _concurrencyLimit;
  int get concurrencyLimit => _concurrencyLimit;

  /// 按聚合键维护独立 FIFO 命令队列
  final Map<String, List<KdsOutboxRecord>> _queues = {};

  /// 正在执行中的聚合键（同一聚合最多 1 个在途写）
  final Set<String> _inFlightAggregates = {};

  /// 被挂起的聚合键（例如发生 UNKNOWN 或重试等待中）
  final Set<String> _pausedAggregates = {};

  /// 挂起聚合的重试定时器映射，防止重叠并发定时器雪崩
  final Map<String, Timer> _retryTimers = {};

  /// 全局调度暂停（断网、通道切换或 Handover 中）
  bool _isPaused = false;
  bool get isPaused => _isPaused;

  /// 通道代际防护（Generation fencing）
  int _generation = 0;
  int get generation => _generation;

  /// 自适应背压指标
  int _consecutiveSuccesses = 0;
  int _totalExecutedCommands = 0;
  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  /// 获取当前所有在排队的指令总数
  int get pendingCount {
    var count = 0;
    for (final q in _queues.values) {
      count += q.length;
    }
    return count;
  }

  /// 获取当前所有未完成指令列表（用于 outbox 队列同步）
  List<KdsOutboxRecord> get allRecords {
    final list = <KdsOutboxRecord>[];
    for (final q in _queues.values) {
      list.addAll(q);
    }
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// 设置目标并发上限（范围 [minConcurrency, maxConcurrency]）
  void setConcurrencyLimit(int limit) {
    final clamped = limit.clamp(minConcurrency, maxConcurrency);
    if (_concurrencyLimit != clamped) {
      _concurrencyLimit = clamped;
      KdsFileLogger.info('[SCHEDULER] 并发度更新为 $_concurrencyLimit');
      _scheduleNext();
    }
  }

  /// 暂停调度新任务（Handover / 断网 / 页面销毁）
  void pause() {
    if (_isDisposed) return;
    if (!_isPaused) {
      _isPaused = true;
      KdsFileLogger.info('[SCHEDULER] 调度器已全局暂停');
      _emitMetrics();
    }
  }

  /// 恢复调度新任务
  void resume() {
    if (_isDisposed) {
      KdsFileLogger.warn('[SCHEDULER] 忽略已销毁调度器的恢复请求');
      return;
    }
    if (_isPaused) {
      _isPaused = false;
      KdsFileLogger.info('[SCHEDULER] 调度器已恢复');
      _scheduleNext();
    }
  }

  /// 通道切换时递增代际，旧代际在途响应直接失效
  int bumpGeneration() {
    _generation++;
    KdsFileLogger.info('[SCHEDULER] 代际递增至 gen=$_generation');
    return _generation;
  }

  /// 入队一条待发送指令
  void enqueue(KdsOutboxRecord record) {
    _ensureActive('enqueue');
    final key = aggregateKeyExtractor(record);
    final queue = _queues.putIfAbsent(key, () => []);
    // 检查是否已有相同 commandId（防重复入队）
    final existingIdx = queue.indexWhere((r) => r.id == record.id);
    if (existingIdx >= 0) {
      queue[existingIdx] = record;
    } else {
      queue.add(record);
    }
    _scheduleNext();
  }

  /// 批量从持久化存储恢复已有未完成指令
  void restore(Iterable<KdsOutboxRecord> records) {
    _ensureActive('restore');
    for (final record in records) {
      final key = aggregateKeyExtractor(record);
      final queue = _queues.putIfAbsent(key, () => []);
      if (!queue.any((r) => r.id == record.id)) {
        queue.add(record);
      }
      if (record.requiresResolution) {
        _pausedAggregates.add(key);
      }
    }
    _scheduleNext();
  }

  /// 挂起指定聚合键（单聚合隔离 UNKNOWN）
  void pauseAggregate(String aggregateKey) {
    _pausedAggregates.add(aggregateKey);
    _emitMetrics();
  }

  /// 解除指定聚合键的挂起状态（查证完成或重试恢复）
  void resumeAggregate(String aggregateKey) {
    _retryTimers.remove(aggregateKey)?.cancel();
    if (_pausedAggregates.remove(aggregateKey)) {
      KdsFileLogger.info('[SCHEDULER] 聚合 $aggregateKey 已解除挂起');
      _scheduleNext();
    }
  }

  /// 解除所有聚合键的挂起状态（通道恢复或主动冲刷时调用）
  void resumeAllAggregates() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    if (_pausedAggregates.isNotEmpty) {
      _pausedAggregates.clear();
      KdsFileLogger.info('[SCHEDULER] 所有挂起聚合已重置并恢复调度');
      _scheduleNext();
    }
  }

  /// 移除指定 commandId（例如外部 WebSocket 已确认，或用户撤销）
  bool removeCommand(String commandId) {
    var removed = false;
    for (final entry in _queues.entries.toList()) {
      final queue = entry.value;
      final idx = queue.indexWhere((r) => r.id == commandId);
      if (idx >= 0) {
        queue.removeAt(idx);
        removed = true;
        if (queue.isEmpty) {
          _queues.remove(entry.key);
          _pausedAggregates.remove(entry.key);
          _retryTimers.remove(entry.key)?.cancel();
        }
        break;
      }
    }
    if (removed) {
      _scheduleNext();
    }
    return removed;
  }

  /// 清空所有队列
  void clear() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _queues.clear();
    _inFlightAggregates.clear();
    _pausedAggregates.clear();
    _emitMetrics();
  }

  /// 核心调度循环：跨聚合并发最多 concurrencyLimit，同聚合严格单在途 FIFO
  void _scheduleNext() {
    if (_isDisposed || _isPaused) {
      _emitMetrics();
      return;
    }

    while (_inFlightAggregates.length < _concurrencyLimit) {
      // 寻找下一个准备好且未被挂起的聚合
      String? selectedKey;
      DateTime? oldestCandidateTime;

      for (final entry in _queues.entries) {
        final key = entry.key;
        if (_inFlightAggregates.contains(key) ||
            _pausedAggregates.contains(key)) {
          continue;
        }
        if (entry.value.isEmpty) continue;

        // 公平策略：优先调度头部指令等待时间最长的聚合（FIFO）
        final headRecord = entry.value.first;
        if (oldestCandidateTime == null ||
            headRecord.createdAt.isBefore(oldestCandidateTime)) {
          oldestCandidateTime = headRecord.createdAt;
          selectedKey = key;
        }
      }

      if (selectedKey == null) {
        // 无可领取的就绪任务
        break;
      }

      // 锁定该聚合，取出队头任务下发 worker 执行
      _inFlightAggregates.add(selectedKey);
      final headRecord = _queues[selectedKey]!.first;
      final currentGen = _generation;

      _runWorker(selectedKey, headRecord, currentGen);
    }

    _emitMetrics();
  }

  Future<void> _runWorker(
    String aggregateKey,
    KdsOutboxRecord record,
    int dispatchGen,
  ) async {
    try {
      final result = await executor(record, dispatchGen);

      if (_isDisposed) return;

      final nextRecord = result.nextRecord;
      if (nextRecord != null) {
        final retained = _replaceQueuedRecord(aggregateKey, record, nextRecord);
        if (!retained) return;
      }

      // Generation fencing：代际变动后忽略迟到响应，防止覆盖新代际 UI
      if (dispatchGen != _generation) {
        KdsFileLogger.warn(
          '[SCHEDULER] cmd=${record.id} 响应迟到 (dispatchGen=$dispatchGen != current=$_generation)，丢弃结果',
        );
        return;
      }

      switch (result.outcome) {
        case KdsCommandExecutionOutcome.success:
          _handleSuccess(aggregateKey, record);
          break;
        case KdsCommandExecutionOutcome.conflict:
          _handleConflict(aggregateKey, record, result.errorMessage);
          break;
        case KdsCommandExecutionOutcome.networkFailure:
          _handleNetworkFailure(aggregateKey, record, result.errorMessage);
          break;
        case KdsCommandExecutionOutcome.rateLimited:
          _handleRateLimited(aggregateKey, record);
          break;
        case KdsCommandExecutionOutcome.businessFailure:
          _handleBusinessFailure(aggregateKey, record, result.errorMessage);
          break;
      }
    } catch (e) {
      if (!_isDisposed && dispatchGen == _generation) {
        _handleNetworkFailure(aggregateKey, record, '$e');
      }
    } finally {
      _inFlightAggregates.remove(aggregateKey);
      _scheduleNext();
    }
  }

  bool _replaceQueuedRecord(
    String aggregateKey,
    KdsOutboxRecord previous,
    KdsOutboxRecord next,
  ) {
    if (next.id != previous.id || aggregateKeyExtractor(next) != aggregateKey) {
      throw StateError(
        'Scheduler executor cannot replace command ${previous.id} with '
        '${next.id} in another aggregate',
      );
    }
    final queue = _queues[aggregateKey];
    final index = queue?.indexWhere((item) => item.id == previous.id) ?? -1;
    if (queue == null || index < 0) {
      KdsFileLogger.info(
        '[SCHEDULER] cmd=${previous.id} 已由 WS/外部确认移除，忽略迟到的 HTTP 队列状态',
      );
      return false;
    }
    queue[index] = next;
    return true;
  }

  void _ensureActive(String operation) {
    if (!_isDisposed) return;
    KdsFileLogger.error(
      '[SCHEDULER] 已销毁调度器收到 $operation，拒绝静默丢弃命令',
    );
    throw StateError('KdsKeyedCommandScheduler is disposed');
  }

  void _handleSuccess(String aggregateKey, KdsOutboxRecord record) {
    _totalExecutedCommands++;
    _consecutiveSuccesses++;

    // 成功后移除该指令
    final q = _queues[aggregateKey];
    if (q != null && q.isNotEmpty && q.first.id == record.id) {
      q.removeAt(0);
      if (q.isEmpty) {
        _queues.remove(aggregateKey);
        _pausedAggregates.remove(aggregateKey);
      }
    }

    // 自适应并发恢复：连续 10 次成功，提升并发度（最高至 maxConcurrency）
    if (_consecutiveSuccesses >= 10 && _concurrencyLimit < maxConcurrency) {
      _consecutiveSuccesses = 0;
      _concurrencyLimit = math.min(maxConcurrency, _concurrencyLimit + 1);
      KdsFileLogger.info('[SCHEDULER] 通道健康，自适应提升并发至 $_concurrencyLimit');
    }
  }

  void _handleConflict(
      String aggregateKey, KdsOutboxRecord record, String? error) {
    KdsFileLogger.warn('[SCHEDULER] cmd=${record.id} 发生 409 冲突: $error');
    final q = _queues[aggregateKey];
    if (q != null && q.isNotEmpty && q.first.id == record.id) {
      q.removeAt(0);
      if (q.isEmpty) {
        _queues.remove(aggregateKey);
        _pausedAggregates.remove(aggregateKey);
      }
    }
  }

  void _handleNetworkFailure(
    String aggregateKey,
    KdsOutboxRecord record,
    String? error,
  ) {
    _consecutiveSuccesses = 0;
    KdsFileLogger.warn(
      '[SCHEDULER] cmd=${record.id} 网络失败，挂起聚合 $aggregateKey 并在 3s 后自动重试: $error',
    );
    // 隔离策略：单聚合挂起，释放 worker 资源，保证其他聚合不被阻断
    _pausedAggregates.add(aggregateKey);
    _retryTimers[aggregateKey]?.cancel();
    _retryTimers[aggregateKey] = Timer(const Duration(seconds: 3), () {
      _retryTimers.remove(aggregateKey);
      if (!_isDisposed) {
        resumeAggregate(aggregateKey);
      }
    });
  }

  void _handleRateLimited(String aggregateKey, KdsOutboxRecord record) {
    _consecutiveSuccesses = 0;
    // 遇到 429 限流：动态将并发降至 1 并稍作退避
    final oldLimit = _concurrencyLimit;
    _concurrencyLimit = minConcurrency;
    KdsFileLogger.warn(
      '[SCHEDULER] 触发 429 限流，并发度从 $oldLimit 紧急降速至 $_concurrencyLimit',
    );
    _pausedAggregates.add(aggregateKey);
    _retryTimers[aggregateKey]?.cancel();
    _retryTimers[aggregateKey] = Timer(const Duration(seconds: 2), () {
      _retryTimers.remove(aggregateKey);
      if (!_isDisposed) {
        resumeAggregate(aggregateKey);
      }
    });
  }

  void _handleBusinessFailure(
    String aggregateKey,
    KdsOutboxRecord record,
    String? error,
  ) {
    KdsFileLogger.warn('[SCHEDULER] cmd=${record.id} 业务失败不可重试并移除: $error');
    final q = _queues[aggregateKey];
    if (q != null && q.isNotEmpty && q.first.id == record.id) {
      q.removeAt(0);
      if (q.isEmpty) {
        _queues.remove(aggregateKey);
        _pausedAggregates.remove(aggregateKey);
      }
    }
  }

  void _emitMetrics() {
    if (_isDisposed) return;
    var readyCount = 0;
    var totalPending = 0;
    var unknownCount = 0;
    DateTime? oldest;

    for (final entry in _queues.entries) {
      final key = entry.key;
      final q = entry.value;
      totalPending += q.length;
      if (!_inFlightAggregates.contains(key) &&
          !_pausedAggregates.contains(key) &&
          q.isNotEmpty) {
        readyCount++;
      }
      for (final r in q) {
        if (r.requiresResolution) unknownCount++;
        if (oldest == null || r.createdAt.isBefore(oldest)) {
          oldest = r.createdAt;
        }
      }
    }

    final oldestAgeMs = oldest != null
        ? DateTime.now().difference(oldest).inMilliseconds.clamp(0, 1 << 30)
        : 0;

    final metrics = KdsSchedulerMetrics(
      activeWorkers: _inFlightAggregates.length,
      readyAggregates: readyCount,
      pausedAggregates: _pausedAggregates.length,
      totalPendingCommands: totalPending,
      unknownCommands: unknownCount,
      oldestPendingAgeMs: oldestAgeMs,
      currentConcurrencyLimit: _concurrencyLimit,
      totalExecutedCommands: _totalExecutedCommands,
    );

    onMetricsUpdated?.call(metrics);
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _queues.clear();
    _inFlightAggregates.clear();
    _pausedAggregates.clear();
  }
}
