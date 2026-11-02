import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_interaction_log.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_models.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_lan_server.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/cashier_kds_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CashierKdsDatabase database;
  late CashierKdsLanServer server;
  late HttpClient client;

  setUp(() async {
    database = CashierKdsDatabase.inMemory();
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '18',
        fulfillmentType: 'dine_in',
        remark: '不要辣',
        createdAtMs: 1000,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '微辣',
            unit: '串',
            quantity: 2,
          ),
        ],
      ),
      eventId: 'order-event-1',
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

  Future<(int?, int)> proxyInvalidUpstreamFrame(
    Object frame, {
    int maxPendingBytes = 1024,
  }) async {
    await server.close();
    final upstreamServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => upstreamServer.close(force: true));
    upstreamServer.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(frame);
    });
    server = CashierKdsLanServer(
      database,
      cloudAuthorityMode: true,
      onCacheCloudDeviceToken: _cacheCloudToken,
      maxPendingBytesPerDevice: maxPendingBytes,
      onProxyLogin: _cloudLoginResponse,
      onProxyWebSocket: (token, query) => WebSocket.connect(
        'ws://127.0.0.1:${upstreamServer.port}/ws/kds/v2',
        headers: {'X-Kds-Device-Token': token},
      ),
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'device_code': 'KDS-WS-INVALID'},
    );
    final token = (login['data'] as Map)['device_token'] as String;
    final downstream = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
    );
    final closed = Completer<void>();
    downstream.listen((_) {}, onDone: closed.complete);

    await closed.future.timeout(const Duration(seconds: 2));
    return (downstream.closeCode, database.readCloudProxyCursor(1));
  }

  test(
    'cloud authority login fails closed without issuing a local token',
    () async {
      await server.close();
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onProxyLogin: (_) async =>
            throw StateError('upstream-secret-must-not-leak'),
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);

      final response = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'KDS-CLOUD-FAIL-CLOSED',
        },
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(response.body['code'], 5030);
      expect(response.body['msg'], isNot(contains('upstream-secret')));
      expect(database.readDeviceByCode('KDS-CLOUD-FAIL-CLOSED'), isNull);
    },
  );

  test(
    'cloud authority login preserves token and one-time code body',
    () async {
      await server.close();
      CashierKdsLoginRequest? forwarded;
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: (request) async {
          forwarded = request;
          return _cloudLoginResponse(request);
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);

      final response = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        token: 'existing-token',
        proxyRequestId: 'login-request-1',
        body: const {
          'device_code': 'KDS-COMPLETE-LOGIN',
          'screen_tag': 'workflow_board',
          'pairing_code': 'ABCDEFGH',
        },
      );

      expect(response.statusCode, 200);
      expect(forwarded?.deviceToken, 'existing-token');
      expect(forwarded?.requestId, 'login-request-1');
      expect(forwarded?.body, {
        'device_code': 'KDS-COMPLETE-LOGIN',
        'screen_tag': 'workflow_board',
        'pairing_code': 'ABCDEFGH',
      });
    },
  );

  test(
    'cloud authority login preserves the cloud rejection response',
    () async {
      await server.close();
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onProxyLogin: (_) async => const CashierKdsProxyResponse(
          statusCode: HttpStatus.forbidden,
          body: '{"code":403,"msg":"invalid cloud pairing ticket"}',
        ),
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);

      final response = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: const {
          'device_code': 'KDS-CLOUD-REJECT',
          'shop_id': 1,
          'screen_tag': 'workflow_board',
          'pairing_code': 'INVALID1',
        },
      );

      expect(response.statusCode, HttpStatus.forbidden);
      expect(response.body, {
        'code': 403,
        'msg': 'invalid cloud pairing ticket',
      });
      expect(database.readDeviceByCode('KDS-CLOUD-REJECT'), isNull);
    },
  );

  test(
    'cloud authority forwards a locally unknown token to the cloud',
    () async {
      await server.close();
      CashierKdsProxyRequest? forwarded;
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onProxyHttp: (request) async {
          forwarded = request;
          return const CashierKdsProxyResponse(
            statusCode: HttpStatus.unauthorized,
            body: '{"code":401,"msg":"cloud rejected token"}',
          );
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);

      final response = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/changes?after_seq=41',
        token: 'not-in-cashier-database',
        proxyRequestId: 'changes-request-1',
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(response.body['msg'], 'cloud rejected token');
      expect(forwarded?.deviceToken, 'not-in-cashier-database');
      expect(forwarded?.query, {'after_seq': '41'});
      expect(forwarded?.requestId, 'changes-request-1');
    },
  );

  test('cloud authority lets cloud reject an uncached command token', () async {
    await server.close();
    CashierKdsProxyRequest? forwarded;
    server = CashierKdsLanServer(
      database,
      cloudAuthorityMode: true,
      onProxyHttp: (request) async {
        forwarded = request;
        return const CashierKdsProxyResponse(
          statusCode: HttpStatus.unauthorized,
          body: '{"code":401,"msg":"cloud rejected command token"}',
        );
      },
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);
    const body = <String, Object?>{
      'command_id': 'cloud-auth-command-1',
      'type': 'advance_item',
      'target': {'detail_id': 9901, 'from_queue': 'pending_prep'},
      'quantity': 1,
      'expected_revision': 7,
    };

    final response = await _rawJsonRequest(
      client,
      server,
      'POST',
      '/kds/v2/commands',
      token: 'not-in-cashier-database',
      body: body,
    );

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(response.body['msg'], 'cloud rejected command token');
    expect(forwarded?.path, '/kds/v2/commands');
    expect(forwarded?.deviceToken, 'not-in-cashier-database');
    expect(forwarded?.body, body);
    expect(database.readAllPendingCommands(), isEmpty);
  });

  test(
    'cloud authority lets cloud resolve an uncached command token',
    () async {
      await server.close();
      CashierKdsProxyRequest? forwarded;
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onProxyHttp: (request) async {
          forwarded = request;
          return const CashierKdsProxyResponse(
            statusCode: HttpStatus.unauthorized,
            body: '{"code":401,"msg":"cloud rejected resolution token"}',
          );
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);

      final response = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/commands/cloud-command-1',
        token: 'not-in-cashier-database',
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(response.body['msg'], 'cloud rejected resolution token');
      expect(forwarded?.path, '/kds/v2/commands/cloud-command-1');
      expect(forwarded?.deviceToken, 'not-in-cashier-database');
    },
  );

  test(
    'ack window closes a stalled KDS while an acknowledging peer stays healthy',
    () async {
      await server.close();
      final upstreamServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => upstreamServer.close(force: true));
      final upstreamConnections = [
        Completer<WebSocket>(),
        Completer<WebSocket>(),
      ];
      var upstreamIndex = 0;
      upstreamServer.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        upstreamConnections[upstreamIndex++].complete(socket);
      });
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        maxPendingFramesPerDevice: 2,
        socketAckTimeout: const Duration(seconds: 1),
        onProxyLogin: _cloudLoginResponse,
        onProxyWebSocket: (token, query) => WebSocket.connect(
          'ws://127.0.0.1:${upstreamServer.port}/ws/kds/v2',
          headers: {'X-Kds-Device-Token': token},
        ),
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-SLOW-TRANSPORT'},
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final downstream = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
      );
      final closed = Completer<void>();
      final firstTwoDelivered = Completer<void>();
      var delivered = 0;
      downstream.listen((_) {
        delivered++;
        if (delivered == 2 && !firstTwoDelivered.isCompleted) {
          firstTwoDelivered.complete();
        }
      }, onDone: closed.complete);
      final upstream = await upstreamConnections[0].future;
      addTearDown(upstream.close);

      upstream.add(_cloudEventEnvelope(101));
      upstream.add(_cloudEventEnvelope(102));
      await firstTwoDelivered.future.timeout(const Duration(seconds: 1));
      upstream.add(_cloudEventEnvelope(103));

      await closed.future.timeout(const Duration(seconds: 2));
      expect(downstream.closeCode, WebSocketStatus.policyViolation);
      final backpressureLogs = database.readInteractionLogs(
        const CashierKdsInteractionLogFilter(
          shopId: 1,
          statuses: {KdsInteractionStatus.failed},
          stages: {KdsInteractionStage.kdsEventPush},
        ),
      );
      expect(
        backpressureLogs.any(
          (log) =>
              log.action == 'ws_session_closed' &&
              log.errorType == 'ack window overflow' &&
              log.metadata['unacknowledged_frames'] == 2,
        ),
        isTrue,
        reason: jsonEncode(
          backpressureLogs.map((log) => log.toJson()).toList(),
        ),
      );

      final healthyLogin = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-HEALTHY-TRANSPORT'},
      );
      final healthyToken =
          (healthyLogin['data'] as Map)['device_token'] as String;
      final healthyDownstream = await WebSocket.connect(
        'ws://127.0.0.1:' +
            server.port.toString() +
            '/ws/kds/v2?token=' +
            healthyToken,
      );
      addTearDown(healthyDownstream.close);
      final healthyEvents = StreamIterator<dynamic>(healthyDownstream);
      addTearDown(healthyEvents.cancel);
      final healthyUpstream = await upstreamConnections[1].future;
      addTearDown(healthyUpstream.close);

      healthyUpstream.add(_cloudEventEnvelope(104));
      expect(
        await healthyEvents.moveNext().timeout(const Duration(seconds: 1)),
        isTrue,
      );
      healthyDownstream.add(_eventAck(104));
      healthyUpstream.add(_cloudEventEnvelope(105));
      expect(
        await healthyEvents.moveNext().timeout(const Duration(seconds: 1)),
        isTrue,
      );
      healthyDownstream.add(_eventAck(105));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(healthyDownstream.readyState, WebSocket.open);
      expect(server.connectedDeviceCount, 1);
    },
  );

  test('cloud authority login requires an upstream proxy', () async {
    await server.close();
    server = CashierKdsLanServer(database, cloudAuthorityMode: true);
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);

    final response = await _rawJsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {
        'pairing_code': server.generatePairingCode(),
        'device_code': 'KDS-CLOUD-NO-PROXY',
      },
    );

    expect(response.statusCode, HttpStatus.serviceUnavailable);
    expect(response.body['code'], 5030);
    expect(database.readDeviceByCode('KDS-CLOUD-NO-PROXY'), isNull);
  });

  test(
    'cloud authority login preserves a safe upstream rejection message',
    () async {
      await server.close();
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onProxyLogin: (_) async =>
            throw const ApiException('收银代理身份无效', code: 4030),
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);

      final response = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-CLOUD-DENIED'},
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(response.body['code'], 5030);
      expect(response.body['msg'], '收银代理身份无效');
    },
  );

  test('cloud authority caches and returns the exact cloud token', () async {
    await server.close();
    const cloudToken = 'cloud-issued-token-001';
    String? cachedToken;
    server = CashierKdsLanServer(
      database,
      cloudAuthorityMode: true,
      onCacheCloudDeviceToken:
          ({required shopId, required deviceCode, required token}) async {
            expect(shopId, 1);
            expect(deviceCode, 'KDS-CLOUD-TOKEN');
            cachedToken = token;
          },
      onProxyLogin: (payload) async {
        expect(payload['device_code'], 'KDS-CLOUD-TOKEN');
        return {
          'code': 0,
          'data': {
            'shop_id': 1,
            'device_code': 'KDS-CLOUD-TOKEN',
            'device_name': '云端设备',
            'device_token': cloudToken,
          },
        };
      },
      onProxyHttp: (_) async => _cloudBootstrapResponse(),
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);

    final login = await _rawJsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'device_code': 'KDS-CLOUD-TOKEN'},
    );
    final bootstrap = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/bootstrap',
      token: cloudToken,
    );

    expect(login.statusCode, HttpStatus.ok);
    expect((login.body['data'] as Map)['device_token'], cloudToken);
    expect(cachedToken, cloudToken);
    expect(bootstrap.statusCode, HttpStatus.ok);
    expect((bootstrap.body['data'] as Map)['authority_mode'], 'cloud');
    final proxyLogs = database.readInteractionLogs(
      const CashierKdsInteractionLogFilter(
        shopId: 1,
        stages: {KdsInteractionStage.proxyHttpForward},
      ),
    );
    expect(
      proxyLogs.map((log) => log.metadata['path']),
      containsAll(['/kds/device/login', '/kds/v2/bootstrap']),
    );
    expect(
      proxyLogs.every((log) => log.deviceCode == 'KDS-CLOUD-TOKEN'),
      isTrue,
    );
  });

  test('cloud login fails closed when secure token caching fails', () async {
    await server.close();
    server = CashierKdsLanServer(
      database,
      cloudAuthorityMode: true,
      onCacheCloudDeviceToken:
          ({required shopId, required deviceCode, required token}) async =>
              throw StateError('platform vault unavailable'),
      onProxyLogin: _cloudLoginResponse,
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);

    final login = await _rawJsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'device_code': 'KDS-CLOUD-VAULT-FAIL'},
    );

    expect(login.statusCode, HttpStatus.serviceUnavailable);
    expect(database.readDeviceByCode('KDS-CLOUD-VAULT-FAIL'), isNull);
  });

  test(
    'cloud authority transparently proxies bootstrap with the same token',
    () async {
      await server.close();
      CashierKdsProxyRequest? forwarded;
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: _cloudLoginResponse,
        onProxyHttp: (request) async {
          forwarded = request;
          return const CashierKdsProxyResponse(
            statusCode: HttpStatus.ok,
            body:
                '{"code":0,"msg":"ok","data":{"protocol_version":2,"shop_id":1,"event_seq":88,"queues":{},"queue_counts":{},"stats":{},"fixed_catalog":[],"config":{}}}',
            headers: {
              'content-type': 'application/json\u0001',
              'x-kds-authority-cursor': '88',
            },
          );
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-PROXY-BOOTSTRAP'},
      );
      final token = (login['data'] as Map)['device_token'] as String;

      final bootstrap = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );

      expect(bootstrap.statusCode, HttpStatus.ok);
      expect(bootstrap.headers['content-type'], startsWith('application/json'));
      expect((bootstrap.body['data'] as Map)['event_seq'], 88);
      expect(forwarded?.path, '/kds/v2/bootstrap');
      expect(forwarded?.deviceToken, token);
    },
  );

  test(
    'cloud authority accepts an upstream-valid token missing from local cache',
    () async {
      await server.close();
      const cloudToken = 'cloud-issued-outside-lan-login';
      final forwardedPaths = <String>[];
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onProxyHttp: (request) async {
          expect(request.deviceToken, cloudToken);
          forwardedPaths.add(request.path);
          if (request.path == '/kds/device/me') {
            return const CashierKdsProxyResponse(
              statusCode: HttpStatus.ok,
              body:
                  '{"code":0,"msg":"ok","data":{"shop_id":1,"device_code":"KDS-DIRECT-CLOUD","device_name":"Direct cloud KDS","screen_tag":"workflow_board","workflows":["prep","cook","serve"],"screen_tags":[]}}',
            );
          }
          return _cloudBootstrapResponse();
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);

      expect(database.readDeviceByCode('KDS-DIRECT-CLOUD'), isNull);
      final response = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: cloudToken,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(forwardedPaths, ['/kds/v2/bootstrap']);
      expect(database.readDeviceByCode('KDS-DIRECT-CLOUD'), isNull);
    },
  );

  test(
    'cloud authority websocket accepts an upstream-valid uncached token',
    () async {
      await server.close();
      const cloudToken = 'cloud-ws-issued-outside-lan-login';
      final upstreamServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => upstreamServer.close(force: true));
      upstreamServer.listen((request) async {
        await WebSocketTransformer.upgrade(request);
      });
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onProxyHttp: (request) async => const CashierKdsProxyResponse(
          statusCode: HttpStatus.ok,
          body:
              '{"code":0,"msg":"ok","data":{"shop_id":1,"device_code":"KDS-DIRECT-CLOUD-WS","device_name":"Direct cloud WS KDS","screen_tag":"workflow_board","workflows":["prep","cook","serve"],"screen_tags":[]}}',
        ),
        onProxyWebSocket: (token, query) {
          expect(token, cloudToken);
          return WebSocket.connect(
            'ws://127.0.0.1:${upstreamServer.port}/ws/kds/v2',
          );
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);

      final downstream = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$cloudToken',
      );
      addTearDown(downstream.close);

      expect(server.connectedDeviceCount, 1);
      expect(server.pairedDevices.single.deviceCode, 'KDS-DIRECT-CLOUD-WS');
    },
  );

  test(
    'cloud authority preserves rejection for an uncached invalid token',
    () async {
      await server.close();
      const invalidToken = 'revoked-cloud-token';
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onProxyHttp: (request) async {
          expect(request.path, '/kds/v2/bootstrap');
          expect(request.deviceToken, invalidToken);
          return const CashierKdsProxyResponse(
            statusCode: HttpStatus.unauthorized,
            body: '{"code":401,"msg":"device token revoked"}',
          );
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);

      final response = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: invalidToken,
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(response.body['msg'], 'device token revoked');
      expect(server.pairedDevices, isEmpty);
    },
  );

  test('cloud proxy preserves UTF-8 JSON instead of returning LAN 500', () async {
    await server.close();
    server = CashierKdsLanServer(
      database,
      cloudAuthorityMode: true,
      onCacheCloudDeviceToken: _cacheCloudToken,
      onProxyLogin: _cloudLoginResponse,
      onProxyHttp: (_) async => const CashierKdsProxyResponse(
        statusCode: HttpStatus.ok,
        body:
            '{"code":0,"msg":"成功","data":{"protocol_version":2,"shop_id":1,"event_seq":89,"queues":{},"queue_counts":{},"stats":{},"fixed_catalog":[{"dish_id":1,"dish_name":"宫保鸡丁"}],"config":{}}}',
        headers: {'content-type': 'application/json'},
      ),
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'device_code': 'KDS-UTF8-BOOTSTRAP'},
    );
    final token = (login['data'] as Map)['device_token'] as String;

    final bootstrap = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/bootstrap',
      token: token,
    );

    expect(bootstrap.statusCode, HttpStatus.ok);
    expect(bootstrap.body['msg'], '成功');
    final data = bootstrap.body['data'] as Map;
    expect((data['fixed_catalog'] as List).single['dish_name'], '宫保鸡丁');
  });

  test(
    'cloud outage serves a bounded stale bootstrap with explicit cache metadata',
    () async {
      await server.close();
      var cloudAvailable = true;
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        enableStaleFallback: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: _cloudLoginResponse,
        onProxyHttp: (_) async {
          if (!cloudAvailable) {
            return const CashierKdsProxyResponse(
              statusCode: HttpStatus.serviceUnavailable,
              body: '{"code":5030,"msg":"cloud unavailable"}',
            );
          }
          return const CashierKdsProxyResponse(
            statusCode: HttpStatus.ok,
            body:
                '{"code":0,"msg":"ok","data":{"protocol_version":2,"shop_id":1,"authority_mode":"cloud","event_seq":88,"queues":{},"queue_counts":{},"stats":{},"fixed_catalog":[],"config":{}}}',
            headers: {'x-kds-authority-cursor': '88'},
          );
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-STALE-BOOTSTRAP'},
      );
      final token = (login['data'] as Map)['device_token'] as String;

      final online = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );
      cloudAvailable = false;
      final stale = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );

      expect(online.statusCode, HttpStatus.ok);
      expect(online.headers['x-kds-cache'], 'MISS');
      expect(stale.statusCode, HttpStatus.ok);
      expect(stale.body, online.body);
      expect(stale.headers['x-kds-served-via'], 'lan-cache');
      expect(stale.headers['x-kds-cache'], 'STALE');
      expect(stale.headers['x-kds-authority-cursor'], '88');
      expect(int.parse(stale.headers['age']!), greaterThanOrEqualTo(0));
      expect(stale.headers['x-kds-cached-at'], isNotEmpty);
    },
  );

  test(
    'strict mode returns 503 and never returns STALE 200 when cloud is unavailable',
    () async {
      await server.close();
      var cloudAvailable = true;
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        enableStaleFallback: false, // 严格模式默认禁止返回 STALE 200
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: _cloudLoginResponse,
        onProxyHttp: (_) async {
          if (!cloudAvailable) {
            throw TimeoutException('cloud unavailable');
          }
          return const CashierKdsProxyResponse(
            statusCode: HttpStatus.ok,
            body:
                '{"code":0,"msg":"ok","data":{"protocol_version":2,"shop_id":1,"authority_mode":"cloud","event_seq":88,"queues":{},"queue_counts":{},"stats":{},"fixed_catalog":[],"config":{}}}',
            headers: {'x-kds-authority-cursor': '88'},
          );
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-STRICT-BOOTSTRAP'},
      );
      final token = (login['data'] as Map)['device_token'] as String;

      final online = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );
      expect(online.statusCode, HttpStatus.ok);

      cloudAvailable = false;
      final fail = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );

      // 负向验收：严格模式严禁返回 STALE 200，必须返回 503
      expect(fail.statusCode, HttpStatus.serviceUnavailable);
      expect(fail.headers['x-kds-cache'], isNull);
    },
  );

  test('stale bootstrap cache is device-scoped and expires closed', () async {
    await server.close();
    var cloudAvailable = true;
    server = CashierKdsLanServer(
      database,
      cloudAuthorityMode: true,
      enableStaleFallback: true,
      onCacheCloudDeviceToken: _cacheCloudToken,
      staleReadTtl: const Duration(milliseconds: 20),
      onProxyLogin: _cloudLoginResponse,
      onProxyHttp: (_) async {
        if (!cloudAvailable) {
          throw TimeoutException('debug cloud intentionally unavailable');
        }
        return _cloudBootstrapResponse();
      },
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);
    final firstLogin = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'device_code': 'KDS-CACHE-A'},
    );
    final secondLogin = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'device_code': 'KDS-CACHE-B'},
    );
    final firstToken = (firstLogin['data'] as Map)['device_token'] as String;
    final secondToken = (secondLogin['data'] as Map)['device_token'] as String;
    final warm = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/bootstrap',
      token: firstToken,
    );
    expect(warm.statusCode, HttpStatus.ok);
    cloudAvailable = false;

    final otherDevice = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/bootstrap',
      token: secondToken,
    );
    expect(otherDevice.statusCode, HttpStatus.serviceUnavailable);
    expect(otherDevice.body['code'], 5030);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    final expired = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/bootstrap',
      token: firstToken,
    );
    expect(expired.statusCode, HttpStatus.serviceUnavailable);
    expect(expired.body['code'], 5030);
  });

  test(
    'cloud authority proxies V2 config without mutating local config',
    () async {
      await server.close();
      CashierKdsProxyRequest? forwarded;
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: _cloudLoginResponse,
        onProxyHttp: (request) async {
          forwarded = request;
          return const CashierKdsProxyResponse(
            statusCode: HttpStatus.ok,
            body:
                '{"code":0,"msg":"ok","data":{"settings":{"enable_prep_workflow":false}}}',
            headers: {},
          );
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-PROXY-CONFIG'},
      );
      final token = (login['data'] as Map)['device_token'] as String;

      final response = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/v2/config',
        token: token,
        body: const {'enable_prep_workflow': 0, 'prep_enabled': 0},
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body['code'], 0);
      expect(forwarded?.method, 'POST');
      expect(forwarded?.path, '/kds/v2/config');
      expect(forwarded?.deviceToken, token);
      expect(forwarded?.body, {'enable_prep_workflow': 0, 'prep_enabled': 0});
      expect(database.readEnablePrepWorkflow(shopId: 1), isTrue);
    },
  );

  test('cloud authority rejects legacy local config writes', () async {
    await server.close();
    server = CashierKdsLanServer(
      database,
      cloudAuthorityMode: true,
      onCacheCloudDeviceToken: _cacheCloudToken,
      onProxyLogin: _cloudLoginResponse,
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'device_code': 'KDS-LEGACY-CONFIG'},
    );
    final token = (login['data'] as Map)['device_token'] as String;

    final response = await _rawJsonRequest(
      client,
      server,
      'POST',
      '/kds/settings',
      token: token,
      body: const {'enable_prep_workflow': 0},
    );

    expect(response.statusCode, HttpStatus.upgradeRequired);
    expect(response.body['code'], 4260);
    expect(database.readEnablePrepWorkflow(shopId: 1), isTrue);
  });

  test('cloud authority websocket relays upstream envelopes unchanged', () async {
    await server.close();
    final upstreamServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => upstreamServer.close(force: true));
    final upstreamReceived = Completer<String>();
    const envelope =
        '{"protocol_version":2,"event_seq":77,"event_id":"cloud-event-77","type":"order_updated","shop_id":1,"patches":[],"queue_counts":{}}';
    upstreamServer.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(envelope);
      socket.listen((message) {
        if (!upstreamReceived.isCompleted) {
          upstreamReceived.complete('$message');
        }
      });
    });
    String? connectorToken;
    server = CashierKdsLanServer(
      database,
      cloudAuthorityMode: true,
      onCacheCloudDeviceToken: _cacheCloudToken,
      onProxyLogin: _cloudLoginResponse,
      onProxyWebSocket: (token, query) {
        connectorToken = token;
        return WebSocket.connect(
          'ws://127.0.0.1:${upstreamServer.port}/ws/kds/v2',
          headers: {'X-Kds-Device-Token': token},
        );
      },
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'device_code': 'KDS-WS-RELAY'},
    );
    final token = (login['data'] as Map)['device_token'] as String;
    final downstream = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
    );
    addTearDown(downstream.close);

    expect(
      await downstream.first.timeout(const Duration(seconds: 2)),
      envelope,
    );
    expect(connectorToken, token);
    expect(database.readCloudProxyCursor(1), 77);
    final ack = jsonEncode({
      'protocol_version': 2,
      'type': 'ack',
      'event_seq': 77,
      'event_id': 'cloud-event-77',
    });
    downstream.add(ack);
    expect(
      await upstreamReceived.future.timeout(const Duration(seconds: 2)),
      ack,
    );
  });

  test('downstream disconnect closes upstream websocket without leak', () async {
    await server.close();
    final upstreamServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => upstreamServer.close(force: true));
    final upstreamClosed = Completer<void>();
    upstreamServer.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen(
        (_) {},
        onDone: () {
          if (!upstreamClosed.isCompleted) {
            upstreamClosed.complete();
          }
        },
      );
    });
    server = CashierKdsLanServer(
      database,
      cloudAuthorityMode: true,
      onCacheCloudDeviceToken: _cacheCloudToken,
      onProxyLogin: _cloudLoginResponse,
      onProxyWebSocket: (token, query) {
        return WebSocket.connect(
          'ws://127.0.0.1:${upstreamServer.port}/ws/kds/v2',
          headers: {'X-Kds-Device-Token': token},
        );
      },
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    server.setActiveShop(1);
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'device_code': 'KDS-WS-FAIL-CLEANUP'},
    );
    final token = (login['data'] as Map)['device_token'] as String;

    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
    );
    await ws.close();

    // Verify upstream WebSocket was closed and did not leak
    await expectLater(
      upstreamClosed.future.timeout(const Duration(seconds: 2)),
      completes,
    );
  });

  test(
    'cloud authority websocket rejects non-monotonic upstream event sequences',
    () async {
      await server.close();
      final upstreamServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => upstreamServer.close(force: true));
      upstreamServer.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add(
          '{"protocol_version":2,"event_seq":78,"event_id":"cloud-event-78","type":"order_updated","shop_id":1,"patches":[],"queue_counts":{}}',
        );
        socket.add(
          '{"protocol_version":2,"event_seq":77,"event_id":"cloud-event-77-late","type":"order_updated","shop_id":1,"patches":[],"queue_counts":{}}',
        );
      });
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: _cloudLoginResponse,
        onProxyWebSocket: (token, query) => WebSocket.connect(
          'ws://127.0.0.1:${upstreamServer.port}/ws/kds/v2',
          headers: {'X-Kds-Device-Token': token},
        ),
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-WS-ORDER'},
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final downstream = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token&after_seq=76',
      );
      final frames = <Map>[];
      final closed = Completer<void>();
      downstream.listen(
        (raw) => frames.add(jsonDecode('$raw') as Map),
        onDone: closed.complete,
      );

      await closed.future.timeout(const Duration(seconds: 2));

      expect(frames.map((frame) => frame['event_seq']), [78]);
      expect(downstream.closeCode, WebSocketStatus.protocolError);
      expect(database.readCloudProxyCursor(1), 78);
    },
  );

  test('cloud authority websocket rejects malformed upstream JSON', () async {
    final result = await proxyInvalidUpstreamFrame('{not-json');

    expect(result.$1, WebSocketStatus.protocolError);
    expect(result.$2, 0);
  });

  test('cloud authority websocket rejects binary upstream frames', () async {
    final result = await proxyInvalidUpstreamFrame(<int>[1, 2, 3]);

    expect(result.$1, WebSocketStatus.unsupportedData);
    expect(result.$2, 0);
  });

  test('cloud authority websocket rejects oversized upstream frames', () async {
    final result = await proxyInvalidUpstreamFrame(
      jsonEncode({
        'protocol_version': 2,
        'event_seq': 79,
        'event_id': 'cloud-event-79',
        'type': 'order_updated',
        'shop_id': 1,
        'patches': const [],
        'queue_counts': const {},
        'padding': 'x' * 256,
      }),
      maxPendingBytes: 128,
    );

    expect(result.$1, WebSocketStatus.messageTooBig);
    expect(result.$2, 0);
  });

  test('order_ready broadcast envelope carries cloud_order_id', () async {
    final receipt = database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '19',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 3000,
        lines: [
          CashierOrderLineDraft(
            dishId: 301,
            dishName: '羊肉串',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
        ],
      ),
      eventId: 'cloud-ready-event',
      cloudOrderId: 88001,
      cloudOrderNo: 'ORD88001',
    );
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {
        'pairing_code': server.generatePairingCode(),
        'device_code': 'KDS-READY',
        'workflows': ['prep', 'cook', 'serve'],
      },
    );
    final token = (login['data'] as Map)['device_token'] as String;
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
    );
    addTearDown(ws.close);
    final nextEvent = ws.first.then((raw) => jsonDecode('$raw') as Map);

    server.broadcastNewOrder(1, receipt);

    final event = await nextEvent.timeout(const Duration(seconds: 2));
    expect(event['type'], 'order_created');
    expect(event['cloud_order_id'], 88001);
    expect(event['cloud_order_no'], 'ORD88001');
    expect(event['order_details'], isNotEmpty);
  });

  test(
    'a reconnect replaces the previous socket for the same KDS device',
    () async {
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'KDS-RECONNECT',
        },
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final first = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
      );
      addTearDown(first.close);
      final firstClosed = Completer<void>();
      first.listen((_) {}, onDone: firstClosed.complete);
      await _eventually(() => server.connectedDeviceCount == 1);

      final second = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
      );
      addTearDown(second.close);
      await firstClosed.future.timeout(const Duration(seconds: 2));
      await _eventually(() => server.connectedDeviceCount == 1);

      final pong = second.first;
      second.add('ping');
      expect(
        await pong.timeout(const Duration(seconds: 2)),
        contains('"type":"pong"'),
      );
    },
  );

  test(
    'connection capacity closes excess KDS devices without displacing live devices',
    () async {
      final bounded = CashierKdsLanServer(
        database,
        cloudAuthorityMode: false,
        maxConnectedDevices: 1,
      );
      await bounded.start(address: InternetAddress.loopbackIPv4, port: 0);
      bounded.setActiveShop(1);
      addTearDown(bounded.close);
      final firstLogin = await _jsonRequest(
        client,
        bounded,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': bounded.generatePairingCode(),
          'device_code': 'KDS-CAPACITY-1',
        },
      );
      final secondLogin = await _jsonRequest(
        client,
        bounded,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': bounded.generatePairingCode(),
          'device_code': 'KDS-CAPACITY-2',
        },
      );
      final first = await WebSocket.connect(
        'ws://127.0.0.1:${bounded.port}/ws/kds/v2?token=${(firstLogin['data'] as Map)['device_token']}',
      );
      addTearDown(first.close);
      await _eventually(() => bounded.connectedDeviceCount == 1);
      await expectLater(
        WebSocket.connect(
          'ws://127.0.0.1:${bounded.port}/ws/kds/v2?token=${(secondLogin['data'] as Map)['device_token']}',
        ),
        throwsA(isA<WebSocketException>()),
      );
      expect(bounded.connectedDeviceCount, 1);
    },
  );

  test('v2 bootstrap is served from cashier SQLite', () async {
    database.replaceDishCatalog(
      shopId: 1,
      updatedAtMs: 1001,
      items: const [
        CashierDishCatalogItem(
          dishId: 101,
          dishName: '油边王',
          unit: '串',
          sequence: 0,
        ),
      ],
    );
    final pairingCode = server.generatePairingCode();
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {
        'pairing_code': pairingCode,
        'device_code': 'KDS-01',
        'screen_tag': 'workflow_board',
        'workflows': ['prep', 'cook', 'serve'],
      },
    );
    final token = (login['data'] as Map)['device_token'] as String;

    final board = await _jsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/bootstrap',
      token: token,
    );

    expect(board['code'], 0);
    final data = board['data'] as Map;
    expect(data['protocol_version'], 2);
    expect(data['shop_id'], 1);
    expect(
      data.keys,
      containsAll(const [
        'device',
        'permissions',
        'queues',
        'queue_counts',
        'fixed_catalog',
        'config',
        'stats',
        'config_version',
      ]),
    );
    final queues = data['queues'] as Map;
    expect(queues.keys.toSet(), {
      'pending_prep',
      'pending_cook',
      'ready_serve',
      'done',
    });
    expect((queues['pending_prep'] as List), hasLength(1));
    final patch = (queues['pending_prep'] as List).single as Map;
    expect(patch['table_number'], '18');
    expect(patch.keys.toSet(), {
      'detail_id',
      'order_id',
      'dish_id',
      'dish_name',
      'line_quantity',
      'refunded_quantity',
      'prep_remaining',
      'cook_remaining',
      'ready_remaining',
      'local_revision',
      'order_revision',
      'fulfillment_bucket',
      'table_number',
      'order_no',
      'specification',
      'unit',
      'remark',
      'created_at_ms',
      'serving_duration_minutes',
      'completed_at_ms',
      'held',
      'rushed',
      'lacked',
      'removed',
      'workflow_queue',
      'is_combo',
      'combo',
      'set_meal',
      'fulfillment_channel',
    });
    expect(patch['serving_duration_minutes'], 10);
    expect((data['queue_counts'] as Map)['pending_prep'], 2); // 数量口径：SUM 可见量
    final parsed = _parseLikeRealKds(board);
    expect(parsed.lines, hasLength(1));
    expect(parsed.catalog.single, (dishId: 101, dishName: '油边王'));
    expect((data['device'] as Map)['permissions'], data['permissions']);
  });

  test(
    'bootstrap keeps four queues but hides unauthorized workflows',
    () async {
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'PREP-ONLY',
          'workflows': ['prep'],
        },
      );
      final board = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: (login['data'] as Map)['device_token'] as String,
      );
      final data = board['data'] as Map;
      final queues = data['queues'] as Map;
      expect((queues['pending_prep'] as List), hasLength(1));
      expect(queues['pending_cook'], isEmpty);
      expect(queues['ready_serve'], isEmpty);
      expect(queues['done'], isEmpty);
      expect((data['permissions'] as Map)['visible_queues'], ['pending_prep']);
    },
  );

  test(
    'KDS can update prep workflow and all clients receive config change',
    () async {
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'KDS-CONFIG-01',
          'workflows': ['prep', 'cook', 'serve'],
        },
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
      );
      addTearDown(ws.close);
      final nextEvent = ws.first.then((raw) => jsonDecode('$raw') as Map);

      final response = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/settings',
        token: token,
        body: const {'enable_prep_workflow': 0, 'prep_enabled': 0},
      );
      final event = await nextEvent.timeout(const Duration(seconds: 2));
      final bootstrap = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );

      expect(response['code'], 0);
      expect(event['type'], 'config_changed');
      expect(database.readEnablePrepWorkflow(shopId: 1), isFalse);
      final data = bootstrap['data'] as Map;
      expect((data['config'] as Map)['enable_prep_workflow'], 0);
      expect((data['config'] as Map)['prep_enabled'], 0);
      expect(data['config_version'], event['config_version']);
    },
  );

  test(
    'invalid prep workflow value is rejected without changing state',
    () async {
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'KDS-CONFIG-INVALID',
        },
      );
      final token = (login['data'] as Map)['device_token'] as String;

      final response = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/settings',
        token: token,
        body: const {'enable_prep_workflow': 'unexpected'},
      );

      expect(response.statusCode, 400);
      expect(response.body['code'], 4000);
      expect(database.readEnablePrepWorkflow(shopId: 1), isTrue);
    },
  );

  test('advance commits locally and broadcasts an update event', () async {
    final pairingCode = server.generatePairingCode();
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {
        'pairing_code': pairingCode,
        'device_code': 'KDS-01',
        'screen_tag': 'workflow_board',
        'workflows': ['prep', 'cook', 'serve'],
      },
    );
    final token = (login['data'] as Map)['device_token'] as String;
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
    );
    addTearDown(ws.close);
    final nextEvent = ws.first.then((raw) => jsonDecode('$raw') as Map);

    final response = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/v2/commands',
      token: token,
      body: {
        'command_id': 'advance-event-1',
        'type': 'advance_item',
        'target': {'detail_id': line.detailId, 'from_queue': 'pending_prep'},
        'quantity': 2,
        'expected_revision': line.localRevision,
        'payload': <String, Object?>{},
      },
    );
    final event = await nextEvent.timeout(const Duration(seconds: 2));

    expect(response['code'], 0);
    expect((response['data'] as Map)['command_id'], 'advance-event-1');
    expect(
      ((response['data'] as Map)['order_summary'] as Map)['order_revision'],
      2,
    );
    expect(
      (((response['data'] as Map)['patches'] as List).single
          as Map)['workflow_queue'],
      'pending_cook',
    );
    expect(event['protocol_version'], 2);
    expect(event['type'], 'advance_item');
    expect(event['event_id'], 'advance-event-1');
    expect(event['event_seq'], (response['data'] as Map)['event_seq']);
    expect(
      database.readWorkflowBoard(shopId: 1, queue: 'pending_cook').lines,
      hasLength(1),
    );
    final logs = database.readInteractionLogs(
      const CashierKdsInteractionLogFilter(
        shopId: 1,
        traceId: 'advance-event-1',
      ),
    );
    expect(
      logs.map((log) => log.stage).toSet(),
      containsAll({
        KdsInteractionStage.kdsCommandReceived,
        KdsInteractionStage.kdsCommandAuthorized,
        KdsInteractionStage.localProjectionApply,
        KdsInteractionStage.cloudEventQueued,
        KdsInteractionStage.kdsCommandResponse,
        KdsInteractionStage.kdsEventPush,
      }),
    );
    expect(
      logs
          .firstWhere((log) => log.stage == KdsInteractionStage.kdsEventPush)
          .metadata['recipient_count'],
      1,
    );
  });

  test(
    'cloud authority proxies the original command without mutating local business state',
    () async {
      final createdEvent = database
          .readDueCloudEvents(nowMs: 1000)
          .singleWhere((event) => event.eventId == 'order-event-1');
      final localLine = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single;
      database.applyCloudAckAndMarkDelivered(
        createdEvent,
        CashierCloudEventAck(
          eventId: createdEvent.eventId,
          cloudOrderId: 9001,
          cloudOrderNo: 'CLOUD-9001',
          detailMappings: {localLine.detailId: 9901},
        ),
        deliveredAtMs: 1100,
      );
      await server.close();
      Map<String, Object?>? forwarded;
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: _cloudLoginResponse,
        onProxyHttp: (request) async {
          if (request.path == '/kds/v2/bootstrap') {
            return CashierKdsProxyResponse(
              statusCode: HttpStatus.ok,
              body: jsonEncode({
                'code': 0,
                'msg': 'ok',
                'data': {
                  'protocol_version': 2,
                  'shop_id': 1,
                  'authority_mode': 'cloud',
                  'event_seq': 1,
                  'queues': {
                    'pending_prep': [
                      {
                        'detail_id': 9901,
                        'order_id': 9001,
                        'dish_id': 101,
                        'dish_name': '油边王',
                        'line_quantity': 2,
                        'refunded_quantity': 0,
                        'prep_remaining': 2,
                        'cook_remaining': 2,
                        'ready_remaining': 2,
                        'local_revision': localLine.localRevision,
                        'order_revision': 1,
                        'fulfillment_bucket': 'dine_in',
                        'table_number': '18',
                        'order_no': 'CLOUD-9001',
                        'specification': '微辣',
                        'unit': '串',
                        'remark': '',
                        'created_at_ms': 1000,
                        'held': false,
                        'rushed': false,
                        'lacked': false,
                        'removed': false,
                        'workflow_queue': 'pending_prep',
                      },
                    ],
                  },
                  'queue_counts': {'pending_prep': 2},
                  'stats': {},
                  'fixed_catalog': [],
                  'config': {},
                },
              }),
            );
          }
          if (request.path == '/kds/v2/commands') {
            forwarded = request.body;
            return CashierKdsProxyResponse(
              statusCode: HttpStatus.ok,
              body: jsonEncode({
                'code': 0,
                'msg': 'ok',
                'data': {
                  'command_id': request.body['command_id'],
                  'duplicate': false,
                  'event_seq': 91,
                  'patches': const [],
                  'queue_counts': const <String, int>{},
                },
              }),
            );
          }
          throw StateError('unexpected proxy route ${request.path}');
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'KDS-CLOUD-AUTHORITY',
          'workflows': ['prep', 'cook', 'serve'],
        },
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final bootstrap = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );
      final canonicalLine =
          (((bootstrap['data'] as Map)['queues'] as Map)['pending_prep']
                      as List)
                  .single
              as Map;
      expect((bootstrap['data'] as Map)['authority_mode'], 'cloud');
      expect(canonicalLine['detail_id'], 9901);
      expect(canonicalLine['order_id'], 9001);
      final before = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single;
      final body = <String, Object?>{
        'command_id': 'cloud-authority-advance-1',
        'type': 'advance_item',
        'target': {'detail_id': 9901, 'from_queue': 'pending_prep'},
        'quantity': 1,
        'expected_revision': before.localRevision,
      };

      final response = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/v2/commands',
        token: token,
        body: body,
      );

      expect(response.statusCode, 200);
      expect(response.body['code'], 0);
      expect(forwarded, body);
      expect(
        database
            .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
            .lines
            .single
            .localRevision,
        before.localRevision,
      );
      expect(
        database.readWorkflowBoard(shopId: 1, queue: 'pending_cook').lines,
        isEmpty,
      );
    },
  );

  test(
    'cloud authority never lets a stale local projection reject a cloud command',
    () async {
      final createdEvent = database
          .readDueCloudEvents(nowMs: 1000)
          .singleWhere((event) => event.eventId == 'order-event-1');
      final localLine = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single;
      database.applyCloudAckAndMarkDelivered(
        createdEvent,
        CashierCloudEventAck(
          eventId: createdEvent.eventId,
          cloudOrderId: 9001,
          cloudOrderNo: 'CLOUD-9001',
          detailMappings: {localLine.detailId: 9901},
        ),
        deliveredAtMs: 1100,
      );
      database.advanceLine(
        shopId: 1,
        detailId: localLine.detailId,
        fromQueue: 'pending_prep',
        quantity: localLine.lineQuantity,
        operationId: 'make-local-projection-stale',
        expectedRevision: localLine.localRevision,
        occurredAtMs: 1200,
      );
      expect(
        database.readWorkflowBoard(shopId: 1, queue: 'pending_cook').lines,
        hasLength(1),
      );

      await server.close();
      CashierKdsProxyRequest? forwarded;
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: (payload) async => {
          'code': 0,
          'data': {
            'shop_id': 1,
            'device_code': payload['device_code'],
            'device_name': payload['device_code'],
            'device_token': 'cloud-token-${payload['device_code']}',
            'workflows': ['prep'],
          },
        },
        onProxyHttp: (request) async {
          forwarded = request;
          return CashierKdsProxyResponse(
            statusCode: HttpStatus.ok,
            body: jsonEncode({
              'code': 0,
              'msg': 'ok',
              'data': {
                'command_id': request.body['command_id'],
                'duplicate': false,
                'event_seq': 92,
                'patches': const [],
                'queue_counts': const <String, int>{},
              },
            }),
          );
        },
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'device_code': 'KDS-PREP-ONLY-CLOUD',
          'workflows': ['prep'],
        },
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final body = <String, Object?>{
        'command_id': 'cloud-authority-stale-local-1',
        'type': 'advance_item',
        'target': {'detail_id': 9901, 'from_queue': 'pending_prep'},
        'quantity': 1,
        'expected_revision': 7,
      };

      final response = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/v2/commands',
        token: token,
        body: body,
      );

      expect(response.statusCode, 200);
      expect(response.body['code'], 0);
      expect(forwarded?.body, body);
    },
  );

  test(
    'cloud authority rejects local command takeover when cloud is unreachable',
    () async {
      await server.close();
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: _cloudLoginResponse,
        onProxyHttp: (_) async => throw const SocketException('offline'),
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'KDS-OFFLINE-QUEUE',
          'workflows': ['prep', 'cook', 'serve'],
        },
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final response = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/v2/commands',
        token: token,
        body: {
          'command_id': 'offline-command-1',
          'type': 'advance_item',
          'target': {'detail_id': 991, 'from_queue': 'pending_prep'},
          'quantity': 1,
          'expected_revision': 7,
        },
      );
      final resolution = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/commands/offline-command-1',
        token: token,
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(response.body['code'], 5030);
      expect(resolution.statusCode, HttpStatus.serviceUnavailable);
      expect(resolution.body['code'], 5030);
      expect(database.readAllPendingCommands(), isEmpty);
    },
  );

  test(
    'cloud outage never turns an absent local relay row into authoritative NOT_FOUND',
    () async {
      await server.close();
      server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: _cloudLoginResponse,
        onProxyHttp: (_) async => throw const SocketException('cloud offline'),
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-RESOLUTION-CACHE'},
      );
      final token = (login['data'] as Map)['device_token'] as String;

      final resolution = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/commands/cloud-origin-unknown',
        token: token,
      );

      expect(resolution.statusCode, HttpStatus.serviceUnavailable);
      expect(resolution.body['code'], 5030);
    },
  );

  test(
    'partial prep patch reaches cook-only WS and changes consumers',
    () async {
      Future<String> login(String code, List<String> workflows) async {
        final response = await _jsonRequest(
          client,
          server,
          'POST',
          '/kds/device/login',
          body: {
            'pairing_code': server.generatePairingCode(),
            'device_code': code,
            'workflows': workflows,
          },
        );
        return (response['data'] as Map)['device_token'] as String;
      }

      final prepToken = await login('PREP-PARTIAL', ['prep']);
      final cookToken = await login('COOK-PARTIAL', ['cook']);
      final line = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single;
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$cookToken',
      );
      addTearDown(ws.close);
      final iterator = StreamIterator<dynamic>(ws);
      ws.add('ping');
      expect(await iterator.moveNext(), isTrue);
      expect('${iterator.current}', contains('"type":"pong"'));
      final nextPatch = iterator.moveNext();

      final command = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/v2/commands',
        token: prepToken,
        body: {
          'command_id': 'partial-for-cook',
          'type': 'advance_item',
          'target': {'detail_id': line.detailId, 'from_queue': 'pending_prep'},
          'quantity': 1,
          'expected_revision': line.localRevision,
        },
      );

      expect(await nextPatch.timeout(const Duration(seconds: 2)), isTrue);
      final wsEvent = jsonDecode('${iterator.current}') as Map;
      final wsPatch = (wsEvent['patches'] as List).single as Map;
      expect(wsPatch['prep_remaining'], 1);
      expect(wsPatch['cook_remaining'], 2);
      final ackDetails = (command['data'] as Map)['order_details'] as List;
      expect(ackDetails, isNotEmpty);
      expect(wsEvent['order_details'], ackDetails);
      final changes = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/changes?after_seq=${line.createdAtMs == 0 ? 0 : 1}',
        token: cookToken,
      );
      final events = ((changes['data'] as Map)['events'] as List);
      expect(events, hasLength(1));
      expect(
        (((events.single as Map)['patches'] as List).single
            as Map)['detail_id'],
        line.detailId,
      );
      expect((events.single as Map)['order_details'], ackDetails);
      expect((command['data'] as Map)['event_seq'], wsEvent['event_seq']);
      await iterator.cancel();
    },
  );

  test('all legacy KDS data routes require protocol upgrade', () async {
    final pairingCode = server.generatePairingCode();
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'pairing_code': pairingCode, 'device_code': 'KDS-REVISION'},
    );
    final token = (login['data'] as Map)['device_token'] as String;
    for (final route in const [
      ('GET', '/dish/listAll'),
      ('GET', '/kds/workflow/board'),
      ('GET', '/kds/workflow/bootstrap'),
      ('POST', '/kds/workflow/advance-item'),
      ('GET', '/kds/order/item/list'),
      ('GET', '/kds/sync/changes'),
    ]) {
      final response = await _rawJsonRequest(
        client,
        server,
        route.$1,
        route.$2,
        token: token,
        body: route.$1 == 'POST' ? const {} : null,
      );
      expect(response.statusCode, 426, reason: route.$2);
      expect(response.body['code'], 4260, reason: route.$2);
    }
  });

  test('bootstrap includes the fixed dish catalog in database order', () async {
    database.setPrintOnAdvance(shopId: 1, enabled: true, updatedAtMs: 1500);
    database.replaceDishCatalog(
      shopId: 1,
      updatedAtMs: 2000,
      items: const [
        CashierDishCatalogItem(
          dishId: 202,
          dishName: '吊龙',
          unit: '份',
          sequence: 0,
          categoryId: 20,
          categoryName: '牛肉',
          categorySequence: 2,
          dishSequence: 2,
        ),
        CashierDishCatalogItem(
          dishId: 101,
          dishName: '油边王',
          unit: '串',
          sequence: 1,
          categoryId: 10,
          categoryName: '肉串',
          categorySequence: 1,
          dishSequence: 5,
        ),
        CashierDishCatalogItem(
          dishId: 102,
          dishName: '羊肉串',
          unit: '串',
          sequence: 2,
          categoryId: 10,
          categoryName: '肉串',
          categorySequence: 1,
          dishSequence: 1,
        ),
      ],
    );
    final pairingCode = server.generatePairingCode();
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {
        'pairing_code': pairingCode,
        'device_code': 'KDS-01',
        'workflows': ['prep', 'cook', 'serve'],
      },
    );
    final token = (login['data'] as Map)['device_token'] as String;

    final response = await _jsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/bootstrap',
      token: token,
    );
    final dishes = ((response['data'] as Map)['catalog'] as List);
    final config = ((response['data'] as Map)['config'] as Map);

    expect(dishes.map((dish) => (dish as Map)['id']), [102, 101, 202]);
    expect(config['print_on_advance'], isTrue);
    expect(dishes.every((dish) => (dish as Map)['onsale'] == true), isTrue);
    expect((dishes.first as Map), containsPair('category_id', 10));
    expect((dishes.first as Map), containsPair('category_name', '肉串'));
    expect((dishes.first as Map), containsPair('category_sequence', 1));
    expect((dishes.first as Map), containsPair('dish_sequence', 1));
  });

  test(
    'completion time is persisted and identical in ACK WS and bootstrap',
    () async {
      var line = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single;
      database.advanceLine(
        shopId: 1,
        detailId: line.detailId,
        fromQueue: 'pending_prep',
        quantity: 2,
        operationId: 'prepare-before-complete',
        expectedRevision: line.localRevision,
        occurredAtMs: 2000,
      );
      line = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_cook')
          .lines
          .single;
      database.advanceLine(
        shopId: 1,
        detailId: line.detailId,
        fromQueue: 'pending_cook',
        quantity: 2,
        operationId: 'cook-before-complete',
        expectedRevision: line.localRevision,
        occurredAtMs: 3000,
      );
      line = database
          .readWorkflowBoard(shopId: 1, queue: 'ready_serve')
          .lines
          .single;
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'COMPLETE-TIME',
          'workflows': ['prep', 'cook', 'serve'],
        },
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
      );
      addTearDown(ws.close);
      final nextEvent = ws.first.then((raw) => jsonDecode('$raw') as Map);

      final ack = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/v2/commands',
        token: token,
        body: {
          'command_id': 'complete-with-time',
          'type': 'advance_item',
          'target': {'detail_id': line.detailId, 'from_queue': 'ready_serve'},
          'quantity': 2,
          'expected_revision': line.localRevision,
        },
      );
      final event = await nextEvent.timeout(const Duration(seconds: 2));
      final ackPatch =
          (((ack['data'] as Map)['patches'] as List).single as Map);
      final wsPatch = ((event['patches'] as List).single as Map);
      final completedAt = ackPatch['completed_at_ms'] as int;

      expect(completedAt, isA<int>());
      expect(wsPatch['completed_at_ms'], completedAt);

      final bootstrap = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );
      final done =
          ((((bootstrap['data'] as Map)['queues'] as Map)['done'] as List)
                  .single
              as Map);
      expect(done['completed_at_ms'], completedAt);

      final revoked = database.executeKdsCommand(
        LocalKdsCommand(
          commandId: 'revoke-after-complete',
          type: LocalKdsCommandType.revokeItem,
          shopId: 1,
          target: LocalKdsCommandTarget(
            detailId: line.detailId,
            fromQueue: 'done',
          ),
          quantity: 1,
          expectedRevision: ackPatch['local_revision'] as int,
          occurredAtMs: completedAt + 1000,
        ),
      );
      expect(revoked.patches.single['completed_at_ms'], completedAt);
      final recompleted = database.executeKdsCommand(
        LocalKdsCommand(
          commandId: 'complete-again',
          type: LocalKdsCommandType.advanceItem,
          shopId: 1,
          target: LocalKdsCommandTarget(
            detailId: line.detailId,
            fromQueue: 'ready_serve',
          ),
          quantity: 1,
          expectedRevision: revoked.patches.single['local_revision'] as int,
          occurredAtMs: completedAt + 2000,
        ),
      );
      expect(recompleted.patches.single['completed_at_ms'], completedAt + 2000);
    },
  );

  test(
    'diagnostics interaction-logs endpoint returns recent logs for authorized device',
    () async {
      database.tryRecordInteraction(
        const CashierKdsInteractionLogDraft(
          traceId: 'trace-diag-1',
          shopId: 1,
          source: KdsInteractionSide.cashier,
          target: KdsInteractionSide.kds,
          direction: KdsInteractionDirection.outbound,
          stage: KdsInteractionStage.kdsEventPush,
          action: 'order_created',
          status: KdsInteractionStatus.sent,
          occurredAtMs: 3000,
          orderNo: 'NO-999',
        ),
      );

      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'KDS-DIAG-01',
          'screen_tag': 'workflow_board',
          'workflows': ['prep', 'cook', 'serve'],
        },
      );
      final token = (login['data'] as Map)['device_token'] as String;

      final res = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/diagnostics/interaction-logs?limit=10',
        token: token,
      );

      expect(res['code'], 0);
      final data = res['data'] as Map;
      expect(data['shop_id'], 1);
      final logs = (data['logs'] as List).cast<Map>();
      expect(logs.any((l) => l['trace_id'] == 'trace-diag-1'), isTrue);
      expect(logs.any((l) => l['order_no'] == 'NO-999'), isTrue);
    },
  );

  test(
    'bootstrap and command ACK include read-only complete order details',
    () async {
      final receipt = database.createOrder(
        const CashierOrderDraft(
          shopId: 1,
          tableNumber: '20',
          fulfillmentType: 'dine_in',
          remark: '',
          createdAtMs: 2000,
          lines: [
            CashierOrderLineDraft(
              dishId: 201,
              dishName: '羊肉串',
              specification: '',
              unit: '串',
              quantity: 1,
            ),
            CashierOrderLineDraft(
              dishId: 202,
              dishName: '牛肉串',
              specification: '',
              unit: '串',
              quantity: 1,
            ),
          ],
        ),
        eventId: 'projection-order',
      );
      final lines = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .where((line) => line.orderId == receipt.orderId)
          .toList();
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'ORDER-PROJECTION',
          'workflows': ['prep', 'cook', 'serve'],
        },
      );
      final token = (login['data'] as Map)['device_token'] as String;

      final refund = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/v2/commands',
        token: token,
        body: {
          'command_id': 'refund-projection-line',
          'type': 'refund_item',
          'target': {
            'detail_id': lines.first.detailId,
            'from_queue': 'pending_prep',
          },
          'quantity': 1,
          'expected_revision': lines.first.localRevision,
        },
      );
      final ackDetails = (refund['data'] as Map)['order_details'] as List;
      expect(ackDetails, hasLength(2));
      final refunded = ackDetails.cast<Map>().singleWhere(
        (detail) => detail['detail_id'] == lines.first.detailId,
      );
      expect(refunded['status'], 'refunded');
      expect(refunded['removed'], isTrue);

      final bootstrap = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );
      final details = (bootstrap['data'] as Map)['order_details'] as List;
      final projected = details
          .cast<Map>()
          .where((detail) => detail['order_id'] == receipt.orderId)
          .toList();
      expect(projected, hasLength(2));
      expect(
        projected.singleWhere(
          (detail) => detail['detail_id'] == lines.first.detailId,
        )['removed'],
        isTrue,
      );
    },
  );

  test(
    'unbound device is rejected and bound device session is persisted',
    () async {
      // 1. 未绑定的设备发起登录，应被 403 拦截并提示未绑定
      final unbound = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-UNBOUND'},
      );
      expect(unbound.statusCode, 403);
      expect(unbound.body['code'], 403);
      expect(unbound.body['msg'], contains('设备未绑定，请先在收银端绑定此设备编码'));

      // 2. 收银端预先绑定设备
      server.upsertBoundDevice(
        shopId: 1,
        deviceCode: 'KDS-01',
        deviceName: '后厨综合屏',
        screenTag: 'workflow_board',
        workflows: ['prep', 'cook'],
        screenTags: ['meat_grill'],
      );

      // 3. 绑定后 KDS 无需配对码即可直接登录
      final first = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-01'},
      );
      expect(first['code'], 0);
      final data = first['data'] as Map;
      expect(data['device_name'], '后厨综合屏');
      expect(data['screen_tags'], ['meat_grill']);
      expect(data['workflows'], ['prep', 'cook']);
      final token = data['device_token'] as String;

      // 4. 取得 token 后可正常查询设备身份
      final me = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/device/me',
        token: token,
      );
      expect((me['data'] as Map)['device_name'], '后厨综合屏');

      // 4.5 硬件编码设备（已绑定且近期有心跳）再次发起登录，不再受“已绑定到其他在线屏幕”限制，成功取得新 token
      final reLogin = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-01'},
      );
      expect(reLogin['code'], 0);
      final newToken = (reLogin['data'] as Map)['device_token'] as String;
      expect(newToken, isNotEmpty);
      expect(newToken != token, isTrue);

      // 5. 设备被收银端禁用后，无法登录且提示已被禁用
      database.disableDevice('KDS-01');
      final disabled = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-01'},
      );
      expect(disabled.statusCode, 403);
      expect(disabled.body['code'], 403);
      expect(disabled.body['msg'], contains('设备已被禁用'));
    },
  );

  test(
    'saved token survives reconnect and cashier revoke closes its WS',
    () async {
      final pairingCode = server.generatePairingCode();
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'pairing_code': pairingCode, 'device_code': 'KDS-REVOKE'},
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final me = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/device/me',
        token: token,
      );
      expect((me['data'] as Map)['protocol_version'], 2);
      final heartbeat = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/heartbeat',
        token: token,
      );
      expect((heartbeat['data'] as Map)['protocol_version'], 2);
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
      );
      final closed = Completer<void>();
      ws.listen((_) {}, onDone: closed.complete, onError: closed.completeError);

      await server.revokeDevice('KDS-REVOKE');
      await closed.future.timeout(const Duration(seconds: 2));
      expect(ws.closeCode, WebSocketStatus.policyViolation);
      expect(server.connectedDeviceCount, 0);

      final revoked = await _rawJsonRequest(
        client,
        server,
        'GET',
        '/kds/device/me',
        token: token,
      );
      expect(revoked.statusCode, 401);
    },
  );

  test('unsigned client-crafted token cannot access another shop', () async {
    final forged = base64Url.encode(
      utf8.encode('{"shop_id":2,"device_code":"ATTACKER","workflows":[]}'),
    );

    final response = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/device/me',
      token: forged,
    );

    expect(response.statusCode, 401);
  });

  test('health requires the active cashier bearer token', () async {
    server.setAdminBearerToken('cashier-admin-jwt');

    final missing = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/health',
    );
    final wrong = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/health',
      bearerToken: 'another-jwt',
    );
    final deviceTokenOnly = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/health',
      token: 'kds-device-token',
    );
    final allowed = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/health',
      bearerToken: 'cashier-admin-jwt',
    );

    expect(missing.statusCode, 401);
    expect(wrong.statusCode, 401);
    expect(deviceTokenOnly.statusCode, 401);
    expect(allowed.statusCode, 200);

    server.setAdminBearerToken('rotated-jwt');
    final stale = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/health',
      bearerToken: 'cashier-admin-jwt',
    );
    final rotated = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/health',
      bearerToken: 'rotated-jwt',
    );
    server.setAdminBearerToken(null);
    final loggedOut = await _rawJsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/health',
      bearerToken: 'rotated-jwt',
    );

    expect(stale.statusCode, 401);
    expect(rotated.statusCode, 200);
    expect(loggedOut.statusCode, 401);
  });

  test('health and sync changes expose authoritative cashier state', () async {
    server.setAdminBearerToken('cashier-admin-jwt');
    final health = await _jsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/health',
      bearerToken: 'cashier-admin-jwt',
    );
    expect((health['data'] as Map)['service'], 'cashier-lan-kds');
    expect((health['data'] as Map)['shop_id'], 1);
    expect((health['data'] as Map)['sqlite'], containsPair('status', 'ok'));
    expect(
      (health['data'] as Map)['primary_node'],
      containsPair('authoritative', true),
    );
    expect((health['data'] as Map)['connected_devices'], 0);
    expect(
      (health['data'] as Map)['outbox'],
      contains('oldest_pending_age_ms'),
    );

    final pairingCode = server.generatePairingCode();
    final login = await _jsonRequest(
      client,
      server,
      'POST',
      '/kds/device/login',
      body: {'pairing_code': pairingCode, 'device_code': 'KDS-01'},
    );
    final token = (login['data'] as Map)['device_token'] as String;
    final changes = await _jsonRequest(
      client,
      server,
      'GET',
      '/kds/v2/changes?after_seq=0',
      token: token,
    );
    final changesData = changes['data'] as Map;
    expect(changesData['event_seq'], 1);
    expect(changesData['latest_event_seq'], changesData['event_seq']);
    expect(changesData['events'], hasLength(1));
    expect(
      (changesData['events'] as List).single,
      containsPair('event_seq', 1),
    );
  });

  test(
    'expired or not-yet-started business-day window must not filter bootstrap orders',
    () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // 场景A：窗口已结束（打烊后/日切中）——订单创建时间在窗口外，修复前
      // 会被窗口过滤导致 bootstrap 返回空、KDS 订单消失。
      database.commitBusinessDayWindow(
        1,
        startMs: nowMs - 7200000,
        endMs: nowMs - 3600000,
      );
      var login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'KDS-EXPIRED-WIN',
          'workflows': ['prep', 'cook', 'serve'],
        },
      );
      var token = (login['data'] as Map)['device_token'] as String;
      var board = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );
      expect(board['code'], 0);
      var queues = (board['data'] as Map)['queues'] as Map;
      expect(
        queues['pending_prep'] as List,
        hasLength(1),
        reason: '窗口已结束仍按窗口过滤会导致正常订单消失',
      );
      expect(
        (board['data'] as Map)['queue_counts'] as Map,
        containsPair('pending_prep', 2), // 数量口径：SUM 可见量
      );

      // 场景B：窗口尚未开始（次日营业前）——同样不得过滤。
      database.commitBusinessDayWindow(
        1,
        startMs: nowMs + 3600000,
        endMs: nowMs + 9000000,
      );
      login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'KDS-FUTURE-WIN',
          'workflows': ['prep', 'cook', 'serve'],
        },
      );
      token = (login['data'] as Map)['device_token'] as String;
      board = await _jsonRequest(
        client,
        server,
        'GET',
        '/kds/v2/bootstrap',
        token: token,
      );
      expect(board['code'], 0);
      queues = (board['data'] as Map)['queues'] as Map;
      expect(
        queues['pending_prep'] as List,
        hasLength(1),
        reason: '窗口尚未开始仍按窗口过滤会导致正常订单消失',
      );
      expect(
        (board['data'] as Map)['queue_counts'] as Map,
        containsPair('pending_prep', 2), // 数量口径：SUM 可见量
      );
    },
  );

  test(
    'broadcastNewOrder falls back to readOrderPatches when eventSeq is 0',
    () async {
      final login = await _jsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'pairing_code': server.generatePairingCode(),
          'device_code': 'KDS-FALLBACK-TEST',
          'workflows': ['prep', 'cook', 'serve'],
        },
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
      );
      addTearDown(ws.close);
      final events = <Map<String, Object?>>[];
      final sub = ws.listen((msg) {
        events.add((jsonDecode('$msg') as Map).cast<String, Object?>());
      });
      addTearDown(sub.cancel);

      final receipt = database.createOrder(
        const CashierOrderDraft(
          shopId: 1,
          tableNumber: '25',
          fulfillmentType: 'dine_in',
          remark: '加菜测试',
          createdAtMs: 5000,
          lines: [
            CashierOrderLineDraft(
              dishId: 501,
              dishName: '烤脑花',
              specification: '麻辣',
              unit: '份',
              quantity: 2,
            ),
          ],
        ),
        eventId: 'order-event-fallback',
      );

      // 模拟 eventSeq = 0（无 journal 的 fallback 分支）
      final fallbackReceipt = CashierOrderReceipt(
        orderId: receipt.orderId,
        orderNo: receipt.orderNo,
        eventSeq: 0,
        eventId: 'fallback-event',
      );

      server.broadcastNewOrder(1, fallbackReceipt);

      await _eventually(() => events.any((e) => e['type'] == 'order_created'));
      final broadcastEvent = events.firstWhere(
        (e) => e['type'] == 'order_created',
      );
      final patches = (broadcastEvent['patches'] as List).cast<Map>();
      expect(patches, isNotEmpty);
      expect(patches.first['dish_name'], '烤脑花');

      final details = (broadcastEvent['order_details'] as List).cast<Map>();
      expect(details, isNotEmpty);
      expect(details.first['dish_name'], '烤脑花');
    },
  );

  test(
    'pairing code auto-binds new device and invalid/expired code is rejected',
    () async {
      // 1. 无配对码且未预绑定 -> 403
      final noCode = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-AUTO-01'},
      );
      expect(noCode.statusCode, 403);
      expect(noCode.body['msg'], contains('设备未绑定'));

      // 2. 错误配对码 -> 401
      final badCode = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-AUTO-01', 'pairing_code': '999999'},
      );
      expect(badCode.statusCode, 401);
      expect(badCode.body['msg'], contains('配对码无效或已过期'));

      // 3. 正确配对码 -> 200，并自动登记入库
      final validCode = server.generatePairingCode();
      final success = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'device_code': 'KDS-AUTO-01',
          'device_name': '素烤档01',
          'pairing_code': validCode,
          'workflows': ['cook'],
          'screen_tags': ['veg_grill'],
        },
      );
      expect(success.statusCode, 200);
      final data = success.body['data'] as Map;
      expect(data['device_code'], 'KDS-AUTO-01');
      expect(data['device_name'], '素烤档01');
      expect(data['device_token'], isNotEmpty);

      // 数据库中已存在该设备
      final bound = database.readDeviceByCode('KDS-AUTO-01');
      expect(bound, isNotNull);
      expect(bound!.deviceName, '素烤档01');
      expect(bound.screenTags, ['veg_grill']);

      // 4. 同一配对码不可重复使用（已核销）-> 401
      final reuseCode = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-AUTO-02', 'pairing_code': validCode},
      );
      expect(reuseCode.statusCode, 401);
      expect(reuseCode.body['msg'], contains('配对码无效或已过期'));

      // 5. 设备已绑定后，后续无需配对码即可凭 device_code 再次登录换发 token
      final reLogin = await _rawJsonRequest(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'KDS-AUTO-01'},
      );
      expect(reLogin.statusCode, 200);
      expect((reLogin.body['data'] as Map)['device_token'], isNotEmpty);
    },
  );
}

class _RawResponse {
  const _RawResponse(this.statusCode, this.body, this.headers);
  final int statusCode;
  final Map<String, Object?> body;
  final Map<String, String> headers;
}

String _cloudEventEnvelope(int sequence) => jsonEncode({
  'protocol_version': 2,
  'type': 'order_updated',
  'shop_id': 1,
  'event_seq': sequence,
  'event_id': 'event-' + sequence.toString(),
  'patches': const [],
  'queue_counts': const {},
});

String _eventAck(int sequence) => jsonEncode({
  'protocol_version': 2,
  'type': 'ack',
  'event_seq': sequence,
  'event_id': 'event-' + sequence.toString(),
});

Future<Map<String, Object?>> _cloudLoginResponse(
  Map<String, Object?> payload,
) async {
  final deviceCode = '${payload['device_code'] ?? payload['deviceCode'] ?? ''}';
  return {
    'code': 0,
    'data': {
      'shop_id': 1,
      'device_code': deviceCode,
      'device_name': deviceCode,
      'device_token': 'cloud-token-$deviceCode',
    },
  };
}

Future<void> _cacheCloudToken({
  required int shopId,
  required String deviceCode,
  required String token,
}) async {}

CashierKdsProxyResponse
_cloudBootstrapResponse() => const CashierKdsProxyResponse(
  statusCode: HttpStatus.ok,
  body:
      '{"code":0,"msg":"ok","data":{"protocol_version":2,"shop_id":1,"authority_mode":"cloud","event_seq":1,"queues":{},"queue_counts":{},"stats":{},"fixed_catalog":[],"config":{}}}',
);

Future<_RawResponse> _rawJsonRequest(
  HttpClient client,
  CashierKdsLanServer server,
  String method,
  String path, {
  Map<String, Object?>? body,
  String? token,
  String? bearerToken,
  String? pairingSecret,
  String? proxyRequestId,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:${server.port}$path'),
  );
  request.headers.contentType = ContentType.json;
  if (token != null) request.headers.set('X-Kds-Device-Token', token);
  if (pairingSecret != null) {
    request.headers.set('X-Kds-Pairing-Secret', pairingSecret);
  }
  if (proxyRequestId != null) {
    request.headers.set('X-KDS-Proxy-Request-Id', proxyRequestId);
  }
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  if (body != null) request.write(jsonEncode(body));
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  return _RawResponse(
    response.statusCode,
    (jsonDecode(text) as Map).cast<String, Object?>(),
    {
      for (final name in const [
        'content-type',
        'age',
        'x-kds-authority-cursor',
        'x-kds-cache',
        'x-kds-cached-at',
        'x-kds-served-via',
      ])
        if (response.headers.value(name) case final value?) name: value,
    },
  );
}

({
  List<Map<String, Object?>> lines,
  List<({int dishId, String dishName})> catalog,
})
_parseLikeRealKds(Map<String, Object?> response) {
  final data = (response['data'] as Map).cast<String, Object?>();
  if (data['protocol_version'] != 2) {
    throw const FormatException('protocol_version must be 2');
  }
  final byDetail = <int, Map<String, Object?>>{};
  final queues = data['queues'];
  if (queues is Map) {
    for (final values in queues.values.whereType<List>()) {
      for (final raw in values.whereType<Map>()) {
        final line = raw.cast<String, Object?>();
        final detailId = (line['detail_id'] as num?)?.toInt() ?? 0;
        if (detailId <= 0) {
          throw const FormatException('detail_id is required');
        }
        byDetail[detailId] = line;
      }
    }
  }
  final catalog = (data['fixed_catalog'] as List? ?? const [])
      .whereType<Map>()
      .map(
        (raw) => (
          dishId: (raw['dish_id'] as num?)?.toInt() ?? 0,
          dishName: '${raw['dish_name'] ?? ''}',
        ),
      )
      .toList(growable: false);
  return (lines: byDetail.values.toList(growable: false), catalog: catalog);
}

Future<Map<String, Object?>> _jsonRequest(
  HttpClient client,
  CashierKdsLanServer server,
  String method,
  String path, {
  Map<String, Object?>? body,
  String? token,
  String? bearerToken,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:${server.port}$path'),
  );
  request.headers.contentType = ContentType.json;
  if (token != null) request.headers.set('X-Kds-Device-Token', token);
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  if (body != null) request.write(jsonEncode(body));
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  expect(response.statusCode, 200, reason: text);
  return (jsonDecode(text) as Map).cast<String, Object?>();
}

Future<void> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
