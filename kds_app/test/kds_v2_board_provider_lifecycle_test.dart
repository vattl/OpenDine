import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_provider.dart';

class _MutableSessionNotifier extends SessionNotifier {
  @override
  SessionState build() => const SessionState();

  void setLoading(bool value) {
    state = state.copyWith(loading: value);
  }
}

class _CountingBoardNotifier extends KdsV2BoardNotifier {
  int buildCount = 0;

  @override
  KdsV2State build() {
    buildCount++;
    return super.build();
  }
}

void main() {
  test('session state changes do not rebuild and dispose the board notifier',
      () async {
    final session = _MutableSessionNotifier();
    final board = _CountingBoardNotifier();
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => session),
        kdsV2BoardProvider.overrideWith(() => board),
      ],
    );
    addTearDown(container.dispose);

    container.read(kdsV2BoardProvider);
    expect(board.buildCount, 1);

    session.setLoading(true);
    await Future<void>.delayed(Duration.zero);

    expect(
      board.buildCount,
      1,
      reason: '会话状态更新应由监听器处理，不能重建 Notifier 并销毁长期资源',
    );
  });
}
