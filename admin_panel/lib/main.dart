import 'dart:async';
import 'package:flutter/material.dart';

import 'src/app/admin_app.dart';
import 'src/core/crash_log.dart';
import 'src/core/terminal_device_service.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      try {
        await CrashLog.instance.init();
      } catch (_) {
        // Logging failure should not block admin startup
      }
      try {
        await TerminalDeviceService.instance.getOrInitializeTerminalId();
      } catch (_) {
        // Non-blocking
      }
      runApp(const AdminPanelFlutterApp());
    },
    (error, stack) {
      CrashLog.instance.write('ERROR', '未捕获运营后台异常: $error', stack);
    },
  );
}
