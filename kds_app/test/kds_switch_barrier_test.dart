import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/lan_v2/kds_dual_mode_transport.dart';
import 'package:kds_app/core/lan_v2/kds_v2_controller.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';

void main() {
  test(
      'T007 End-to-End Barrier: Failover handover barrier, in-flight wait, anti-regression recovery barrier',
      () async {
    // 1. Initial State: Both LAN and Cloud are ready.
    final lan = _MockBarrierTransport(
      bootstrapData: _bootstrap(
        shopId: 100,
        eventSeq: 1,
        lines: [
          _line(detailId: 1, orderId: 10, revision: 1, queue: 'pending_cook')
        ],
      ),
    );

    final cloud = _MockBarrierTransport(
      bootstrapData: _bootstrap(
        shopId: 100,
        eventSeq: 1,
        lines: [
          _line(detailId: 1, orderId: 10, revision: 1, queue: 'pending_cook')
        ],
      ),
    );

    final stateHistory = <KdsChannelState>[];
    final channelHistory = <KdsActiveChannel>[];

    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.lan,
      onChannelStateChanged: stateHistory.add,
      onChannelSwitched: channelHistory.add,
    );
    addTearDown(transport.dispose);

    // Initial bootstrap on LAN
    final initialBoot = await transport.bootstrap();
    expect(initialBoot.lines.first.revision, 1);
    expect(transport.activeChannel, KdsActiveChannel.lan);
    expect(transport.channelState, KdsChannelState.stable);

    // 2. Simulate LAN failure during write -> Failover Barrier
    lan.failCommands = true;
    final failoverCmd = KdsV2Command(
      commandId: 'cmd-failover-1',
      type: KdsV2CommandType.advanceItem,
      target: const KdsV2CommandTarget(detailId: 1, fromQueue: 'pending_cook'),
      quantity: 1,
      expectedRevision: 1,
    );

    await expectLater(
      transport.command(failoverCmd),
      throwsA(isA<ApiException>()),
    );

    // Failover barrier triggered: entered handover and transitioned to cloud
    expect(channelHistory, contains(KdsActiveChannel.cloud));
    expect(stateHistory, contains(KdsChannelState.handover));
    expect(transport.activeChannel, KdsActiveChannel.cloud);
    expect(transport.channelState, KdsChannelState.handover);

    // 3. While on Cloud: Kitchen marks dish as completed (cooked/ready)
    cloud.bootstrapData = _bootstrap(
      shopId: 100,
      eventSeq: 5,
      lines: [
        _line(detailId: 1, orderId: 10, revision: 3, queue: 'ready_serve')
      ],
    );

    // KDS refreshes from Cloud while operating in cloudDirect
    final cloudBoot = await transport.bootstrap();
    expect(transport.channelState, KdsChannelState.stable);
    expect(cloudBoot.lines.first.queue, 'ready_serve');
    expect(cloudBoot.lines.first.revision, 3);
    expect(transport.cloudMaxObservedRevisionByDetailId[1], 3);

    // 4. LAN Cashier restarts/reconnects with STALE data (still revision 1, pending_cook)
    // Anti-resurrection barrier test: LAN bootstrap must be rejected!
    lan.failCommands = false;
    lan.bootstrapData = _bootstrap(
      shopId: 100,
      eventSeq: 1,
      lines: [
        _line(detailId: 1, orderId: 10, revision: 1, queue: 'pending_cook')
      ],
    );

    final staleLanBoot = await lan.bootstrap();
    final canFailbackStale = transport.verifyLanRecoveryBarrier(staleLanBoot);
    expect(
      canFailbackStale,
      isFalse,
      reason:
          'Recovery barrier must block failback when LAN has stale revision to prevent dish resurrection!',
    );

    // 5. Cashier syncs inbound from Cloud: LAN now catches up to revision 3
    lan.bootstrapData = _bootstrap(
      shopId: 100,
      eventSeq: 5,
      lines: [
        _line(detailId: 1, orderId: 10, revision: 3, queue: 'ready_serve')
      ],
    );

    final caughtUpBoot = await lan.bootstrap();
    final canFailbackCaughtUp =
        transport.verifyLanRecoveryBarrier(caughtUpBoot);
    expect(
      canFailbackCaughtUp,
      isTrue,
      reason:
          'Recovery barrier permits failback once LAN revisions match or exceed Cloud!',
    );
  });

  test('T007 Cloud Replica Probe resolves UNKNOWN LAN commands during outage',
      () async {
    final lan = _MockBarrierTransport();
    final cloud = _MockBarrierTransport(
      resolutions: {
        'cmd-lan-unknown-1': KdsV2CommandResolution(
          commandId: 'cmd-lan-unknown-1',
          status: KdsV2CommandResolutionStatus.applied,
          result: KdsV2CommandResult(
            commandId: 'cmd-lan-unknown-1',
            duplicate: true,
            eventSeq: 12,
            patches: const [],
            queueCounts: const {},
          ),
        ),
      },
    );

    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.cloud,
    );
    addTearDown(transport.dispose);

    // While activeChannel is cloud, probe LAN-origin command via cloud replica probe
    final resolution = await transport.resolveCommand(
      'cmd-lan-unknown-1',
      originChannel: KdsActiveChannel.lan,
    );

    expect(resolution.status, KdsV2CommandResolutionStatus.applied);
    expect(resolution.result?.eventSeq, 12);
  });
}

KdsV2Bootstrap _bootstrap({
  required int shopId,
  required int eventSeq,
  required List<KdsV2Line> lines,
  Map<String, dynamic> stats = const {},
}) =>
    KdsV2Bootstrap(
      shopId: shopId,
      eventSeq: eventSeq,
      lines: lines,
      queueCounts: const {},
      stats: stats,
      catalog: const [],
      config: const {},
    );

KdsV2Line _line({
  required int detailId,
  required int orderId,
  required int revision,
  required String queue,
}) =>
    KdsV2Line.fromJson({
      'detail_id': detailId,
      'order_id': orderId,
      'cloud_detail_id': detailId,
      'cloud_order_id': orderId,
      'dish_id': 101,
      'dish_name': '特制烤羊肉串',
      'line_quantity': 2,
      'refunded_quantity': 0,
      'prep_remaining': 0,
      'cook_remaining': queue == 'pending_cook' ? 2 : 0,
      'ready_remaining': 2,
      'local_revision': revision,
      'order_revision': 1,
      'fulfillment_bucket': 'dine_in',
      'table_number': 'T08',
      'order_no': 'ORD20260913001',
      'specification': '微辣',
      'unit': '手',
      'remark': '',
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      'held': false,
      'rushed': false,
      'lacked': false,
      'removed': false,
      'workflow_queue': queue,
    });

class _MockBarrierTransport implements KdsV2Transport, KdsV2CommandResolver {
  _MockBarrierTransport({
    this.bootstrapData,
    this.resolutions = const {},
  });

  KdsV2Bootstrap? bootstrapData;
  bool failCommands = false;
  final Map<String, KdsV2CommandResolution> resolutions;

  @override
  Future<KdsV2Bootstrap> bootstrap() async =>
      bootstrapData ?? (throw StateError('bootstrap data not set'));

  @override
  Future<KdsV2CommandResult> command(KdsV2Command command) async {
    if (failCommands) {
      throw ApiException('LAN network timeout', isNetworkError: true);
    }
    return KdsV2CommandResult(
      commandId: command.commandId,
      duplicate: false,
      eventSeq: 1,
      patches: const [],
      queueCounts: const {},
    );
  }

  @override
  Future<KdsV2CommandResolution> resolveCommand(String commandId) async {
    return resolutions[commandId] ??
        KdsV2CommandResolution(
          commandId: commandId,
          status: KdsV2CommandResolutionStatus.notFound,
        );
  }

  @override
  Future<Map<String, dynamic>> businessDayOrders(
          {int? afterId, int limit = 200}) =>
      throw UnimplementedError();

  @override
  Future<KdsV2Changes> changes(int afterSeq) => throw UnimplementedError();

  @override
  Future<void> updateConfig(Map<String, dynamic> config) =>
      throw UnimplementedError();
}
