import 'dart:async';

import 'package:admin_panel_flutter/src/features/kds_local/sync/cashier_cloud_events_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cashier cloud wake event parsing', () {
    test('parses kds_delivery_available frame with head cursor', () {
      final event = CashierCloudWakeEvent.tryParse(
        '{"type":"kds_delivery_available","headCursor":128,"ts":1720000000000}',
      );
      expect(event, isNotNull);
      expect(event!.isDeliveryAvailable, isTrue);
      expect(event.isHeadCursor, isFalse);
      expect(event.headCursor, 128);
      expect(event.ts, 1720000000000);
    });

    test('parses headCursor frame with snake_case cursor alias', () {
      final event = CashierCloudWakeEvent.tryParse(
        '{"type":"headCursor","head_cursor":"99","ts":1720000000001}',
      );
      expect(event, isNotNull);
      expect(event!.isHeadCursor, isTrue);
      expect(event.headCursor, 99);
    });

    test('rejects non-json frames and frames without a valid type', () {
      expect(CashierCloudWakeEvent.tryParse('not json'), isNull);
      expect(CashierCloudWakeEvent.tryParse('{"headCursor":1}'), isNull);
      expect(CashierCloudWakeEvent.tryParse('{"type":42}'), isNull);
    });
  });

  group('cashier cloud events client lifecycle', () {
    test('connects with bearer and cashier identity headers', () async {
      Map<String, String>? capturedHeaders;
      final client = CashierCloudEventsClient(
        wsUrl: 'ws://api.test/ws/cashier-events',
        token: 'tok',
        shopId: 7,
        deviceCode: 'DEV-1',
        authorityEpoch: '3',
        leaseToken: 'LEASE-9',
        onWake: (_) {},
        connector: (url, {headers}) async {
          capturedHeaders = headers;
          throw StateError('connection refused');
        },
      );
      await client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!['Authorization'], 'Bearer tok');
      expect(capturedHeaders!['X-Shop-Id'], '7');
      expect(capturedHeaders!['X-Cashier-Device-Code'], 'DEV-1');
      expect(capturedHeaders!['X-Cashier-Authority-Epoch'], '3');
      expect(capturedHeaders!['X-Cashier-Lease-Token'], 'LEASE-9');
      await client.dispose();
    });

    test('omits optional identity headers when empty', () async {
      Map<String, String>? capturedHeaders;
      final client = CashierCloudEventsClient(
        wsUrl: 'ws://api.test/ws/cashier-events',
        token: 'tok',
        shopId: 7,
        onWake: (_) {},
        connector: (url, {headers}) async {
          capturedHeaders = headers;
          throw StateError('connection refused');
        },
      );
      await client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!.containsKey('X-Cashier-Device-Code'), isFalse);
      expect(capturedHeaders!.containsKey('X-Cashier-Authority-Epoch'), isFalse);
      expect(capturedHeaders!.containsKey('X-Cashier-Lease-Token'), isFalse);
      await client.dispose();
    });

    test('dispose is idempotent and stops reconnects', () async {
      var connectCalls = 0;
      final client = CashierCloudEventsClient(
        wsUrl: 'ws://api.test/ws/cashier-events',
        token: 'tok',
        shopId: 7,
        onWake: (_) {},
        reconnectBaseDelay: const Duration(milliseconds: 1),
        connector: (url, {headers}) async {
          connectCalls += 1;
          throw StateError('refused');
        },
      );
      await client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(connectCalls, greaterThan(1));

      await client.dispose();
      final callsAfterDispose = connectCalls;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(connectCalls, callsAfterDispose);
      await client.dispose();
      expect(client.isConnected, isFalse);
    });
  });
}
