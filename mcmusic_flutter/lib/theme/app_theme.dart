import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Electric Azure Spotify Palette
  static const Color primaryAzure = Color(0xFF00A3FF);
  static const Color primaryAzureHover = Color(0xFF2EB4FF);
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkCard = Color(0xFF181818);
  static const Color darkSurface = Color(0xFF242424);
  static const Color darkSurfaceHover = Color(0xFF2E2E2E);
  static const Color textMuted = Color(0xFFB3B3B3);
  static const Color textLight = Color(0xFFFFFFFF);

  static ThemeData get darkTheme {
    final baseTextTheme = ThemeData.dark().textTheme;
    // Spotify Circular equivalent: Figtree (Geometric, Rounded, Modern Grotesque)
    final spotifyTextTheme = GoogleFonts.figtreeTextTheme(baseTextTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      primaryColor: primaryAzure,
      canvasColor: darkBackground,
      cardColor: darkCard,
      fontFamily: GoogleFonts.figtree().fontFamily,
      textTheme: spotifyTextTheme,
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
