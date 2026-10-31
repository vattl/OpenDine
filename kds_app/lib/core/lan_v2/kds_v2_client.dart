import 'package:kds_app/core/api/kds_api_client.dart';
import 'package:kds_app/core/lan_v2/kds_v2_controller.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';

abstract interface class KdsV2Http {
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  });
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  });
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  });
}

class KdsV2HttpAdapter implements KdsV2Http {
  const KdsV2HttpAdapter(this.client);
  final KdsApiClient client;
  @override
  Future<Map<String, dynamic>> get(String path,
          {Map<String, dynamic>? query}) =>
      client.get(path, query: query);
  @override
  Future<Map<String, dynamic>> post(String path,
          {Map<String, dynamic>? body}) =>
      client.post(path, body: body);
  @override
  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) =>
      client.put(path, body: body);
}

class KdsV2Client implements KdsV2Transport, KdsV2CommandResolver {
  const KdsV2Client(this.http);
  final KdsV2Http http;

  @override
  Future<KdsV2Bootstrap> bootstrap() async => KdsV2Bootstrap.fromJson(
        await http.get('/kds/v2/bootstrap'),
      );

  @override
  Future<Map<String, dynamic>> businessDayOrders(
          {int? afterId, int limit = 200}) =>
      http.get('/kds/v2/business-day/orders', query: {
        if (afterId != null) 'after_id': afterId,
        'limit': limit,
      });

  @override
  Future<KdsV2Changes> changes(int afterSeq) async => KdsV2Changes.fromJson(
        await http.get('/kds/v2/changes', query: {'after_seq': afterSeq}),
      );

  @override
  Future<KdsV2CommandResult> command(KdsV2Command command) async {
    final response =
        await http.post('/kds/v2/commands', body: command.toJson());
    final rawBody = response['data'];
    final body = rawBody is Map ? Map<String, dynamic>.from(rawBody) : response;
    if ('${body['status'] ?? ''}'.toUpperCase() == 'ACCEPTED_OFFLINE') {
      final commandId = '${body['command_id'] ?? ''}'.trim();
      if (commandId != command.commandId) {
        throw const FormatException(
          'KDS accepted-offline response command_id mismatch',
        );
      }
      throw KdsCommandAcceptedOffline(commandId);
    }
    return KdsV2CommandResult.fromJson(response);
  }

  @override
  Future<KdsV2CommandResolution> resolveCommand(String commandId) async =>
      KdsV2CommandResolution.fromJson(
        await http.get(
          '/kds/v2/commands/${Uri.encodeComponent(commandId)}',
        ),
      );

  @override
  Future<void> updateConfig(Map<String, dynamic> config) async {
    await http.post('/kds/v2/config', body: config);
  }
}
