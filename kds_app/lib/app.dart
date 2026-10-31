import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kds_app/core/layout/kds_display_scope.dart';
import 'package:kds_app/core/theme/kds_theme.dart';
import 'package:kds_app/features/auth/login_page.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_page.dart';
import 'package:kds_app/features/diagnostics/kds_inspector_modal.dart';
import 'package:kds_app/features/settings/kds_live_log_page.dart';
import 'package:kds_app/features/settings/kds_v2_settings_page.dart';
import 'package:kds_app/shared/widgets/kds_error_page.dart';

part 'router.dart';

final fatalErrorProvider = StateProvider<String?>((ref) => null);

class KdsApp extends ConsumerStatefulWidget {
  const KdsApp({super.key});

  @override
  ConsumerState<KdsApp> createState() => _KdsAppState();
}

class _KdsAppState extends ConsumerState<KdsApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onPause: () => ref.read(sessionProvider.notifier).handleAppPaused(),
      onResume: () => unawaited(
        ref.read(sessionProvider.notifier).handleAppResumed(),
      ),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fatal = ref.watch(fatalErrorProvider);
    if (fatal != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildKdsTheme(),
        home: KdsErrorPage(
          message: fatal,
          onRestart: () async {
            ref.read(fatalErrorProvider.notifier).state = null;
            await ref.read(sessionProvider.notifier).logout();
          },
        ),
      );
    }

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'KDS 厨显',
      debugShowCheckedModeBanner: false,
      theme: buildKdsTheme(),
      routerConfig: router,
      builder: (context, child) {
        return KdsDisplayScope(
          child: Scaffold(
            backgroundColor: KdsColors.shellBg,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(child: child ?? const SizedBox.shrink())],
            ),
          ),
        );
      },
    );
  }
}
