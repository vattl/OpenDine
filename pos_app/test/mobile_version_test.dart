import 'package:admin_panel_flutter/src/features/mobile/data/app_version_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppVersionPolicy policy({
    String latest = '2.0.1',
    String minSupported = '2.0.0',
    bool forceUpdate = false,
  }) =>
      AppVersionPolicy(
        latest: latest,
        minSupported: minSupported,
        forceUpdate: forceUpdate,
      );

  group('evaluateVersion（语义化比较，指南 §7）', () {
    test('低于 minSupported → 阻断', () {
      expect(
        evaluateVersion('1.9.9', policy()),
        VersionStatus.belowMinSupported,
      );
    });

    test('低于 latest 且 forceUpdate → 强制升级', () {
      expect(
        evaluateVersion('2.0.0', policy(forceUpdate: true)),
        VersionStatus.forceUpdate,
      );
    });

    test('低于 latest 非强制 → 可选升级', () {
      expect(
        evaluateVersion('2.0.0', policy()),
        VersionStatus.optionalUpdate,
      );
    });

    test('等于 latest → 最新', () {
      expect(evaluateVersion('2.0.1', policy()), VersionStatus.upToDate);
    });

    test('高于 latest → 最新（灰度先发型）', () {
      expect(evaluateVersion('2.1.0', policy()), VersionStatus.upToDate);
    });

    test('语义化比较：2.10.0 > 2.9.9（字典序会判反）', () {
      expect(
        evaluateVersion('2.9.9', policy(latest: '2.10.0', minSupported: '2.0.0')),
        VersionStatus.optionalUpdate,
      );
      expect(
        evaluateVersion('2.10.0', policy(latest: '2.10.0', minSupported: '2.0.0')),
        VersionStatus.upToDate,
      );
    });

    test('带 build 后缀按核心版本比较', () {
      expect(
        evaluateVersion('2.0.1+202', policy()),
        VersionStatus.upToDate,
      );
    });
  });
}
