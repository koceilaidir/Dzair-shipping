import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class DzChartColors {
  static const bleu = Color(0xFF7DD3FC);
  static const violet = Color(0xFFC4B5FD);
  static const jaune = Color(0xFFF2C74B);
  static const rose = Color(0xFFFDA4AF);
  static const menthe = Color(0xFF5EEAD4);
}

class DzSegment {
  final double valeur;
  final Color couleur;
  const DzSegment(this.valeur, this.couleur);
}

class DzDonut extends StatelessWidget {
  final List<DzSegment> segments;
  final double taille;
  final double epaisseur;
  final Widget? centre;
  const DzDonut({super.key, required this.segments, this.taille = 140,
      this.epaisseur = 15, this.centre});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: taille, height: taille,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size.square(taille),
            painter: _DonutPainter(segments, epaisseur)),
        if (centre != null) centre!,
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DzSegment> segs;
  final double ep;
  _DonutPainter(this.segs, this.ep);

  @override
  void paint(Canvas canvas, Size size) {
    final total = segs.fold<double>(0, (s, x) => s + x.valeur);
    final rect = Rect.fromLTWH(ep / 2, ep / 2, size.width - ep, size.height - ep);
    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, Paint()
        ..style = PaintingStyle.stroke..strokeWidth = ep..color = DzColors.card2);
      return;
    }

    final visibles = segs.where((s) => s.valeur > 0).length;
    final gap = visibles > 1 ? 0.06 : 0.0;
    var angle = -math.pi / 2;
    for (final s in segs) {
      if (s.valeur <= 0) continue;
      final balaye = s.valeur / total * math.pi * 2;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ep
        ..strokeCap = StrokeCap.round
        ..color = s.couleur;
      canvas.drawArc(rect, angle + gap / 2, math.max(0.02, balaye - gap), false, p);
      angle += balaye;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.segs != segs || old.ep != ep;
}

class DzLegende extends StatelessWidget {
  final Color couleur;
  final String libelle;
  final String valeur;
  final String part;
  const DzLegende({super.key, required this.couleur, required this.libelle,
      required this.valeur, this.part = ''});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(libelle,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: DzColors.txt2, fontSize: 12))),
        Text(valeur, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        if (part.isNotEmpty)
          SizedBox(width: 40, child: Text(part, textAlign: TextAlign.right,
              style: const TextStyle(color: DzColors.mut, fontSize: 10.5))),
      ]),
    );
  }
}

class DzBarreMois {
  final String mois;
  final double valeur;
  final bool actif;
  const DzBarreMois(this.mois, this.valeur, {this.actif = false});
}

class DzBarres extends StatelessWidget {
  final List<DzBarreMois> barres;
  final double hauteur;
  final bool valeursEnMilliers;
  const DzBarres({super.key, required this.barres, this.hauteur = 120,
      this.valeursEnMilliers = true});

  @override
  Widget build(BuildContext context) {
    final maxV = barres.fold<double>(0, (m, b) => math.max(m, b.valeur));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final b in barres)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (valeursEnMilliers)
                  Text(b.valeur > 0 ? '${(b.valeur / 1000).round()} k' : '',
                      style: TextStyle(
                          color: b.actif ? DzColors.lime : DzColors.mut2,
                          fontSize: 9.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Container(
                  height: maxV <= 0 ? 2 : math.max(2, b.valeur / maxV * hauteur),
                  constraints: const BoxConstraints(maxWidth: 34),
                  decoration: BoxDecoration(
                    color: b.actif ? DzColors.lime : DzColors.card2,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(7), bottom: Radius.circular(3)),
                  ),
                ),
                const SizedBox(height: 5),
                Text(b.mois, style: const TextStyle(color: DzColors.mut, fontSize: 10)),
              ]),
            ),
          ),
      ],
    );
  }
}

class DzStack extends StatelessWidget {
  final List<DzSegment> segments;
  final double hauteur;
  const DzStack({super.key, required this.segments, this.hauteur = 14});

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (s, x) => s + x.valeur);
    if (total <= 0) {
      return Container(height: hauteur,
          decoration: BoxDecoration(color: DzColors.card2,
              borderRadius: BorderRadius.circular(99)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: hauteur,
        child: Row(children: [
          for (final s in segments)
            if (s.valeur > 0)
              Expanded(
                flex: math.max(1, (s.valeur / total * 1000).round()),
                child: Container(
                    color: s.couleur,
                    margin: const EdgeInsets.only(right: 2)),
              ),
        ]),
      ),
    );
  }
}

class DzVolProgress extends StatelessWidget {
  final double progression;
  const DzVolProgress({super.key, required this.progression});

  @override
  Widget build(BuildContext context) {
    final p = progression.clamp(0.0, 1.0);
    return SizedBox(
      height: 36,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final x = (w - 26) * p;
        return Stack(clipBehavior: Clip.none, children: [

          Positioned(left: 0, right: 0, top: 17,
              child: Container(height: 2,
                  decoration: BoxDecoration(color: DzColors.line,
                      borderRadius: BorderRadius.circular(99)))),
          Positioned(left: 0, top: 17,
              child: Container(height: 2, width: w * p,
                  decoration: BoxDecoration(color: DzColors.lime,
                      borderRadius: BorderRadius.circular(99)))),

          Positioned(left: 0, top: 13,
              child: Container(width: 10, height: 10,
                  decoration: const BoxDecoration(
                      color: DzColors.lime, shape: BoxShape.circle))),
          Positioned(right: 0, top: 13,
              child: Container(width: 10, height: 10,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: DzColors.card2,
                      border: Border.all(color: DzColors.line, width: 2)))),

          Positioned(left: x, top: 2,
              child: Transform.rotate(angle: math.pi / 4,
                  child: const Icon(Icons.flight, color: DzColors.lime, size: 26))),
        ]);
      }),
    );
  }
}
