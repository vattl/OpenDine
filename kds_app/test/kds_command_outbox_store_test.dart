import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/storage/kds_command_outbox_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  KdsV2Command createTestCommand({
    required String commandId,
    KdsV2CommandType type = KdsV2CommandType.advanceItem,
    int detailId = 101,
    String? fromQueue = 'pending_prep',
  }) {
    return KdsV2Command(
      commandId: commandId,
      type: type,
      target: KdsV2CommandTarget(
        detailId: detailId,
        fromQueue: fromQueue,
      ),
      quantity: 2,
      expectedRevision: 5,
    );
  }

  test('KdsV2CommandTarget and KdsV2Command JSON serialization round-trip', () {
    final cmd = KdsV2Command(
      commandId: 'cmd-uuid-001',
      type: KdsV2CommandType.advanceItem,
      target: const KdsV2CommandTarget(
        orderId: 10,
        detailId: 20,
        detailIds: [20, 21],
        fromQueue: 'pending_cook',
      ),
      quantity: 3,
      expectedRevision: 7,
      remark: '微辣',
      setSoldOut: false,
      expectedRevisions: {20: 7, 21: 8},
    );

    final jsonMap = cmd.toJson();
    final restored = KdsV2Command.fromJson(jsonMap);

    expect(restored.commandId, 'cmd-uuid-001');
    expect(restored.type, KdsV2CommandType.advanceItem);
    expect(restored.target.orderId, 10);
    expect(restored.target.detailId, 20);
    expect(restored.target.detailIds, [20, 21]);
    expect(restored.target.fromQueue, 'pending_cook');
    expect(restored.quantity, 3);
    expect(restored.expectedRevision, 7);
    expect(restored.remark, '微辣');
    expect(restored.setSoldOut, false);
    expect(restored.expectedRevisions, {20: 7, 21: 8});
  });

  test(
      'KdsCommandOutboxStore saves and restores pending commands across restarts',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = await KdsCommandOutboxStore.inMemory(legacyPrefs: prefs);

    final cmd1 = createTestCommand(commandId: 'cmd-001');
    final cmd2 = createTestCommand(commandId: 'cmd-002', detailId: 102);

    final record1 = KdsOutboxRecord(
      id: cmd1.commandId,
      command: cmd1,
      hiddenKeys: {'101:pending_prep'},
      createdAt: DateTime.now(),
      status: KdsOutboxStatus.pending,
      originChannel: 'lan',
      requiresResolution: true,
    );
    final record2 = KdsOutboxRecord(
      id: cmd2.commandId,
      command: cmd2,
      hiddenKeys: {'102:pending_prep'},
      createdAt: DateTime.now(),
      status: KdsOutboxStatus.sending,
      retryCount: 1,
      originChannel: 'cloud',
    );

    await store.save([record1, record2], shopId: 1);

    // Simulate process restart by reloading from store
    final restored = await store.load(expectedShopId: 1);
    expect(restored.length, 2);

    expect(restored[0].id, 'cmd-001');
    expect(restored[0].command.commandId, 'cmd-001');
    expect(restored[0].status, KdsOutboxStatus.pending);
    expect(restored[0].hiddenKeys, {'101:pending_prep'});
    expect(restored[0].originChannel, 'lan');
    expect(restored[0].requiresResolution, isTrue);

    // Previously SENDING record must be recovered as RETRY_WAIT to safely re-dispatch
    expect(restored[1].id, 'cmd-002');
    expect(restored[1].command.commandId, 'cmd-002');
    expect(restored[1].status, KdsOutboxStatus.retryWait);
    expect(restored[1].retryCount, 1);
    expect(restored[1].requiresResolution, isTrue);
  });

  test('KdsCommandOutboxStore ignores ACKED or CONFLICT records on restore',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = await KdsCommandOutboxStore.inMemory(legacyPrefs: prefs);

    final cmdAcked = createTestCommand(commandId: 'cmd-acked');
    final cmdPending = createTestCommand(commandId: 'cmd-pending');

    await store.save([
      KdsOutboxRecord(
        id: cmdAcked.commandId,
        command: cmdAcked,
        hiddenKeys: const {},
        createdAt: DateTime.now(),
        status: KdsOutboxStatus.acked,
      ),
      KdsOutboxRecord(
        id: cmdPending.commandId,
        command: cmdPending,
        hiddenKeys: const {},
        createdAt: DateTime.now(),
        status: KdsOutboxStatus.pending,
      ),
    ], shopId: 1);

    final restored = await store.load(expectedShopId: 1);
    expect(restored.length, 1);
    expect(restored[0].id, 'cmd-pending');
  });

  test('KdsCommandOutboxStore scopes records by shopId and clears correctly',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = await KdsCommandOutboxStore.inMemory(legacyPrefs: prefs);

    final cmdShop1 = createTestCommand(commandId: 'shop1-cmd');
    final cmdShop2 = createTestCommand(commandId: 'shop2-cmd');

    await store.save([
      KdsOutboxRecord(
        id: cmdShop1.commandId,
        command: cmdShop1,
        hiddenKeys: const {},
        createdAt: DateTime.now(),
      ),
    ], shopId: 1);

    await store.save([
      KdsOutboxRecord(
        id: cmdShop2.commandId,
        command: cmdShop2,
        hiddenKeys: const {},
        createdAt: DateTime.now(),
      ),
    ], shopId: 2);

    expect(
        (await store.load(expectedShopId: 1)).map((r) => r.id), ['shop1-cmd']);
    expect(
        (await store.load(expectedShopId: 2)).map((r) => r.id), ['shop2-cmd']);

    await store.clear(shopId: 1);
    expect(await store.load(expectedShopId: 1), isEmpty);
    expect((await store.load(expectedShopId: 2)).length, 1);
  });

  test('KdsCommandOutboxStore refuses capacity overflow without data loss',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = await KdsCommandOutboxStore.inMemory(legacyPrefs: prefs);

    final records = List.generate(550, (i) {
      final cmd = createTestCommand(commandId: 'cmd-$i', detailId: i);
      return KdsOutboxRecord(
        id: cmd.commandId,
        command: cmd,
        hiddenKeys: const {},
        createdAt: DateTime.now(),
        status: KdsOutboxStatus.pending,
      );
    });

    await expectLater(
      store.save(records, shopId: 1),
      throwsA(isA<StateError>()),
    );
    expect(await store.load(expectedShopId: 1), isEmpty);
  });

  test('SQLite outbox survives close/reopen and migrates legacy preferences',
      () async {
    final directory = Directory.systemTemp.createTempSync('kds-outbox-');
    final path = '${directory.path}${Platform.pathSeparator}outbox.db';
    final prefs = await SharedPreferences.getInstance();
    final command = createTestCommand(commandId: 'legacy-cmd');
    final legacyRecord = KdsOutboxRecord(
      id: command.commandId,
      command: command,
      hiddenKeys: const {'101:pending_prep'},
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      status: KdsOutboxStatus.sending,
      retryCount: 2,
      originChannel: 'lan',
    );
    await prefs.setString(
      'kds_command_outbox_v1_7',
      jsonEncode([legacyRecord.toJson()]),
    );

    var store = await KdsCommandOutboxStore.open(
      databasePath: path,
      legacyPrefs: prefs,
    );
    var restored = await store.load(expectedShopId: 7);
    expect(restored.single.id, 'legacy-cmd');
    expect(restored.single.status, KdsOutboxStatus.retryWait);
    expect(restored.single.requiresResolution, isTrue);
    await store.close();

    store = await KdsCommandOutboxStore.open(databasePath: path);
    restored = await store.load(expectedShopId: 7);
    expect(restored.single.command.commandId, 'legacy-cmd');
    expect(restored.single.originChannel, 'lan');
    await store.close();
    directory.deleteSync(recursive: true);
  });

  test('legacy migration never silently truncates outbox exceeding soft cap',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final records = List.generate(550, (i) {
      final cmd = createTestCommand(commandId: 'legacy-$i', detailId: i);
      return KdsOutboxRecord(
        id: cmd.commandId,
        command: cmd,
        hiddenKeys: const {},
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000 + i),
        status: KdsOutboxStatus.pending,
      );
    });
    await prefs.setString(
      'kds_command_outbox_v1_9',
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );

    final store = await KdsCommandOutboxStore.inMemory(legacyPrefs: prefs);
    final restored = await store.load(expectedShopId: 9);

    // All 550 records must be preserved without silent truncation
    expect(restored.length, 550);
    expect(restored.first.id, 'legacy-0');
    expect(restored.last.id, 'legacy-549');
    await store.close();
  });

  test('getOldestPendingAgeMs calculates oldest pending command age accurately',
      () async {
    final store = await KdsCommandOutboxStore.inMemory();
    final now = DateTime.now();
    final cmd1 = createTestCommand(commandId: 'cmd-old', detailId: 101);
    final cmd2 = createTestCommand(commandId: 'cmd-new', detailId: 102);

    final recordOld = KdsOutboxRecord(
      id: cmd1.commandId,
      command: cmd1,
      hiddenKeys: const {},
      createdAt: now.subtract(const Duration(seconds: 45)),
      status: KdsOutboxStatus.pending,
    );
    final recordNew = KdsOutboxRecord(
      id: cmd2.commandId,
      command: cmd2,
      hiddenKeys: const {},
      createdAt: now.subtract(const Duration(seconds: 10)),
      status: KdsOutboxStatus.pending,
    );

    await store.enqueue(recordOld, shopId: 10);
    await store.enqueue(recordNew, shopId: 10);

    final ageMs = await store.getOldestPendingAgeMs(shopId: 10);
    expect(ageMs, isNotNull);
    expect(ageMs!, greaterThanOrEqualTo(44000));
    expect(ageMs, lessThan(60000));

    // When all are acked, oldest pending age should be null
    await store.save([], shopId: 10);
    final emptyAge = await store.getOldestPendingAgeMs(shopId: 10);
    expect(emptyAge, isNull);

    await store.close();
  });
}

