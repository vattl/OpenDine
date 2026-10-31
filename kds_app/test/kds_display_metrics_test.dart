import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/layout/kds_display_metrics.dart';

void main() {
  group('KdsDisplayMetrics', () {
    test('scales from 1920x1080 design baseline', () {
      final m = KdsDisplayMetrics.fromLogicalSize(const Size(1920, 1080), 1.0);
      expect(m.uiScale, closeTo(1.0, 0.01));
      expect(m.formFactor, KdsFormFactor.kdsWall);
      expect(m.dp(100), closeTo(100, 0.01));
    });

    test('clamps scale for compact screens', () {
      final m = KdsDisplayMetrics.fromLogicalSize(const Size(640, 360), 2.0);
      expect(m.uiScale, greaterThanOrEqualTo(0.72));
      expect(m.formFactor, KdsFormFactor.compact);
    });

    test('gridColumns adapts to content width and dish card scale', () {
      final wall =
          KdsDisplayMetrics.fromLogicalSize(const Size(1920, 1080), 1.0);
      expect(wall.gridColumns(1800), 6);

      final tablet =
          KdsDisplayMetrics.fromLogicalSize(const Size(1024, 768), 1.0);
      expect(tablet.gridColumns(960), 4);
      expect(tablet.gridColumns(600), 3);
    });

    test('resolutionLabel includes logical size and dpr', () {
      final m = KdsDisplayMetrics.fromLogicalSize(const Size(1280, 720), 1.5);
      expect(m.resolutionLabel, '1280×720 · 1.5x');
    });

    test('landscape dialog viewport uses reduced inset and scale', () {
      final m = KdsDisplayMetrics.fromLogicalSize(const Size(1920, 720), 1.0);
      expect(m.isLandscape, isTrue);
      expect(m.dialogInset.vertical, lessThan(m.dialogInset.horizontal));
      expect(m.dialogUiScale, lessThan(m.uiScale));
      expect(m.dialogViewportSize.height,
          closeTo(1920 * 720 / 1920 - m.dialogInset.vertical, 30));
    });
  });
}
