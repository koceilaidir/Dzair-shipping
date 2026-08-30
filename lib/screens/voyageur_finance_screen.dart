import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/charts.dart';

class VoyageurFinanceScreen extends StatefulWidget {
  const VoyageurFinanceScreen({super.key});

  @override
  State<VoyageurFinanceScreen> createState() => _VoyageurFinanceScreenState();
}

class _VoyageurFinanceScreenState extends State<VoyageurFinanceScreen> {
  Map? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/rapports/ma-finance') as Map;
      if (mounted) setState(() => _d = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.round().toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  String _dateFr(dynamic d) {
    final s = '$d';
    return s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}' : '—';
  }

  static const _moisCourt = ['', 'janv', 'févr', 'mars', 'avril', 'mai', 'juin',
    'juil', 'août', 'sept', 'oct', 'nov', 'déc'];

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)));
    }
    if (_d == null) {
      return const Center(child: CircularProgressIndicator(color: DzColors.lime));
    }
    final v = _d!['voyageur'] as Map;
    final sym = v['devise_compte'] == 'EUR' ? '€' : '\$';
    return RefreshIndicator(
      color: DzColors.lime,
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 1000;
        final gauche = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (v['dette_active'] == true) _carteDette(v),
          _carteBEA(v, sym),
        ]);
        final droite = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _carteGainsMissions(),
          _carteSejour(),
          _carteGainsMois(),
        ]);
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          children: [
            const Text('Ma finance',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            const Text('Ton argent, tes gains, ta dette — rien d’autre que le tien.',
                style: TextStyle(color: DzColors.mut, fontSize: 12.5)),
            const SizedBox(height: 16),
            _kpis(v, sym, wide),
            const SizedBox(height: 16),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: gauche),
                const SizedBox(width: 16),
                Expanded(child: droite),
              ])
            else ...[gauche, droite],
          ],
        );
      }),
    );
  }

  Widget _kpis(Map v, String sym, bool wide) {
    final detteReste =
        (_n(v['dette_montant']) - _n(v['dette_rembourse'])).clamp(0.0, double.infinity);
    final cards = [
      _kpi('Mon compte BEA', '${_f(_n(v['solde_devises']))} $sym',
          sub: 'solde restant sur la carte'),
      _kpi('L’agence me doit',
          _n(_d!['agence_me_doit']) > 0 ? '${_f(_n(_d!['agence_me_doit']))} DA' : 'Rien ✓',
          color: _n(_d!['agence_me_doit']) > 0 ? DzColors.amber : DzColors.lime,
          sub: 'commissions + primes à recevoir'),
      _kpi('Mes gains', '${_f(_n(_d!['gains_total']))} DA',
          color: DzColors.lime, sub: 'commissions + primes (total)'),
      _kpi('Ma dette',
          v['dette_active'] == true ? '${_f(detteReste)} DA' : 'Aucune ✓',
          color: v['dette_active'] == true && detteReste > 0 ? DzColors.txt : DzColors.lime,
          sub: v['dette_active'] == true
              ? 'reste sur ${_f(_n(v['dette_montant']))} DA'
              : 'pas de dépôt avancé'),
    ];
    if (wide) {
      return Row(children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: cards[i]),
        ],
      ]);
    }
    return Column(children: [
      Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
    ]);
  }

  Widget _kpi(String label, String val, {Color color = DzColors.txt, String? sub}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
            color: DzColors.card, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: const TextStyle(color: DzColors.mut, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: .8)),
          const SizedBox(height: 7),
          FittedBox(child: Text(val,
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800))),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
            ),
        ]),
      );

  Widget _carte(String titre, Widget enfant) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
            child: Text(titre.toUpperCase(),
                style: const TextStyle(color: DzColors.mut, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: .8)),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: DzColors.card, borderRadius: BorderRadius.circular(16)),
            child: enfant,
          ),
        ]),
      );

  Widget _ligne(String l, String v, {bool gras = false, Color? c}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(children: [
          Expanded(child: Text(l,
              style: const TextStyle(color: DzColors.mut, fontSize: 12))),
          Text(v, style: TextStyle(
              fontSize: gras ? 13 : 12,
              fontWeight: gras ? FontWeight.w800 : FontWeight.w600,
              color: c ?? DzColors.txt)),
        ]),
      );

  Widget _carteDette(Map v) {
    final total = _n(v['dette_montant']);
    final fait = _n(v['dette_rembourse']).clamp(0.0, total);
    final reste = (total - fait).clamp(0.0, double.infinity);
    final pct = total > 0 ? (fait / total * 100).round() : 0;
    final remb = ((_d!['remboursements'] as List?) ?? []).cast<Map>();
    return _carte('Ma dette envers l’agence', Column(children: [
      Row(children: [
        DzDonut(
          taille: 116, epaisseur: 13,
          segments: [
            DzSegment(fait, DzColors.lime),
            DzSegment(reste, DzColors.card2),
          ],
          centre: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$pct %', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Text('remboursé', style: TextStyle(color: DzColors.mut, fontSize: 8.5)),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(children: [
            DzLegende(couleur: DzColors.lime, libelle: 'Remboursé', valeur: '${_f(fait)} DA'),
            DzLegende(couleur: DzColors.card2, libelle: 'Reste', valeur: '${_f(reste)} DA'),
            const SizedBox(height: 4),
            Text('dépôt avancé par l’agence : ${_f(total)} DA',
                style: const TextStyle(color: DzColors.mut2, fontSize: 10)),
          ]),
        ),
      ]),
      if (remb.isNotEmpty) ...[
        const Divider(color: DzColors.line, height: 18),
        for (final r in remb.take(5))
          _ligne('${_dateFr(r['date'])} · remboursement',
              '− ${_f(_n(r['montant']))} ${r['devise'] ?? 'DA'}'),
      ],
    ]));
  }

  Widget _carteBEA(Map v, String sym) {
    final tranches = ((_d!['tranches_encours'] as List?) ?? []).cast<Map>();
    final depots = tranches.where((t) => '${t['motif']}' == 'voyage').toList();
    return _carte('Mon compte BEA (devises)', Column(children: [
      if (depots.isEmpty)
        const Text('Aucun mouvement sur le séjour en cours.',
            style: TextStyle(color: DzColors.mut, fontSize: 12))
      else
        for (final t in depots)
          _ligne('${_dateFr(t['created_at'])} · ${'${t['source'] ?? ''}'.isEmpty ? 'dépôt carte' : t['source']}',
              '+ ${_f(_n(t['usd']))} ${t['devise'] ?? sym}'),
      const Divider(color: DzColors.line, height: 16),
      _ligne('Solde', '${_f(_n(v['solde_devises']))} $sym',
          gras: true, c: DzColors.lime),
    ]));
  }

  Widget _carteGainsMissions() {
    final missions = ((_d!['missions'] as List?) ?? []).cast<Map>();
    if (missions.isEmpty) {
      return _carte('Mes gains — mission par mission',
          const Text('Pas encore de mission.',
              style: TextStyle(color: DzColors.mut, fontSize: 12)));
    }
    return _carte('Mes gains — mission par mission', Column(children: [
      for (var i = 0; i < missions.length && i < 8; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: i == 0 ? null : const BoxDecoration(
              border: Border(top: BorderSide(color: DzColors.line))),
          child: Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${missions[i]['code']}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                TextSpan(
                    text: missions[i]['statut'] == 'cloturee'
                        ? '  · clôturée ${_dateFr(missions[i]['cloture_date'])}'
                        : '  · en cours',
                    style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
              ])),
            ),
            _chipGain(missions[i]),
            const SizedBox(width: 8),
            SizedBox(
              width: 86,
              child: Text(
                  missions[i]['statut'] == 'cloturee'
                      ? '${_f(_n(missions[i]['gain']))} DA' : 'à la clôture',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: missions[i]['statut'] == 'cloturee' ? 12.5 : 11,
                      fontWeight: FontWeight.w700,
                      color: missions[i]['statut'] == 'cloturee'
                          ? DzColors.txt : DzColors.mut)),
            ),
          ]),
        ),
    ]));
  }

  Widget _chipGain(Map m) {
    final (lab, c) = m['statut'] != 'cloturee'
        ? ('en mission', DzColors.mut)
        : m['versee'] == true
            ? ('✓ reçue', DzColors.limeDim)
            : ('à recevoir', DzColors.amber);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
          color: DzColors.card2, borderRadius: BorderRadius.circular(99)),
      child: Text(lab,
          style: TextStyle(color: c, fontSize: 9.5, fontWeight: FontWeight.w700)),
    );
  }

  Widget _carteSejour() {
    final missions = ((_d!['missions'] as List?) ?? []).cast<Map>();
    final enc = missions.where((m) => '${m['statut']}' != 'cloturee').toList();
    if (enc.isEmpty) return const SizedBox.shrink();
    final poche = _n(enc.first['poche_da']);
    final reste = _n(enc.first['reste_da']);
    if (poche <= 0) return const SizedBox.shrink();
    return _carte('Mes dépenses du séjour en cours', Column(children: [
      _ligne('Argent de poche remis au départ', '${_f(poche)} DA'),
      if (reste > 0) ...[
        _ligne('Restant déclaré à l’arrivée', '− ${_f(reste)} DA'),
        const Divider(color: DzColors.line, height: 14),
        _ligne('Dépensé sur place', '${_f((poche - reste).clamp(0, double.infinity))} DA',
            gras: true),
      ] else
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Déclare ton argent restant à l’arrivée pour voir le détail.',
              style: TextStyle(color: DzColors.mut2, fontSize: 10.5)),
        ),
    ]));
  }

  Widget _carteGainsMois() {
    final pm = ((_d!['gains_par_mois'] as List?) ?? []).cast<Map>();
    final six = pm.length > 6 ? pm.sublist(pm.length - 6) : pm;
    if (six.isEmpty) return const SizedBox.shrink();
    final moisNow =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    return _carte('Mes gains par mois', Column(children: [
      DzBarres(hauteur: 96, barres: [
        for (final e in six)
          DzBarreMois(
              '${e['mois']}'.length >= 7
                  ? _moisCourt[int.tryParse('${e['mois']}'.substring(5, 7)) ?? 0]
                  : '${e['mois']}',
              _n(e['gain']),
              actif: '${e['mois']}' == moisNow),
      ]),
    ]));
  }
}
