import 'package:admin_panel_flutter/src/core/responsive_design_viewport.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps the 1920 by 1080 design viewport on 16:9 displays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Size? mediaSize;
    BoxConstraints? childConstraints;
    await tester.pumpWidget(
      MaterialApp(
        home: CashierResponsiveViewport(
          child: Builder(
            builder: (context) {
              mediaSize = MediaQuery.sizeOf(context);
              return LayoutBuilder(
                builder: (context, constraints) {
                  childConstraints = constraints;
                  return const SizedBox.expand();
                },
              );
            },
          ),
        ),
      ),
    );

    expect(mediaSize, const Size(1920, 1080));
    expect(childConstraints?.biggest, const Size(1920, 1080));
  });

  testWidgets('expands the logical canvas to fill an ultra-wide display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Size? mediaSize;
    await tester.pumpWidget(
      MaterialApp(
        home: CashierResponsiveViewport(
          child: Builder(
            builder: (context) {
              mediaSize = MediaQuery.sizeOf(context);
              return const ColoredBox(
                key: Key('responsive-canvas'),
                color: Colors.blue,
              );
            },
          ),
        ),
      ),
    );

    expect(mediaSize, const Size(2560, 1080));
    expect(
      tester.getRect(find.byKey(const Key('responsive-canvas'))),
      const Rect.fromLTWH(0, 0, 2560, 1080),
    );
  });

  testWidgets('expands the logical canvas to fill a taller display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Size? mediaSize;
    await tester.pumpWidget(
      MaterialApp(
        home: CashierResponsiveViewport(
          child: Builder(
            builder: (context) {
              mediaSize = MediaQuery.sizeOf(context);
              return const ColoredBox(
                key: Key('responsive-canvas'),
                color: Colors.blue,
              );
            },
          ),
        ),
      ),
    );

    expect(mediaSize, const Size(1920, 1200));
    expect(
      tester.getRect(find.byKey(const Key('responsive-canvas'))),
      const Rect.fromLTWH(0, 0, 1280, 800),
    );
  });

  testWidgets('theme toggle switches between light and dark modes', (
    tester,
  ) async {
    var mode = ThemeMode.light;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          theme: CashierAppTheme.light(),
          darkTheme: CashierAppTheme.dark(),
          themeMode: mode,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: CashierThemeToggle(
                themeMode: mode,
                onChanged: (value) => setState(() => mode = value),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('cashier-theme-toggle')));
    await tester.pumpAndSettle();

    expect(mode, ThemeMode.dark);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(CashierThemeToggle))).brightness,
      Brightness.dark,
    );
  });

  test('dark theme uses the unified 2D2D2D surface color', () {
    final theme = CashierAppTheme.dark();

    expect(theme.scaffoldBackgroundColor, const Color(0xff2d2d2d));
    expect(theme.colorScheme.surface, const Color(0xff2d2d2d));
    expect(theme.dialogTheme.backgroundColor, const Color(0xff2d2d2d));
    expect(theme.inputDecorationTheme.fillColor, const Color(0xff2d2d2d));
  });
}
