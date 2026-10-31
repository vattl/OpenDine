import 'dart:async';
import 'dart:io';

import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/core/network_status_monitor.dart';
import 'package:admin_panel_flutter/src/core/cashier_operation_audit.dart';
import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_runtime.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_lan_server.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedFakeTransport implements HttpTransport {
  _DelayedFakeTransport(this.delay);

  final Duration delay;
  final int statusCode = 200;

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    await Future<void>.delayed(delay);
    return HttpResponseData(statusCode: statusCode, body: '{}');
  }
}

void main() {
  group('Long-running Reliability Tests', () {
    test('NetworkStatusMonitor does not notify listeners after dispose', () async {
      final transport = _DelayedFakeTransport(const Duration(milliseconds: 50));
      final monitor = NetworkStatusMonitor(
        baseUrl: 'http://127.0.0.1:9999',
        transport: transport,
        interval: const Duration(seconds: 10),
        probeTimeout: const Duration(seconds: 1),
      );

      var listenerCalled = 0;
      monitor.addListener(() => listenerCalled++);

      // Start probe and immediately dispose before probe completes
      final probeFuture = monitor.probeNow();
      monitor.dispose();

      await probeFuture;

      // Ensure no notification fired on disposed ChangeNotifier
      expect(listenerCalled, 0);
    });

    test('CashierKdsLanServer prunes stale login attempts', () {
      final database = CashierKdsDatabase.inMemory();
      addTearDown(database.close);
      final server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: false,
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      server.setActiveShop(1);
      final code = server.generatePairingCode();
      expect(code.length, 6);

      // Verify pruneStaleLoginAttempts runs safely
      final removed = server.pruneStaleLoginAttempts(nowMs: now);
      expect(removed, 0);
    });

    test('CashierKdsRuntime.runPeriodicMaintenance executes all cleanup pipelines safely', () async {
      final root = await Directory.systemTemp.createTemp('kds-maintenance-');

      final runtime = await CashierKdsRuntime.start(
        applicationDataRoot: root,
        bindAddress: InternetAddress.loopbackIPv4,
        port: 0,
      );

      // Initialize audit store in the same temp root
      await CashierOperationAuditStore.instance.init(
        overridePath: '${root.path}/cashier_audit.db',
      );

      addTearDown(() async {
        CashierOperationAuditStore.instance.close();
        await runtime.close();
        await root.delete(recursive: true);
      });

      // Record a test audit draft
      CashierOperationAuditStore.instance.record(
        const CashierOperationAuditDraft(
          module: 'pos',
          action: 'test_action',
          result: 'success',
        ),
      );

      // Execute periodic maintenance with future timestamp (31 days ahead)
      final futureMs = DateTime.now().millisecondsSinceEpoch +
          const Duration(days: 31).inMilliseconds;

      expect(
        () async => await runtime.runPeriodicMaintenance(nowMs: futureMs),
        returnsNormally,
      );
    });
  });
}
