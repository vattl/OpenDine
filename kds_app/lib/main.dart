import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kds_app/app.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 网络/API 短暂故障不是应用崩溃：必须保留已登录会话和看板页面，
/// 由看板自身显示连接状态并继续处理离线待同步操作。
bool isRecoverableAppError(Object error) =>
    error is ApiException ||
    error is TimeoutException ||
    error is SocketException ||
    error is HttpException;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await KdsFileLogger.init();

  FlutterError.onError = (details) {
    KdsFileLogger.error('FlutterError', details.exception, details.stack);
  };

  if (!kIsWeb) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await WakelockPlus.enable();
  }

  final container = ProviderContainer();

  PlatformDispatcher.instance.onError = (error, stack) {
    KdsFileLogger.error('Uncaught', error, stack);
    if (!isRecoverableAppError(error)) {
      container.read(fatalErrorProvider.notifier).state = error.toString();
    }
    return true;
  };

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KdsApp(),
    ),
  );

  unawaited(container.read(sessionProvider.notifier).bootstrap());
}
