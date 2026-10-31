import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/storage/app_prefs.dart';
import 'package:kds_app/core/storage/session_storage.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Session and Settings Preservation Tests', () {
    test('SessionStorage.isPreservedSettingKey correctly identifies protected settings', () {
      // 业务设置参数
      expect(SessionStorage.isPreservedSettingKey('kds_prep_flow_enabled'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('kds_fixed_dish_order'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('kds_merge_same_dish_name'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('new_order_sound'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('kds_sla_minutes'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('kds_card_scale_percent'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('kds_printer_ip'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('kds_last_shop_id'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('kds_last_workflows'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('kds_last_device_name'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('kds_api_base'), isTrue);
      expect(SessionStorage.isPreservedSettingKey('kds_cloud_api_base'), isTrue);

      // 应当被清理的会话和 Token
      expect(SessionStorage.isPreservedSettingKey('kds_session_json'), isFalse);
      expect(SessionStorage.isPreservedSettingKey('kds_device_token'), isFalse);
      expect(SessionStorage.isPreservedSettingKey('kds_cloud_token'), isFalse);
    });

    test('AppPrefs settings are preserved across logout and relogin', () async {
      SharedPreferences.setMockInitialValues({
        'kds_prep_flow_enabled': true,
        'kds_fixed_dish_order': true,
        'kds_merge_same_dish_name': true,
        'new_order_sound': true,
        'kds_sla_minutes': 15,
        'kds_card_scale_percent': 100,
      });

      final prefs = await AppPrefs.load();
      // 用户自定义配置
      await prefs.setPrepFlowEnabled(false);
      await prefs.setNewOrderSoundEnabled(false);
      await prefs.setMergeSameDishNameEnabled(false);
      await prefs.setSlaMinutes(25);
      await prefs.setCardScalePercent(120);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionProvider.notifier);
      await notifier.bootstrap();

      // 模拟登出
      await notifier.logout();

      // 验证 AppPrefs 依然保持修改后的值，未被清空
      final reloadedPrefs = await AppPrefs.load();
      expect(reloadedPrefs.prepFlowEnabled, isFalse);
      expect(reloadedPrefs.newOrderSoundEnabled, isFalse);
      expect(reloadedPrefs.mergeSameDishNameEnabled, isFalse);
      expect(reloadedPrefs.slaMinutes, 25);
      expect(reloadedPrefs.cardScalePercent, 120);
    });

    test('clearAllCache with preserveSettings preserves user configuration', () async {
      SharedPreferences.setMockInitialValues({
        'new_order_sound': false,
        'kds_sla_minutes': 30,
        'kds_last_shop_id': 88,
        'kds_last_workflows': '["cook","serve"]',
        'kds_last_device_name': '后厨热菜1号',
        'unrelated_temp_key': 'temp_value',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionProvider.notifier);
      await notifier.bootstrap();

      // 执行带保护的缓存清理
      await notifier.clearAllCache(preserveSettings: true);

      final sharedPrefs = await SharedPreferences.getInstance();
      // 设置和记忆信息得到保护
      expect(sharedPrefs.getBool('new_order_sound'), isFalse);
      expect(sharedPrefs.getInt('kds_sla_minutes'), 30);
      expect(sharedPrefs.getInt('kds_last_shop_id'), 88);
      expect(sharedPrefs.getString('kds_last_workflows'), '["cook","serve"]');
      expect(sharedPrefs.getString('kds_last_device_name'), '后厨热菜1号');

      // 非白名单项被安全移除
      expect(sharedPrefs.containsKey('unrelated_temp_key'), isFalse);
    });

    test('SessionStorage correctly stores and retrieves last shopId and workflows', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionProvider.notifier);
      await notifier.bootstrap();
      final storage = notifier.storage;

      await storage.setLastShopId(99);
      await storage.setLastWorkflows(['prep', 'cook']);
      await storage.setLastDeviceName('传菜口大屏');

      expect(storage.getLastShopId(), 99);
      expect(storage.getLastWorkflows(), ['prep', 'cook']);
      expect(storage.getLastDeviceName(), '传菜口大屏');

      // clearAll 仅清理 session 数据，不清除 lastShopId / lastWorkflows
      await storage.clearAll();
      expect(storage.getLastShopId(), 99);
      expect(storage.getLastWorkflows(), ['prep', 'cook']);
      expect(storage.getLastDeviceName(), '传菜口大屏');
    });
  });
}
