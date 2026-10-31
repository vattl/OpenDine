import 'package:flutter/material.dart';

import 'cashier_tokens.dart';

abstract final class CashierAppTheme {
  static const _lightCanvas = Color(0xfff1f3f5);
  static const _lightSurface = Color(0xffffffff);
  static const _darkCanvas = Color(0xff09090b);
  static const _darkSurface = Color(0xff121214);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = dark
        ? const ColorScheme.dark(
            surface: _darkSurface,
            onSurface: Colors.white,
            primary: Colors.white,
            onPrimary: Color(0xff09090b),
            outline: Color(0xff27272a),
            outlineVariant: Color(0xff3f3f46),
            surfaceContainerHighest: Color(0xff202024),
          )
        : const ColorScheme.light(
            surface: _lightSurface,
            onSurface: Color(0xff111827),
            primary: Color(0xff111827),
            onPrimary: Colors.white,
            outline: Color(0xffdee2e6),
            outlineVariant: Color(0xffced4da),
            surfaceContainerHighest: Color(0xffe9ecef),
          );
    final border = dark ? const Color(0xff27272a) : const Color(0xffdee2e6);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'NotoSansSC',
      scaffoldBackgroundColor: dark ? _darkCanvas : _lightCanvas,
      dividerColor: border,
      canvasColor: dark ? _darkCanvas : _lightCanvas,
      extensions: [dark ? CashierTokens.dark : CashierTokens.light],
      visualDensity: VisualDensity.standard,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: dark,
        fillColor: dark ? _darkSurface : Colors.white,
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(color: scheme.onInverseSurface),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class CashierThemeToggle extends StatelessWidget {
  const CashierThemeToggle({
    super.key,
    required this.themeMode,
    required this.onChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = themeMode == ThemeMode.dark;
    final scheme = Theme.of(context).colorScheme;
    final target = dark ? ThemeMode.light : ThemeMode.dark;
    final label = dark ? '切换到明亮界面' : '切换到暗色界面';

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: IconButton(
            key: const Key('cashier-theme-toggle'),
            onPressed: () => onChanged(target),
            icon: Icon(
              dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            style: IconButton.styleFrom(
              foregroundColor: scheme.onSurface,
              backgroundColor: scheme.surfaceContainerHighest,
              side: BorderSide(color: Theme.of(context).dividerColor),
              minimumSize: const Size.square(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
