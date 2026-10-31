import 'package:flutter/material.dart';

abstract final class CashierPalette {
  static const canvas = Color(0xffe9e9e9);
  static const surface = Colors.white;
  static const subtle = Color(0xfff5f5f5);
  static const row = Color(0xfff1f1f1);
  static const ink = Color(0xff342e2e);
  static const inkSecondary = Color(0xff555555);
  static const inkMuted = Color(0xff737373);
  static const border = Color(0xffd8d8d8);
  static const selected = Color(0xff075985);
  static const selectedBackground = Color(0xffe0f2fe);
  static const focus = Color(0xff2563eb);
  static const success = Color(0xff166534);
  static const successBackground = Color(0xffdcfce7);
  static const warning = Color(0xff92400e);
  static const warningBackground = Color(0xfffef3c7);
  static const danger = Color(0xffb91c1c);
  static const dangerBackground = Color(0xfffee2e2);
  static const disabledBackground = Color(0xfff3f4f6);
  static const disabledForeground = Color(0xff9ca3af);
  static const overlayScrim = Color(0x73000000);
  static const dishSufficient = Color(0xff50d664);
  static const dishLowStock = Color(0xff59a0f0);
  static const dishSoldOut = Color(0xffe55353);
}

abstract final class CashierSpacing {
  static const xSmall = 4.0;
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const xLarge = 20.0;
  static const xxLarge = 24.0;
  static const section = 32.0;
}

abstract final class CashierMetrics {
  static const minimumTouchTarget = 48.0;
  static const buttonHeight = 56.0;
  static const primaryActionHeight = 64.0;
  static const posActionHeight = 72.0;
  static const listRowHeight = 72.0;
  static const dialogHeaderHeight = 80.0;
  static const dialogRadius = 24.0;
  static const cardRadius = 18.0;
  static const controlRadius = 10.0;
}

abstract final class CashierTypography {
  static const amount = TextStyle(
    fontSize: 48,
    height: 52 / 48,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const amountMedium = TextStyle(
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const headline = TextStyle(
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w700,
  );

  static const title = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
  );

  static const body = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  static const bodyMedium = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );

  static const caption = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  static const code = TextStyle(
    fontSize: 13,
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
