import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/app.dart';
import 'package:kds_app/features/auth/session_provider.dart';

void main() {
  testWidgets('app lifecycle pauses and resumes the KDS session',
      (tester) async {
    final notifier = _LifecycleSessionNotifier();
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionProvider.overrideWith(() => notifier)],
      child: const KdsApp(),
    ));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(notifier.pauses, 1);
    expect(notifier.resumes, 1);
  });
}

class _LifecycleSessionNotifier extends SessionNotifier {
  int pauses = 0;
  int resumes = 0;

  @override
  SessionState build() => const SessionState();

  @override
  void handleAppPaused() => pauses++;

  @override
  Future<void> handleAppResumed() async => resumes++;
}
