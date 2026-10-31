import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import 'cashier_kds_proxy.dart';

class AdminApiCashierKdsProxyClient {
  AdminApiCashierKdsProxyClient(
    this._client, {
    required String cashierDeviceCode,
  }) : _cashierDeviceCode = _validatedDeviceCode(cashierDeviceCode);

  final AdminApiClient _client;
  final String _cashierDeviceCode;

  String get cloudBaseUrl => _client.baseUrl;
  String get cashierDeviceCode => _cashierDeviceCode;

  Map<String, String> get _fencingHeaders => {
    'X-Cashier-Device-Code': _cashierDeviceCode,
  };

  Future<CashierKdsProxyResponse> proxyDeviceLogin(
    CashierKdsLoginRequest request, {
    int? shopId,
  }) async {
    final client = shopId != null ? _client.copyWith(shopId: shopId) : _client;
    final response = await client.requestRaw(
      const AdminEndpoint(
        method: 'POST',
        path: '/kds/device/login',
        permissionCode: 'cashier:operate',
        preserveEmptyStrings: true,
        preserveEmptyCollections: true,
      ),
      headers: {
        ..._fencingHeaders,
        if (request.deviceToken != null && request.deviceToken!.isNotEmpty)
          'X-Kds-Device-Token': request.deviceToken!,
        'X-KDS-Proxy-Request-Id': request.requestId,
        'Via': 'cashier-lan/1.0',
      },
      body: request.body,
    );
    return CashierKdsProxyResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }

  Future<CashierKdsProxyResponse> proxyKdsHttp(
    CashierKdsProxyRequest request, {
    int? shopId,
  }) async {
    final client = shopId != null ? _client.copyWith(shopId: shopId) : _client;
    final response = await client.requestRaw(
      AdminEndpoint(
        method: request.method,
        path: request.path,
        permissionCode: 'cashier:operate',
        preserveEmptyStrings: true,
        preserveEmptyCollections: true,
      ),
      query: request.query,
      body: request.body,
      headers: {
        ..._fencingHeaders,
        'X-Kds-Device-Token': request.deviceToken,
        'X-KDS-Proxy-Device-Code': _cashierDeviceCode,
        'X-KDS-Proxy-Request-Id': request.requestId,
        'X-Request-Id': request.requestId,
        if (request.commandId != null && request.commandId!.trim().isNotEmpty)
          'X-KDS-Command-Id': request.commandId!.trim(),
        if (request.deviceCode != null && request.deviceCode!.trim().isNotEmpty)
          'X-KDS-Device-Code': request.deviceCode!.trim(),
        'Via': 'cashier-lan/1.0',
      },
    );
    return CashierKdsProxyResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }
}

String _validatedDeviceCode(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 64) {
    throw ArgumentError.value(
      value,
      'cashierDeviceCode',
      'must be 1..64 chars',
    );
  }
  return normalized;
}
