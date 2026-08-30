import 'package:flutter/material.dart';

class DzColors {
  static const bg = Color(0xFF0A0A0B);
  static const panel = Color(0xFF0A0A0B);
  static const card = Color(0xFF1C1C1E);
  static const card2 = Color(0xFF242428);
  static const line = Color(0x12FFFFFF);
  static const lime = Color(0xFFCDFF3D);
  static const limeDim = Color(0xFFA6D62F);
  static const inkOnLime = Color(0xFF131400);
  static const txt = Color(0xFFFFFFFF);
  static const txt2 = Color(0xFFC7C7CC);
  static const mut = Color(0xFF8E8E93);
  static const mut2 = Color(0xFF636366);
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
