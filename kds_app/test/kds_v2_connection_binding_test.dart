import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/ws/kds_websocket.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_provider.dart';

void main() {
  test('replacing websocket changes the board connection binding key', () {
    KdsWebSocketService socket() => KdsWebSocketService(
          getBaseUrl: () => 'http://127.0.0.1:17026',
          getShopId: () => 1,
          getScreenTag: () => 'workflow_board',
          getToken: () => 'token',
        );
    final first = socket();
    final second = socket();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    expect(
      kdsV2ConnectionBindingKey('http://127.0.0.1:17026', 'token', first, 1),
      isNot(kdsV2ConnectionBindingKey(
          'http://127.0.0.1:17026', 'token', second, 2)),
    );
  });
}
