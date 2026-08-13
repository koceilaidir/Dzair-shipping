import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette officielle Dzair Shipping (identité verrouillée août 2026).
class DzColors {
  static const bg = Color(0xFF0B0D09);
  static const card = Color(0xFF15180F);
  static const card2 = Color(0xFF1C2013);
  static const line = Color(0xFF262B1C);
  static const lime = Color(0xFFC9F231);
  static const limeDim = Color(0xFF9DC026);
  static const inkOnLime = Color(0xFF131606);
  static const txt = Color(0xFFF2F4EC);
  static const mut = Color(0xFF8F957F);
  static const red = Color(0xFFFF6B5E);
  static const amber = Color(0xFFF2C74B);
}

ThemeData dzairTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  // Une seule famille dans toute l'app : Poppins.
  // La hiérarchie se fait par la graisse (400/500 texte, 600 labels, 700/800 titres et chiffres).
  final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme)
      .apply(bodyColor: DzColors.txt, displayColor: DzColors.txt);
  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: DzColors.bg,
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: DzColors.lime,
      onPrimary: DzColors.inkOnLime,
      secondary: DzColors.limeDim,
      surface: DzColors.card,
      onSurface: DzColors.txt,
      error: DzColors.red,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: DzColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: DzColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DzColors.card2,
      labelStyle: GoogleFonts.poppins(color: DzColors.mut, fontWeight: FontWeight.w500),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DzColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DzColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DzColors.lime, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DzColors.lime,
        foregroundColor: DzColors.inkOnLime,
        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: DzColors.bg,
      indicatorColor: DzColors.lime.withValues(alpha: .16),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? DzColors.lime : DzColors.mut,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? DzColors.lime : DzColors.mut,
        ),
      ),
    ),
  );
}
