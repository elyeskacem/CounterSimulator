import 'package:flutter/material.dart';

import '../models.dart';

class Palette {
  static const bg = Color(0xFF07090C);
  static const panel = Color(0xFF10141A);
  static const panel2 = Color(0xFF161B23);
  static const line = Color(0xFF232A35);
  static const track = Color(0xFF1A2029);
  static const muted = Color(0xFF7D8896);
  static const accent = Color(0xFF2BE0A0);
  static const warn = Color(0xFFFFC83D);
  static const danger = Color(0xFFFF4D4D);
  static const info = Color(0xFF4DB8FF);

  static Color forLevel(AlertLevel level) {
    switch (level) {
      case AlertLevel.ok:
        return accent;
      case AlertLevel.info:
        return info;
      case AlertLevel.warn:
        return warn;
      case AlertLevel.danger:
        return danger;
    }
  }
}

/// Monospaced digits (Menlo on iOS).
TextStyle mono({double size = 16, FontWeight weight = FontWeight.w400, Color? color}) => TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['Courier New', 'monospace'],
      fontSize: size,
      fontWeight: weight,
      color: color,
    );

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.accent,
      brightness: Brightness.dark,
    ).copyWith(surface: Palette.bg, primary: Palette.accent),
  );
  return base.copyWith(
    scaffoldBackgroundColor: Palette.bg,
    appBarTheme: const AppBarTheme(backgroundColor: Palette.bg, surfaceTintColor: Colors.transparent),
    dividerColor: Palette.line,
    listTileTheme: const ListTileThemeData(tileColor: Palette.panel2),
  );
}
