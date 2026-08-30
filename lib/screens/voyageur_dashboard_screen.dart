import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import 'voyageur_mission_screen.dart';

class VoyageurDashboardScreen extends StatefulWidget {
  final VoidCallback? onOuvrirMessages;
  const VoyageurDashboardScreen({super.key, this.onOuvrirMessages});

  @override
  State<VoyageurDashboardScreen> createState() => _VoyageurDashboardScreenState();
}

class _VoyageurDashboardScreenState extends State<VoyageurDashboardScreen> {
  List? _missions;
  Map? _finance;
  List? _contacts;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Future<T?> tente<T>(Future<dynamic> f) async {
      try { return await f as T; } catch (_) { return null; }
    }
    final res = await Future.wait([
      tente<List>(Api.get('/missions')),
      tente<Map>(Api.get('/rapports/ma-finance')),
      tente<List>(Api.get('/messages/contacts')),
    ]);
    if (!mounted) return;
    setState(() {
      _missions = res[0] as List?;
      _finance = res[1] as Map?;
      _contacts = res[2] as List?;
      _loaded = true;
    });
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.round().toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  String _dateFr(dynamic d) {
    final s = '$d';
    return s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}' : '—';
  }
  String _dureeTxt(int min) =>
      min >= 60 ? '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}' : '$min min';
  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  List<Map> get _mes => (_missions ?? []).cast<Map>();
  List<Map> get _enCours => _mes.where((m) => m['statut'] != 'cloturee').toList();

  (Map, double, int, DateTime)? get _volEnCours {
    final now = DateTime.now();
    for (final m in _enCours) {
      final dec = DateTime.tryParse('${m['heure_decollage'] ?? ''}')?.toLocal();
      final duree = _n(m['duree_vol_min']).round();
      if (dec == null || duree <= 0) continue;
      final att = dec.add(Duration(minutes: duree));
      if (now.isAfter(dec) && now.isBefore(att)) {
        return (m, now.difference(dec).inMinutes / duree, att.difference(now).inMinutes, att);
      }
    }
    return null;
  }

  int get _nonLus => ((_contacts ?? []).cast<Map>())
      .fold<int>(0, (s, c) => s + (num.tryParse('${c['non_lus']}') ?? 0).toInt());

  static const _moisCourt = ['', 'janv', 'févr', 'mars', 'avril', 'mai', 'juin',
    'juil', 'août', 'sept', 'oct', 'nov', 'déc'];

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator(color: DzColors.lime));
    }
    final v = _finance?['voyageur'] as Map?;
    final prenom = '${v?['nom'] ?? Api.nom ?? ''}'.split(' ').last;
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
            Text('Salut $prenom 👋',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                    letterSpacing: -.4)),
            const Text('Ton espace — tes missions, ton vol, tes gains.',
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
    final v = _finance?['voyageur'] as Map?;
    final vol = _volEnCours;
    final encours = _enCours.isNotEmpty ? _enCours.first : null;
    final cards = [
      _kpi('Mission en cours', encours == null ? '—' : '${encours['code']}',
          sub: encours == null
              ? 'aucune mission en ce moment'
              : vol != null
                  ? 'en vol — atterrissage ≈ ${_hm(vol.$4)}'
                  : 'retour prévu le ${_dateFr(encours['retour'])}'),
      _kpi('Mes gains', '${_f(_n(_finance?['gains_total']))} DA',
          color: DzColors.lime,
          sub: '${((_finance?['missions'] as List?) ?? []).where((m) => (m as Map)['statut'] == 'cloturee').length} mission(s) clôturée(s)'),
      _kpi('Mon compte BEA',
          v == null ? '—' : '${_f(_n(v['solde_devises']))} ${v['devise_compte'] == 'EUR' ? '€' : '\$'}',
          sub: 'solde restant sur la carte'),
      _kpi('L’agence me doit',
          _n(_finance?['agence_me_doit']) > 0
              ? '${_f(_n(_finance?['agence_me_doit']))} DA' : 'Rien ✓',
          color: _n(_finance?['agence_me_doit']) > 0 ? DzColors.amber : DzColors.lime,
          sub: 'commissions à recevoir'),
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
    final donut = _cartePoche();
    final gains = _carteGainsMois();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (vol != null) ...[
        _lab('Ton vol en cours'),
        _group(Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            decoration: BoxDecoration(
                color: DzColors.card2, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('${vol.$1['vol'] ?? vol.$1['code']}  · ton retour',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                _pastille('En vol', DzColors.lime),
              ]),
              const SizedBox(height: 10),
              DzVolProgress(progression: vol.$2),
              const SizedBox(height: 2),
              Row(children: [
                const Text('Canton CAN',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                Expanded(
                  child: Text('${(vol.$2 * 100).round()} % · reste ≈ ${_dureeTxt(vol.$3)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Alger ALG',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  Text('atterrissage ≈ ${_hm(vol.$4)}',
                      style: const TextStyle(color: DzColors.mut, fontSize: 10)),
                ]),
              ]),
            ]),
          ),
        )),
        const SizedBox(height: 16),
      ],
      _lab('Tes missions'),
      _group(_mes.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Pas encore de mission — l’admin t’assignera bientôt.',
                  style: TextStyle(color: DzColors.mut, fontSize: 12.5)))
          : Column(children: [
              for (var i = 0; i < _mes.length && i < 5; i++)
                _missionRow(_mes[i], first: i == 0),
            ])),
      const SizedBox(height: 16),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: donut),
          const SizedBox(width: 16),
          Expanded(child: gains),
        ])
      else ...[donut, const SizedBox(height: 16), gains],
    ]);
  }

  Widget _missionRow(Map m, {bool first = false}) {
    final vol = _volEnCours;
    final enVol = vol != null && vol.$1['id'] == m['id'];
    final cloturee = '${m['statut']}' == 'cloturee';
    final gain = _n(m['commission']) + _n(m['primes']);
    final (lab, col) = enVol
        ? ('En vol', DzColors.lime)
        : cloturee
            ? ('Terminée', DzColors.mut)
            : _n(m['kg_total']) == 0
                ? ('Préparation', DzColors.amber)
                : ('En cours', DzColors.amber);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => VoyageurMissionScreen(id: m['id'] as int)))
          .then((_) => _load()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: first ? null : const BoxDecoration(
            border: Border(top: BorderSide(color: DzColors.line))),
        child: Row(children: [
          Container(
            width: 32, height: 32, alignment: Alignment.center,
            decoration: const BoxDecoration(color: DzColors.card2, shape: BoxShape.circle),
            child: Icon(
                cloturee ? Icons.check_rounded
                    : enVol ? Icons.flight : Icons.flight_takeoff_outlined,
                size: 15, color: cloturee ? DzColors.mut : DzColors.lime),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m['code']}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(
                  cloturee
                      ? 'clôturée le ${_dateFr(m['cloture_date'])} · '
                        '${_n(m['kg_total']).toStringAsFixed(1)} kg · ton gain : ${_f(gain)} DA'
                      : '${'${m['vol'] ?? ''}'.isNotEmpty ? '${m['vol']} · ' : ''}'
                        'départ ${_dateFr(m['depart'])}'
                        '${'${m['heure_depart'] ?? ''}'.isNotEmpty ? ' ${m['heure_depart']}' : ''}'
                        ' · retour ${_dateFr(m['retour'])}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: DzColors.mut, fontSize: 11)),
            ]),
          ),
          _pastille(lab, col),
        ]),
      ),
    );
  }

  Widget _cartePoche() {
    final missionEnc = ((_finance?['missions'] as List?) ?? []).cast<Map>()
        .where((m) => '${m['statut']}' != 'cloturee').toList();
    final poche = missionEnc.isEmpty ? 0.0 : _n(missionEnc.first['poche_da']);
    final reste = missionEnc.isEmpty ? 0.0 : _n(missionEnc.first['reste_da']);
    final depense = (poche - reste).clamp(0.0, double.infinity);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Mon argent de poche (séjour)'),
      _group(Padding(
        padding: const EdgeInsets.all(16),
        child: poche <= 0
            ? const Text('Rien de remis pour l’instant.',
                style: TextStyle(color: DzColors.mut, fontSize: 12))
            : Row(children: [
                DzDonut(
                  taille: 104, epaisseur: 12,
                  segments: reste > 0
                      ? [DzSegment(depense, DzColors.card2), DzSegment(reste, DzColors.lime)]
                      : [DzSegment(poche, DzColors.lime)],
                  centre: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(reste > 0 ? '${(reste / poche * 100).round()} %' : '100 %',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(reste > 0 ? 'restant' : 'remis',
                        style: const TextStyle(color: DzColors.mut, fontSize: 8.5)),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(children: [
                    DzLegende(couleur: DzColors.lime,
                        libelle: reste > 0 ? 'Restant' : 'Remis au départ',
                        valeur: '${_f(reste > 0 ? reste : poche)} DA'),
                    if (reste > 0)
                      DzLegende(couleur: DzColors.card2, libelle: 'Dépensé',
                          valeur: '${_f(depense)} DA'),
                    const SizedBox(height: 4),
                    Text(reste > 0
                            ? 'sur ${_f(poche)} DA remis au départ'
                            : 'déclare tes restes à l’arrivée',
                        style: const TextStyle(color: DzColors.mut2, fontSize: 10)),
                  ]),
                ),
              ]),
      )),
    ]);
  }

  Widget _carteGainsMois() {
    final pm = ((_finance?['gains_par_mois'] as List?) ?? []).cast<Map>();
    final six = pm.length > 6 ? pm.sublist(pm.length - 6) : pm;
    final moisNow =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Mes gains par mois'),
      _group(Padding(
        padding: const EdgeInsets.all(16),
        child: six.isEmpty
            ? const Text('Tes gains apparaîtront à ta première clôture.',
                style: TextStyle(color: DzColors.mut, fontSize: 12))
            : Column(children: [
                DzBarres(hauteur: 84, barres: [
                  for (final e in six)
                    DzBarreMois(
                        '${e['mois']}'.length >= 7
                            ? _moisCourt[int.tryParse('${e['mois']}'.substring(5, 7)) ?? 0]
                            : '${e['mois']}',
                        _n(e['gain']),
                        actif: '${e['mois']}' == moisNow),
                ]),
                const SizedBox(height: 5),
                const Text('commissions + primes',
                    style: TextStyle(color: DzColors.mut2, fontSize: 9.5)),
              ]),
      )),
    ]);
  }

  Widget _colDroite() {
    final notifs = _notifications();
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
      _labAction('Discussions', 'Ouvrir la messagerie'),
      _group(_carteDiscussions()),
    ]);
  }

  List<(IconData, String, Color, VoidCallback?)> _notifications() {
    final out = <(IconData, String, Color, VoidCallback?)>[];
    final now = DateTime.now();
    for (final m in _enCours) {
      final dep = DateTime.tryParse('${m['depart'] ?? ''}'.length >= 10
          ? '${m['depart']}'.substring(0, 10) : '');
      if (dep != null && dep.isAfter(now)) {
        final j = dep.difference(DateTime(now.year, now.month, now.day)).inDays;
        out.add((Icons.flight_takeoff_outlined,
            'Tu es assigné à ${m['code']} — départ le ${_dateFr(m['depart'])}'
            '${'${m['heure_depart'] ?? ''}'.isNotEmpty ? ' à ${m['heure_depart']}' : ''}'
            '${j <= 7 ? ' (dans $j j !)' : ''}',
            j <= 3 ? DzColors.amber : DzColors.lime, null));
        final checks = (m['check_depart'] as Map?) ?? {};
        final faits = checks.values.where((v) => v == true).length;
        if (faits < 9 && j <= 15) {
          out.add((Icons.checklist_rounded,
              'Check de départ ${m['code']} : $faits/9 — termine ta préparation',
              DzColors.amber, null));
        }
      }
    }
    final vol = _volEnCours;
    if (vol != null) {
      out.add((Icons.flight_land,
          'Atterrissage dans ≈ ${_dureeTxt(vol.$3)} — pense au bon de douane et à tes restes',
          DzColors.lime, null));
    }
    if (_nonLus > 0) {
      out.add((Icons.chat_bubble_outline,
          '$_nonLus message${_nonLus > 1 ? 's' : ''} non lu${_nonLus > 1 ? 's' : ''}',
          DzColors.lime, widget.onOuvrirMessages));
    }
    if (_n(_finance?['agence_me_doit']) > 0) {
      out.add((Icons.payments_outlined,
          '${_f(_n(_finance?['agence_me_doit']))} DA de commission à recevoir',
          DzColors.amber, null));
    }
    return out.take(5).toList();
  }

  Widget _carteDiscussions() {
    final fils = ((_contacts ?? []).cast<Map>()).take(4).toList();
    if (fils.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Tu peux écrire aux admins et aux voyageurs avec qui tu as partagé un séjour.',
            style: TextStyle(color: DzColors.mut, fontSize: 12)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(children: [
        for (var i = 0; i < fils.length; i++)
          InkWell(
            onTap: widget.onOuvrirMessages,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: i == 0 ? null : const BoxDecoration(
                  border: Border(top: BorderSide(color: DzColors.line))),
              child: Row(children: [
                Container(
                  width: 30, height: 30, alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: DzColors.card2, shape: BoxShape.circle),
                  child: Text('${fils[i]['nom']}'.isNotEmpty
                          ? '${fils[i]['nom']}'[0].toUpperCase() : '?',
                      style: const TextStyle(color: DzColors.lime,
                          fontSize: 12, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('${fils[i]['nom']}',
                          style: TextStyle(fontSize: 12.5,
                              fontWeight: _n(fils[i]['non_lus']) > 0
                                  ? FontWeight.w800 : FontWeight.w600)),
                      const SizedBox(width: 6),
                      Text(fils[i]['role'] == 'admin' ? 'admin' : 'voyageur',
                          style: const TextStyle(color: DzColors.mut2, fontSize: 9.5)),
                    ]),
                    if (fils[i]['dernier_texte'] != null)
                      Text('${fils[i]['dernier_recu'] == true ? '' : 'Toi : '}${fils[i]['dernier_texte']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _n(fils[i]['non_lus']) > 0
                                  ? DzColors.txt : DzColors.mut,
                              fontSize: 11.5)),
                  ]),
                ),
                if (_n(fils[i]['non_lus']) > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
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
      ]),
    );
  }

  Widget _lab(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: DzColors.mut, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: .8)),
      );

  Widget _labAction(String t, String action) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
        child: Row(children: [
          Expanded(child: Text(t.toUpperCase(),
              style: const TextStyle(color: DzColors.mut, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: .8))),
          GestureDetector(
            onTap: widget.onOuvrirMessages,
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
