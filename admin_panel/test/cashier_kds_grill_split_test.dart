import 'dart:convert';
import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_models.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_lan_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// D026 设备级岗分流（收银端）：设备可见岗 × 菜品所属岗过滤。
Future<Map<String, dynamic>> _jsonRequest(
  HttpClient client,
  CashierKdsLanServer server,
  String method,
  String path, {
  Map<String, Object?>? body,
  String? token,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:${server.port}$path'),
  );
  if (token != null) request.headers.set('X-Kds-Device-Token', token);
  request.headers.contentType = ContentType.json;
  if (body != null) request.write(jsonEncode(body));
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  return jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _login(
  HttpClient client,
  CashierKdsLanServer server,
  String deviceCode, {
  List<String> screenTags = const [],
}) async {
  server.upsertBoundDevice(
    shopId: 1,
    deviceCode: deviceCode,
    deviceName: deviceCode,
    screenTag: 'workflow_board',
    screenTags: screenTags,
  );
  final login = await _jsonRequest(
    client,
    server,
    'POST',
    '/kds/device/login',
    body: {
      'device_code': deviceCode,
      'screen_tag': 'workflow_board',
      'workflows': const ['prep', 'cook', 'serve'],
      if (screenTags.isNotEmpty) 'screen_tags': screenTags,
    },
  );
  expect(login['code'], 0);
  return login;
}

void main() {
  late CashierKdsDatabase database;
  late CashierKdsLanServer server;
  late HttpClient client;

  setUp(() async {
    database = CashierKdsDatabase.inMemory();
    // 菜品目录带岗（收银端随菜品数据传入 screen_tag）
    database.replaceDishCatalog(
      shopId: 1,
      updatedAtMs: 1001,
      items: const [
        CashierDishCatalogItem(
          dishId: 101,
          dishName: '牛肉串',
          unit: '串',
          sequence: 0,
          screenTag: 'meat_grill',
        ),
        CashierDishCatalogItem(
          dishId: 102,
          dishName: '韭菜串',
          unit: '串',
          sequence: 1,
          screenTag: 'veg_grill',
        ),
        CashierDishCatalogItem(
          dishId: 103,
          dishName: '生蚝',
          unit: '只',
          sequence: 2,
          screenTag: 'seafood_special',
        ),
        CashierDishCatalogItem(
          dishId: 104,
          dishName: '老火汤',
          unit: '盅',
          sequence: 3,
        ),
      ],
    );
    // 一个工单同时含四类菜品（荤/素/海鲜/无岗）
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '18',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 1000,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '牛肉串',
            specification: '',
            unit: '串',
            quantity: 2,
          ),
          CashierOrderLineDraft(
            dishId: 102,
            dishName: '韭菜串',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
          CashierOrderLineDraft(
            dishId: 103,
            dishName: '生蚝',
            specification: '',
            unit: '只',
            quantity: 3,
          ),
          CashierOrderLineDraft(
            dishId: 104,
            dishName: '老火汤',
            specification: '',
            unit: '盅',
            quantity: 1,
          ),
        ],
      ),
      eventId: 'grill-order-1',
    );
    server = CashierKdsLanServer(database, cloudAuthorityMode: false);
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    database.close();
  });

  List<String> pendingDishIds(Map<String, dynamic> board) {
    final data = board['data'] as Map;
    final lines = (data['queues'] as Map)['pending_prep'] as List;
    return lines
        .map((line) => '${(line as Map)['dish_id']}')
        .toList(growable: false);
  }

  test('login persists screen_tags on the paired device (D026)', () async {
    final login = await _login(client, server, 'KDS-MEAT-01',
        screenTags: const ['meat_grill']);

    final data = login['data'] as Map;
    expect((data['screen_tags'] as List).cast<String>(), ['meat_grill']);

    final devices = database.readDevices(shopId: 1);
    final device = devices.singleWhere((d) => d.deviceCode == 'KDS-MEAT-01');
    expect(device.screenTags, ['meat_grill']);
  });

  test('legacy device without screen_tags gets three-grill visibility',
      () async {
    final login = await _login(client, server, 'KDS-LEGACY');
    final data = login['data'] as Map;
    expect(data['screen_tags'], isEmpty);

    final board = await _jsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/bootstrap',
      token: data['device_token'] as String,
    );
    expect(board['code'], 0);
    expect(pendingDishIds(board).toSet(), {'101', '102', '103', '104'});
  });

  test('bootstrap filters lines by device grill tags (D026)', () async {
    final meat = await _login(client, server, 'KDS-MEAT-01',
        screenTags: const ['meat_grill']);
    final veg = await _login(client, server, 'KDS-VEG-01',
        screenTags: const ['veg_grill']);
    final seafood = await _login(client, server, 'KDS-SEA-01',
        screenTags: const ['seafood_special']);

    Future<List<String>> dishIds(Map login) async {
      final board = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: (login['data'] as Map)['device_token'] as String,
      );
      expect(board['code'], 0);
      return pendingDishIds(board);
    }

    // 各岗只看到本岗 + 无岗菜品（保守可见，防漏单）
    expect(await dishIds(meat), containsAll(['101', '104']));
    expect(await dishIds(meat), isNot(contains('102')));
    expect(await dishIds(meat), isNot(contains('103')));

    expect(await dishIds(veg), containsAll(['102', '104']));
    expect(await dishIds(veg), isNot(contains('101')));

    expect(await dishIds(seafood), containsAll(['103', '104']));
    expect(await dishIds(seafood), isNot(contains('101')));
  });

  test('bootstrap fixed_catalog carries dish screen_tag (D026)', () async {
    final login = await _login(client, server, 'KDS-MEAT-01',
        screenTags: const ['meat_grill']);
    final board = await _jsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/bootstrap',
      token: (login['data'] as Map)['device_token'] as String,
    );
    final catalog = (board['data'] as Map)['fixed_catalog'] as List;
    final byDish = {
      for (final item in catalog) '${(item as Map)['dish_id']}': item,
    };
    expect(byDish['101']?['screen_tag'], 'meat_grill');
    expect(byDish['102']?['screen_tag'], 'veg_grill');
    expect(byDish['104']?['screen_tag'], isNull);
  });

  test('WS broadcast filters patches by device grill tags (D026)', () async {
    final meat = await _login(client, server, 'KDS-MEAT-01',
        screenTags: const ['meat_grill']);
    final veg = await _login(client, server, 'KDS-VEG-01',
        screenTags: const ['veg_grill']);

    final meatWs = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/ws/kds/v2?token=${(meat['data'] as Map)['device_token']}',
    );
    addTearDown(meatWs.close);
    final vegWs = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/ws/kds/v2?token=${(veg['data'] as Map)['device_token']}',
    );
    addTearDown(vegWs.close);
    final meatEvent = meatWs.first.then((raw) => jsonDecode('$raw') as Map);
    final vegEvent = vegWs.first.then((raw) => jsonDecode('$raw') as Map);

    // 新工单：牛肉串（荤烤）+ 韭菜串（素烤）
    final receipt = database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '19',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 5000,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '牛肉串',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
          CashierOrderLineDraft(
            dishId: 102,
            dishName: '韭菜串',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
        ],
      ),
      eventId: 'grill-order-2',
    );
    server.broadcastNewOrder(1, receipt);

    final meatEventMap = await meatEvent.timeout(const Duration(seconds: 2));
    final vegEventMap = await vegEvent.timeout(const Duration(seconds: 2));

    List<String> dishIds(Map event) => (event['patches'] as List)
        .map((patch) => '${(patch as Map)['dish_id']}')
        .toList(growable: false);

    expect(dishIds(meatEventMap), contains('101'));
    expect(dishIds(meatEventMap), isNot(contains('102')));
    expect(dishIds(vegEventMap), contains('102'));
    expect(dishIds(vegEventMap), isNot(contains('101')));
  });
}
