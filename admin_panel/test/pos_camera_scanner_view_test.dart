import 'package:admin_panel_flutter/src/features/pos/presentation/pos_camera_scanner_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PosCameraScannerView Widget Tests', () {
    testWidgets('renders camera scanner viewfinder with overlays and buttons', (tester) async {
      String? scannedCode;
      bool switchedToGun = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosCameraScannerView(
              onBarcodeScanned: (code) => scannedCode = code,
              onSwitchToManualOrGun: () => switchedToGun = true,
              initialIsFrontCamera: false,
            ),
          ),
        ),
      );

      // Verify prompt text
      expect(find.text('请将顾客微信付款码（条形码/二维码）对准扫描框'), findsOneWidget);
      expect(find.text('平板摄像头免扫码枪扫码模式'), findsOneWidget);

      // Verify controls
      expect(find.byKey(const Key('camera-switch-lens-button')), findsOneWidget);
      expect(find.text('后置镜头'), findsOneWidget);

      expect(find.byKey(const Key('camera-toggle-torch-button')), findsOneWidget);
      expect(find.text('补光关'), findsOneWidget);

      // Test lens toggle
      await tester.tap(find.byKey(const Key('camera-switch-lens-button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('前置镜头'), findsOneWidget);

      // Test torch toggle
      await tester.tap(find.byKey(const Key('camera-toggle-torch-button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('补光已开'), findsOneWidget);

      // Test switch to gun
      await tester.tap(find.byKey(const Key('camera-switch-to-scanner-gun-button')));
      await tester.pump();
      expect(switchedToGun, isTrue);

      // Simulate barcode callback
      final scannerFinder = find.byType(PosCameraScannerView);
      final PosCameraScannerView widget = tester.widget(scannerFinder);
      widget.onBarcodeScanned('134567890123456789');
      expect(scannedCode, '134567890123456789');
    });
  });
}
