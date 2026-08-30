import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/charts.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  Map? _data;
  String? _error;
  String _annee = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('/rapports/finance');
      if (mounted) setState(() => _data = d as Map);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.round().toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  static const _moisCourt = ['', 'janv', 'févr', 'mars', 'avril', 'mai', 'juin',
    'juil', 'août', 'sept', 'oct', 'nov', 'déc'];
  static const _postes = [
    ('billets', 'Billets d’avion', DzColors.lime),
    ('poche', 'Poche voyageurs (net des restes)', DzChartColors.bleu),
    ('douane', 'Douane 5 % + IFU 0,5 %', DzChartColors.violet),
    ('carte', 'Taxes de carte', DzChartColors.jaune),
    ('demarches', 'Démarches & visas', DzChartColors.rose),
    ('autres', 'Manques, saisies & autres', DzChartColors.menthe),
  ];

  String _anneeDe(Map m) {
    final s = '${m['depart'] ?? m['cloture_date'] ?? ''}';
    return s.length >= 4 ? s.substring(0, 4) : '';
  }

  List<Map> get _missionsFiltrees {
    final all = ((_data?['missions'] as List?) ?? []).cast<Map>();
    if (_annee.isEmpty) return all;
    return all.where((m) => _anneeDe(m) == _annee).toList();
  }

  _Totaux get _totaux {
    double sortis = 0, revenus = 0, part = 0, creances = 0;
    final detail = {for (final (k, _, _) in _postes) k: 0.0};
    final parMois = <String, double>{};
    for (final m in _missionsFiltrees) {
      final frais = _n(m['frais']);
      final p = _n(m['commission']) + _n(m['primes']);
      final net = _n(m['attendu']) - frais - p;
      sortis += frais;
      revenus += _n(m['attendu']);
      part += p;
      if (_n(m['solde']) > 0) creances += _n(m['solde']);
      final fd = (m['frais_detail'] as Map?) ?? {};
      for (final k in detail.keys) detail[k] = detail[k]! + _n(fd[k]);
      final mois = '${m['depart'] ?? m['cloture_date'] ?? ''}';
      final k = mois.length >= 7 ? mois.substring(0, 7) : 'inconnu';
      parMois[k] = (parMois[k] ?? 0) + net;
    }
    return (sortis: sortis, revenus: revenus, part: part,
        net: revenus - sortis - part, creances: creances,
        detail: detail, parMois: parMois);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)));
    if (_data == null) return const Center(child: CircularProgressIndicator(color: DzColors.lime));
    final t = _totaux;
    final annees = (((_data!['missions'] as List?) ?? []).cast<Map>()
            .map(_anneeDe).where((a) => a.isNotEmpty).toSet().toList()
          ..sort())
        .reversed.toList();

    return RefreshIndicator(
      color: DzColors.lime,
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 1000;
        final donut = _carteDonutFrais(t.detail, t.sortis);
        final mois = _carteNetParMois(t.parMois);
        return ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 32), children: [
          Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Finance', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                Text('Comptabilité réelle — missions clôturées uniquement. La marchandise n’est jamais une dépense.',
                    style: TextStyle(color: DzColors.mut, fontSize: 12)),
              ]),
            ),
            if (annees.length > 1 || _annee.isNotEmpty) _selecteurAnnee(annees),
          ]),
          const SizedBox(height: 16),
          _kpis(t, wide),
          const SizedBox(height: 16),
          _carteStack(t),
          const SizedBox(height: 16),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: donut),
              const SizedBox(width: 16),
              Expanded(flex: 7, child: mois),
            ])
          else ...[donut, const SizedBox(height: 16), mois],
          const SizedBox(height: 16),
          _carteMissions(wide),
        ]);
      }),
    );
  }

  Widget _selecteurAnnee(List<String> annees) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: DzColors.card, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final a in ['', ...annees])
            GestureDetector(
              onTap: () => setState(() => _annee = a),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _annee == a ? DzColors.lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(a.isEmpty ? 'Tout' : a,
                    style: TextStyle(
                        color: _annee == a ? DzColors.inkOnLime : DzColors.mut,
                        fontSize: 11.5,
                        fontWeight: _annee == a ? FontWeight.w700 : FontWeight.w600)),
              ),
            ),
        ]),
      );

  Widget _kpis(_Totaux t, bool wide) {
    final cards = [
      _kpi('Sortis (frais)', '${_f(t.sortis)} DA', DzColors.txt,
          sub: 'billets, douane+IFU, cartes, manques…'),
      _kpi('Revenus (attendus)', '${_f(t.revenus)} DA', DzColors.txt),
      _kpi('Net agence', '${_f(t.net)} DA',
          t.net >= 0 ? DzColors.lime : DzColors.red,
          sub: 'après commissions et primes'),
      _kpi('Part voyageurs', '${_f(t.part)} DA', DzColors.txt,
          sub: 'commissions + primes'),
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

  Widget _kpi(String l, String v, Color c, {String? sub}) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: DzColors.card,
            borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.toUpperCase(), style: const TextStyle(color: DzColors.mut, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: .8)),
          const SizedBox(height: 7),
          FittedBox(child: Text(v, style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w800))),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
            ),
        ]),
      );

  Widget _carteStack(_Totaux t) {
    final total = t.revenus;
    String part(num v) => total > 0 ? '${(v / total * 100).round()} %' : '';
    Widget item(Color c, String l, num v) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text.rich(TextSpan(children: [
            TextSpan(text: '$l ', style: const TextStyle(color: DzColors.txt2, fontSize: 11.5)),
            TextSpan(text: _f(v), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            TextSpan(text: ' · ${part(v)}', style: const TextStyle(color: DzColors.mut, fontSize: 11)),
          ])),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Où va chaque dinar du revenu'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: DzColors.card,
            borderRadius: BorderRadius.circular(16)),
        child: total <= 0
            ? const Text('Pas encore de mission clôturée.',
                style: TextStyle(color: DzColors.mut, fontSize: 12))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DzStack(segments: [
                  DzSegment(t.sortis, DzColors.card2),
                  DzSegment(t.part, DzChartColors.jaune),
                  DzSegment(t.net < 0 ? 0 : t.net, DzColors.lime),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 20, runSpacing: 6, children: [
                  item(DzColors.card2, 'Frais', t.sortis),
                  item(DzChartColors.jaune, 'Part voyageurs', t.part),
                  item(DzColors.lime, 'Net agence', t.net),
                ]),
              ]),
      ),
    ]);
  }

  Widget _carteDonutFrais(Map<String, double> detail, double totalFrais) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Où part l’argent (frais)'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: DzColors.card,
            borderRadius: BorderRadius.circular(16)),
        child: totalFrais <= 0
            ? const Text('Pas encore de frais enregistrés.',
                style: TextStyle(color: DzColors.mut, fontSize: 12))
            : Column(children: [
                DzDonut(
                  taille: 150, epaisseur: 16,
                  segments: [
                    for (final (k, _, c) in _postes) DzSegment(detail[k] ?? 0, c),
                  ],
                  centre: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        totalFrais >= 1000000
                            ? '${(totalFrais / 1000000).toStringAsFixed(2).replaceAll('.', ',')} M'
                            : '${(totalFrais / 1000).round()} k',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const Text('DA de frais',
                        style: TextStyle(color: DzColors.mut, fontSize: 9.5)),
                  ]),
                ),
                const SizedBox(height: 14),
                for (final (k, l, c) in _postes)
                  DzLegende(couleur: c, libelle: l, valeur: _f(detail[k] ?? 0),
                      part: '${((detail[k] ?? 0) / totalFrais * 100).round()} %'),
              ]),
      ),
    ]);
  }

  Widget _carteNetParMois(Map<String, double> parMois) {
    final cles = parMois.keys.toList()..sort();
    final six = cles.length > 6 ? cles.sublist(cles.length - 6) : cles;
    final moisNow =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    final barres = [
      for (final k in six)
        DzBarreMois(
            k.length >= 7 ? _moisCourt[int.tryParse(k.substring(5, 7)) ?? 0] : k,
            parMois[k]!, actif: k == moisNow),
    ];
    String meilleurTxt = '';
    if (six.isNotEmpty) {
      final meilleur = six.reduce((a, b) => parMois[a]! >= parMois[b]! ? a : b);
      final nom = meilleur.length >= 7
          ? _moisCourt[int.tryParse(meilleur.substring(5, 7)) ?? 0] : meilleur;
      meilleurTxt = 'Meilleur mois : $nom — ${_f(parMois[meilleur]!)} DA';
    }
    final moyenne = six.isEmpty
        ? 0.0 : six.fold<double>(0, (s, k) => s + parMois[k]!) / six.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Net agence par mois'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: DzColors.card,
            borderRadius: BorderRadius.circular(16)),
        child: six.isEmpty
            ? const Text('Pas encore de mission clôturée.',
                style: TextStyle(color: DzColors.mut, fontSize: 12))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DzBarres(barres: barres, hauteur: 118),
                const Divider(color: DzColors.line, height: 22),
                Row(children: [
                  Expanded(child: Text(meilleurTxt,
                      style: const TextStyle(color: DzColors.mut, fontSize: 11))),
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: 'moyenne ',
                        style: TextStyle(color: DzColors.txt2, fontSize: 11.5)),
                    TextSpan(text: '${_f(moyenne)} DA',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                    const TextSpan(text: '/mois',
                        style: TextStyle(color: DzColors.txt2, fontSize: 11.5)),
                  ])),
                ]),
              ]),
      ),
    ]);
  }

  Widget _carteMissions(bool wide) {
    final missions = _missionsFiltrees;
    double netDe(Map m) =>
        _n(m['attendu']) - _n(m['frais']) - _n(m['commission']) - _n(m['primes']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Missions clôturées${_annee.isEmpty ? '' : ' · $_annee'}'),
      Container(
        decoration: BoxDecoration(color: DzColors.card,
            borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: missions.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucune mission clôturée.',
                    style: TextStyle(color: DzColors.mut, fontSize: 12)))
            : Column(children: [
                if (wide)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(children: [
                      SizedBox(width: 250, child: _EnTete('Mission')),
                      Spacer(),
                      SizedBox(width: 100, child: _EnTete('Frais', droite: true)),
                      SizedBox(width: 100, child: _EnTete('Attendu', droite: true)),
                      SizedBox(width: 95, child: _EnTete('Commission', droite: true)),
                      SizedBox(width: 100, child: _EnTete('Net', droite: true)),
                      SizedBox(width: 95, child: _EnTete('Solde', droite: true)),
                    ]),
                  ),
                for (var i = 0; i < missions.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: (wide || i > 0)
                        ? const BoxDecoration(
                            border: Border(top: BorderSide(color: DzColors.line)))
                        : null,
                    child: wide
                        ? Row(children: [
                            SizedBox(
                              width: 250,
                              child: Text.rich(TextSpan(children: [
                                TextSpan(text: '${missions[i]['code']}',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                TextSpan(text: '  ${missions[i]['voyageur']} · ${_dateFr(missions[i]['depart'])}',
                                    style: const TextStyle(color: DzColors.mut, fontSize: 11)),
                              ]), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            const Spacer(),
                            _cell('${_f(_n(missions[i]['frais']))}', 100),
                            _cell('${_f(_n(missions[i]['attendu']))}', 100),
                            _cell('${_f(_n(missions[i]['commission']) + _n(missions[i]['primes']))}', 95),
                            SizedBox(width: 100, child: Text(_f(netDe(missions[i])),
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                                    color: netDe(missions[i]) >= 0 ? DzColors.txt : DzColors.red))),
                            SizedBox(width: 95, child: Text(
                                _n(missions[i]['solde']) > 0
                                    ? _f(_n(missions[i]['solde'])) : 'soldée',
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 11.5,
                                    color: _n(missions[i]['solde']) > 0
                                        ? DzColors.amber : DzColors.limeDim))),
                          ])
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('${missions[i]['code']} · ${missions[i]['voyageur']}',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                              Text('${_f(netDe(missions[i]))} DA',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800,
                                      color: netDe(missions[i]) >= 0 ? DzColors.lime : DzColors.red)),
                            ]),
                            Text('frais ${_f(_n(missions[i]['frais']))} · attendu ${_f(_n(missions[i]['attendu']))} · '
                                'part ${_f(_n(missions[i]['commission']) + _n(missions[i]['primes']))}'
                                '${_n(missions[i]['solde']) > 0 ? ' · créance ${_f(_n(missions[i]['solde']))}' : ''}',
                                style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
                          ]),
                  ),
              ]),
      ),
    ]);
  }

  String _dateFr(dynamic d) {
    final s = '$d';
    return s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}' : '—';
  }

  Widget _cell(String v, double w) => SizedBox(
      width: w,
      child: Text(v, textAlign: TextAlign.right,
          style: const TextStyle(color: DzColors.txt2, fontSize: 12)));

  Widget _lab(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: DzColors.mut, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: .8)),
      );
}

typedef _Totaux = ({double sortis, double revenus, double part, double net,
    double creances, Map<String, double> detail, Map<String, double> parMois});

class _EnTete extends StatelessWidget {
  final String t;
  final bool droite;
  const _EnTete(this.t, {this.droite = false});
  @override
  Widget build(BuildContext context) => Text(t.toUpperCase(),
      textAlign: droite ? TextAlign.right : TextAlign.left,
      style: const TextStyle(color: DzColors.mut, fontSize: 9.5,
          fontWeight: FontWeight.w700, letterSpacing: .8));
}
