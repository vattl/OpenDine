import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_v2_client.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';

void main() {
  test('uses only locked LAN v2 paths and after_seq', () async {
    final http = FakeHttp();
    final client = KdsV2Client(http);
    await client.bootstrap();
    await client.changes(8);
    await client.command(KdsV2Command(
      commandId: 'c1',
      type: KdsV2CommandType.advanceItem,
      target: const KdsV2CommandTarget(detailId: 2),
    ));
    await client.resolveCommand('c1');

    expect(http.calls, [
      'GET /kds/v2/bootstrap {}',
      'GET /kds/v2/changes {after_seq: 8}',
      'POST /kds/v2/commands',
      'GET /kds/v2/commands/c1 {}',
    ]);
  });

  test('updates shared prep workflow through the dual-mode V2 endpoint',
      () async {
    final http = FakeHttp();
    final client = KdsV2Client(http);

    await client.updateConfig(const {
      'enable_prep_workflow': 0,
      'prep_enabled': 0,
    });

    expect(http.calls, ['POST /kds/v2/config']);
  });

  test('accepted offline is an ambiguous pending result, not a malformed ack',
      () async {
    final http = FakeHttp()..acceptOffline = true;
    final client = KdsV2Client(http);

    await expectLater(
      client.command(KdsV2Command(
        commandId: 'pending-1',
        type: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(detailId: 2),
      )),
      throwsA(
        isA<KdsCommandAcceptedOffline>().having(
          (error) => error.commandId,
          'commandId',
          'pending-1',
        ),
      ),
    );
  });

  test('parses a stable rejected command resolution', () async {
    final http = FakeHttp()..rejectResolution = true;
    final resolution = await KdsV2Client(http).resolveCommand('c1');

    expect(resolution.status, KdsV2CommandResolutionStatus.rejected);
    expect(resolution.result, isNull);
  });
}

class FakeHttp implements KdsV2Http {
  final calls = <String>[];
  bool acceptOffline = false;
  bool rejectResolution = false;
  @override
  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? query}) async {
    calls.add('GET $path ${query ?? {}}');
    if (path.endsWith('bootstrap')) {
      return {'protocol_version': 2, 'event_seq': 0, 'queues': {}};
    }
    if (path.contains('/commands/')) {
      return {
        'protocol_version': 2,
        'command_id': 'c1',
        'status': rejectResolution ? 'REJECTED' : 'NOT_FOUND',
      };
    }
    return {
      'protocol_version': 2,
      'event_seq': query?['after_seq'] ?? 0,
      'snapshot_required': false,
      'events': []
    };
  }

  @override
  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic>? body}) async {
    calls.add('POST $path');
    if (acceptOffline && path == '/kds/v2/commands') {
      return {
        'protocol_version': 2,
        'command_id': body!['command_id'],
        'status': 'ACCEPTED_OFFLINE',
      };
    }
    return {
      'command_id': body!['command_id'],
      'duplicate': false,
      'event_seq': 1,
      'patches': [],
      'queue_counts': {},
    };
  }

  @override
  Future<Map<String, dynamic>> put(String path,
      {Map<String, dynamic>? body}) async {
    calls.add('PUT $path');
    return <String, dynamic>{};
  }
}
