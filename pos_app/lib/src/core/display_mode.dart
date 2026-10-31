import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const kAppFlavor = String.fromEnvironment('APP_FLAVOR', defaultValue: 'pos');
const kIsMobileApp = kAppFlavor == 'mobile';

Future<void> configurePreferredDisplay({
  TargetPlatform? platform,
  bool? isWeb,
}) async {
  final resolvedPlatform = platform ?? defaultTargetPlatform;
  final resolvedIsWeb = isWeb ?? kIsWeb;
  if (resolvedIsWeb || resolvedPlatform != TargetPlatform.android) return;

  // 手机端/全端强制横屏（支持双向横屏旋转与沉浸式体验）
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}
