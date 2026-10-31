import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/api/api_response.dart';
import 'package:kds_app/core/api/kds_api_client.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/lan_v2/kds_dual_mode_transport.dart';
import 'package:kds_app/core/lan_v2/kds_v2_client.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/ws/kds_websocket.dart';

// Explicit opt-in: requires the production cashier proxy harness and the real
// debug Spring/MySQL service. No fake transport or generated business data.
void main() {
  final enabled = Platform.environment['RUN_REAL_KDS_FAILOVER'] == 'true';
  test(
    'KDS transport automatically fails over to cloud and safely returns to LAN',
    () async {
      final lanBase = _requiredEnvironment('KDS_DEBUG_LAN_URL');
      final cloudBase = _requiredEnvironment('KDS_DEBUG_CLOUD_URL');
      final deviceCode = _requiredEnvironment('KDS_DEBUG_DEVICE_CODE');
      final pairingCode = _requiredEnvironment('KDS_PAIRING_CODE');
      final controlFile = File(
        _requiredEnvironment('KDS_PROXY_CONTROL_FILE'),
      );
      final stateFile = File(_requiredEnvironment('KDS_PROXY_STATE_FILE'));
      String? token;
      Object? recoveryError;
      var directCloudAvailable = true;
      KdsWebSocketService? realtimeSocket;
      StreamSubscription<bool>? realtimeConnectionSub;

      final lanApi = KdsApiClient(
        getBaseUrl: () => lanBase,
        getToken: () => token,
      );
      final cloudApi = KdsApiClient(
        getBaseUrl: () =>
            directCloudAvailable ? cloudBase : 'http://127.0.0.1:1',
        getToken: () => token,
      );
      final cloudClient = KdsV2Client(KdsV2HttpAdapter(cloudApi));
      late final KdsDualModeTransport transport;
      transport = KdsDualModeTransport(
        lanTransport: KdsV2Client(KdsV2HttpAdapter(lanApi)),
        cloudTransport: cloudClient,
        mode: KdsConnectionMode.lanFirst,
        expectedShopId: 1,
        onChannelSwitched: (channel) {
          if (channel != KdsActiveChannel.lan) return;
          unawaited(
            transport.bootstrap().then((_) {
              transport.completeHandover();
            }).catchError((Object error) {
              recoveryError = error;
            }),
          );
        },
      );

      try {
        final login = await lanApi.post(
          '/kds/device/login',
          body: {
            'device_code': deviceCode,
            'shop_id': 1,
            'screen_tag': 'workflow_board',
            'workflows': ['prep', 'cook', 'serve'],
            'screen_tags': ['meat_grill'],
            'pairing_code': pairingCode,
          },
          skipAuth: true,
        );
        token = '${readDeviceJson(login)['device_token'] ?? ''}'.trim();
        expect(token, isNotEmpty, reason: '登录必须返回云端签发的 device token');

        final initial = await transport.bootstrap();
        expect(transport.activeChannel, KdsActiveChannel.lan);
        expect(initial.shopId, 1);
        expect(initial.isStale, isFalse);

        // Warmed bootstrap data must remain visibly stale (never promoted to
        // fresh authority) when only the cashier-to-cloud link is unavailable.
        // The payload still comes from the real debug cloud/MySQL response.
        await controlFile.writeAsString('cloud_off', flush: true);
        await _waitForHarnessState(
          stateFile,
          'running',
          cloudForwarding: false,
        );
        final cachedDuringCloudLinkLoss = await transport.bootstrap();
        expect(transport.activeChannel, KdsActiveChannel.lan);
        expect(cachedDuringCloudLinkLoss.isStale, isTrue);
        expect(cachedDuringCloudLinkLoss.servedVia, 'lan-cache');
        expect(cachedDuringCloudLinkLoss.cacheAgeSeconds, isNotNull);
        expect(
          cachedDuringCloudLinkLoss.authorityCursor,
          cachedDuringCloudLinkLoss.eventSeq,
        );
        _expectSameAuthoritySnapshot(cachedDuringCloudLinkLoss, initial);

        // archive_clear is a real cloud-ledger command that needs no fabricated
        // order/detail. When both cloud paths are unavailable, the cashier must
        // reject local ownership and the KDS outbox must retain this exact ID.
        final pendingCommand = KdsV2Command(
          commandId: 'cloud-loss-${DateTime.now().microsecondsSinceEpoch}',
          type: KdsV2CommandType.archiveClear,
          target: const KdsV2CommandTarget(),
        );
        directCloudAvailable = false;
        await expectLater(
          transport.command(pendingCommand),
          throwsA(
            isA<ApiException>()
                .having((error) => error.statusCode, 'statusCode', 503)
                .having((error) => error.code, 'code', 5030),
          ),
        );
        expect(transport.activeChannel, KdsActiveChannel.lan);
        expect(transport.channelState, KdsChannelState.stable);

        await controlFile.writeAsString('cloud_on', flush: true);
        directCloudAvailable = true;
        await _waitForHarnessState(
          stateFile,
          'running',
          cloudForwarding: true,
        );
        final freshAfterCloudLinkRecovery = await transport.bootstrap();
        expect(freshAfterCloudLinkRecovery.isStale, isFalse);
        expect(transport.activeChannel, KdsActiveChannel.lan);
        expect(freshAfterCloudLinkRecovery.shopId, initial.shopId);

        final applied = await transport.command(pendingCommand);
        expect(applied.commandId, pendingCommand.commandId);
        final resolved = await _waitForAppliedResolution(
          transport,
          pendingCommand.commandId,
        );
        expect(resolved.result?.commandId, pendingCommand.commandId);
        final duplicate = await cloudClient.command(pendingCommand);
        expect(duplicate.commandId, pendingCommand.commandId);
        expect(duplicate.duplicate, isTrue);
        final afterRecoveredCommand = await transport.bootstrap();

        final lanSocketOnline = Completer<void>();
        realtimeSocket = KdsWebSocketService(
          getBaseUrl: () => lanBase,
          getShopId: () => initial.shopId,
          getScreenTag: () => 'workflow_board',
          getToken: () => token,
          reconnectBaseDelay: const Duration(seconds: 5),
          reconnectMaxDelay: const Duration(seconds: 5),
          reconnectJitterMax: Duration.zero,
        );
        realtimeConnectionSub = realtimeSocket.connectedStream.listen((online) {
          if (online && !lanSocketOnline.isCompleted) {
            lanSocketOnline.complete();
          } else if (!online) {
            transport.reportRealtimeDisconnected(KdsActiveChannel.lan);
          }
        });
        realtimeSocket.connect();
        await lanSocketOnline.future.timeout(const Duration(seconds: 5));

        final disconnectedAt = Stopwatch()..start();
        await controlFile.writeAsString('stop', flush: true);
        await _waitForHarnessState(stateFile, 'stopped');
        await _waitUntil(
          () => transport.activeChannel == KdsActiveChannel.cloud,
          timeout: const Duration(seconds: 3),
        );
        disconnectedAt.stop();
        expect(
          disconnectedAt.elapsed,
          lessThan(const Duration(seconds: 3)),
          reason: 'LAN WebSocket 断开必须直接触发云端接管，不能等待 15 秒轮询',
        );
        final duringLoss = await transport.bootstrap();
        expect(transport.activeChannel, KdsActiveChannel.cloud);
        _expectSameAuthoritySnapshot(duringLoss, afterRecoveredCommand);

        await controlFile.writeAsString('start', flush: true);
        await _waitForHarnessState(stateFile, 'running');
        await _waitUntil(
          () =>
              transport.activeChannel == KdsActiveChannel.lan &&
              transport.channelState == KdsChannelState.stable,
          timeout: const Duration(seconds: 15),
        );
        expect(recoveryError, isNull);
        final afterRecovery = await transport.bootstrap();
        expect(transport.activeChannel, KdsActiveChannel.lan);
        _expectSameAuthoritySnapshot(afterRecovery, duringLoss);
      } finally {
        await realtimeConnectionSub?.cancel();
        realtimeSocket?.dispose();
        transport.dispose();
        if (controlFile.parent.existsSync()) {
          await controlFile.writeAsString('exit', flush: true);
        }
      }
    },
    skip: enabled
        ? false
        : 'Set RUN_REAL_KDS_FAILOVER=true with the real proxy harness',
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

Future<KdsV2CommandResolution> _waitForAppliedResolution(
  KdsDualModeTransport transport,
  String commandId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (true) {
    final resolution = await transport.resolveCommand(
      commandId,
      originChannel: KdsActiveChannel.lan,
    );
    if (resolution.status == KdsV2CommandResolutionStatus.applied) {
      return resolution;
    }
    if (resolution.status == KdsV2CommandResolutionStatus.rejected) {
      throw StateError('debug command rejected after cloud recovery');
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('command did not reach APPLIED within 15 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void _expectSameAuthoritySnapshot(
  KdsV2Bootstrap actual,
  KdsV2Bootstrap expected,
) {
  expect(actual.shopId, expected.shopId);
  expect(actual.eventSeq, expected.eventSeq);
  expect(actual.config, expected.config);
  expect(actual.queueCounts, expected.queueCounts);
  expect(
    actual.lines.map(_lineIdentity).toList(growable: false),
    expected.lines.map(_lineIdentity).toList(growable: false),
  );
}

(int, int, int, String, num) _lineIdentity(KdsV2Line line) => (
      line.orderId,
      line.detailId,
      line.revision,
      line.queue,
      line.quantity,
    );

Future<void> _waitForHarnessState(
  File file,
  String expected, {
  bool? cloudForwarding,
}) =>
    _waitUntil(
      () {
        if (!file.existsSync()) return false;
        final body = jsonDecode(file.readAsStringSync());
        return body is Map &&
            body['state'] == expected &&
            (cloudForwarding == null ||
                body['cloud_forwarding'] == cloudForwarding);
      },
      timeout: const Duration(seconds: 10),
    );

Future<void> _waitUntil(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not reached within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim() ?? '';
  if (value.isEmpty) throw StateError('$name is required');
  return value;
}
