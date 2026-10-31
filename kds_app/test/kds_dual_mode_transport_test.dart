import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/lan_v2/kds_dual_mode_transport.dart';
import 'package:kds_app/core/lan_v2/kds_v2_controller.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';

void main() {
  KdsV2Command command() => KdsV2Command(
        commandId: 'cmd-ambiguous-1',
        type: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(
          detailId: 10,
          fromQueue: 'pending_cook',
        ),
        quantity: 1,
        expectedRevision: 2,
      );

  test('cloud bootstrap failure suggests LAN without switching automatically',
      () async {
    final suggestions = <KdsChannelSwitchSuggestion>[];
    final cloud = _FakeTransport(
      bootstrapError: ApiException('cloud link down', isNetworkError: true),
    );
    final lan = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 9,
        lines: const [],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.cloudFirst,
      onChannelSwitchSuggested: suggestions.add,
    );
    addTearDown(transport.dispose);

    await expectLater(transport.bootstrap(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);

    expect(cloud.bootstrapCalls, 1);
    expect(lan.bootstrapCalls, 1);
    expect(transport.activeChannel, KdsActiveChannel.cloud);
    expect(suggestions, hasLength(1));
    expect(suggestions.single.targetChannel, KdsActiveChannel.lan);
  });

  test('ambiguous cloud write suggests LAN without blind replay or auto switch',
      () async {
    final suggestions = <KdsChannelSwitchSuggestion>[];
    final cloud = _FakeTransport(
      commandError: ApiException('cloud ack lost', isNetworkError: true),
    );
    final lan = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 9,
        lines: const [],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.cloudFirst,
      onChannelSwitchSuggested: suggestions.add,
    );
    addTearDown(transport.dispose);

    await expectLater(
        transport.command(command()), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);

    expect(cloud.commandCalls, 1);
    expect(lan.commandCalls, 0);
    expect(transport.activeChannel, KdsActiveChannel.cloud);
    expect(suggestions.single.targetChannel, KdsActiveChannel.lan);
  });

  test('LAN proxy resolves an ambiguous cloud-origin command after failover',
      () async {
    final cloud = _FakeTransport();
    final lan = _FakeTransport(
      resolutionStatus: KdsV2CommandResolutionStatus.applied,
    );
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.cloudFirst,
      initialChannel: KdsActiveChannel.lan,
    );
    addTearDown(transport.dispose);

    final result = await transport.resolveCommand(
      'cmd-cloud-origin',
      originChannel: KdsActiveChannel.cloud,
    );

    expect(result.status, KdsV2CommandResolutionStatus.applied);
    expect(lan.resolveCalls, 1);
    expect(cloud.resolveCalls, 0);
  });

  test('cloud websocket disconnect suggests LAN and keeps cloud selected',
      () async {
    final suggestions = <KdsChannelSwitchSuggestion>[];
    final transport = KdsDualModeTransport(
      lanTransport: _FakeTransport(
        bootstrapResult: KdsV2Bootstrap(
          shopId: 1,
          eventSeq: 1,
          lines: const [],
          queueCounts: const {},
          stats: const {},
          catalog: const [],
          config: const {},
        ),
      ),
      cloudTransport: _FakeTransport(),
      mode: KdsConnectionMode.cloudFirst,
      onChannelSwitchSuggested: suggestions.add,
    );
    addTearDown(transport.dispose);

    transport.reportRealtimeDisconnected(KdsActiveChannel.cloud);
    await Future<void>.delayed(Duration.zero);

    expect(transport.activeChannel, KdsActiveChannel.cloud);
    expect(transport.channelState, KdsChannelState.switchRecommended);
    expect(suggestions.single.targetChannel, KdsActiveChannel.lan);
  });

  test('confirmed manual switch validates bootstrap before changing channel',
      () async {
    final channels = <KdsActiveChannel>[];
    final lan = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 9,
        lines: const [],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: _FakeTransport(),
      mode: KdsConnectionMode.cloudFirst,
      expectedShopId: 1,
      onChannelSwitched: channels.add,
    );
    addTearDown(transport.dispose);

    final switched = await transport.requestChannelSwitch(KdsActiveChannel.lan);

    expect(switched, isTrue);
    expect(lan.bootstrapCalls, 1);
    expect(transport.activeChannel, KdsActiveChannel.lan);
    expect(transport.channelState, KdsChannelState.handover);
    expect(channels, [KdsActiveChannel.lan]);
  });

  test('LAN disconnect suggests recovered cloud without automatic failback',
      () async {
    final suggestions = <KdsChannelSwitchSuggestion>[];
    final transport = KdsDualModeTransport(
      lanTransport: _FakeTransport(),
      cloudTransport: _FakeTransport(
        bootstrapResult: KdsV2Bootstrap(
          shopId: 1,
          eventSeq: 12,
          lines: const [],
          queueCounts: const {},
          stats: const {},
          catalog: const [],
          config: const {},
        ),
      ),
      mode: KdsConnectionMode.cloudFirst,
      initialChannel: KdsActiveChannel.lan,
      expectedShopId: 1,
      onChannelSwitchSuggested: suggestions.add,
    );
    addTearDown(transport.dispose);

    transport.reportRealtimeDisconnected(KdsActiveChannel.lan);
    await Future<void>.delayed(Duration.zero);

    expect(transport.activeChannel, KdsActiveChannel.lan);
    expect(suggestions.single.targetChannel, KdsActiveChannel.cloud);
  });

  test('manual cloud switch is blocked when authority cursor is behind',
      () async {
    final lan = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 12,
        lines: const [],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final cloud = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 11,
        lines: const [],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.cloudFirst,
      initialChannel: KdsActiveChannel.lan,
      expectedShopId: 1,
    );
    addTearDown(transport.dispose);
    await transport.bootstrap();

    await expectLater(
      transport.requestChannelSwitch(KdsActiveChannel.cloud),
      throwsA(isA<StateError>()),
    );

    expect(transport.activeChannel, KdsActiveChannel.lan);
  });

  test('dual bootstrap failure is exposed and a later LAN success clears it',
      () async {
    final states = <KdsChannelState>[];
    final cloud = _FakeTransport(
      bootstrapError: ApiException('cloud down', isNetworkError: true),
    );
    final failingLan = _FakeTransport(
      bootstrapError: ApiException('lan down', isNetworkError: true),
    );
    final failedTransport = KdsDualModeTransport(
      lanTransport: failingLan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.cloudFirst,
      onChannelStateChanged: states.add,
    );
    addTearDown(failedTransport.dispose);

    await expectLater(
        failedTransport.bootstrap(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);
    expect(failedTransport.activeChannel, KdsActiveChannel.cloud);
    expect(failedTransport.channelState, KdsChannelState.unavailable);
    expect(states.last, KdsChannelState.unavailable);

    final recoveredTransport = KdsDualModeTransport(
      lanTransport: _FakeTransport(
        bootstrapResult: KdsV2Bootstrap(
          shopId: 1,
          eventSeq: 1,
          lines: const [],
          queueCounts: const {},
          stats: const {},
          catalog: const [],
          config: const {},
        ),
      ),
      cloudTransport: cloud,
      mode: KdsConnectionMode.cloudFirst,
      initialChannel: KdsActiveChannel.lan,
    );
    addTearDown(recoveredTransport.dispose);
    recoveredTransport.reportActiveChannelUnavailable('both down');

    await recoveredTransport.bootstrap();

    expect(recoveredTransport.channelState, KdsChannelState.stable);
  });

  test('LAN link failure during cloud-first fallback exposes dual outage',
      () async {
    final lan = _FakeTransport(
      commandError: ApiException('lan link down', isNetworkError: true),
    );
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: _FakeTransport(),
      mode: KdsConnectionMode.cloudFirst,
      initialChannel: KdsActiveChannel.lan,
    );
    addTearDown(transport.dispose);

    await expectLater(
        transport.command(command()), throwsA(isA<ApiException>()));

    expect(transport.channelState, KdsChannelState.unavailable);
    expect(lan.commandCalls, 1);
  });

  test('ambiguous LAN write switches health but is not replayed to cloud',
      () async {
    final lan = _FakeTransport(
      commandError: ApiException('ack lost', isNetworkError: true),
    );
    final cloud = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 9,
        lines: [_line(localDetailId: 110, localOrderId: 120)],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
    );
    addTearDown(transport.dispose);

    await expectLater(
        transport.command(command()), throwsA(isA<ApiException>()));

    expect(lan.commandCalls, 1);
    expect(cloud.commandCalls, 0);
    expect(transport.activeChannel, KdsActiveChannel.cloud);
  });

  test('LAN business rejection neither switches channel nor calls cloud',
      () async {
    final lan = _FakeTransport(
      commandError: ApiException('revision conflict', statusCode: 409),
    );
    final cloud = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 9,
        lines: [_line(localDetailId: 110, localOrderId: 120)],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
    );
    addTearDown(transport.dispose);

    await expectLater(
        transport.command(command()), throwsA(isA<ApiException>()));

    expect(lan.commandCalls, 1);
    expect(cloud.commandCalls, 0);
    expect(transport.activeChannel, KdsActiveChannel.lan);
  });

  test('LAN 401 logs out at the session boundary without switching channel',
      () async {
    final lan = _FakeTransport(
      commandError: ApiException('token revoked', statusCode: 401, code: 401),
    );
    final cloud = _FakeTransport();
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
    );
    addTearDown(transport.dispose);

    await expectLater(
      transport.command(command()),
      throwsA(isA<ApiException>()),
    );

    expect(lan.commandCalls, 1);
    expect(cloud.commandCalls, 0);
    expect(transport.activeChannel, KdsActiveChannel.lan);
  });

  test('cloud can confirm a replicated LAN command while LAN is down',
      () async {
    final lan = _FakeTransport();
    final cloud = _FakeTransport(
      resolutionStatus: KdsV2CommandResolutionStatus.applied,
    );
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.cloud,
    );
    addTearDown(transport.dispose);

    final resolution = await transport.resolveCommand(
      'cmd-ambiguous-1',
      originChannel: KdsActiveChannel.lan,
    );

    expect(resolution.status, KdsV2CommandResolutionStatus.applied);
    expect(lan.resolveCalls, 0);
    expect(cloud.resolveCalls, 1);
  });

  test('cloud NOT_FOUND never authorizes replay of a LAN-origin command',
      () async {
    final lan = _FakeTransport();
    final cloud = _FakeTransport();
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.cloud,
    );
    addTearDown(transport.dispose);

    await expectLater(
      transport.resolveCommand(
        'cmd-ambiguous-1',
        originChannel: KdsActiveChannel.lan,
      ),
      throwsA(isA<KdsCommandStillUnknown>()),
    );

    expect(lan.resolveCalls, 0);
    expect(cloud.resolveCalls, 1);
  });

  test('cloud takeover preserves the complete command identity and payload',
      () async {
    final lan = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 7,
        lines: [_line(localDetailId: 10, localOrderId: 20)],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final cloud = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 9,
        lines: [_line(localDetailId: 110, localOrderId: 120)],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
    );
    addTearDown(transport.dispose);

    await transport.bootstrap();
    transport.updateMode(KdsConnectionMode.cloudDirect);
    await transport.bootstrap();
    await transport.command(KdsV2Command(
      commandId: 'cmd-stable-id-1',
      type: KdsV2CommandType.advanceItem,
      target: const KdsV2CommandTarget(
        orderId: 20,
        detailId: 10,
        detailIds: [10],
        fromQueue: 'pending_cook',
      ),
      quantity: 1,
      expectedRevision: 2,
      expectedRevisions: const {10: 2},
    ));

    expect(cloud.lastCommand?.commandId, 'cmd-stable-id-1');
    expect(cloud.lastCommand?.target.orderId, 20);
    expect(cloud.lastCommand?.target.detailId, 10);
    expect(cloud.lastCommand?.target.detailIds, [10]);
    expect(cloud.lastCommand?.expectedRevisions, {10: 2});
  });

  test('failover barrier engages handover state and notifies listener',
      () async {
    final lan = _FakeTransport(
      commandError: ApiException('lan down', isNetworkError: true),
    );
    final cloud = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 1,
        lines: const [],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final states = <KdsChannelState>[];
    final channels = <KdsActiveChannel>[];

    final transport = KdsDualModeTransport(
      lanTransport: lan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
      onChannelStateChanged: states.add,
      onChannelSwitched: channels.add,
    );
    addTearDown(transport.dispose);

    expect(transport.channelState, KdsChannelState.stable);
    await expectLater(
      transport.command(command()),
      throwsA(isA<ApiException>()),
    );

    expect(channels, contains(KdsActiveChannel.cloud));
    expect(states, contains(KdsChannelState.handover));
    expect(transport.channelState, KdsChannelState.handover);
    expect(transport.activeChannel, KdsActiveChannel.cloud);
    await transport.bootstrap();
    expect(transport.channelState, KdsChannelState.stable);
  });

  test('LAN websocket disconnect immediately hands realtime traffic to cloud',
      () {
    final channels = <KdsActiveChannel>[];
    final transport = KdsDualModeTransport(
      lanTransport: _FakeTransport(),
      cloudTransport: _FakeTransport(),
      mode: KdsConnectionMode.lanFirst,
      onChannelSwitched: channels.add,
    );
    addTearDown(transport.dispose);

    transport.reportRealtimeDisconnected(KdsActiveChannel.lan);

    expect(transport.activeChannel, KdsActiveChannel.cloud);
    expect(transport.channelState, KdsChannelState.handover);
    expect(channels, [KdsActiveChannel.cloud]);
  });

  test('stale LAN websocket disconnect cannot disturb active cloud channel',
      () {
    final channels = <KdsActiveChannel>[];
    final transport = KdsDualModeTransport(
      lanTransport: _FakeTransport(),
      cloudTransport: _FakeTransport(),
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.cloud,
      onChannelSwitched: channels.add,
    );
    addTearDown(transport.dispose);

    transport.reportRealtimeDisconnected(KdsActiveChannel.lan);

    expect(transport.activeChannel, KdsActiveChannel.cloud);
    expect(transport.channelState, KdsChannelState.stable);
    expect(channels, isEmpty);
  });

  test(
      'recovery barrier blocks failback when LAN bootstrap has stale revisions',
      () async {
    final cloud = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 10,
        lines: [_line(localDetailId: 10, localOrderId: 20, revision: 5)],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final staleLan = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 5,
        // LAN still has revision 2, whereas cloud reached revision 5!
        lines: [_line(localDetailId: 10, localOrderId: 20, revision: 2)],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );

    final transport = KdsDualModeTransport(
      lanTransport: staleLan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.cloud,
    );
    addTearDown(transport.dispose);

    // KDS bootstraps from Cloud while on Cloud
    await transport.bootstrap();
    expect(transport.cloudMaxObservedRevisionByDetailId[10], 5);

    // Barrier check on stale LAN bootstrap must fail!
    final staleBoot = await staleLan.bootstrap();
    expect(transport.verifyLanRecoveryBarrier(staleBoot), isFalse);
  });

  test('recovery barrier permits failback when LAN revisions catch up to cloud',
      () async {
    final cloud = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 10,
        lines: [_line(localDetailId: 10, localOrderId: 20, revision: 5)],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final freshLan = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 10,
        // LAN has synced and caught up to revision 5
        lines: [_line(localDetailId: 10, localOrderId: 20, revision: 5)],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );

    final transport = KdsDualModeTransport(
      lanTransport: freshLan,
      cloudTransport: cloud,
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.cloud,
    );
    addTearDown(transport.dispose);

    await transport.bootstrap();
    final freshBoot = await freshLan.bootstrap();
    expect(transport.verifyLanRecoveryBarrier(freshBoot), isTrue);
  });

  test('recovery barrier blocks failback when cashier outbox is auth_paused',
      () async {
    final pausedLan = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 10,
        lines: const [],
        queueCounts: const {},
        stats: {'outbox_auth_paused': 1},
        catalog: const [],
        config: const {},
      ),
    );
    final transport = KdsDualModeTransport(
      lanTransport: pausedLan,
      cloudTransport: _FakeTransport(),
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.cloud,
    );
    addTearDown(transport.dispose);

    final boot = await pausedLan.bootstrap();
    expect(transport.verifyLanRecoveryBarrier(boot), isFalse);
  });

  test(
      'recovery barrier blocks failback when shopId does not match expectedShopId (T-F03-1)',
      () async {
    final mismatchedLan = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 99, // Wrong shop!
        eventSeq: 10,
        lines: const [],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final transport = KdsDualModeTransport(
      lanTransport: mismatchedLan,
      cloudTransport: _FakeTransport(),
      expectedShopId: 1, // Expected shop is 1
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.cloud,
    );
    addTearDown(transport.dispose);

    final boot = await mismatchedLan.bootstrap();
    expect(transport.verifyLanRecoveryBarrier(boot), isFalse);
  });

  test(
      'recovery barrier blocks failback when cloud observed active lines are missing from LAN (T-F03-2)',
      () async {
    final cloud = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 10,
        lines: [
          _line(localDetailId: 10, localOrderId: 20, revision: 5),
          _line(
              localDetailId: 11,
              localOrderId: 20,
              revision: 1), // Newly added line on cloud!
        ],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final incompleteLan = _FakeTransport(
      bootstrapResult: KdsV2Bootstrap(
        shopId: 1,
        eventSeq: 8,
        // LAN has line 10, but is missing line 11
        lines: [_line(localDetailId: 10, localOrderId: 20, revision: 5)],
        queueCounts: const {},
        stats: const {},
        catalog: const [],
        config: const {},
      ),
    );
    final transport = KdsDualModeTransport(
      lanTransport: incompleteLan,
      cloudTransport: cloud,
      expectedShopId: 1,
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.cloud,
    );
    addTearDown(transport.dispose);

    await transport.bootstrap();
    expect(transport.cloudObservedActiveDetailIds.contains(10), isTrue);
    expect(transport.cloudObservedActiveDetailIds.contains(11), isTrue);

    // Incomplete LAN snapshot is rejected!
    final incompleteBoot = await incompleteLan.bootstrap();
    expect(transport.verifyLanRecoveryBarrier(incompleteBoot), isFalse);
  });

  test('completeHandover releases handover barrier state (T-F03-3)', () {
    final transport = KdsDualModeTransport(
      lanTransport: _FakeTransport(),
      cloudTransport: _FakeTransport(),
      mode: KdsConnectionMode.lanFirst,
      initialChannel: KdsActiveChannel.lan,
    );
    addTearDown(transport.dispose);

    transport.updateMode(KdsConnectionMode.cloudDirect);
    expect(transport.channelState, KdsChannelState.handover);

    transport.completeHandover();
    expect(transport.channelState, KdsChannelState.stable);
  });
}

KdsV2Line _line({
  required int localDetailId,
  required int localOrderId,
  int revision = 2,
}) =>
    KdsV2Line.fromJson({
      'detail_id': localDetailId,
      'order_id': localOrderId,
      'cloud_detail_id': 110,
      'cloud_order_id': 120,
      'dish_id': 1,
      'dish_name': '测试菜',
      'line_quantity': 1,
      'refunded_quantity': 0,
      'prep_remaining': 0,
      'cook_remaining': 1,
      'ready_remaining': 1,
      'local_revision': revision,
      'order_revision': 3,
      'fulfillment_bucket': 'dine_in',
      'table_number': 'A1',
      'order_no': 'ORDER-1',
      'specification': '',
      'unit': '份',
      'remark': '',
      'created_at_ms': 1,
      'held': false,
      'rushed': false,
      'lacked': false,
      'removed': false,
      'workflow_queue': 'pending_cook',
    });

class _FakeTransport implements KdsV2Transport, KdsV2CommandResolver {
  _FakeTransport({
    this.commandError,
    this.bootstrapError,
    this.resolutionStatus = KdsV2CommandResolutionStatus.notFound,
    this.bootstrapResult,
  });

  final Object? commandError;
  final Object? bootstrapError;
  final KdsV2CommandResolutionStatus resolutionStatus;
  final KdsV2Bootstrap? bootstrapResult;
  int commandCalls = 0;
  int resolveCalls = 0;
  int bootstrapCalls = 0;
  KdsV2Command? lastCommand;

  @override
  Future<KdsV2CommandResult> command(KdsV2Command command) async {
    commandCalls++;
    lastCommand = command;
    if (commandError case final error?) throw error;
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
    resolveCalls++;
    return KdsV2CommandResolution(
      commandId: commandId,
      status: resolutionStatus,
      result: resolutionStatus == KdsV2CommandResolutionStatus.applied
          ? KdsV2CommandResult(
              commandId: commandId,
              duplicate: false,
              eventSeq: 8,
              patches: const [],
              queueCounts: const {},
            )
          : null,
    );
  }

  @override
  Future<KdsV2Bootstrap> bootstrap() async {
    bootstrapCalls++;
    if (bootstrapError case final error?) throw error;
    return bootstrapResult ?? (throw UnimplementedError());
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
