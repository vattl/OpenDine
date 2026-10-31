import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/core/app_state.dart';
import 'package:admin_panel_flutter/src/core/crash_log.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/auth_models.dart';

void main() {
  group('Shop Model Deduplication Tests', () {
    test('LoginSession.fromLoginData deduplicates shops by id', () {
      final json = {
        'token': 'test-token',
        'adminId': 10,
        'displayName': '张三',
        'shops': [
          {'id': 1, 'name': '总店', 'code': 'ZD01'},
          {'id': 2, 'name': '分店', 'code': 'FD02'},
          {'id': 1, 'name': '总店重复条目', 'code': 'ZD01'},
          {'id': 2, 'name': '分店重复条目', 'code': 'FD02'},
          {'id': 3, 'name': '三店', 'code': 'SD03'},
        ],
      };

      final session = LoginSession.fromLoginData(json);
      expect(session.shops.length, 3);
      expect(session.shops.map((s) => s.id).toList(), [1, 2, 3]);
      expect(session.shops[0].name, '总店');
    });

    test('LoginSession.merge deduplicates shops when merging shopData', () {
      final session = LoginSession.fromLoginData({
        'token': 'test-token',
        'shops': [
          {'id': 1, 'name': '门店1', 'code': 'M1'},
        ],
      });

      final merged = session.merge(
        shopData: {
          'shops': [
            {'id': 5, 'name': '门店5', 'code': 'M5'},
            {'id': 5, 'name': '门店5重复', 'code': 'M5'},
            {'id': 6, 'name': '门店6', 'code': 'M6'},
          ],
        },
      );

      expect(merged.shops.length, 2);
      expect(merged.shops.map((s) => s.id).toList(), [5, 6]);
    });
  });

  group('AppState selectShop Safety Tests', () {
    test('selectShop throws ArgumentError and preserves scope when shop is missing', () {
      final appState = AppState();
      appState.applySession(
        LoginSession.fromLoginData({
          'token': 'valid-token',
          'shops': [
            {'id': 10, 'name': '旗舰店', 'code': 'QJD'},
            {'id': 20, 'name': '标准店', 'code': 'BZD'},
          ],
        }),
      );

      expect(appState.currentShopId, 10);

      // Switching to a valid shop
      appState.selectShop(20);
      expect(appState.currentShopId, 20);

      // Switching to an invalid shop ID throws ArgumentError
      expect(() => appState.selectShop(999), throwsArgumentError);
      // Scope remains at last valid shop
      expect(appState.currentShopId, 20);
    });
  });

  group('Crash Recovery Widget Tests', () {
    testWidgets('renders recovery UI and back button navigates back', (tester) async {
      const details = FlutterErrorDetails(
        exception: FormatException('测试组件渲染异常拦截'),
        stack: StackTrace.empty,
      );

      var popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CashierCrashRecoveryWidget(details: details),
                      ),
                    ).then((_) => popped = true);
                  },
                  child: const Text('打开故障页'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open error page
      await tester.tap(find.text('打开故障页'));
      await tester.pumpAndSettle();

      expect(find.text('界面渲染暂时遇到问题'), findsOneWidget);
      expect(find.textContaining('测试组件渲染异常拦截'), findsOneWidget);
      expect(find.byKey(const Key('crash-recovery-back-button')), findsOneWidget);
      expect(find.byKey(const Key('crash-recovery-home-button')), findsOneWidget);
      expect(find.byKey(const Key('crash-recovery-retry-button')), findsOneWidget);

      // Tap back button
      await tester.tap(find.byKey(const Key('crash-recovery-back-button')));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      expect(find.text('打开故障页'), findsOneWidget);
    });
  });
}
