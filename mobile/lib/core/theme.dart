import 'package:flutter/material.dart';

/// Catppuccin Mocha color palette
///
/// Phase 04: Mobile App
/// https://catppuccin.com/
class CatppuccinMocha {
  // Base colors
  static const base = Color(0xFF1E1E2E);      // Dark background
  static const mantle = Color(0xFF181825);    // Darker background
  static const crust = Color(0xFF11111B);     // Darkest background

  // Surface colors
  static const surface = Color(0xFF313244);   // Card/surface background
  static const surface0 = Color(0xFF45475A);  // Surface 0
  static const surface1 = Color(0xFF585B70);  // Surface 1

  // Text colors
  static const text = Color(0xFFCDD6F4);      // Primary text
  static const subtext1 = Color(0xFFBAC2DE);  // Secondary text
  static const subtext0 = Color(0xFFA6ADC8);  // Tertiary text
  static const overlay2 = Color(0xFF9399B2);  // Overlay 2
  static const overlay1 = Color(0xFF7F849C);  // Overlay 1
  static const overlay0 = Color(0xFF6C7086);  // Overlay 0

  // Accent colors
  static const primary = Color(0xFFCBA6F7);   // Mauve (primary)
  static const secondary = Color(0xFF89B4FA); // Blue
  static const tertiary = Color(0xFFF5C2E7);  // Pink

  // Functional colors
  static const blue = Color(0xFF89B4FA);      // Info
  static const lavender = Color(0xFFB4BEFE);  // Accent
  static const sapphire = Color(0xFF74C7EC);  // Accent 2
  static const sky = Color(0xFF89Dceb);       // Accent 3
  static const teal = Color(0xFF94E2D5);      // Accent 4
  static const green = Color(0xFFA6E3A1);     // Success
  static const yellow = Color(0xFFF9E2AF);    // Warning
  static const peach = Color(0xFFfab387);     // Warning 2
  static const maroon = Color(0xFFEBA0AC);    // Error 2
  static const red = Color(0xFFF38BA8);       // Error
  static const mauve = Color(0xFFCBA6F7);     // Purple
  static const flamingo = Color(0xFFF2CDCD);  // Pink 2
  static const rosewater = Color(0xFFF5E0DC); // Pink 3

  // Transparent overlay
  static const overlay1Opacity = 0.16;

  /// Light theme (not used for MVP, but defined for completeness)
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: lavender,
        secondary: blue,
        surface: surface,
        error: red,
        onPrimary: base,
        onSecondary: base,
        onSurface: text,
        onError: base,
      ),
      scaffoldBackgroundColor: base,
      appBarTheme: const AppBarTheme(
        backgroundColor: base,
        foregroundColor: text,
        elevation: 0,
      ),
    );
  }

  /// Dark theme (primary for Comacode)
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: mauve,
        secondary: blue,
        surface: surface,
        error: red,
        onPrimary: base,
        onSecondary: base,
        onSurface: text,
        onError: base,
      ),
      scaffoldBackgroundColor: base,
      appBarTheme: const AppBarTheme(
        backgroundColor: mantle,
        foregroundColor: text,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: mauve,
          foregroundColor: base,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: mauve,
          side: const BorderSide(color: mauve, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: mauve,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: mauve, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: red, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: mauve,
        foregroundColor: base,
        elevation: 0,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: mantle,
        selectedItemColor: mauve,
        unselectedItemColor: overlay1,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: surface0,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(
        color: text,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: const TextStyle(color: text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Terminal-specific colors
  static const terminalBackground = Color(0xFF1E1E2E);
  static const terminalForeground = Color(0xFFCDD6F4);
  static const terminalCursor = Color(0xFFCBA6F7);

  /// ANSI color palette for terminal
  static const ansiBlack = Color(0xFF45475A);
  static const ansiRed = Color(0xFFF38BA8);
  static const ansiGreen = Color(0xFFA6E3A1);
  static const ansiYellow = Color(0xFFF9E2AF);
  static const ansiBlue = Color(0xFF89B4FA);
  static const ansiMagenta = Color(0xFFCBA6F7);
  static const ansiCyan = Color(0xFF94E2D5);
  static const ansiWhite = Color(0xFFBAC2DE);

  static const ansiBrightBlack = Color(0xFF585B70);
  static const ansiBrightRed = Color(0xFFEBA0AC);
  static const ansiBrightGreen = Color(0xFF94E2D5);
  static const ansiBrightYellow = Color(0xFFFAB387);
  static const ansiBrightBlue = Color(0xFF89DCEB);
  static const ansiBrightMagenta = Color(0xFFF5C2E7);
  static const ansiBrightCyan = Color(0xFF89Dceb);
  static const ansiBrightWhite = Color(0xFFA6ADC8);
}
