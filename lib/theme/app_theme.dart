import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData dark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF5B8CFF),
      onPrimary: Color(0xFFEAF0FF),
      secondary: Color(0xFF8BD2FF),
      onSecondary: Color(0xFF0B2536),
      tertiary: Color(0xFF22C55E),
      onTertiary: Color(0xFF082014),
      error: Color(0xFFFF6B6B),
      onError: Color(0xFF2A0B0B),
      background: Color(0xFF0F1724),
      onBackground: Color(0xFFDCE4EE),
      surface: Color(0xFF151E2B),
      onSurface: Color(0xFFDCE4EE),
      surfaceVariant: Color(0xFF1F2A3A),
      onSurfaceVariant: Color(0xFFB6C2D2),
      outline: Color(0xFF2B384B),
      outlineVariant: Color(0xFF253245),
      shadow: Color(0xFF0B111A),
      scrim: Color(0xFF0B111A),
      inverseSurface: Color(0xFFE6EEF8),
      onInverseSurface: Color(0xFF1B2433),
      inversePrimary: Color(0xFF3C6DFF),
    );

    final base = ThemeData.dark();
    final textTheme = base.textTheme
        .copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 15),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 12),
        )
        .apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
          fontFamily: 'SF Pro Display',
          fontFamilyFallback: const ['SF Pro Text', 'Segoe UI', 'Helvetica Neue'],
        );

    return base.copyWith(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.background,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: colorScheme.surfaceVariant,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceVariant,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colorScheme.surfaceVariant,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(colorScheme.outline),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }
}
