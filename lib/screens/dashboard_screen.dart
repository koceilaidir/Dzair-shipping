import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';

/// Tableau de bord admin — fidèle à la maquette validée.
/// NOTE : données de démonstration en dur pour l'instant ;
/// elles seront branchées sur l'API avec le module Missions.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 1000;
      final main = _MainColumn(wide: wide);
      if (!wide) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [main, const SizedBox(height: 14), const _Rail()],
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: main),
            const SizedBox(width: 14),
            const SizedBox(width: 300, child: _Rail()),
          ],
        ),
      );
    });
  }
}

/* ============================ COLONNE PRINCIPALE ============================ */

class _MainColumn extends StatelessWidget {
  final bool wide;
  const _MainColumn({required this.wide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Salut ${Api.nom ?? ''} 👋',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const Text('Août 2026 · vue d’ensemble',
            style: TextStyle(color: DzColors.mut, fontSize: 12)),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: wide ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: wide ? 1.9 : 1.55,
          children: const [
            _Kpi(label: 'Net agence (mois)', value: '+1 295 500', unit: 'DA',
                color: DzColors.lime, sub: '▲ 12% vs juillet'),
            _Kpi(label: 'DA encaissés', value: '7 340 000', unit: 'DA',
                sub: 'sortis : 6 044 500'),
            _Kpi(label: 'Créances dehors', value: '224 500', unit: 'DA',
                color: DzColors.amber, sub: '3 dépôts · 1 à relancer'),
            _Kpi(label: 'Missions du mois', value: '14 / 20', unit: '',
                sub: '6 créneaux libres'),
          ],
        ),
        const SizedBox(height: 12),
        if (wide)
          const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 13, child: _CardMarchandise()),
            SizedBox(width: 12),
            Expanded(flex: 10, child: _CardBenefice()),
          ])
        else ...[
          const _CardMarchandise(),
          const SizedBox(height: 12),
          const _CardBenefice(),
        ],
        const SizedBox(height: 12),
        const _CardMissions(),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label, value, unit, sub;
  final Color color;
  const _Kpi({required this.label, required this.value, required this.unit,
      required this.sub, this.color = DzColors.txt});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: const TextStyle(color: DzColors.mut, fontSize: 9,
                  fontWeight: FontWeight.w600, letterSpacing: 1.1)),
          const Spacer(),
          FittedBox(
            child: Text('$value ${unit.isNotEmpty ? unit : ''}',
                style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          Text(sub, style: const TextStyle(color: DzColors.mut, fontSize: 10)),
        ]),
      ),
    );
  }
}

/* ---------- Donut marchandise ---------- */

class _CardMarchandise extends StatelessWidget {
  const _CardMarchandise();

  static const cats = [
    ('Électronique', 2964000, Color(0xFF3987E5)),
    ('Montres', 1546000, Color(0xFFD95926)),
    ('Accessoires', 1160000, Color(0xFF199E70)),
    ('Autres', 773000, Color(0xFFC98500)),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Text('Marchandise du mois',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            Spacer(),
            Text('par catégorie', style: TextStyle(color: DzColors.mut, fontSize: 10.5)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(
              width: 120, height: 120,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(size: const Size.square(120), painter: _DonutPainter()),
                const Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('412 kg', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('14 valises', style: TextStyle(color: DzColors.mut, fontSize: 9.5)),
                ]),
              ]),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Wrap(spacing: 16, runSpacing: 9, children: [
                for (final (nom, val, col) in cats)
                  SizedBox(
                    width: 118,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 8, height: 8,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(color: col,
                              borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(nom, style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
                          Text('${_fmt(val)} DA',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final total = _CardMarchandise.cats.fold<num>(0, (s, c) => s + c.$2);
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 17
      ..strokeCap = StrokeCap.butt;
    double start = -math.pi / 2;
    for (final (_, val, col) in _CardMarchandise.cats) {
      final sweep = val / total * 2 * math.pi - .04;
      canvas.drawArc(rect.deflate(9), start, sweep, false, stroke..color = col);
      start += sweep + .04;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/* ---------- Courbe bénéfice ---------- */

class _CardBenefice extends StatelessWidget {
  const _CardBenefice();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Text('Bénéfice cumulé',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            Spacer(),
            Text('août', style: TextStyle(color: DzColors.mut, fontSize: 10.5)),
          ]),
          const SizedBox(height: 8),
          const Text('+1 295 500 DA',
              style: TextStyle(color: DzColors.lime, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SizedBox(height: 84, width: double.infinity,
              child: CustomPaint(painter: _AreaPainter())),
        ]),
      ),
    );
  }
}

class _AreaPainter extends CustomPainter {
  static const pts = [.06, .12, .18, .15, .30, .38, .34, .52, .60, .72, .80, .86];

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFF2C2C31)..strokeWidth = 1;
    for (final f in [.25, .55, .85]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), grid);
    }
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = size.width * i / (pts.length - 1);
      final y = size.height * (1 - pts[i] * .92) - 2;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [DzColors.lime.withValues(alpha: .25), DzColors.lime.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..color = DzColors.lime);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/* ---------- Missions récentes ---------- */

class _CardMissions extends StatelessWidget {
  const _CardMissions();

  static const rows = [
    ('MSN-014', 'Yacine B.', '44,2', '+243 700', DzColors.lime, '✈ En vol', DzColors.lime),
    ('MSN-013', 'Samir K.', '45,8', '+228 400', DzColors.lime, '✓ Clôturée', DzColors.mut),
    ('MSN-012', 'Rédha M.', '42,0', '+176 900', DzColors.lime, '◫ Créance', DzColors.amber),
    ('MSN-011', 'Amine T.', '46,0', '−12 300', DzColors.red, '✕ Invendus', DzColors.red),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Text('Missions récentes',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            Spacer(),
            Text('voir tout →', style: TextStyle(color: DzColors.mut, fontSize: 10.5)),
          ]),
          const SizedBox(height: 6),
          for (final (code, nom, kg, benef, bCol, statut, sCol) in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: DzColors.line))),
              child: Row(children: [
                SizedBox(width: 74,
                    child: Text(code, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                Expanded(child: Text(nom, style: const TextStyle(fontSize: 12.5))),
                SizedBox(width: 52,
                    child: Text('$kg kg',
                        style: const TextStyle(color: DzColors.mut, fontSize: 11.5))),
                SizedBox(width: 76,
                    child: Text(benef, textAlign: TextAlign.right,
                        style: TextStyle(color: bCol, fontSize: 12, fontWeight: FontWeight.w700))),
                const SizedBox(width: 12),
                _Pill(text: statut, color: sCol),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w700)),
    );
  }
}

/* ============================ RAIL DROIT ============================ */

class _Rail extends StatelessWidget {
  const _Rail();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _RailTitle('Vols en cours'),
      const _VolCard(nom: 'AH 4022 · Yacine', route: 'CAN → ALG', progress: .72,
          gauche: 'Décollé 12:10', droite: 'Atterrissage 18:40'),
      const _VolCard(nom: 'MSN-015 · Samir', route: 'préparation', progress: 0,
          gauche: 'Départ 15 août · 09:35', droite: 'valise 38,6 / 46 kg'),
      const SizedBox(height: 14),
      const _RailTitle('Notifications'),
      const _Notif(ic: '◫', color: DzColors.red,
          txt: 'Créance dépôt El Hamiz — 84 500 DA à J+7, relancer.', quand: 'il y a 2 h'),
      const _Notif(ic: '🛂', color: DzColors.amber,
          txt: 'Visa de Samir expire dans 21 jours.', quand: 'ce matin'),
      const _Notif(ic: '⚖', color: DzColors.amber,
          txt: 'MSN-014 à 91 % du plafond légal.', quand: 'hier'),
      const _Notif(ic: '✓', color: DzColors.lime,
          txt: 'Paiement reçu : 200 000 DA (MSN-013).', quand: 'hier'),
      const SizedBox(height: 14),
      const _RailTitle('Agenda'),
      const _Agenda(j: '15', s: 'VEN', t: 'Départ Samir — AH 4020',
          d: 'douane à préparer : 78 400 DA'),
      const _Agenda(j: '16', s: 'SAM', t: 'Retour Yacine + taxi dépôts',
          d: 'règlement de mission à faire'),
      const _Agenda(j: '19', s: 'MAR', t: 'Départ Amine — Istanbul',
          d: '2ᵉ mission du mois (2/2)'),
      const _Agenda(j: '30', s: 'MER', t: 'Autorisation Rédha expire',
          d: 'renouvellement 5 000 DA'),
    ]);
  }
}

class _RailTitle extends StatelessWidget {
  final String t;
  const _RailTitle(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

class _VolCard extends StatelessWidget {
  final String nom, route, gauche, droite;
  final double progress;
  const _VolCard({required this.nom, required this.route, required this.progress,
      required this.gauche, required this.droite});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(nom, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(route, style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
          ]),
          const SizedBox(height: 7),
          SizedBox(
            height: 24,
            child: LayoutBuilder(builder: (context, c) {
              const lineY = 12.0; // centre vertical de la piste
              const planeSize = 18.0;
              return Stack(children: [
                Positioned(top: lineY - 1, left: 0, right: 0,
                    child: CustomPaint(size: Size(c.maxWidth, 2), painter: _DashPainter())),
                Positioned(top: lineY - 1, left: 0,
                    child: Container(width: c.maxWidth * progress, height: 2, color: DzColors.lime)),
                Positioned(
                  left: (c.maxWidth * progress - planeSize / 2)
                      .clamp(0, c.maxWidth - planeSize),
                  top: lineY - planeSize / 2, // l'avion est centré SUR la ligne
                  child: Transform.rotate(
                    angle: math.pi / 2,
                    child: Icon(Icons.flight, size: planeSize,
                        color: progress > 0 ? DzColors.lime : DzColors.mut),
                  ),
                ),
              ]);
            }),
          ),
          const SizedBox(height: 3),
          Row(children: [
            Text(gauche, style: const TextStyle(color: DzColors.mut, fontSize: 9.5)),
            const Spacer(),
            Text(droite,
                style: const TextStyle(color: DzColors.lime, fontSize: 9.5,
                    fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF3A3A41)..strokeWidth = 2;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 1), Offset(math.min(x + 5, size.width), 1), p);
      x += 10;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Notif extends StatelessWidget {
  final String ic, txt, quand;
  final Color color;
  const _Notif({required this.ic, required this.color, required this.txt, required this.quand});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 27, height: 27, alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(8)),
          child: Text(ic, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(txt, style: const TextStyle(fontSize: 11.5, height: 1.35)),
            Text(quand, style: const TextStyle(color: DzColors.mut, fontSize: 9.5)),
          ]),
        ),
      ]),
    );
  }
}

class _Agenda extends StatelessWidget {
  final String j, s, t, d;
  const _Agenda({required this.j, required this.s, required this.t, required this.d});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        Container(
          width: 36,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: DzColors.card2,
              border: Border.all(color: DzColors.line),
              borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Text(s, style: const TextStyle(color: DzColors.mut, fontSize: 7.5,
                fontWeight: FontWeight.w600)),
            Text(j, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            Text(d, style: const TextStyle(color: DzColors.mut, fontSize: 10)),
          ]),
        ),
      ]),
    );
  }
}

String _fmt(num n) => n.toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
