import 'dart:convert';
import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_lan_server.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_transport_proof.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/cashier_kds_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final caCertFile = File('build/test_certs/ca.crt');
  final serverCertFile = File('build/test_certs/server.crt');
  final serverKeyFile = File('build/test_certs/server.key');
  final untrustedCertFile = File('build/test_certs/untrusted.crt');
  final untrustedKeyFile = File('build/test_certs/untrusted.key');

  final hasCerts = caCertFile.existsSync() &&
      serverCertFile.existsSync() &&
      serverKeyFile.existsSync() &&
      untrustedCertFile.existsSync() &&
      untrustedKeyFile.existsSync();

  group('KDS LAN TLS and Transport Proof Verification (T004)', () {
    const testToken = 'cloud-issued-device-token-12345';

    SecurityContext createServerContext(File certFile, File keyFile) {
      return SecurityContext(withTrustedRoots: false)
        ..useCertificateChain(certFile.path)
        ..usePrivateKey(keyFile.path);
    }

    HttpClient createPkiClient({required bool trustRootCa}) {
      final context = SecurityContext(withTrustedRoots: false);
      if (trustRootCa) {
        context.setTrustedCertificates(caCertFile.path);
      }
      // Note: NO badCertificateCallback! Strict PKI validation is enforced.
      return HttpClient(context: context);
    }

    Map<String, String> generateProof({
      required String token,
      required String method,
      required String path,
      Map<String, String> query = const {},
      Map<String, Object?> body = const {},
      int? overrideTimestampMs,
      String? overrideNonce,
    }) {
      final timestampMs =
          overrideTimestampMs ?? DateTime.now().millisecondsSinceEpoch;
      final nonce = overrideNonce ??
          'nonce-${DateTime.now().microsecondsSinceEpoch.toString().padLeft(16, "0")}';
      final bodyHash = kdsLanBodySha256(body);
      return {
        kKdsLanTimestampHeader: '$timestampMs',
        kKdsLanNonceHeader: nonce,
        kKdsLanBodySha256Header: bodyHash,
        kKdsLanSignatureHeader: kdsLanSignature(
          token: token,
          timestampMs: timestampMs,
          nonce: nonce,
          method: method,
          path: path,
          query: query,
          bodySha256: bodyHash,
        ),
      };
    }

    test(
      '1. PKI validation: client trusting Root CA successfully performs TLS handshake and gets 200',
      () async {
        final db = CashierKdsDatabase.inMemory();
        final server = CashierKdsLanServer(
          db,
          cloudAuthorityMode: true,
          onProxyHttp: (_) async => const CashierKdsProxyResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"ok","data":{"cursor":50}}',
          ),
        );
        addTearDown(() async {
          await server.close();
          db.close();
        });

        await server.start(
          address: InternetAddress.loopbackIPv4,
          port: 0,
          securityContext: createServerContext(serverCertFile, serverKeyFile),
        );

        final client = createPkiClient(trustRootCa: true);
        addTearDown(() => client.close(force: true));

        final proof = generateProof(
          token: testToken,
          method: 'GET',
          path: '/kds/v2/bootstrap',
        );

        final request = await client.getUrl(
          Uri.parse('https://127.0.0.1:${server.port}/kds/v2/bootstrap'),
        );
        request.headers.set('X-Kds-Device-Token', testToken);
        proof.forEach(request.headers.set);

        final response = await request.close();
        final bodyStr = await utf8.decoder.bind(response).join();

        expect(response.statusCode, HttpStatus.ok);
        expect(bodyStr, contains('"cursor":50'));
      },
      skip: !hasCerts,
    );

    test(
      '2. Strict security: untrusted rogue certificate is rejected by client PKI with HandshakeException',
      () async {
        final db = CashierKdsDatabase.inMemory();
        final server = CashierKdsLanServer(
          db,
          cloudAuthorityMode: true,
          onProxyHttp: (_) async => const CashierKdsProxyResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"ok"}',
          ),
        );
        addTearDown(() async {
          await server.close();
          db.close();
        });

        // Server uses untrusted self-signed certificate (not signed by Root CA)
        await server.start(
          address: InternetAddress.loopbackIPv4,
          port: 0,
          securityContext:
              createServerContext(untrustedCertFile, untrustedKeyFile),
        );

        final client = createPkiClient(trustRootCa: true);
        addTearDown(() => client.close(force: true));

        expect(
          () async {
            final request = await client.getUrl(
              Uri.parse('https://127.0.0.1:${server.port}/kds/v2/bootstrap'),
            );
            await request.close();
          },
          throwsA(isA<HandshakeException>()),
        );
      },
      skip: !hasCerts,
    );

    test(
      '3. Clock skew defense: requests with timestamp deviating > 60s are rejected with 401',
      () async {
        final db = CashierKdsDatabase.inMemory();
        final server = CashierKdsLanServer(
          db,
          cloudAuthorityMode: true,
          onProxyHttp: (_) async => const CashierKdsProxyResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"ok"}',
          ),
        );
        addTearDown(() async {
          await server.close();
          db.close();
        });

        await server.start(
          address: InternetAddress.loopbackIPv4,
          port: 0,
          securityContext: createServerContext(serverCertFile, serverKeyFile),
        );

        final client = createPkiClient(trustRootCa: true);
        addTearDown(() => client.close(force: true));

        // 3a. Timestamp 65 seconds in the past
        final pastTimestamp =
            DateTime.now().millisecondsSinceEpoch - 65 * 1000;
        final pastProof = generateProof(
          token: testToken,
          method: 'GET',
          path: '/kds/v2/bootstrap',
          overrideTimestampMs: pastTimestamp,
        );

        final pastReq = await client.getUrl(
          Uri.parse('https://127.0.0.1:${server.port}/kds/v2/bootstrap'),
        );
        pastReq.headers.set('X-Kds-Device-Token', testToken);
        pastProof.forEach(pastReq.headers.set);

        final pastResp = await pastReq.close();
        final pastBody = await utf8.decoder.bind(pastResp).join();
        expect(pastResp.statusCode, HttpStatus.unauthorized);
        expect(pastBody, contains('LAN transport proof'));

        // 3b. Timestamp 65 seconds in the future
        final futureTimestamp =
            DateTime.now().millisecondsSinceEpoch + 65 * 1000;
        final futureProof = generateProof(
          token: testToken,
          method: 'GET',
          path: '/kds/v2/bootstrap',
          overrideTimestampMs: futureTimestamp,
        );

        final futureReq = await client.getUrl(
          Uri.parse('https://127.0.0.1:${server.port}/kds/v2/bootstrap'),
        );
        futureReq.headers.set('X-Kds-Device-Token', testToken);
        futureProof.forEach(futureReq.headers.set);

        final futureResp = await futureReq.close();
        final futureBody = await utf8.decoder.bind(futureResp).join();
        expect(futureResp.statusCode, HttpStatus.unauthorized);
        expect(futureBody, contains('LAN transport proof'));
      },
      skip: !hasCerts,
    );

    test(
      '4. Replay attack defense: identical proof replay is rejected with 401',
      () async {
        final db = CashierKdsDatabase.inMemory();
        final server = CashierKdsLanServer(
          db,
          cloudAuthorityMode: true,
          onProxyHttp: (_) async => const CashierKdsProxyResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"ok"}',
          ),
        );
        addTearDown(() async {
          await server.close();
          db.close();
        });

        await server.start(
          address: InternetAddress.loopbackIPv4,
          port: 0,
          securityContext: createServerContext(serverCertFile, serverKeyFile),
        );

        final client = createPkiClient(trustRootCa: true);
        addTearDown(() => client.close(force: true));

        const fixedNonce = 'fixed-nonce-0123456789abcdef';
        final fixedProof = generateProof(
          token: testToken,
          method: 'GET',
          path: '/kds/v2/bootstrap',
          overrideNonce: fixedNonce,
        );

        // First attempt: should succeed (200)
        final req1 = await client.getUrl(
          Uri.parse('https://127.0.0.1:${server.port}/kds/v2/bootstrap'),
        );
        req1.headers.set('X-Kds-Device-Token', testToken);
        fixedProof.forEach(req1.headers.set);
        final resp1 = await req1.close();
        await utf8.decoder.bind(resp1).join();
        expect(resp1.statusCode, HttpStatus.ok);

        // Second attempt with exact same proof: must be rejected as replayed (401)
        final req2 = await client.getUrl(
          Uri.parse('https://127.0.0.1:${server.port}/kds/v2/bootstrap'),
        );
        req2.headers.set('X-Kds-Device-Token', testToken);
        fixedProof.forEach(req2.headers.set);
        final resp2 = await req2.close();
        final body2 = await utf8.decoder.bind(resp2).join();
        expect(resp2.statusCode, HttpStatus.unauthorized);
        expect(body2, contains('replayed LAN transport proof'));
      },
      skip: !hasCerts,
    );
    test(
      '5. Real WSS: WebSocket connection over TLS with Root CA trust is accepted and transmits frames',
      () async {
        final upstreamServer =
            await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => upstreamServer.close(force: true));
        upstreamServer.listen((request) async {
          if (WebSocketTransformer.isUpgradeRequest(request)) {
            final socket = await WebSocketTransformer.upgrade(request);
            socket.add(jsonEncode({
              'protocol_version': 2,
              'type': 'order_updated',
              'shop_id': 1,
              'event_seq': 1,
              'event_id': 'event-test-001',
              'occurred_at_ms': 1790812800000,
              'patches': [],
            }));
          }
        });

        final db = CashierKdsDatabase.inMemory();
        final server = CashierKdsLanServer(
          db,
          cloudAuthorityMode: true,
          onProxyHttp: (req) async => const CashierKdsProxyResponse(
            statusCode: 200,
            body: '{"code":0,"msg":"ok","data":{"shop_id":1,"device_code":"KDS-TEST","enabled":1,"scopes":["kds:read","kds:operate"]}}',
          ),
          onProxyWebSocket: (token, query) => WebSocket.connect(
            'ws://127.0.0.1:${upstreamServer.port}/ws/kds/v2',
            headers: {'X-Kds-Device-Token': token},
          ),
        );
        addTearDown(() async {
          await server.close();
          db.close();
        });

        server.setActiveShop(1);
        await server.start(
          address: InternetAddress.loopbackIPv4,
          port: 0,
          securityContext: createServerContext(serverCertFile, serverKeyFile),
        );

        final client = createPkiClient(trustRootCa: true);
        addTearDown(() => client.close(force: true));

        final proof = generateProof(
          token: testToken,
          method: 'GET',
          path: '/ws/kds/v2',
        );

        final ws = await WebSocket.connect(
          'wss://127.0.0.1:${server.port}/ws/kds/v2',
          customClient: client,
          headers: {
            'X-Kds-Device-Token': testToken,
            ...proof,
          },
        );
        addTearDown(() => ws.close());

        expect(ws.readyState, WebSocket.open);

        final response = await ws.first.timeout(const Duration(seconds: 5));
        final decoded = jsonDecode(response as String) as Map<String, Object?>;
        expect(decoded['type'], 'order_updated');
        expect(decoded['protocol_version'], 2);
        expect(decoded['event_seq'], 1);
      },
      skip: !hasCerts,
    );
  });
}
