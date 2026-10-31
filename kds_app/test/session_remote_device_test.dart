import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/kds_api.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/features/auth/session_provider.dart';

void main() {
  test('remote empty workflows explicitly clears local assignments', () {
    final current = KdsDevice(
      id: 1,
      shopId: 7,
      screenTag: KdsScreenTag.workflowBoard,
      deviceCode: 'KDS-01',
      deviceToken: 'token',
      workflows: const [KdsWorkflow.prep, KdsWorkflow.cook],
    );
    final remote = KdsDevice(
      id: 1,
      shopId: 7,
      screenTag: KdsScreenTag.workflowBoard,
      deviceCode: 'KDS-01',
      deviceToken: 'token',
      workflows: const [],
    );

    final merged = mergeRemoteKdsDevice(current, remote, token: 'token');

    expect(merged.workflows, isEmpty);
  });

  group('D026 screen_tags', () {
    test('fromJson parses screen_tags and toJson round-trips', () {
      final json = <String, dynamic>{
        'id': 3,
        'shop_id': 7,
        'screen_tag': 'workflow_board',
        'device_code': 'KDS-01',
        'device_name': '烤台一',
        'workflows': ['prep', 'cook', 'serve'],
        'screen_tags': ['meat_grill', 'seafood_special'],
      };
      final device = KdsDevice.fromJson(json, token: 'tok');

      expect(device.screenTags, ['meat_grill', 'seafood_special']);
      expect(device.toJson()['screen_tags'], ['meat_grill', 'seafood_special']);
    });

    test('fromJson tolerates missing/blank screen_tags', () {
      final json = <String, dynamic>{
        'id': 3,
        'shop_id': 7,
        'screen_tag': 'workflow_board',
        'device_code': 'KDS-01',
        'workflows': ['prep', 'cook', 'serve'],
      };
      final device = KdsDevice.fromJson(json, token: 'tok');

      expect(device.screenTags, isEmpty);
      expect(device.toJson()['screen_tags'], isEmpty);
    });

    test('merge keeps server screen_tags authoritative', () {
      final current = KdsDevice(
        id: 1,
        shopId: 7,
        screenTag: KdsScreenTag.workflowBoard,
        deviceCode: 'KDS-01',
        deviceToken: 'token',
        workflows: const [KdsWorkflow.prep, KdsWorkflow.cook],
        screenTags: const ['meat_grill'],
      );
      final remote = KdsDevice(
        id: 1,
        shopId: 7,
        screenTag: KdsScreenTag.workflowBoard,
        deviceCode: 'KDS-01',
        deviceToken: 'token',
        workflows: const [KdsWorkflow.prep, KdsWorkflow.cook],
        screenTags: const ['veg_grill'],
      );

      final merged = mergeRemoteKdsDevice(current, remote, token: 'token');

      expect(merged.screenTags, ['veg_grill']);
    });
  });
}
