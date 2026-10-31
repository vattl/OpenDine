import 'package:admin_panel_flutter/src/features/mobile/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('home notification action uses the configured router', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomePage()),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const Scaffold(body: Text('通知路由已打开')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('通知'));
    await tester.pumpAndSettle();

    expect(find.text('通知路由已打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
