import 'package:flutter/material.dart';

/// Palette officielle Dzair Shipping — v2 (alignée sur la référence design) :
/// fonds neutres gris-noirs, accent vert lime vif. Le logo suit `lime`.
class DzColors {
  static const bg = Color(0xFF131316); // fond de page
  static const panel = Color(0xFF19191C); // sidebar / rails
  static const card = Color(0xFF1E1E22); // cartes
  static const card2 = Color(0xFF26262A); // champs, surfaces internes
  static const line = Color(0xFF2C2C31); // bordures fines
  static const lime = Color(0xFFB7F23B); // accent : action + argent qui rentre
  static const limeDim = Color(0xFF8FC92B);
  static const inkOnLime = Color(0xFF151A06);
  static const txt = Color(0xFFF4F4F5);
  static const mut = Color(0xFF9A9AA3);
  static const red = Color(0xFFFF6B5E);
  static const amber = Color(0xFFF2C74B);
}

ThemeData dzairTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  // Une seule famille dans toute l'app : Poppins, EMBARQUÉE en assets
  // (aucun téléchargement Google — fonctionne hors ligne et en Chine).
  final textTheme = base.textTheme
      .apply(fontFamily: 'Poppins', bodyColor: DzColors.txt, displayColor: DzColors.txt);
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
      // Espace intérieur généreux : le label flottant ne colle plus le champ du dessus.
      contentPadding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      labelStyle: const TextStyle(
          fontFamily: 'Poppins', color: DzColors.mut, fontWeight: FontWeight.w500),
      floatingLabelStyle: const TextStyle(
          fontFamily: 'Poppins', color: DzColors.lime, fontWeight: FontWeight.w600),
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
        textStyle: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15),
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
        (states) => TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? DzColors.lime : DzColors.mut,
        ),
      ),
    ),
  );
}
