import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_models.dart';
import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'startup creates a recoverable database backup with retention',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'cashier-kds-storage-',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = CashierKdsStorage(root);
      await storage.prepare();
      await File(storage.databasePath).writeAsBytes([1, 2, 3]);

      for (var index = 0; index < 4; index++) {
        await storage.backupBeforeOpen(nowMs: 1000 + index, retentionCount: 2);
      }

      final backups = storage.backupDirectory
          .listSync()
          .whereType<Directory>()
          .toList();
      expect(backups, hasLength(2));
      expect(
        backups.every(
          (directory) => File(
            '${directory.path}${Platform.pathSeparator}cashier_kds.sqlite',
          ).existsSync(),
        ),
        isTrue,
      );
    },
  );

  test('uses and backs up the established cashier database in place', () async {
    final root = await Directory.systemTemp.createTemp('cashier-kds-legacy-');
    addTearDown(() => root.delete(recursive: true));
    final legacyDirectory = Directory(
      '${root.path}${Platform.pathSeparator}LaofeiCashier',
    );
    await legacyDirectory.create(recursive: true);
    final legacy = File(
      '${legacyDirectory.path}${Platform.pathSeparator}cashier_kds.sqlite',
    );
    await legacy.writeAsBytes([9, 8, 7]);
    final storage = CashierKdsStorage(root);

    final backup = await storage.backupBeforeOpen(nowMs: 1234);

    expect(storage.databasePath, legacy.path);
    expect(await legacy.readAsBytes(), [9, 8, 7]);
    expect(
      await File(
        '${backup!.path}${Platform.pathSeparator}cashier_kds.sqlite',
      ).readAsBytes(),
      [9, 8, 7],
    );
  });

  test(
    'backup capacity failure preserves the prior recoverable snapshot',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'cashier-kds-capacity-',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = CashierKdsStorage(root);
      await storage.prepare();
      await File(storage.databasePath).writeAsBytes(List<int>.filled(8, 1));
      final first = await storage.backupBeforeOpen(
        nowMs: 1000,
        retentionCount: 2,
        maxBackupBytes: 32,
      );

      await expectLater(
        storage.backupBeforeOpen(
          nowMs: 1001,
          retentionCount: 2,
          maxBackupBytes: 15,
        ),
        throwsA(isA<CashierKdsBackupCapacityException>()),
      );
      expect(
        await File(
          '${first!.path}${Platform.pathSeparator}cashier_kds.sqlite',
        ).readAsBytes(),
        List<int>.filled(8, 1),
      );
      expect(
        storage.backupDirectory.listSync().whereType<Directory>().where(
          (directory) => directory.path.contains('.pending-'),
        ),
        isEmpty,
      );
    },
  );

  test('configuration snapshot is versioned and expires explicitly', () {
    final database = CashierKdsDatabase.inMemory();
    addTearDown(database.close);
    database.writeConfigSnapshot(
      const CashierKdsConfigSnapshot(
        shopId: 1,
        version: 7,
        payload: {
          'queues': ['pending_prep'],
        },
        updatedAtMs: 1000,
        expiresAtMs: 2000,
      ),
    );

    expect(database.readConfigSnapshot(shopId: 1, nowMs: 1999)?.version, 7);
    expect(database.readConfigSnapshot(shopId: 1, nowMs: 2001), isNull);
  });

  test('authority lock is exclusive and released with its owner', () async {
    final root = await Directory.systemTemp.createTemp('cashier-kds-lock-');
    addTearDown(() => root.delete(recursive: true));
    final storage = CashierKdsStorage(root);

    final first = await storage.acquireAuthorityLock();
    await expectLater(
      storage.acquireAuthorityLock(),
      throwsA(isA<CashierKdsAuthorityLockException>()),
    );
    first.release();

    final replacement = await storage.acquireAuthorityLock();
    replacement.release();
  });
}
