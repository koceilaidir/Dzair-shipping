import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import 'mission_detail_screen.dart';

/// Tableau de bord — charte v3 « iOS sombre », branché sur l'API réelle.
/// KPIs (missions, net du mois, créances, stock exposé) · missions en cours ·
/// seuil de collecte du séjour · alertes · activité récente.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

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
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Chaque source est indépendante : si une tombe, le reste du tableau vit.
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
    ]);
    if (!mounted) return;
    setState(() {
      _missions = res[0] as List?;
      _finance = res[1] as Map?;
      _creances = res[2] as Map?;
      _stock = res[3] as Map?;
      _activite = res[4] as List?;
      _voyageurs = res[5] as List?;
      _loaded = true;
    });
  }

  /* ---------- Calculs (mêmes formules que le serveur) ---------- */
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

  static const _moisFr = ['', 'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

  /* ---------- KPIs ---------- */
  (String, String, Color, String) get _kpiNet {
    final pm = (_finance?['par_mois'] as List?) ?? [];
    if (pm.isEmpty) return ('Net agence', '—', DzColors.txt, 'aucune clôture');
    final last = pm.last as Map;
    final mois = '${last['mois']}';
    final nom = mois.length >= 7 ? _moisFr[int.tryParse(mois.substring(5, 7)) ?? 0] : mois;
    final net = _n(last['net']);
    return ('Net agence · $nom', '${_f(net)} DA',
        net >= 0 ? DzColors.lime : DzColors.red, 'missions clôturées du mois');
  }

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

  /* ---------- Alertes ---------- */
  List<(IconData, String, Color)> get _alertes {
    final out = <(IconData, String, Color)>[];
    // Marchandise encore à l'hôtel alors qu'un retour approche.
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
            min <= 2 ? DzColors.red : DzColors.amber));
      }
    }
    // Documents voyageurs proches de la péremption.
    for (final v in (_voyageurs ?? []).cast<Map>()) {
      final jp = _joursAvant(v['passeport_expire']);
      if (jp != null && jp < 8 * 30) {
        out.add((Icons.badge_outlined,
            'Passeport de ${v['nom']} expire dans ${(jp / 30).floor()} mois',
            jp < 90 ? DzColors.red : DzColors.amber));
      }
      final ja = _joursAvant(v['autorisation_expire']);
      if (ja != null && ja < 60) {
        out.add((Icons.gavel_outlined,
            'Autorisation ANAE de ${v['nom']} expire dans $ja j', DzColors.red));
      }
    }
    // Créance la plus lourde.
    final cm = (_creances?['missions'] as List?) ?? [];
    Map? pire;
    for (final m in cm.cast<Map>()) {
      if (_n(m['reste']) > 0 && (pire == null || _n(m['reste']) > _n(pire['reste']))) pire = m;
    }
    if (pire != null) {
      out.add((Icons.account_balance_wallet_outlined,
          '${_f(_n(pire['reste']))} DA à encaisser — ${pire['code']} (${pire['voyageur']})',
          DzColors.amber));
    }
    return out.take(4).toList();
  }

  /* ---------- Activité : phrase courte par action ---------- */
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

  /* ================================ UI ================================ */
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
        final gauche = _colGauche();
        final droite = _colDroite();
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          children: [
            const Text('Tableau de bord',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            const Text('Vue d’ensemble — missions, stock, argent.',
                style: TextStyle(color: DzColors.mut, fontSize: 12.5)),
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

  Widget _kpis(bool wide) {
    final (netLab, netVal, netCol, netSub) = _kpiNet;
    final (stockVal, stockSub) = _kpiStock;
    final cr = _n(_creances?['total_a_recuperer']);
    final crN = ((_creances?['missions'] as List?) ?? [])
        .cast<Map>().where((m) => _n(m['reste']) > 0).length;
    final cards = [
      _kpi('Missions en cours', '${_enCours.length}',
          sub: _missions == null ? 'hors ligne' : 'sur ${(_missions ?? []).length} au total'),
      _kpi(netLab, netVal, color: netCol, sub: netSub),
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

  /* ---------- Colonne gauche : missions en cours + seuil ---------- */
  Widget _colGauche() {
    final seuil = _stock?['seuil'] as Map?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
      if (seuil != null && _n(seuil['kg_libre']) > 0) ...[
        const SizedBox(height: 16),
        _lab('Seuil de collecte du séjour'),
        _group(Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: _f(_n(seuil['seuil_kg'])),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const TextSpan(text: '  DA/kg minimum',
                      style: TextStyle(color: DzColors.mut, fontSize: 12, fontWeight: FontWeight.w600)),
                ])),
                const SizedBox(height: 3),
                Text('${_f(_n(seuil['a_couvrir']))} DA à couvrir · '
                    '${_n(seuil['kg_libre']).toStringAsFixed(0)} kg libres · '
                    '${seuil['voyageurs']} voyageur(s) en collecte',
                    style: const TextStyle(color: DzColors.mut, fontSize: 11)),
              ]),
            ),
          ]),
        )),
      ],
    ]);
  }

  Widget _missionRow(Map m, {bool first = false}) {
    final b = _benefDe(m);
    final pret = _n(m['kg_total']) > 0 && b >= _n(m['objectif']);
    final (lab, col) = m['statut'] == 'planifiee' || _n(m['kg_total']) == 0
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

  /* ---------- Colonne droite : alertes + activité ---------- */
  Widget _colDroite() {
    final alertes = _alertes;
    final acts = (_activite ?? []).take(7).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Alertes'),
      _group(alertes.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Rien à signaler ✓',
                  style: TextStyle(color: DzColors.mut, fontSize: 12.5)))
          : Column(children: [
              for (var i = 0; i < alertes.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: i == 0 ? null : const BoxDecoration(
                      border: Border(top: BorderSide(color: DzColors.line))),
                  child: Row(children: [
                    Icon(alertes[i].$1, size: 16, color: alertes[i].$3),
                    const SizedBox(width: 11),
                    Expanded(child: Text(alertes[i].$2,
                        style: const TextStyle(color: DzColors.txt2, fontSize: 12))),
                  ]),
                ),
            ])),
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

  /* ---------- Briques v3 ---------- */
  Widget _lab(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: DzColors.mut, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: .8)),
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
