import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

/// Le mark officiel : D arrondi avec l'avion en espace négatif.
/// Reproduction exacte du SVG maître (viewBox 200×200).
class DzairLogo extends StatelessWidget {
  final double size;
  final Color color;
  const DzairLogo({super.key, this.size = 96, this.color = DzColors.lime});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DzairLogoPainter(color),
    );
  }
}

class _DzairLogoPainter extends CustomPainter {
  final Color color;
  _DzairLogoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.scale(s);

    // Le D : coins extérieurs gauches arrondis, demi-cercle à droite.
    final d = Path()
      ..moveTo(56, 26)
      ..lineTo(92, 26)
      ..arcToPoint(const Offset(92, 174), radius: const Radius.circular(74))
      ..lineTo(56, 174)
      ..quadraticBezierTo(30, 174, 30, 148)
      ..lineTo(30, 52)
      ..quadraticBezierTo(30, 26, 56, 26)
      ..close();
    canvas.drawPath(d, Paint()..color = color);

    // L'avion, découpé en négatif (BlendMode.clear).
    final clearStroke = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final clearFill = Paint()..blendMode = BlendMode.clear;

    // Fuselage (la queue perce le bord gauche du D).
    canvas.drawLine(
      const Offset(18, 100), const Offset(128, 100), clearStroke..strokeWidth = 20);

    // Ailes effilées : larges près du corps.
    final wingTop = Path()
      ..moveTo(103, 100)..lineTo(76, 100)..lineTo(51, 61)..lineTo(65, 56)..close();
    final wingBottom = Path()
      ..moveTo(103, 100)..lineTo(76, 100)..lineTo(51, 139)..lineTo(65, 144)..close();
    for (final w in [wingTop, wingBottom]) {
      canvas.drawPath(w, clearFill);
      canvas.drawPath(w, clearStroke..strokeWidth = 9);
    }

    // Empennage large, arrondi visible à l'arrière.
    final tailTop = Path()
      ..moveTo(44, 100)..lineTo(26, 100)..lineTo(13, 79)..lineTo(28, 76)..close();
    final tailBottom = Path()
      ..moveTo(44, 100)..lineTo(26, 100)..lineTo(13, 121)..lineTo(28, 124)..close();
    for (final t in [tailTop, tailBottom]) {
      canvas.drawPath(t, clearFill);
      canvas.drawPath(t, clearStroke..strokeWidth = 8);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DzairLogoPainter old) => old.color != color;
}

/// Wordmark "Dzair Shipping" à côté du logo.
class DzairWordmark extends StatelessWidget {
  final double fontSize;
  const DzairWordmark({super.key, this.fontSize = 26});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: DzColors.txt,
        ),
        children: const [
          TextSpan(text: 'Dzair '),
          TextSpan(text: 'Shipping', style: TextStyle(color: DzColors.lime)),
        ],
      ),
    );
  }
}
