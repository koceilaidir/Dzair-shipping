import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/date_field.dart';
import '../widgets/depense_dialog.dart';
import 'mission_detail_screen.dart';

class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  List<dynamic>? _list;
  String? _error;
  String _filtre = 'en_cours';

  int? _ouvertId;
  Map? _ouvert;
  bool _chargeOuvert = false;

  static const _filtres = [
    ('en_cours', 'En cours'),
    ('cloturee', 'Clôturées'),
    ('toutes', 'Toutes'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  int _i(dynamic v, [int defaut = 0]) =>
      v is int ? v : (num.tryParse('$v')?.toInt() ?? defaut);
  String _f(num n) => n.round().toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  String _kg(num n) => n == n.roundToDouble()
      ? n.round().toString() : n.toStringAsFixed(1);

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

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await Api.get('/sejours') as List;
      if (!mounted) return;
      setState(() => _list = data);
      if (_ouvertId != null) await _rafraichirOuvert();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _rafraichirOuvert() async {
    if (_ouvertId == null) return;
    try {
      final d = await Api.get('/sejours/$_ouvertId') as Map;
      if (mounted) setState(() => _ouvert = d);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() { _ouvertId = null; _ouvert = null; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _ouvrir(int id) async {
    setState(() { _ouvertId = id; _ouvert = null; _chargeOuvert = true; });
    await _rafraichirOuvert();
    if (mounted) setState(() => _chargeOuvert = false);
  }

  void _fermer() {
    setState(() { _ouvertId = null; _ouvert = null; });
    _load();
  }

  List<dynamic> get _filtrees {
    final l = _list ?? [];
    return switch (_filtre) {
      'cloturee' => l.where((s) => (s as Map)['etat'] == 'cloturee').toList(),
      'toutes' => l,
      _ => l.where((s) => (s as Map)['etat'] != 'cloturee').toList(),
    };
  }

  (String, Color) _etatDe(Map s) => switch ('${s['etat']}') {
        'cloturee' => ('Clôturée', DzColors.mut),
        'en_cours' => ('Sur place', DzColors.amber),
        _ => ('Préparation', DzColors.mut2),
      };

  @override
  Widget build(BuildContext context) {
    if (_ouvertId != null) return _vueMission();
    return _vueListe();
  }

  Widget _lab(String t) => Text(t.toUpperCase(),
      style: const TextStyle(color: DzColors.mut, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: .8));

  Widget _segment() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: DzColors.card, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (cle, lab) in _filtres)
            GestureDetector(
              onTap: () => setState(() => _filtre = cle),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _filtre == cle ? DzColors.lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(lab,
                    style: TextStyle(
                        color: _filtre == cle ? DzColors.inkOnLime : DzColors.mut,
                        fontSize: 11.5,
                        fontWeight: _filtre == cle ? FontWeight.w700 : FontWeight.w600)),
              ),
            ),
        ]),
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

  Widget _badge(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
            color: DzColors.card2, borderRadius: BorderRadius.circular(99)),
        child: Text(t,
            style: TextStyle(color: c, fontSize: 8.5,
                fontWeight: FontWeight.w800, letterSpacing: .6)),
      );

  Widget _avatar(String nom, {bool admin = false, double taille = 30}) => Container(
        width: taille, height: taille, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: admin ? DzColors.lime : DzColors.card2,
          shape: BoxShape.circle,
        ),
        child: Text(nom.isEmpty ? '?' : nom.characters.first.toUpperCase(),
            style: TextStyle(
                color: admin ? DzColors.inkOnLime : DzColors.txt2,
                fontSize: taille * .38, fontWeight: FontWeight.w700)),
      );

  Widget _stat(String label, String valeur, {Color couleur = DzColors.txt, String? sous}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(color: DzColors.mut, fontSize: 9.5,
                    fontWeight: FontWeight.w700, letterSpacing: .8)),
            const SizedBox(height: 4),
            Text(valeur, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: couleur, fontSize: 16, fontWeight: FontWeight.w800)),
            if (sous != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(sous, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: DzColors.mut, fontSize: 10)),
              ),
          ]);

  Widget _jauge(double part, {Color? couleur}) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: part.clamp(0.0, 1.0),
          minHeight: 6,
          backgroundColor: DzColors.card2,
          valueColor: AlwaysStoppedAnimation(
              couleur ?? (part >= .95 ? DzColors.amber : DzColors.limeDim)),
        ),
      );

  Widget _vueListe() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: DzColors.lime,
        foregroundColor: DzColors.inkOnLime,
        icon: const Icon(Icons.add),
        label: const Text('Mission', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: DzColors.lime,
        onRefresh: _load,
        child: _error != null
            ? _ErrorView(msg: _error!, onRetry: _load)
            : _list == null
                ? const Center(child: CircularProgressIndicator(color: DzColors.lime))
                : LayoutBuilder(builder: (context, c) {
                    final wide = c.maxWidth > 900;
                    final missions = _filtrees;
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                      children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Missions',
                                      style: TextStyle(fontSize: 22,
                                          fontWeight: FontWeight.w800, letterSpacing: -.4)),
                                  Text('Un voyage, ses passagers, ses dépenses.',
                                      style: TextStyle(color: DzColors.mut, fontSize: 12.5)),
                                ]),
                          ),
                          if (wide) _segment(),
                        ]),
                        if (!wide) ...[
                          const SizedBox(height: 12),
                          Align(alignment: Alignment.centerLeft, child: _segment()),
                        ],
                        const SizedBox(height: 16),
                        _lab('${missions.length} mission(s)'),
                        const SizedBox(height: 10),
                        if (missions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                  'Aucune mission ici.\nCrée la première avec le bouton +.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: DzColors.mut, height: 1.6)),
                            ),
                          )
                        else
                          for (final s in missions) ...[
                            _carteMission(s as Map, wide),
                            const SizedBox(height: 12),
                          ],
                      ],
                    );
                  }),
      ),
    );
  }

  Widget _carteMission(Map s, bool wide) {
    final (etatLab, etatCol) = _etatDe(s);
    final passagers = (s['passagers'] as List?) ?? [];
    final capacite = _n(s['capacite']);
    final kg = _n(s['kg_total']);
    final libres = _n(s['kg_libres']);
    final benef = _n(s['benefice']);
    final seuil = _n(s['seuil_kg']);
    final jours = _joursAvant(s['depart']);
    final joursRetour = _joursAvant(s['retour']);

    final quand = s['etat'] == 'cloturee'
        ? 'clôturée'
        : jours != null && jours > 0
            ? 'départ dans $jours j'
            : joursRetour != null && joursRetour >= 0
                ? 'retour dans $joursRetour j'
                : '';

    final stats = [
      _stat('Bénéfice projeté',
          '${benef >= 0 ? '+ ' : '− '}${_f(benef.abs())} DA',
          couleur: benef >= 0 ? DzColors.lime : DzColors.red),
      _stat('Dépenses du voyage', '${_f(_n(s['total_da']))} DA',
          sous: _n(s['total_da']) > 0
              ? '${_f(_n(s['part']))} DA par personne' : 'aucune pour l’instant'),
      _stat('Kilo à viser',
          seuil > 0 ? '${_f(seuil)} DA/kg' : 'objectif atteint',
          couleur: seuil > 0 ? DzColors.amber : DzColors.lime,
          sous: seuil > 0 ? 'sur ${_kg(libres)} kg libres' : null),
    ];

    return Material(
      color: DzColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _ouvrir(_i(s['id'])),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                            '${s['vol'] ?? ''}'.isNotEmpty
                                ? '${s['vol']}' : 'Mission #${s['id']}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        if ('${s['vol'] ?? ''}'.isNotEmpty)
                          Text('#${s['id']}',
                              style: const TextStyle(color: DzColors.mut, fontSize: 12)),
                        _pastille(etatLab, etatCol),
                      ]),
                  const SizedBox(height: 4),
                  Text(
                      '${_dateFr(s['depart'])} → ${_dateFr(s['retour'])}'
                      ' · ${s['nb_membres']} passager(s)'
                      '${quand.isEmpty ? '' : ' · $quand'}',
                      style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                ]),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 30,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < passagers.length && i < 4; i++)
                    Transform.translate(
                      offset: Offset(-9.0 * i, 0),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                              BorderSide(color: DzColors.card, width: 2.5)),
                        ),
                        child: _avatar('${(passagers[i] as Map)['voyageur_nom']}',
                            admin: (passagers[i] as Map)['est_admin'] == true),
                      ),
                    ),
                  if (passagers.length > 4)
                    Transform.translate(
                      offset: const Offset(-36, 0),
                      child: Container(
                        width: 30, height: 30, alignment: Alignment.center,
                        decoration: const BoxDecoration(
                            color: DzColors.card2, shape: BoxShape.circle),
                        child: Text('+${passagers.length - 4}',
                            style: const TextStyle(color: DzColors.mut,
                                fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: wide
                  ? CrossAxisAlignment.end : CrossAxisAlignment.stretch,
              children: [
                _remplissage(kg, capacite, libres, large: wide),
                if (wide) const SizedBox(width: 24) else const SizedBox(height: 16),
                for (var i = 0; i < stats.length; i++) ...[
                  if (wide)
                    Expanded(child: stats[i])
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: stats[i],
                    ),
                  if (wide && i < stats.length - 1) const SizedBox(width: 18),
                ],
                if (wide)
                  const Padding(
                    padding: EdgeInsets.only(left: 6, bottom: 2),
                    child: Icon(Icons.chevron_right_rounded,
                        size: 20, color: DzColors.mut),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _remplissage(double kg, double capacite, double libres, {bool large = false}) {
    final part = capacite > 0 ? kg / capacite : 0.0;
    final contenu = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_kg(kg),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(width: 5),
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Text('/ ${_kg(capacite)} kg chargés',
              style: const TextStyle(color: DzColors.mut, fontSize: 11)),
        ),
        const Spacer(),
        Text(libres > 0 ? '${_kg(libres)} kg libres' : 'bagages pleins',
            style: TextStyle(
                color: libres > 0
                    ? (part >= .95 ? DzColors.amber : DzColors.lime) : DzColors.amber,
                fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 7),
      _jauge(part),
    ]);
    return large ? Expanded(flex: 3, child: contenu) : contenu;
  }

  Widget _vueMission() {
    final s = _ouvert;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: s == null
          ? Center(
              child: _chargeOuvert
                  ? const CircularProgressIndicator(color: DzColors.lime)
                  : TextButton(onPressed: _fermer, child: const Text('Retour aux missions')),
            )
          : RefreshIndicator(
              color: DzColors.lime,
              onRefresh: _rafraichirOuvert,
              child: LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth > 1000;
                final passagers = (s['passagers'] as List?) ?? [];
                final (etatLab, etatCol) = _etatDe(s);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                  children: [
                    Row(children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _fermer,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                          child: Text('Missions',
                              style: TextStyle(color: DzColors.mut, fontSize: 12)),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 15, color: DzColors.mut2),
                      Text(
                          '${s['vol'] ?? ''}'.isNotEmpty
                              ? '${s['vol']}' : 'Mission #${s['id']}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 10),
                    Builder(builder: (_) {
                      final titre = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                                Wrap(spacing: 11, runSpacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                          '${s['vol'] ?? ''}'.isNotEmpty
                                              ? '${s['vol']}' : 'Mission #${s['id']}',
                                          style: const TextStyle(fontSize: 22,
                                              fontWeight: FontWeight.w800, letterSpacing: -.4)),
                                      Text('#${s['id']}',
                                          style: const TextStyle(
                                              color: DzColors.mut, fontSize: 13)),
                                      _pastille(etatLab, etatCol),
                                    ]),
                                const SizedBox(height: 3),
                                Text(
                                    '${_dateFr(s['depart'])} → ${_dateFr(s['retour'])}'
                                    ' · ${s['nb_membres']} passager(s)',
                                    style: const TextStyle(
                                        color: DzColors.mut, fontSize: 12.5)),
                          ]);
                      final boutons = Row(mainAxisSize: MainAxisSize.min, children: [
                        _boutonSecondaire(
                            Icons.edit_calendar_outlined, 'Dates', _editerDates),
                        const SizedBox(width: 10),
                        _boutonPrincipal(Icons.add_rounded, 'Dépense', _ajouterDepense),
                      ]);
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Expanded(child: titre), boutons],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [titre, const SizedBox(height: 14), boutons],
                      );
                    }),
                    const SizedBox(height: 16),
                    if (wide)
                      IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(flex: 10, child: _carteDepenses(s)),
                          const SizedBox(width: 14),
                          Expanded(flex: 13, child: _statsMission(s)),
                        ]),
                      )
                    else ...[
                      _carteDepenses(s),
                      const SizedBox(height: 14),
                      _statsMission(s),
                    ],
                    const SizedBox(height: 22),
                    Row(children: [
                      _lab('Passagers · ${passagers.length}'),
                      const Spacer(),
                      const Text('un clic ouvre la fiche du passager',
                          style: TextStyle(color: DzColors.mut2, fontSize: 11)),
                    ]),
                    const SizedBox(height: 10),
                    for (final p in passagers) ...[
                      _tuilePassager(p as Map, wide),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              }),
            ),
    );
  }

  Widget _boutonPrincipal(IconData ic, String t, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
              color: DzColors.lime, borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic, size: 15, color: DzColors.inkOnLime),
            const SizedBox(width: 7),
            Text(t, style: const TextStyle(color: DzColors.inkOnLime,
                fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _boutonSecondaire(IconData ic, String t, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
              color: DzColors.card2, borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic, size: 15, color: DzColors.mut),
            const SizedBox(width: 7),
            Text(t, style: const TextStyle(color: DzColors.txt2,
                fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _carteDepenses(Map s) {
    final total = _n(s['total_da']);
    final nb = _i(s['nb_membres'], 1);
    final parType = (s['par_type'] as Map?) ?? {};
    const couleurs = {
      'hotel': DzChartColors.bleu,
      'nourriture': DzChartColors.violet,
      'transport': DzChartColors.menthe,
      'autre': DzChartColors.rose,
    };
    return Container(
      decoration: BoxDecoration(
          color: DzColors.card, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _lab('Dépenses du voyage')),
          if (total > 0)
            GestureDetector(
              onTap: _voirHistorique,
              child: const Text('Historique',
                  style: TextStyle(color: DzColors.lime,
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 14),
        if (total <= 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(children: [
              const Text('Aucune dépense sur place enregistrée.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DzColors.mut, fontSize: 12)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _ajouterDepense,
                child: const Text('Ajouter la première',
                    style: TextStyle(color: DzColors.lime,
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
          )
        else ...[
          Row(children: [
            DzDonut(
              taille: 108, epaisseur: 12,
              segments: [
                for (final k in couleurs.keys)
                  DzSegment(_n(parType[k]), couleurs[k]!),
              ],
              centre: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_f(total / (nb < 1 ? 1 : nb)),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const Text('DA chacun',
                    style: TextStyle(color: DzColors.mut, fontSize: 9)),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(children: [
                for (final k in couleurs.keys)
                  if (_n(parType[k]) > 0)
                    DzLegende(
                      couleur: couleurs[k]!,
                      libelle: libelleType(k),
                      valeur: _f(_n(parType[k])),
                      part: '${(_n(parType[k]) / total * 100).round()} %',
                    ),
              ]),
            ),
          ]),
          const Divider(color: DzColors.line, height: 22),
          Text(
              '${_f(total)} DA divisés entre les $nb passagers — ajoutés à leurs frais, '
              'le prix du kilo à viser monte d’autant.',
              style: const TextStyle(color: DzColors.mut2, fontSize: 11, height: 1.5)),
        ],
      ]),
    );
  }

  Widget _statsMission(Map s) {
    final benef = _n(s['benefice']);
    final objectif = _n(s['objectif']);
    final seuil = _n(s['seuil_kg']);
    final kg = _n(s['kg_total']);
    final capacite = _n(s['capacite']);

    Widget tuile(Widget enfant) => Expanded(
          child: Container(
            decoration: BoxDecoration(
                color: DzColors.card, borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            child: enfant,
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 10),
        child: _lab('La mission a-t-elle été rentable ?'),
      ),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        tuile(_stat('Bénéfice de la mission',
            '${benef >= 0 ? '+ ' : '− '}${_f(benef.abs())}',
            couleur: benef >= 0 ? DzColors.lime : DzColors.red,
            sous: objectif > 0
                ? 'objectif ${_f(objectif)} DA · ${benef >= objectif ? 'dépassé' : 'pas encore'}'
                : null)),
        const SizedBox(width: 12),
        tuile(_stat('Frais totaux', _f(_n(s['frais'])),
            sous: 'billets · démarches · douane · séjour')),
        ]),
      ),
      const SizedBox(height: 12),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        tuile(Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
              _lab('Remplissage'),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_kg(kg),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('/ ${_kg(capacite)} kg',
                      style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                ),
              ]),
              const SizedBox(height: 8),
              _jauge(capacite > 0 ? kg / capacite : 0),
            ])),
        const SizedBox(width: 12),
        tuile(_stat('Kilo à viser',
            seuil > 0 ? _f(seuil) : 'atteint',
            couleur: seuil > 0 ? DzColors.amber : DzColors.lime,
            sous: seuil > 0
                ? 'sur les ${_kg(_n(s['kg_libres']))} kg encore libres'
                : 'objectif couvert')),
        ]),
      ),
    ]);
  }

  Widget _tuilePassager(Map p, bool wide) {
    final kg = _n(p['kg_total']), capacite = _n(p['capacite']);
    final libres = _n(p['kg_libres']);
    final benef = _n(p['benefice']);
    final admin = p['est_admin'] == true;
    final sansCarte = p['sans_carte'] == true;
    final part = capacite > 0 ? kg / capacite : 0.0;

    final mention = admin
        ? 'rien de déclaré · commission 0'
        : sansCarte
            ? 'rien de déclaré · commission normale'
            : 'carte auto-entrepreneur';

    final identite = Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Flexible(
              child: Text('${p['voyageur_nom']}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            if (admin) ...[
              const SizedBox(width: 7),
              _badge('ADMIN', DzColors.lime),
            ] else if (sansCarte) ...[
              const SizedBox(width: 7),
              _badge('SANS CARTE', DzColors.amber),
            ],
          ]),
          const SizedBox(height: 2),
          Text('${p['code']} · $mention',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
        ]);

    final remplissage = Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_kg(kg),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 5),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text('/ ${_kg(capacite)} kg',
                  style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
            ),
          ]),
          const SizedBox(height: 6),
          _jauge(part),
        ]);

    final restants = Column(crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min, children: [
          Text('${_kg(libres)} kg',
              style: TextStyle(
                  color: libres <= 0
                      ? DzColors.amber
                      : part >= .95 ? DzColors.amber : DzColors.lime,
                  fontSize: 17, fontWeight: FontWeight.w800)),
          const Text('restants', style: TextStyle(color: DzColors.mut, fontSize: 9.5)),
        ]);

    final benefice = Column(crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min, children: [
          Text('${benef >= 0 ? '+ ' : '− '}${_f(benef.abs())} DA',
              style: TextStyle(
                  color: benef >= _n(p['objectif'])
                      ? DzColors.lime
                      : benef >= 0 ? DzColors.amber : DzColors.red,
                  fontSize: 14, fontWeight: FontWeight.w800)),
          const Text('bénéfice', style: TextStyle(color: DzColors.mut, fontSize: 9.5)),
        ]);

    return Material(
      color: DzColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => MissionDetailScreen(id: _i(p['id']))))
            .then((_) => _rafraichirOuvert()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: wide
              ? Row(children: [
                  _avatar('${p['voyageur_nom']}', admin: admin, taille: 38),
                  const SizedBox(width: 15),
                  SizedBox(width: 210, child: identite),
                  const SizedBox(width: 15),
                  Expanded(child: remplissage),
                  const SizedBox(width: 18),
                  SizedBox(width: 92, child: restants),
                  const SizedBox(width: 16),
                  Container(width: 1, height: 36, color: DzColors.line),
                  const SizedBox(width: 16),
                  SizedBox(width: 124, child: benefice),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, size: 19, color: DzColors.mut),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    _avatar('${p['voyageur_nom']}', admin: admin, taille: 38),
                    const SizedBox(width: 13),
                    Expanded(child: identite),
                    const Icon(Icons.chevron_right_rounded, size: 19, color: DzColors.mut),
                  ]),
                  const SizedBox(height: 14),
                  remplissage,
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: Align(alignment: Alignment.centerLeft, child: benefice),
                    ),
                    restants,
                  ]),
                ]),
        ),
      ),
    );
  }

  Future<void> _ajouterDepense() async {
    final s = _ouvert;
    if (s == null) return;
    List admins = [];
    try { admins = await Api.get('/admins') as List; } catch (_) {}
    if (!mounted) return;
    final ok = await montrerDepenseDialog(context, sejour: s, admins: admins);
    if (ok) await _rafraichirOuvert();
  }

  Future<void> _voirHistorique() async {
    final s = _ouvert;
    if (s == null) return;
    await montrerHistoriqueDepenses(context, sejour: s, onChange: _rafraichirOuvert);
    await _rafraichirOuvert();
  }

  Future<void> _editerDates() async {
    final s = _ouvert;
    if (s == null) return;
    final passagers = (s['passagers'] as List?) ?? [];
    if (passagers.isEmpty) return;

    final vol = TextEditingController(text: '${s['vol'] ?? ''}');
    DateTime? depart = DateTime.tryParse('${s['depart'] ?? ''}');
    DateTime? retour = DateTime.tryParse('${s['retour'] ?? ''}');
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          if (saving) return;
          if (depart == null) {
            ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Choisis au moins la date de départ.')));
            return;
          }
          if (retour != null && retour!.isBefore(depart!)) {
            ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Le retour ne peut pas précéder le départ.')));
            return;
          }
          setSt(() => saving = true);
          try {
            for (final p in passagers) {
              if ((p as Map)['statut'] == 'cloturee') continue;
              await Api.put('/missions/${p['id']}', {
                'vol': vol.text.trim(),
                'depart': isoDate(depart!),
                'retour': retour == null ? null : isoDate(retour!),
              });
            }
            if (ctx.mounted) Navigator.pop(ctx);
            await _rafraichirOuvert();
            await _load();
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
            }
          }
        }

        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Dates de la mission',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text(
                        'Appliqué à tous les passagers encore ouverts. Pour décaler une '
                        'seule personne, passe par sa fiche.',
                        style: TextStyle(color: DzColors.mut, fontSize: 11.5, height: 1.4)),
                    const SizedBox(height: 18),
                    TextField(
                      controller: vol,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'N° de vol / billet'),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: DzDateField(
                          label: 'Départ', value: depart,
                          onChanged: (d) => setSt(() => depart = d))),
                      const SizedBox(width: 12),
                      Expanded(child: DzDateField(
                          label: 'Retour', value: retour,
                          onChanged: (d) => setSt(() => retour = d))),
                    ]),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: saving ? null : save,
                      child: saving
                          ? const SizedBox(height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Enregistrer'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _openCreate() async {
    List<dynamic> voyageurs;
    List<dynamic> admins;
    try {
      voyageurs = await Api.get('/voyageurs') as List;
      admins = await Api.get('/admins') as List;
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (voyageurs.isEmpty && admins.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ajoute d’abord un voyageur.')));
      }
      return;
    }
    if (!mounted) return;

    final vol = TextEditingController(text: 'AH — CAN→ALG');
    DateTime depart = DateTime.now();
    DateTime? retour;
    final selected = <int>{};
    final selectedAdmins = <int>{};
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          if ((selected.isEmpty && selectedAdmins.isEmpty) || saving) return;
          setSt(() => saving = true);
          try {
            await Api.post('/missions', {
              'voyageur_ids': selected.toList(),
              'admin_user_ids': selectedAdmins.toList(),
              'vol': vol.text.trim(),
              'depart': isoDate(depart),
              'retour': retour == null ? null : isoDate(retour!),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(e.message), backgroundColor: const Color(0xFF3A1512)));
            }
          }
        }

        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min, children: [
                  const Text('Nouvelle mission',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 18),
                  TextField(textCapitalization: TextCapitalization.characters, controller: vol,
                      decoration: const InputDecoration(labelText: 'N° de vol / billet')),
                  const SizedBox(height: 16),
                  const Text('DATES DU VOL DES ADMINS',
                      style: TextStyle(color: DzColors.mut, fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: DzDateField(
                        label: 'Départ', value: depart,
                        onChanged: (d) => setSt(() => depart = d))),
                    const SizedBox(width: 12),
                    Expanded(child: DzDateField(
                        label: 'Retour', value: retour,
                        onChanged: (d) => setSt(() => retour = d))),
                  ]),
                  const SizedBox(height: 6),
                  const Text(
                      'Ce sont les dates du séjour. Un voyageur qui part plus tard ou '
                      'rentre plus tôt — tu ajustes ses dates sur sa fiche après.',
                      style: TextStyle(color: DzColors.mut, fontSize: 10.5, height: 1.4)),
                  const SizedBox(height: 20),
                  const Text('ADMINS DU VOYAGE',
                      style: TextStyle(color: DzColors.mut, fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  const Text(
                      'Coche qui part. Chaque admin coché a sa propre mission '
                      '(billet, démarches, valise) sans carte auto-entrepreneur.',
                      style: TextStyle(color: DzColors.mut, fontSize: 11)),
                  const SizedBox(height: 8),
                  ...admins.map((a) {
                    final id = _i(a['id']);
                    final on = selectedAdmins.contains(id);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: DzColors.lime,
                      checkColor: DzColors.inkOnLime,
                      value: on,
                      onChanged: (x) => setSt(() =>
                          x! ? selectedAdmins.add(id) : selectedAdmins.remove(id)),
                      title: Text('${a['nom']}',
                          style: const TextStyle(fontSize: 13.5, color: DzColors.txt)),
                      subtitle: const Text('admin — prend en charge les dépenses du séjour',
                          style: TextStyle(color: DzColors.mut, fontSize: 11)),
                    );
                  }),
                  if (selectedAdmins.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      decoration: BoxDecoration(
                          color: DzColors.card2,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Row(children: [
                        Icon(Icons.info_outline_rounded,
                            size: 16, color: DzColors.lime),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                              'Un admin est du voyage : plus d’argent de poche pour '
                              'personne. Les dépenses sur place (hôtel, nourriture, '
                              'transport) se divisent entre tous les membres du séjour '
                              'et font monter le prix du kilo à viser.',
                              style: TextStyle(color: DzColors.txt2,
                                  fontSize: 11, height: 1.45)),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text('ASSIGNER LES VOYAGEURS',
                      style: TextStyle(color: DzColors.mut, fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  const Text(
                      'Une fiche est créée pour chacun (sa valise, ses frais). Billet, '
                      'démarches, objectif et heures de vol s’ajoutent ensuite sur sa fiche.',
                      style: TextStyle(color: DzColors.mut, fontSize: 11)),
                  const SizedBox(height: 8),

                  ...voyageurs.map((v) {
                    final id = _i(v['id']);
                    final on = selected.contains(id);
                    final statut = '${v['statut_dispo'] ?? 'disponible'}';
                    final sansCarte = v['sans_carte'] == true;
                    final bloque = statut == 'indisponible'
                        || (statut == 'limite' && !sansCarte);
                    final motif = statut == 'limite'
                        ? 'limite atteinte — 2 missions ce mois'
                        : 'indisponible';
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: DzColors.lime,
                      checkColor: DzColors.inkOnLime,
                      value: on && !bloque,
                      enabled: !bloque,
                      onChanged: bloque ? null : (x) =>
                          setSt(() => x! ? selected.add(id) : selected.remove(id)),
                      title: Text('${v['nom']}',
                          style: TextStyle(fontSize: 13.5,
                              color: bloque ? DzColors.mut.withValues(alpha: .6) : DzColors.txt)),
                      subtitle: Text(
                          bloque
                              ? motif
                              : '${_i(v['bagages'], 2)} valise(s) → '
                                  '${_i(v['bagages'], 2) * 23} kg'
                                  '${sansCarte ? ' · sans carte' : ''}',
                          style: TextStyle(
                              color: bloque
                                  ? (statut == 'limite' ? DzColors.amber : DzColors.red)
                                      .withValues(alpha: .8)
                                  : DzColors.mut,
                              fontSize: 11)),
                    );
                  }),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(selected.isEmpty && selectedAdmins.isEmpty
                            ? 'Sélectionne au moins une personne'
                            : 'Créer ${selected.length + selectedAdmins.length} mission(s)'),
                  ),
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const _ErrorView({required this.msg, required this.onRetry});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.cloud_off, color: DzColors.mut.withValues(alpha: .6), size: 44),
          const SizedBox(height: 12),
          Center(child: Text(msg, textAlign: TextAlign.center,
              style: const TextStyle(color: DzColors.mut))),
          const SizedBox(height: 16),
          Center(child: TextButton(onPressed: onRetry, child: const Text('Réessayer'))),
        ],
      );
}
