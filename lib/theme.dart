import 'package:flutter/material.dart';

/// Charte v3 « iOS sombre » — direction A validée sur maquettes (29/08/2026).
/// Anatomie iOS : groupes #1C1C1E SANS bordures sur fond quasi noir,
/// séparateurs fins, boutons en pilules, Plus Jakarta Sans (embarquée,
/// China-proof). Le lime reste l'unique accent : actions + chiffres clés.
class DzColors {
  static const bg = Color(0xFF0A0A0B);        // fond — quasi noir (sidebar comprise)
  static const panel = Color(0xFF0A0A0B);     // = bg (l'app est d'un seul tenant)
  static const card = Color(0xFF1C1C1E);      // groupe iOS — jamais de bordure
  static const card2 = Color(0xFF242428);     // champs, jauges, pastilles
  static const line = Color(0x12FFFFFF);      // hairline (séparateurs ~7 % blanc)
  static const lime = Color(0xFFC9F231);      // accent — actions + chiffres clés
  static const limeDim = Color(0xFF9DC026);
  static const inkOnLime = Color(0xFF131400);
  static const txt = Color(0xFFFFFFFF);       // titres, valeurs
  static const txt2 = Color(0xFFC7C7CC);      // texte secondaire
  static const mut = Color(0xFF8E8E93);       // libellés, méta (gris iOS)
  static const mut2 = Color(0xFF636366);      // légendes discrètes
  static const red = Color(0xFFFF6B5E);
  static const amber = Color(0xFFF2C74B);
}

ThemeData dzairTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: DzColors.bg,
    textTheme: base.textTheme.apply(
      fontFamily: 'PlusJakartaSans',
      bodyColor: DzColors.txt,
      displayColor: DzColors.txt,
    ),
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: DzColors.lime,
      onPrimary: DzColors.inkOnLime,
      secondary: DzColors.limeDim,
      surface: DzColors.card,
      onSurface: DzColors.txt,
      error: DzColors.red,
    ),
    // Groupe iOS : aucune bordure — la surface se détache du fond par son ton.
    cardTheme: base.cardTheme.copyWith(
      color: DzColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(color: DzColors.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DzColors.card2,
      labelStyle: const TextStyle(color: DzColors.mut),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DzColors.lime, width: 1.4),
      ),
    ),
    // Pilules : tout bouton plein est une pilule lime.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DzColors.lime,
        foregroundColor: DzColors.inkOnLime,
        textStyle: const TextStyle(
            fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w700, fontSize: 14),
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DzColors.txt2,
        backgroundColor: DzColors.card2,
        side: BorderSide.none,
        textStyle: const TextStyle(
            fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w600, fontSize: 13),
        shape: const StadiumBorder(),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: DzColors.bg,
      indicatorColor: DzColors.card,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? DzColors.lime : DzColors.mut,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: states.contains(WidgetState.selected) ? DzColors.txt : DzColors.mut,
        ),
      ),
    ),
  );
}
