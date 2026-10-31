import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/storage/app_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('KDS workflow preferences use safe defaults and persist changes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await AppPrefs.load();

    expect(prefs.prepFlowEnabled, isTrue);
    expect(prefs.fixedDishOrderEnabled, isTrue);
    expect(prefs.mergeSameDishNameEnabled, isTrue);
    expect(prefs.newOrderSoundEnabled, isTrue);

    await prefs.setPrepFlowEnabled(false);
    await prefs.setFixedDishOrderEnabled(false);
    await prefs.setMergeSameDishNameEnabled(false);
    await prefs.setNewOrderSoundEnabled(false);

    final reloaded = await AppPrefs.load();
    expect(reloaded.prepFlowEnabled, isFalse);
    expect(reloaded.fixedDishOrderEnabled, isFalse);
    expect(reloaded.mergeSameDishNameEnabled, isFalse);
    expect(reloaded.newOrderSoundEnabled, isFalse);
  });
}
