import 'dart:convert';
import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_tls.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_lan_server.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_transport_proof.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/cashier_kds_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final enabled = Platform.environment['RUN_KDS_REAL_TLS_TEST'] == '1';

  test(
    'real TLS socket accepts one signed request and rejects its replay',
    () async {
      final tls = CashierKdsTlsConfiguration.fromEnvironment(
        Platform.environment,
      )!;
      final database = CashierKdsDatabase.inMemory();
      final server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onProxyHttp: (_) async => const CashierKdsProxyResponse(
          statusCode: 200,
          body: '{"code":0,"msg":"ok","data":{"orders":[]}}',
        ),
      );
      addTearDown(() async {
        await server.close();
        database.close();
      });
      await server.start(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        securityContext: tls.securityContext,
      );

      const token = 'real-tls-device-token';
      final proof = _proof(token);
      final client = HttpClient()
        ..badCertificateCallback = (_, _, _) => true;
      addTearDown(() => client.close(force: true));

      Future<HttpClientResponse> send() async {
        final request = await client.getUrl(
          Uri.parse('https://127.0.0.1:${server.port}/kds/v2/bootstrap'),
        );
        request.headers.set('X-Kds-Device-Token', token);
        proof.forEach(request.headers.set);
        return request.close();
      }

      final accepted = await send();
      await utf8.decoder.bind(accepted).join();
      expect(accepted.statusCode, HttpStatus.ok);

      final replayed = await send();
      final replayBody = await utf8.decoder.bind(replayed).join();
      expect(replayed.statusCode, HttpStatus.unauthorized);
      expect(replayBody, contains('replayed LAN transport proof'));
    },
    skip: enabled
        ? false
        : 'set RUN_KDS_REAL_TLS_TEST=1 with test certificate paths',
  );
}

Map<String, String> _proof(String token) {
  const body = <String, Object?>{};
  const nonce = 'real-tls-nonce-0001';
  final timestampMs = DateTime.now().millisecondsSinceEpoch;
  final bodyHash = kdsLanBodySha256(body);
  return {
    kKdsLanTimestampHeader: '$timestampMs',
    kKdsLanNonceHeader: nonce,
    kKdsLanBodySha256Header: bodyHash,
    kKdsLanSignatureHeader: kdsLanSignature(
      token: token,
      timestampMs: timestampMs,
      nonce: nonce,
      method: 'GET',
      path: '/kds/v2/bootstrap',
      query: const {},
      bodySha256: bodyHash,
    ),
  };
}
