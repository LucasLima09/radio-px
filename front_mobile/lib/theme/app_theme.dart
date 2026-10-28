import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tema do app em um lugar só.
class AppTheme {
  const AppTheme._();

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: pxAccent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: pxAccent,
          onPrimary: pxOnAccent,
          surface: pxSurface,
        ),
        scaffoldBackgroundColor: pxSurface,
        appBarTheme: const AppBarTheme(
          backgroundColor: pxSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: pxText,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 15, color: pxText),
          bodyMedium: TextStyle(fontSize: 14, color: Color(0xFFD0D1DC)),
          titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF181920),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: pxBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: pxBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: pxAccent),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: pxBorder,
          thickness: 1,
          space: 1,
        ),
        useMaterial3: true,
      );
}
