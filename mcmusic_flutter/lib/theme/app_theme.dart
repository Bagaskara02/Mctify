// ignore: unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTheme {
  // Spotify Authentic Tokens & Electric Azure Palette
  static const Color spotifyGreen = Color(0xFF3B82F6);
  static const Color spotifyGreenHover = Color(0xFF2563EB);
  static const Color primaryAzure = Color(0xFF3B82F6);
  static const Color primaryAzureHover = Color(0xFF2563EB);
  static const Color mctifyBlue = Color(0xFF3B82F6);
  static const Color mctifyBlueHover = Color(0xFF2563EB);
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkCard = Color(0xFF181818);
  static const Color darkSurface = Color(0xFF242424);
  static const Color darkSurfaceHover = Color(0xFF2E2E2E);
  static const Color textMuted = Color(0xFFB3B3B3);
  static const Color textLight = Color(0xFFFFFFFF);

  static ThemeData get darkTheme {
    final baseTextTheme = ThemeData.dark().textTheme;
    // Spotify Authentic Circular Std Typography (Book, Medium, Bold, Black)
    final spotifyTextTheme = baseTextTheme.apply(
      fontFamily: 'CircularStd',
      fontFamilyFallback: ['Figtree', 'sans-serif'],
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      primaryColor: primaryAzure,
      canvasColor: darkBackground,
      cardColor: darkCard,
      fontFamily: 'CircularStd',
      fontFamilyFallback: const ['Figtree', 'sans-serif'],
      textTheme: spotifyTextTheme,
      primaryTextTheme: spotifyTextTheme,
      colorScheme: const ColorScheme.dark(
        primary: primaryAzure,
        secondary: primaryAzureHover,
        surface: darkBackground,
        surfaceContainerHighest: darkSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.black,
        selectedItemColor: primaryAzure,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 10,
      ),
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryAzure,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayColor: primaryAzure.withAlpha(40),
        trackHeight: 3.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
    );
  }
}
