import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/avatar_user.dart';
import '../widgets/charts.dart';
import 'mission_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onOuvrirMessages;
  const DashboardScreen({super.key, this.onOuvrirMessages});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List? _missions;
  Map? _finance;
  Map? _creances;
  Map? _stock;
  List? _activite;
  List? _voyageurs;
  List? _contacts;
  bool _loaded = false;

  int _periodeJours = 30;
  static const _periodes = [(7, '7 jours'), (30, '30 jours'), (90, '3 mois'), (365, 'Année')];
  final _reponse = TextEditingController();
  bool _envoiReponse = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reponse.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    Future<T?> tente<T>(Future<dynamic> f) async {
      try { return await f as T; } catch (_) { return null; }
    }
    final res = await Future.wait([
      tente<List>(Api.get('/missions')),
      tente<Map>(Api.get('/rapports/finance')),
      tente<Map>(Api.get('/rapports/creances')),
      tente<Map>(Api.get('/inventaire/stock')),
      tente<List>(Api.get('/rapports/activite')),
      tente<List>(Api.get('/voyageurs')),
      tente<List>(Api.get('/messages/contacts')),
    ]);
    if (!mounted) return;
    setState(() {
      _missions = res[0] as List?;
      _finance = res[1] as Map?;
      _creances = res[2] as Map?;
      _stock = res[3] as Map?;
      _activite = res[4] as List?;
      _voyageurs = res[5] as List?;
      _contacts = res[6] as List?;
      _loaded = true;
    });
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.round().toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  double _fraisDe(Map m) {
    final poche = _n(m['poche_da']) > 0
        ? _n(m['poche_da']) : _n(m['jours']) * _n(m['budget_jour']);
    return _n(m['billet']) + _n(m['dem_cout']) + _n(m['frais_visa']) +
        (poche - _n(m['reste_da'])).clamp(0, double.infinity) +
        _n(m['douane']) + _n(m['taxes_carte']) + _n(m['autres']) +
        _n(m['manques_da']) + _n(m['saisie_da']) +
        (m['valise_sup'] == true ? _n(m['valise_sup_prix']) : 0);
  }

  double _benefDe(Map m) =>
      (m['statut'] == 'cloturee' ? _n(m['attendu']) : _n(m['revenu'])) - _fraisDe(m);

  List<Map> get _enCours => (_missions ?? [])
      .cast<Map>().where((m) => m['statut'] != 'cloturee').toList();

  String _dateFr(dynamic d) {
    final s = '$d';
    return s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}' : '—';
  }

  int? _joursAvant(dynamic d) {
    final dt = DateTime.tryParse('$d'.length >= 10 ? '$d'.substring(0, 10) : '');
    if (dt == null) return null;
    final now = DateTime.now();
    return dt.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  static const _moisCourt = ['', 'janv', 'févr', 'mars', 'avril', 'mai', 'juin',
    'juil', 'août', 'sept', 'oct', 'nov', 'déc'];

  (Map, double, int, DateTime)? get _volEnCours {
    final now = DateTime.now();
    for (final m in _enCours) {
      final dec = DateTime.tryParse('${m['heure_decollage'] ?? ''}')?.toLocal();
      final duree = _n(m['duree_vol_min']).round();
      if (dec == null || duree <= 0) continue;
      final att = dec.add(Duration(minutes: duree));
      if (now.isAfter(dec) && now.isBefore(att)) {
        final p = now.difference(dec).inMinutes / duree;
        return (m, p, att.difference(now).inMinutes, att);
      }
    }
    return null;
  }

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _dureeTxt(int min) =>
      min >= 60 ? '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}' : '$min min';

  ({double frais, double part, double net, double attendu, int nb}) get _periode {
    final depuis = DateTime.now().subtract(Duration(days: _periodeJours));
    double frais = 0, part = 0, attendu = 0;
    int nb = 0;
    for (final m in ((_finance?['missions'] as List?) ?? []).cast<Map>()) {
      final d = DateTime.tryParse(
          '${m['cloture_date'] ?? m['depart'] ?? ''}'.length >= 10
              ? '${m['cloture_date'] ?? m['depart']}'.substring(0, 10) : '');
      if (d == null || d.isBefore(depuis)) continue;
      frais += _n(m['frais']);
      part += _n(m['commission']) + _n(m['primes']);
      attendu += _n(m['attendu']);
      nb++;
    }
    return (frais: frais, part: part, net: attendu - frais - part,
        attendu: attendu, nb: nb);
  }

  List<DzBarreMois> get _netParMois {
    final pm = ((_finance?['par_mois'] as List?) ?? []).cast<Map>();
    final six = pm.length > 6 ? pm.sublist(pm.length - 6) : pm;
    final moisNow =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    return [
      for (final e in six)
        DzBarreMois(
          '${e['mois']}'.length >= 7
              ? _moisCourt[int.tryParse('${e['mois']}'.substring(5, 7)) ?? 0]
              : '${e['mois']}',
          _n(e['net']),
          actif: '${e['mois']}' == moisNow,
        ),
    ];
  }

  int get _nonLus => ((_contacts ?? []).cast<Map>())
      .fold<int>(0, (s, c) => s + (num.tryParse('${c['non_lus']}') ?? 0).toInt());

  (String, String) get _kpiStock {
    final lignes = (_stock?['lignes'] as List?) ?? [];
    double da = 0, kgHotel = 0, kgValise = 0;
    for (final l in lignes.cast<Map>()) {
      da += _n(l['gain_restant']) + _n(l['gain_en_cours']);
      kgHotel += _n(l['kg_restant']);
      kgValise += _n(l['kg_en_cours']);
    }
    return ('${_f(da)} DA',
        '${kgHotel.toStringAsFixed(0)} kg à l’hôtel · ${kgValise.toStringAsFixed(0)} kg en valise');
  }

  List<(IconData, String, Color, VoidCallback?)> get _notifications {
    final out = <(IconData, String, Color, VoidCallback?)>[];

    final nl = _nonLus;
    if (nl > 0) {
      final qui = ((_contacts ?? []).cast<Map>())
          .where((c) => _n(c['non_lus']) > 0).map((c) => '${c['nom']}').take(2).join(', ');
      out.add((Icons.chat_bubble_outline,
          '$nl message${nl > 1 ? 's' : ''} non lu${nl > 1 ? 's' : ''} — $qui t’attend',
          DzColors.lime, widget.onOuvrirMessages));
    }

    final vol = _volEnCours;
    if (vol != null) {
      out.add((Icons.flight_land,
          '${vol.$1['vol'] ?? vol.$1['code']} atterrit dans ≈ ${_dureeTxt(vol.$3)} — prépare la récupération',
          DzColors.lime, null));
    }

    final lignes = (_stock?['lignes'] as List?) ?? [];
    final kgHotel = lignes.cast<Map>().fold<double>(0, (s, l) => s + _n(l['kg_restant']));
    final ouvertes = (_stock?['ouvertes'] as List?) ?? [];
    if (kgHotel > 0.5 && ouvertes.isNotEmpty) {
      int? min;
      String qui = '';
      for (final o in ouvertes.cast<Map>()) {
        final j = _joursAvant(o['retour']);
        if (j != null && (min == null || j < min)) { min = j; qui = '${o['voyageur']}'; }
      }
      if (min != null && min <= 7) {
        out.add((Icons.warning_amber_rounded,
            'Retour de $qui dans $min j — ${kgHotel.toStringAsFixed(1)} kg encore à l’hôtel',
            min <= 2 ? DzColors.red : DzColors.amber, null));
      }
    }

    for (final v in (_voyageurs ?? []).cast<Map>()) {
      final jp = _joursAvant(v['passeport_expire']);
      if (jp != null && jp < 8 * 30) {
        out.add((Icons.badge_outlined,
            'Passeport de ${v['nom']} expire dans ${(jp / 30).floor()} mois',
            jp < 90 ? DzColors.red : DzColors.amber, null));
      }
      final ja = _joursAvant(v['autorisation_expire']);
      if (ja != null && ja < 60) {
        out.add((Icons.gavel_outlined,
            'Autorisation ANAE de ${v['nom']} expire dans $ja j', DzColors.red, null));
      }
    }

    final cm = (_creances?['missions'] as List?) ?? [];
    Map? pire;
    for (final m in cm.cast<Map>()) {
      if (_n(m['reste']) > 0 && (pire == null || _n(m['reste']) > _n(pire['reste']))) pire = m;
    }
    if (pire != null) {
      out.add((Icons.account_balance_wallet_outlined,
          '${_f(_n(pire['reste']))} DA à encaisser — ${pire['code']} (${pire['voyageur']})',
          DzColors.amber, null));
    }
    return out.take(5).toList();
  }

  String _phrase(Map a) {
    final d = (a['details'] as Map?) ?? {};
    final code = d['code'] ?? d['chambre'] ?? '';
    switch ('${a['action']}') {
      case 'create': return a['entite'] == 'mission'
          ? 'a créé la mission ${d['code'] ?? ''}' : 'a créé ${a['entite']} $code';
      case 'cloture': return 'a clôturé ${d['code'] ?? 'une mission'}';
      case 'valise_ajout': return 'a ajouté ${d['produit'] ?? 'un produit'}'
          '${d['bagage_main'] == true ? ' au bagage à main' : ' à la valise'} ${d['code'] ?? ''}';
      case 'valise_retrait': return 'a remis ${d['produit'] ?? 'un produit'} en stock';
      case 'tranche': return 'a ajouté ${_f(_n(d['montant']))} ${d['devise'] ?? ''} (${d['motif'] ?? ''}) — ${d['code'] ?? ''}';
      case 'encaissement': return 'a encaissé ${_f(_n(d['montant']))} DA'
          '${d['depot'] != null ? ' — dépôt ${d['depot']}' : ''} (${d['code'] ?? ''})';
      case 'arrivee': return 'a saisi l’arrivée de ${d['code'] ?? ''} — taxes ${_f(_n(d['taxes_da']))} DA';
      case 'arrivee_photo': return 'a joint la photo du bon de douane — ${d['code'] ?? ''}';
      case 'bon_ajout': return 'a complété un bon — chambre ${d['chambre'] ?? ''}';
      case 'retour_chambre': return 'a rendu ${_f(_n(d['quantite']))} pc à la chambre ${d['chambre'] ?? ''}';
      case 'depot_statut': return 'dépôt ${d['depot'] ?? ''} → ${d['statut'] ?? ''} (${d['code'] ?? ''})';
      case 'update': return 'a modifié ${a['entite']} ${d['code'] ?? ''}';
      default: return '${a['action']} ${a['entite']} $code';
    }
  }

  String _quand(dynamic created) {
    final dt = DateTime.tryParse('$created');
    if (dt == null) return '';
    final l = dt.toLocal();
    final now = DateTime.now();
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator(color: DzColors.lime));
    }
    return RefreshIndicator(
      color: DzColors.lime,
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 1000;
        final gauche = _colGauche(wide);
        final droite = _colDroite();
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Tableau de bord',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                  Text('Vue d’ensemble — missions, vols, argent, messages.',
                      style: TextStyle(color: DzColors.mut, fontSize: 12.5)),
                ]),
              ),
              if (wide) _selecteurPeriode(),
            ]),
            if (!wide) ...[
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: _selecteurPeriode()),
            ],
            const SizedBox(height: 16),
            _kpis(wide),
            const SizedBox(height: 16),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 7, child: gauche),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: droite),
              ])
            else ...[gauche, const SizedBox(height: 16), droite],
          ],
        );
      }),
    );
  }

  Widget _selecteurPeriode() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: DzColors.card, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (j, lab) in _periodes)
            GestureDetector(
              onTap: () => setState(() => _periodeJours = j),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(
                  color: _periodeJours == j ? DzColors.lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(lab,
                    style: TextStyle(
                        color: _periodeJours == j ? DzColors.inkOnLime : DzColors.mut,
                        fontSize: 11.5,
                        fontWeight: _periodeJours == j ? FontWeight.w700 : FontWeight.w600)),
              ),
            ),
        ]),
      );

  String get _periodeLab =>
      _periodes.firstWhere((p) => p.$1 == _periodeJours).$2.toLowerCase();

  Widget _kpis(bool wide) {
    final p = _periode;
    final (stockVal, stockSub) = _kpiStock;
    final cr = _n(_creances?['total_a_recuperer']);
    final crN = ((_creances?['missions'] as List?) ?? [])
        .cast<Map>().where((m) => _n(m['reste']) > 0).length;
    final vol = _volEnCours;
    final volId = vol?.$1['id'];
    final surPlace = _enCours.where((m) =>
        m['id'] != volId && m['statut'] != 'planifiee' && _n(m['kg_total']) > 0).length;
    final prepa = _enCours.length - (vol != null ? 1 : 0) - surPlace;
    final cards = [
      _kpi('Missions en cours', '${_enCours.length}',
          sub: _missions == null
              ? 'hors ligne'
              : '${vol != null ? '1 en vol · ' : ''}'
                '$surPlace sur place · $prepa en préparation'),
      _kpi('Net agence · $_periodeLab', p.nb == 0 ? '—' : '${_f(p.net)} DA',
          color: p.net >= 0 ? DzColors.lime : DzColors.red,
          sub: p.nb == 0
              ? 'aucune clôture sur la période'
              : '${p.nb} mission${p.nb > 1 ? 's' : ''} clôturée${p.nb > 1 ? 's' : ''} sur la période'),
      _kpi('Créances dehors', cr > 0 ? '${_f(cr)} DA' : 'Soldé ✓',
          color: cr > 0 ? DzColors.amber : DzColors.lime,
          sub: cr > 0 ? '$crN mission(s) à encaisser' : 'tout est encaissé'),
      _kpi('Stock exposé', stockVal, sub: stockSub),
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
          Text(val, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.w800)),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
            ),
        ]),
      );

  Widget _colGauche(bool wide) {
    final vol = _volEnCours;
    final donut = _carteDonutPeriode();
    final seuil = _carteSeuil();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (vol != null) ...[
        _lab('Vol en cours'),
        _group(_carteVol(vol)),
        const SizedBox(height: 16),
      ],
      _lab('Missions en cours'),
      _group(_enCours.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucune mission en cours — crée-en une depuis Missions.',
                  style: TextStyle(color: DzColors.mut, fontSize: 12.5)))
          : Column(children: [
              for (var i = 0; i < _enCours.length && i < 5; i++)
                _missionRow(_enCours[i], first: i == 0),
            ])),
      const SizedBox(height: 16),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: donut),
          const SizedBox(width: 16),
          Expanded(child: seuil),
        ])
      else ...[donut, const SizedBox(height: 16), seuil],
    ]);
  }

  Widget _carteVol((Map, double, int, DateTime) vol) {
    final (m, p, resteMin, att) = vol;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        decoration: BoxDecoration(
            color: DzColors.card2, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${'${m['vol'] ?? ''}'.isNotEmpty ? m['vol'] : m['code']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                TextSpan(text: '  · retour ${m['code']} · ${m['voyageur_nom']}',
                    style: const TextStyle(color: DzColors.mut, fontSize: 11)),
              ]), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            _pastille('En vol', DzColors.lime),
          ]),
          const SizedBox(height: 10),
          DzVolProgress(progression: p),
          const SizedBox(height: 2),
          Row(children: [
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Canton CAN', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${(p * 100).round()} %',
                    style: const TextStyle(color: DzColors.lime, fontSize: 11, fontWeight: FontWeight.w700)),
                TextSpan(text: ' · reste ≈ ${_dureeTxt(resteMin)}',
                    style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
              ]), textAlign: TextAlign.center),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Alger ALG', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              Text('atterrissage ≈ ${_hm(att)}',
                  style: const TextStyle(color: DzColors.mut, fontSize: 10)),
            ]),
          ]),
        ]),
      ),
    );
  }

  Widget _carteDonutPeriode() {
    final p = _periode;
    final pct = p.attendu > 0 ? (p.net / p.attendu * 100).round() : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('La période en un coup d’œil'),
      _group(Padding(
        padding: const EdgeInsets.all(16),
        child: p.nb == 0
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Aucune mission clôturée sur la période.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: DzColors.mut, fontSize: 12)))
            : Column(children: [
                Row(children: [
                  DzDonut(
                    taille: 116, epaisseur: 13,
                    segments: [
                      DzSegment(p.frais, DzColors.card2),
                      DzSegment(p.part, DzChartColors.jaune),
                      DzSegment(p.net < 0 ? 0 : p.net, DzColors.lime),
                    ],
                    centre: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$pct %',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      const Text('de net',
                          style: TextStyle(color: DzColors.mut, fontSize: 9)),
                    ]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(children: [
                      DzLegende(couleur: DzColors.lime, libelle: 'Net agence',
                          valeur: _f(p.net),
                          part: p.attendu > 0 ? '$pct %' : ''),
                      DzLegende(couleur: DzChartColors.jaune, libelle: 'Part voyageur',
                          valeur: _f(p.part),
                          part: p.attendu > 0 ? '${(p.part / p.attendu * 100).round()} %' : ''),
                      DzLegende(couleur: DzColors.card2, libelle: 'Frais',
                          valeur: _f(p.frais),
                          part: p.attendu > 0 ? '${(p.frais / p.attendu * 100).round()} %' : ''),
                    ]),
                  ),
                ]),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('sur ${_f(p.attendu)} DA attendus ($_periodeLab)',
                      style: const TextStyle(color: DzColors.mut2, fontSize: 10)),
                ),
              ]),
      )),
    ]);
  }

  Widget _carteSeuil() {
    final seuil = _stock?['seuil'] as Map?;
    final barres = _netParMois;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Seuil & net par mois'),
      _group(Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (seuil != null && _n(seuil['kg_libre']) > 0) ...[
            Text.rich(TextSpan(children: [
              TextSpan(text: _f(_n(seuil['seuil_kg'])),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const TextSpan(text: '  DA/kg minimum',
                  style: TextStyle(color: DzColors.mut, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ])),
            const SizedBox(height: 3),
            Text('${_f(_n(seuil['a_couvrir']))} DA à couvrir · '
                '${_n(seuil['kg_libre']).toStringAsFixed(0)} kg libres · '
                '${seuil['voyageurs']} voyageur(s) en collecte',
                style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
            const Divider(color: DzColors.line, height: 22),
          ],
          if (barres.isEmpty)
            const Text('Pas encore de mois clôturé.',
                style: TextStyle(color: DzColors.mut, fontSize: 12))
          else ...[
            DzBarres(barres: barres, hauteur: 74),
            const SizedBox(height: 5),
            const Center(child: Text('net agence par mois',
                style: TextStyle(color: DzColors.mut2, fontSize: 9.5))),
          ],
        ]),
      )),
    ]);
  }

  Widget _missionRow(Map m, {bool first = false}) {
    final b = _benefDe(m);
    final vol = _volEnCours;
    final enVol = vol != null && vol.$1['id'] == m['id'];
    final pret = _n(m['kg_total']) > 0 && b >= _n(m['objectif']);
    final (lab, col) = enVol
        ? ('En vol', DzColors.lime)
        : m['statut'] == 'planifiee' || _n(m['kg_total']) == 0
            ? ('Préparation', DzColors.amber)
            : pret ? ('Prêt', DzColors.lime) : ('En cours', DzColors.amber);
    return InkWell(
      onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => MissionDetailScreen(id: m['id'] as int)))
          .then((_) => _load()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: first ? null : const BoxDecoration(
            border: Border(top: BorderSide(color: DzColors.line))),
        child: Row(children: [
          Container(
            width: 32, height: 32, alignment: Alignment.center,
            decoration: const BoxDecoration(color: DzColors.card2, shape: BoxShape.circle),
            child: Text('${m['voyageur_nom'] ?? '?'}'.characters.first.toUpperCase(),
                style: const TextStyle(color: DzColors.txt2, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m['code']} · ${m['voyageur_nom']}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(
                  '${'${m['vol'] ?? ''}'.isNotEmpty ? '${m['vol']} · ' : ''}'
                  'retour ${_dateFr(m['retour'])} · '
                  '${_n(m['kg_total']).toStringAsFixed(1)} kg · '
                  '${b >= 0 ? 'bénéf ${_f(b)} DA' : 'manque ${_f(-b)} DA'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: DzColors.mut, fontSize: 11)),
            ]),
          ),
          _pastille(lab, col),
        ]),
      ),
    );
  }

  Widget _colDroite() {
    final notifs = _notifications;
    final acts = (_activite ?? []).take(6).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Notifications'),
      _group(notifs.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Rien à signaler ✓',
                  style: TextStyle(color: DzColors.mut, fontSize: 12.5)))
          : Column(children: [
              for (var i = 0; i < notifs.length; i++)
                InkWell(
                  onTap: notifs[i].$4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: i == 0 ? null : const BoxDecoration(
                        border: Border(top: BorderSide(color: DzColors.line))),
                    child: Row(children: [
                      Icon(notifs[i].$1, size: 16, color: notifs[i].$3),
                      const SizedBox(width: 11),
                      Expanded(child: Text(notifs[i].$2,
                          style: const TextStyle(color: DzColors.txt2, fontSize: 12))),
                      if (notifs[i].$4 != null)
                        const Icon(Icons.arrow_forward_rounded,
                            size: 14, color: DzColors.lime),
                    ]),
                  ),
                ),
            ])),
      const SizedBox(height: 16),
      _labAction('Discussions en cours', 'Ouvrir la messagerie', widget.onOuvrirMessages),
      _group(_carteDiscussions()),
      const SizedBox(height: 16),
      _lab('Activité récente'),
      _group(acts.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucune activité pour l’instant.',
                  style: TextStyle(color: DzColors.mut, fontSize: 12.5)))
          : Column(children: [
              for (var i = 0; i < acts.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: i == 0 ? null : const BoxDecoration(
                      border: Border(top: BorderSide(color: DzColors.line))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${(acts[i] as Map)['auteur'] ?? 'Admin'} ',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        TextSpan(text: _phrase(acts[i] as Map),
                            style: const TextStyle(color: DzColors.txt2, fontSize: 12)),
                      ]), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(_quand((acts[i] as Map)['created_at']),
                        style: const TextStyle(color: DzColors.mut2, fontSize: 10.5)),
                  ]),
                ),
            ])),
    ]);
  }

  Widget _carteDiscussions() {
    final fils = ((_contacts ?? []).cast<Map>())
        .where((c) => c['dernier_texte'] != null).take(3).toList();
    if (fils.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Aucune discussion — les comptes admins et voyageurs apparaîtront ici.',
            style: TextStyle(color: DzColors.mut, fontSize: 12)),
      );
    }
    final cible = fils.firstWhere((c) => _n(c['non_lus']) > 0, orElse: () => fils.first);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(children: [
        for (var i = 0; i < fils.length; i++)
          InkWell(
            onTap: widget.onOuvrirMessages,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: i == 0 ? null : const BoxDecoration(
                  border: Border(top: BorderSide(color: DzColors.line))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AvatarUser(userId: fils[i]['id'] as int?,
                    nom: '${fils[i]['nom']}', taille: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('${fils[i]['nom']}',
                          style: TextStyle(fontSize: 12.5,
                              fontWeight: _n(fils[i]['non_lus']) > 0
                                  ? FontWeight.w800 : FontWeight.w600)),
                      const SizedBox(width: 6),
                      Text(fils[i]['role'] == 'voyageur' ? 'voyageur' : 'admin',
                          style: const TextStyle(color: DzColors.mut2, fontSize: 9.5)),
                    ]),
                    Text(
                      '${fils[i]['dernier_recu'] == true ? '' : 'Toi : '}${fils[i]['dernier_texte']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _n(fils[i]['non_lus']) > 0 ? DzColors.txt : DzColors.mut,
                          fontSize: 11.5),
                    ),
                  ]),
                ),
                if (_n(fils[i]['non_lus']) > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 6, top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: DzColors.lime, borderRadius: BorderRadius.circular(99)),
                    child: Text('${_n(fils[i]['non_lus']).toInt()}',
                        style: const TextStyle(color: DzColors.inkOnLime,
                            fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _reponse,
              style: const TextStyle(fontSize: 12.5),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _repondre(cible),
              decoration: InputDecoration(
                  isDense: true, hintText: 'Répondre à ${cible['nom']}…'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 38, height: 38,
            child: FilledButton(
              onPressed: _envoiReponse ? null : () => _repondre(cible),
              style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero, shape: const CircleBorder()),
              child: const Icon(Icons.arrow_upward_rounded, size: 17),
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _repondre(Map cible) async {
    final t = _reponse.text.trim();
    if (t.isEmpty || _envoiReponse) return;
    setState(() => _envoiReponse = true);
    try {
      await Api.post('/messages/avec/${cible['id']}', {'texte': t});
      _reponse.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _envoiReponse = false);
    }
  }

  Widget _lab(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: DzColors.mut, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: .8)),
      );

  Widget _labAction(String t, String action, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
        child: Row(children: [
          Expanded(
            child: Text(t.toUpperCase(),
                style: const TextStyle(color: DzColors.mut, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: .8)),
          ),
          if (onTap != null)
            GestureDetector(
              onTap: onTap,
              child: Text(action,
                  style: const TextStyle(color: DzColors.lime, fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
      );

  Widget _group(Widget child) => Container(
        decoration: BoxDecoration(
            color: DzColors.card, borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  Widget _pastille(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
            color: DzColors.card2, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ]),
      );
}
