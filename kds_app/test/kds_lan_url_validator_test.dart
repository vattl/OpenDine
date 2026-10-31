import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/config/api_base_util.dart';

void main() {
  test('accepts explicit cashier private LAN endpoints', () {
    expect(isPrivateLanApiBase('http://192.168.1.20:8080'), isTrue);
    expect(isPrivateLanApiBase('http://10.0.0.8'), isTrue);
    expect(isPrivateLanApiBase('http://172.16.4.2'), isTrue);
    expect(isPrivateLanApiBase('http://cashier.local:8080'), isTrue);
  });

  test('rejects public cloud and malformed endpoints without inference', () {
    expect(isPrivateLanApiBase('https://kds.example.com'), isFalse);
    expect(isPrivateLanApiBase('not a url'), isFalse);
    expect(isPrivateLanApiBase(''), isFalse);
  });

  test('secure private LAN validator rejects plaintext non-loopback URLs', () {
    expect(isSecurePrivateLanApiBase('https://192.168.1.20:17026'), isTrue);
    expect(isSecurePrivateLanApiBase('http://192.168.1.20:17026'), isFalse);
    expect(
      isSecurePrivateLanApiBase(
        'http://127.0.0.1:17026',
        allowLoopbackHttp: true,
      ),
      isTrue,
    );
    expect(isSecurePrivateLanApiBase('http://127.0.0.1:17026'), isFalse);
  });
}
