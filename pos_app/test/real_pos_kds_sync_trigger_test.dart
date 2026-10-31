import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/features/pos/data/real_pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful add dishes immediately triggers a KDS cloud pull', () async {
    var pulls = 0;
    final transport = _SuccessTransport();
    final repository = RealPosRepository(
      AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'token',
        shopId: 1,
      ),
      onKitchenOrderChanged: () => pulls++,
    );
    final dish = PosDish.fromJson({
      'id': 7,
      'name': '测试菜品',
      'typeId': 3,
      'unitprice': 15,
      'unit': '份',
    });

    await repository.addDishes(
      orderNo: 'ORD-1',
      tableNumber: 'A01',
      lines: const PosCart().add(dish).lines,
      clientRequestId: 'stable-add-dishes-1',
    );

    expect(pulls, 1);
    expect(
      transport.lastHeaders['X-Client-Request-Id'],
      'stable-add-dishes-1',
    );
  });
}

class _SuccessTransport implements HttpTransport {
  Map<String, String> lastHeaders = const {};

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    lastHeaders = headers;
    return HttpResponseData(
      statusCode: 200,
      body: jsonEncode({'code': 200, 'data': <String, Object?>{}}),
    );
  }
}
