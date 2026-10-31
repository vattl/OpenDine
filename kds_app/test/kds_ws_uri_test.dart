import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/config/api_base_util.dart';
import 'package:kds_app/core/ws/kds_ws_uri.dart';

void main() {
  group('normalizeApiBase', () {
    test('strips invalid :0 port', () {
      expect(
        normalizeApiBase('https://www.laofei.com.cn:0'),
        'https://www.laofei.com.cn',
      );
    });

    test('strips hash fragment', () {
      expect(
        normalizeApiBase('https://www.laofei.com.cn#'),
        'https://www.laofei.com.cn',
      );
    });
  });

  group('isValidApiBase', () {
    test('accepts base after stripping :0', () {
      expect(isValidApiBase('https://example.com:0'), isTrue);
    });
  });

  group('isInsecureApiBase', () {
    test('http is insecure', () {
      expect(isInsecureApiBase('http://192.168.1.10:8080'), isTrue);
    });

    test('https is secure', () {
      expect(isInsecureApiBase('https://www.laofei.com.cn'), isFalse);
    });

    test('empty is not insecure', () {
      expect(isInsecureApiBase(''), isFalse);
    });
  });

  group('buildKdsWebSocketUri', () {
    test('uses explicit 443 for wss default port', () {
      final uri = buildKdsWebSocketUri(
        apiBase: 'https://www.laofei.com.cn',
        shopId: 1,
        screenTag: 'workflow_board',
      );
      expect(uri.scheme, 'wss');
      expect(uri.port, 443);
      expect(uri.path, '/ws/kds/v2');
      expect(uri.queryParameters['protocol_version'], '2');
      expect(uri.toString(), isNot(contains(':0')));
      expect(uri.queryParameters, isNot(contains('token')));
    });

    test('handles historical :0 api base', () {
      final uri = buildKdsWebSocketUri(
        apiBase: 'https://www.laofei.com.cn:0',
        shopId: 1,
        screenTag: 'workflow_board',
      );
      expect(uri.port, 443);
      expect(uri.toString(), isNot(contains(':0')));
    });

    test('preserves custom port', () {
      final uri = buildKdsWebSocketUri(
        apiBase: 'http://127.0.0.1:8080',
        shopId: 1,
        screenTag: 'workflow_board',
      );
      expect(uri.scheme, 'ws');
      expect(uri.port, 8080);
    });
  });

  group('previewKdsWebSocketUrl', () {
    test('masks token header hint and uses wss:443', () {
      final url = previewKdsWebSocketUrl(apiBase: 'https://www.laofei.com.cn');
      expect(url, contains('wss://www.laofei.com.cn:443/ws/kds/v2'));
      expect(url, contains('X-Kds-Device-Token=***'));
      expect(url, isNot(contains(':0')));
    });
  });
}
