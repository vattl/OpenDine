import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/api/api_response.dart';
import 'package:kds_app/core/api/kds_api_client.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';

class KdsDevice {
  KdsDevice(
      {required this.id,
      required this.shopId,
      required this.screenTag,
      required this.deviceCode,
      required this.deviceToken,
      this.workflows = const [],
      this.screenTags = const [],
      this.deviceName});
  final int id;
  final int shopId;
  final KdsScreenTag screenTag;
  final String deviceCode;
  final String deviceToken;
  final List<KdsWorkflow> workflows;

  /// D026 可见烤制岗（荤烤/素烤/海鲜）。空 = 三岗全选，与旧设备一致。
  final List<String> screenTags;
  final String? deviceName;

  factory KdsDevice.fromJson(Map<String, dynamic> json,
          {required String token}) =>
      KdsDevice(
        id: (json['id'] as num?)?.toInt() ?? 0,
        shopId: (json['shop_id'] as num?)?.toInt() ??
            (json['shopId'] as num?)?.toInt() ??
            0,
        screenTag: KdsScreenTag.fromValue(json['screen_tag'] as String? ??
                json['screenTag'] as String?) ??
            KdsScreenTag.workflowBoard,
        deviceCode: json['device_code'] as String? ??
            json['deviceCode'] as String? ??
            '',
        deviceToken: token,
        workflows: (json['workflows'] as List?)
                ?.map((v) => KdsWorkflow.fromValue('$v'))
                .whereType<KdsWorkflow>()
                .toList() ??
            const [],
        screenTags:
            (json['screen_tags'] as List? ?? json['screenTags'] as List?)
                    ?.whereType<String>()
                    .where((v) => v.trim().isNotEmpty)
                    .toList() ??
                const [],
        deviceName: (json['device_name'] ?? json['deviceName']) as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'shop_id': shopId,
        'screen_tag': screenTag.value,
        'device_code': deviceCode,
        'device_name': deviceName,
        'workflows': workflows.map((v) => v.apiValue).toList(),
        'screen_tags': screenTags,
      };
}

class KdsLanHealth {
  const KdsLanHealth({required this.shopId, required this.ready});
  final int? shopId;
  final bool ready;
}

/// Device identity only. Order business data lives behind [KdsV2Client].
class KdsApi {
  KdsApi(this._client);
  final KdsApiClient _client;

  Future<KdsLanHealth> health() async {
    final response = await _client.get('/kds/v2/health', skipAuth: true);
    _requireV2(response, '/kds/v2/health');
    final data = asJsonMap(response['data']) ?? response;
    final sqlite = asJsonMap(data['sqlite']);
    final primary = asJsonMap(data['primary_node']);
    final ready = sqlite?['status'] == 'ok' &&
        primary?['role'] == 'primary' &&
        primary?['authoritative'] == true;
    if (!ready) {
      throw ApiException('收银端本地 KDS 尚未处于可用主节点状态');
    }
    final shopId = (data['shop_id'] as num?)?.toInt();
    if (shopId == null || shopId <= 0) {
      throw ApiException('收银端本地 KDS 尚未绑定有效门店');
    }
    return KdsLanHealth(
      shopId: shopId,
      ready: true,
    );
  }

  Future<KdsDevice> login(
      {required String deviceCode,
      required KdsScreenTag screenTag,
      int? shopId,
      String? kdsPin,
      List<KdsWorkflow> workflows = const [],
      List<String> screenTags = const [],
      String? deviceName,
      String? pairingCode,
      String? currentToken}) async {
    final existingToken = currentToken?.trim() ?? '';
    final response = await _client.post(
      '/kds/device/login',
      skipAuth: true,
      // 登录端点由服务端控制器自行校验当前 Token / 配对凭据，因此跳过
      // 通用拦截器后仍需显式携带已有 Token，避免无凭据轮换。
      headers: existingToken.isEmpty
          ? null
          : {
              'X-Kds-Device-Token': existingToken,
            },
      body: {
        'protocol_version': 2,
        'device_code': deviceCode,
        'screen_tag': screenTag.value,
        if (shopId != null && shopId > 0) ...{
          'shop_id': shopId,
          'shopId': shopId,
        },
        if (kdsPin != null && kdsPin.trim().isNotEmpty) ...{
          'kds_pin': kdsPin.trim(),
          'kdsPin': kdsPin.trim(),
        },
        if (workflows.isNotEmpty)
          'workflows': workflows.map((v) => v.apiValue).toList(),
        // D026：可见烤制岗；不传/传空 = 三岗全选（与旧设备一致）
        if (screenTags.isNotEmpty) 'screen_tags': screenTags,
        if (deviceName != null && deviceName.trim().isNotEmpty)
          'device_name': deviceName.trim(),
        if (pairingCode != null && pairingCode.trim().isNotEmpty)
          'pairing_code': pairingCode.trim(),
      },
    );
    _requireV2(response, '/kds/device/login');
    final json = readDeviceJson(response);
    final token = json['device_token'] as String? ?? '';
    if (token.isEmpty) throw ApiException('登录响应缺少 device_token');
    return KdsDevice.fromJson(json, token: token);
  }

  Future<KdsDevice> fetchDeviceMe({required String token}) async {
    final response =
        await _client.get('/kds/device/me', query: {'protocol_version': 2});
    _requireV2(response, '/kds/device/me');
    return KdsDevice.fromJson(readDeviceJson(response), token: token);
  }

  /// 心跳必须携带 `X-Kds-Device-Token`（拦截器注入）；服务端以 token
  /// 绑定设备为准，body 中的 device_code 仅为旧版收银端兼容字段。
  Future<void> heartbeat(String deviceCode) async {
    final response = await _client.post('/kds/device/heartbeat',
        body: {'protocol_version': 2, 'device_code': deviceCode});
    _requireV2(response, '/kds/device/heartbeat');
  }
}

void _requireV2(Map<String, dynamic> response, String endpoint) {
  final data = asJsonMap(response['data']);
  final raw = response['protocol_version'] ?? data?['protocol_version'];
  final version = raw is num ? raw.toInt() : int.tryParse('$raw');
  if (version != 2) throw ApiException('$endpoint 未返回 protocol_version=2');
}
