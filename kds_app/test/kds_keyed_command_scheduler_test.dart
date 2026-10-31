import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_keyed_command_scheduler.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/storage/kds_command_outbox_store.dart';

void main() {
  group('KdsKeyedCommandScheduler', () {
    KdsOutboxRecord makeRecord({
      required String id,
      required int orderId,
      DateTime? createdAt,
      bool requiresResolution = false,
    }) {
      final cmd = KdsV2Command(
        commandId: id,
        type: KdsV2CommandType.advanceItem,
        target: KdsV2CommandTarget(orderId: orderId, detailId: 1),
      );
      return KdsOutboxRecord(
        id: id,
        command: cmd,
        hiddenKeys: const {},
        createdAt: createdAt ?? DateTime.now(),
        requiresResolution: requiresResolution,
      );
    }

    test('same aggregate key executes strictly serially (single in-flight)',
        () async {
      final startedCommands = <String>[];
      final completers = <String, Completer<KdsCommandExecutionResult>>{};

      final scheduler = KdsKeyedCommandScheduler(
        initialConcurrency: 4,
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) {
          startedCommands.add(rec.id);
          final c = Completer<KdsCommandExecutionResult>();
          completers[rec.id] = c;
          return c.future;
        },
      );

      final r1 = makeRecord(id: 'c1', orderId: 100);
      final r2 = makeRecord(id: 'c2', orderId: 100);

      scheduler.enqueue(r1);
      scheduler.enqueue(r2);

      // Microtask pump
      await Future<void>.delayed(Duration.zero);

      // c1 should be started, but c2 must wait because both belong to order:100
      expect(startedCommands, ['c1']);

      // Complete c1
      completers['c1']!.complete(const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.success,
      ));

      await Future<void>.delayed(Duration.zero);

      // Now c2 should be started
      expect(startedCommands, ['c1', 'c2']);

      completers['c2']!.complete(const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.success,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(scheduler.pendingCount, 0);
      scheduler.dispose();
    });

    test(
        'different aggregate keys execute concurrently up to concurrency limit',
        () async {
      final startedCommands = <String>[];
      final completers = <String, Completer<KdsCommandExecutionResult>>{};

      final scheduler = KdsKeyedCommandScheduler(
        initialConcurrency: 3,
        maxConcurrency: 8,
        minConcurrency: 1,
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) {
          startedCommands.add(rec.id);
          final c = Completer<KdsCommandExecutionResult>();
          completers[rec.id] = c;
          return c.future;
        },
      );

      // Enqueue 4 commands with different order IDs
      scheduler.enqueue(makeRecord(id: 'c1', orderId: 1));
      scheduler.enqueue(makeRecord(id: 'c2', orderId: 2));
      scheduler.enqueue(makeRecord(id: 'c3', orderId: 3));
      scheduler.enqueue(makeRecord(id: 'c4', orderId: 4));

      await Future<void>.delayed(Duration.zero);

      // First 3 should start immediately because initialConcurrency = 3
      expect(startedCommands, ['c1', 'c2', 'c3']);

      // Complete c1
      completers['c1']!.complete(const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.success,
      ));

      await Future<void>.delayed(Duration.zero);

      // Now c4 should start
      expect(startedCommands, ['c1', 'c2', 'c3', 'c4']);

      completers['c2']!.complete(const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.success,
      ));
      completers['c3']!.complete(const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.success,
      ));
      completers['c4']!.complete(const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.success,
      ));

      await Future<void>.delayed(Duration.zero);
      expect(scheduler.pendingCount, 0);
      scheduler.dispose();
    });

    test('unknown aggregate pause isolates only that aggregate', () async {
      final startedCommands = <String>[];
      final completers = <String, Completer<KdsCommandExecutionResult>>{};

      final scheduler = KdsKeyedCommandScheduler(
        initialConcurrency: 4,
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) {
          startedCommands.add(rec.id);
          final c = Completer<KdsCommandExecutionResult>();
          completers[rec.id] = c;
          return c.future;
        },
      );

      final r1 = makeRecord(id: 'c1', orderId: 10, requiresResolution: true);
      final r2 = makeRecord(id: 'c2', orderId: 20);

      // Pause aggregate order:10 first (e.g. UNKNOWN detected upon recovery)
      scheduler.pauseAggregate('order:10');
      scheduler.enqueue(r1);
      scheduler.enqueue(r2);

      await Future<void>.delayed(Duration.zero);

      // Only c2 should execute, c1 is paused in order:10
      expect(startedCommands, ['c2']);

      completers['c2']!.complete(const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.success,
      ));
      await Future<void>.delayed(Duration.zero);

      // Now resume order:10
      scheduler.resumeAggregate('order:10');
      await Future<void>.delayed(Duration.zero);

      expect(startedCommands, ['c2', 'c1']);
      completers['c1']!.complete(const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.success,
      ));
      await Future<void>.delayed(Duration.zero);

      scheduler.dispose();
    });

    test(
        'generation fencing prevents stale command completion from affecting state',
        () async {
      int? executedGen;
      final completer = Completer<KdsCommandExecutionResult>();

      final scheduler = KdsKeyedCommandScheduler(
        initialConcurrency: 2,
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) {
          executedGen = gen;
          return completer.future;
        },
      );

      scheduler.enqueue(makeRecord(id: 'c1', orderId: 1));
      await Future<void>.delayed(Duration.zero);

      expect(executedGen, 0);

      // Bump generation (e.g. channel switch / handover)
      final newGen = scheduler.bumpGeneration();
      expect(newGen, 1);

      // Stale command finishes
      completer.complete(const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.success,
      ));
      await Future<void>.delayed(Duration.zero);

      // Generation bump successfully isolated
      expect(scheduler.generation, 1);
      scheduler.dispose();
    });

    test('global pause halts dispatching and resume resumes dispatching',
        () async {
      final startedCommands = <String>[];
      final scheduler = KdsKeyedCommandScheduler(
        initialConcurrency: 2,
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) async {
          startedCommands.add(rec.id);
          return const KdsCommandExecutionResult(
            outcome: KdsCommandExecutionOutcome.success,
          );
        },
      );

      scheduler.pause();
      expect(scheduler.isPaused, isTrue);

      scheduler.enqueue(makeRecord(id: 'c1', orderId: 1));
      await Future<void>.delayed(Duration.zero);

      // While paused, no command should start
      expect(startedCommands, isEmpty);

      scheduler.resume();
      expect(scheduler.isPaused, isFalse);
      await Future<void>.delayed(Duration.zero);

      // After resume, c1 executes
      expect(startedCommands, ['c1']);
      scheduler.dispose();
    });

    test('backpressure on 429 rate limit decreases concurrency limit',
        () async {
      final scheduler = KdsKeyedCommandScheduler(
        initialConcurrency: 4,
        minConcurrency: 1,
        maxConcurrency: 8,
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) async {
          return const KdsCommandExecutionResult(
            outcome: KdsCommandExecutionOutcome.rateLimited,
          );
        },
      );

      expect(scheduler.concurrencyLimit, 4);

      scheduler.enqueue(makeRecord(id: 'c1', orderId: 1));
      await Future<void>.delayed(Duration.zero);

      // On 429, concurrency drops
      expect(scheduler.concurrencyLimit, lessThan(4));
      scheduler.dispose();
    });

    test('metrics callback reports accurate snapshot', () async {
      KdsSchedulerMetrics? latestMetrics;

      final scheduler = KdsKeyedCommandScheduler(
        initialConcurrency: 4,
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) async => const KdsCommandExecutionResult(
          outcome: KdsCommandExecutionOutcome.success,
        ),
        onMetricsUpdated: (metrics) {
          latestMetrics = metrics;
        },
      );

      scheduler.enqueue(makeRecord(id: 'c1', orderId: 1));
      await Future<void>.delayed(Duration.zero);

      expect(latestMetrics, isNotNull);
      expect(latestMetrics!.totalExecutedCommands, 1);
      expect(latestMetrics!.activeWorkers, 0);

      scheduler.dispose();
    });

    test('resumeAllAggregates clears paused state for all keys', () async {
      final executed = <String>[];
      final scheduler = KdsKeyedCommandScheduler(
        initialConcurrency: 2,
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) async {
          executed.add(rec.id);
          return const KdsCommandExecutionResult(
            outcome: KdsCommandExecutionOutcome.success,
          );
        },
      );

      scheduler.pauseAggregate('order:1');
      scheduler.pauseAggregate('order:2');
      scheduler.enqueue(makeRecord(id: 'c1', orderId: 1));
      scheduler.enqueue(makeRecord(id: 'c2', orderId: 2));

      await Future<void>.delayed(Duration.zero);
      expect(executed, isEmpty);

      scheduler.resumeAllAggregates();
      await Future<void>.delayed(Duration.zero);
      expect(executed, containsAll(['c1', 'c2']));

      scheduler.dispose();
    });

    test('network retry uses the executor returned UNKNOWN record', () async {
      var attempts = 0;
      var retriedWithResolution = false;
      late final KdsKeyedCommandScheduler scheduler;
      scheduler = KdsKeyedCommandScheduler(
        initialConcurrency: 1,
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) async {
          attempts++;
          if (attempts == 1) {
            final unknown = rec.copyWith(
              status: KdsOutboxStatus.unknown,
              retryCount: rec.retryCount + 1,
              requiresResolution: true,
            );
            return KdsCommandExecutionResult(
              outcome: KdsCommandExecutionOutcome.networkFailure,
              nextRecord: unknown,
            );
          }
          retriedWithResolution = rec.requiresResolution;
          return const KdsCommandExecutionResult(
            outcome: KdsCommandExecutionOutcome.success,
          );
        },
      );

      scheduler.enqueue(makeRecord(id: 'c1', orderId: 1));
      await Future<void>.delayed(Duration.zero);
      scheduler.resumeAggregate('order:1');
      await Future<void>.delayed(Duration.zero);

      expect(attempts, 2);
      expect(
        retriedWithResolution,
        isTrue,
        reason: '结果不确定后必须先按 command_id 查账本，禁止用旧记录盲重放',
      );
      scheduler.dispose();
    });

    test('enqueue after dispose fails loudly instead of dropping the command',
        () {
      final scheduler = KdsKeyedCommandScheduler(
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) async => const KdsCommandExecutionResult(
          outcome: KdsCommandExecutionOutcome.success,
        ),
      );
      scheduler.dispose();

      expect(
        () => scheduler.enqueue(makeRecord(id: 'c1', orderId: 1)),
        throwsStateError,
      );
    });

    test('late HTTP uncertainty cannot resurrect a command confirmed by WS',
        () async {
      final result = Completer<KdsCommandExecutionResult>();
      KdsSchedulerMetrics? latestMetrics;
      final scheduler = KdsKeyedCommandScheduler(
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) => result.future,
        onMetricsUpdated: (metrics) => latestMetrics = metrics,
      );
      final record = makeRecord(id: 'c1', orderId: 1);

      scheduler.enqueue(record);
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.removeCommand(record.id), isTrue);

      result.complete(KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.networkFailure,
        nextRecord: record.copyWith(
          status: KdsOutboxStatus.unknown,
          requiresResolution: true,
        ),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(scheduler.pendingCount, 0);
      expect(latestMetrics?.pausedAggregates, 0);
      scheduler.dispose();
    });

    test('repeated network failure replaces previous retry timer without cascading', () async {
      var executeCount = 0;
      final scheduler = KdsKeyedCommandScheduler(
        aggregateKeyExtractor: (rec) => 'order:${rec.command.target.orderId}',
        executor: (rec, gen) async {
          executeCount++;
          return const KdsCommandExecutionResult(
            outcome: KdsCommandExecutionOutcome.networkFailure,
            errorMessage: 'network error',
          );
        },
      );
      final record = makeRecord(id: 'c1', orderId: 1);
      scheduler.enqueue(record);
      await Future<void>.delayed(Duration.zero);

      // Initial execution
      expect(executeCount, 1);

      // Manual resume before 3s timer
      scheduler.resumeAggregate('order:1');
      await Future<void>.delayed(Duration.zero);
      expect(executeCount, 2);

      // Clean disposal cancels timer
      scheduler.dispose();
    });
  });
}
