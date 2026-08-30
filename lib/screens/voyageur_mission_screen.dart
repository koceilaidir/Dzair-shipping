import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/download.dart';
import '../services/upload.dart';
import '../theme.dart';
import '../widgets/charts.dart';

class VoyageurMissionScreen extends StatefulWidget {
  final int id;
  const VoyageurMissionScreen({super.key, required this.id});

  @override
  State<VoyageurMissionScreen> createState() => _VoyageurMissionScreenState();
}

class _VoyageurMissionScreenState extends State<VoyageurMissionScreen> {
  Map? _m;
  List? _factures;
  String? _error;

  static const _itemsDepart = [
    ('passeport', 'Passeport valide en poche'),
    ('autorisations', 'Autorisations ANAE imprimées'),
    ('carte_ae', 'Carte auto-entrepreneur'),
    ('argent_depose', 'Argent déposé dans les cartes'),
    ('enveloppe_douane', 'Enveloppe douane préparée (DA en liquide)'),
    ('sim', 'Puce SIM emportée'),
    ('vpn', 'VPN installé'),
    ('wechat_alipay', 'WeChat + Alipay authentifiés'),
    ('nourriture', 'Nourriture (5 jours)'),
  ];
  static const _itemsRetour = [
    ('factures_dl', 'Factures téléchargées (PDF)'),
    ('factures_cachet', 'Factures imprimées et cachetées'),
    ('factures_scan', 'Factures scannées'),
    ('factures_anae', 'Factures chargées sur le site ANAE'),
    ('qr_colles', 'Codes QR imprimés et collés sur les valises'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.round().toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  String _dateFr(dynamic d) {
    final s = '$d';
    return s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}' : '—';
  }

  Future<void> _load() async {
    try {
      final m = await Api.get('/missions/${widget.id}') as Map;
      if (mounted) setState(() => _m = m);
      try {
        final f = await Api.get('/factures?mission=${widget.id}') as List;
        if (mounted) setState(() => _factures = f);
      } catch (_) {}
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  List<Map> get _affSoute => ((_m?['affectations'] as List?) ?? [])
      .cast<Map>().where((a) => '${a['emplacement']}' != 'main').toList();
  List<Map> get _affMain => ((_m?['affectations'] as List?) ?? [])
      .cast<Map>().where((a) => '${a['emplacement']}' == 'main').toList();
  List<Map> get _tranches => ((_m?['tranches'] as List?) ?? []).cast<Map>();

  double _kg(List<Map> affs) =>
      affs.fold(0.0, (s, a) => s + _n(a['quantite']) * _n(a['poids_unit']));

  (double, int, DateTime)? get _volEnCours {
    final dec = DateTime.tryParse('${_m?['heure_decollage'] ?? ''}')?.toLocal();
    final duree = _n(_m?['duree_vol_min']).round();
    if (dec == null || duree <= 0) return null;
    final att = dec.add(Duration(minutes: duree));
    final now = DateTime.now();
    if (now.isBefore(dec) || now.isAfter(att)) return null;
    return (now.difference(dec).inMinutes / duree, att.difference(now).inMinutes, att);
  }

  Future<void> _toggleCheck(String champ, String cle, bool val) async {
    final map = Map<String, dynamic>.from((_m?[champ] as Map?) ?? {});
    map[cle] = val;
    try {
      await Api.put('/missions/${widget.id}', {champ: map});
      if (mounted) setState(() => _m![champ] = map);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _telechargerFactures() async {
    try {
      final bytes = await Api.getBytes('/factures/mission/${widget.id}/pdf');
      await saveFile('factures-${_m?['code']}.pdf', bytes);
    } catch (e) {
      _snack('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DzColors.bg,
      appBar: AppBar(
        backgroundColor: DzColors.bg,
        title: Text('${_m?['code'] ?? 'Mission'}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [if (_m != null) Padding(
            padding: const EdgeInsets.only(right: 14), child: _pastilleStatut())],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)))
          : _m == null
              ? const Center(child: CircularProgressIndicator(color: DzColors.lime))
              : RefreshIndicator(
                  color: DzColors.lime,
                  onRefresh: _load,
                  child: LayoutBuilder(builder: (context, c) {
                    final wide = c.maxWidth > 1000;
                    final gauche = Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _carteVol(),
                          _carteFrais(),
                          _carteArgentDepose(),
                          _carteValise(),
                          if (_m!['bagage_main'] == true) _carteBagageMain(),
                        ]);
                    final droite = Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _carteChecklist('Checklist avant départ', 'check_depart', _itemsDepart),
                          _carteFactures(),
                          _carteChecklist('Checklist avant le retour', 'check_retour', _itemsRetour),
                          if ('${_m!['statut']}' == 'cloturee') _carteRecap() else _carteArrivee(),
                        ]);
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        Text('${_m!['vol'] ?? ''} · ${_dateFr(_m!['depart'])}'
                            '${'${_m!['heure_depart'] ?? ''}'.isNotEmpty ? ' ${_m!['heure_depart']}' : ''}'
                            ' → ${_dateFr(_m!['retour'])} · ta mission',
                            style: const TextStyle(color: DzColors.mut, fontSize: 12)),
                        const SizedBox(height: 14),
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
                ),
    );
  }

  Widget _pastilleStatut() {
    final s = '${_m!['statut']}';
    final vol = _volEnCours;
    final (lab, c) = s == 'cloturee'
        ? ('Terminée', DzColors.mut)
        : vol != null
            ? ('En vol', DzColors.lime)
            : s == 'planifiee' ? ('Préparation', DzColors.amber) : ('En cours', DzColors.amber);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
          color: DzColors.card2, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(lab, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(l,
              style: const TextStyle(color: DzColors.mut, fontSize: 12.5))),
          Text(v, style: TextStyle(
              fontSize: gras ? 13.5 : 12.5,
              fontWeight: gras ? FontWeight.w800 : FontWeight.w600,
              color: c ?? DzColors.txt)),
        ]),
      );

  Widget _carteVol() {
    final hd = '${_m!['heure_depart'] ?? ''}';
    final ha = '${_m!['heure_arrivee'] ?? ''}';
    final vol = _volEnCours;
    return _carte('Ton vol', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('${_m!['vol'] ?? ''}',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
        if (vol != null)
          Text('${(vol.$1 * 100).round()} % · reste ≈ ${vol.$2 ~/ 60} h ${(vol.$2 % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(color: DzColors.lime, fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
      ]),
      if (vol != null) ...[
        const SizedBox(height: 8),
        DzVolProgress(progression: vol.$1),
      ],
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _ligne('Départ ${_dateFr(_m!['depart'])}', hd.isEmpty ? '—' : hd)),
        const SizedBox(width: 16),
        Expanded(child: _ligne('Arrivée', ha.isEmpty ? '—' : ha)),
      ]),
      _ligne('Retour prévu', _dateFr(_m!['retour'])),
    ]));
  }

  Widget _carteFrais() {
    final total = _n(_m!['billet']) + _n(_m!['dem_cout']) + _n(_m!['frais_visa']);
    return _carte('Frais avant départ', Column(children: [
      _ligne('Billet A/R', '${_f(_n(_m!['billet']))} DA'),
      _ligne('Démarches', '${_f(_n(_m!['dem_cout']))} DA'),
      _ligne('Dépôt de visa', '${_f(_n(_m!['frais_visa']))} DA'),
      const Divider(color: DzColors.line, height: 16),
      _ligne('Total', '${_f(total)} DA', gras: true),
    ]));
  }

  Widget _carteArgentDepose() {
    final depots = _tranches.where((t) => '${t['motif']}' == 'voyage').toList();
    if (depots.isEmpty) return const SizedBox.shrink();
    final total = depots.fold(0.0, (s, t) => s + _n(t['usd']));
    final devise = depots.isNotEmpty ? '${depots.first['devise'] ?? 'USD'}' : 'USD';
    return _carte('Argent déposé sur ton compte', Column(children: [
      for (final t in depots)
        _ligne('${_dateFr(t['created_at'])} · ${'${t['source'] ?? ''}'.isEmpty ? 'dépôt' : t['source']}',
            '${_f(_n(t['usd']))} ${t['devise'] ?? '\$'} × ${_n(t['taux']).toStringAsFixed(0)}'),
      const Divider(color: DzColors.line, height: 16),
      _ligne('Total déposé', '${_f(total)} $devise', gras: true, c: DzColors.lime),
    ]));
  }

  Widget _carteValise() {
    final affs = _affSoute;
    final kg = _kg(affs);
    final cap = _n(_m!['kg_soute']) +
        (_m!['valise_sup'] == true ? _n(_m!['valise_sup_kg']) : 0);
    return _carte('Ta valise — compte et vérifie', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: cap > 0 ? (kg / cap).clamp(0.0, 1.0).toDouble() : 0,
              minHeight: 6,
              backgroundColor: DzColors.card2,
              valueColor: const AlwaysStoppedAnimation(DzColors.limeDim),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('${kg.toStringAsFixed(1)} / ${cap.toStringAsFixed(0)} kg',
            style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
      ]),
      const SizedBox(height: 10),
      const Row(children: [
        Expanded(child: _Lab('Produit')),
        SizedBox(width: 52, child: _Lab('Qté', droite: true)),
        SizedBox(width: 72, child: _Lab('Déclaré', droite: true)),
        SizedBox(width: 62, child: _Lab('Poids', droite: true)),
      ]),
      if (affs.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Valise vide pour l’instant.',
              style: TextStyle(color: DzColors.mut, fontSize: 12)),
        ),
      for (final a in affs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3.5),
          child: Row(children: [
            Expanded(child: Text.rich(TextSpan(children: [
              TextSpan(text: '${a['produit']}', style: const TextStyle(fontSize: 12.5)),
              if (_n(a['saisis']) > 0)
                TextSpan(text: '  · ${_f(_n(a['saisis']))} saisie(s)',
                    style: const TextStyle(color: DzColors.red, fontSize: 10.5)),
            ]))),
            SizedBox(width: 52, child: Text('${_f(_n(a['quantite']))}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: DzColors.mut, fontSize: 11.5))),
            SizedBox(width: 72, child: Text(
                _n(a['prix_declare']) > 0
                    ? '${_n(a['prix_declare']).toStringAsFixed(2)} \$' : '—',
                textAlign: TextAlign.right,
                style: const TextStyle(color: DzColors.mut, fontSize: 11.5))),
            SizedBox(width: 62, child: Text(
                '${(_n(a['quantite']) * _n(a['poids_unit'])).toStringAsFixed(1)} kg',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
        ),
      const Divider(color: DzColors.line, height: 16),
      const Text('Lecture seule — les prix affichés sont ceux déclarés sur les factures. '
          'Un doute sur une pièce ? Écris à l’admin.',
          style: TextStyle(color: DzColors.mut2, fontSize: 10.5)),
    ]));
  }

  Widget _carteBagageMain() {
    final affs = _affMain;
    final kg = _kg(affs);
    final cap = _n(_m!['bagage_main_kg']);
    return _carte('Ton bagage à main', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: cap > 0 ? (kg / cap).clamp(0.0, 1.0).toDouble() : 0,
              minHeight: 6,
              backgroundColor: DzColors.card2,
              valueColor: const AlwaysStoppedAnimation(DzColors.limeDim),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('${kg.toStringAsFixed(1)} / ${cap.toStringAsFixed(0)} kg',
            style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
      ]),
      const SizedBox(height: 8),
      for (final a in affs)
        _ligne('${a['produit']} · ${_f(_n(a['quantite']))} pc',
            '${(_n(a['quantite']) * _n(a['poids_unit'])).toStringAsFixed(1)} kg'),
    ]));
  }

  Widget _carteChecklist(String titre, String champ, List<(String, String)> items) {
    final map = (_m![champ] as Map?) ?? {};
    final faits = items.where((i) => map[i.$1] == true).length;
    return _carte('$titre · $faits/${items.length}', Column(children: [
      for (var i = 0; i < items.length; i++)
        InkWell(
          onTap: '${_m!['statut']}' == 'cloturee'
              ? null
              : () => _toggleCheck(champ, items[i].$1, map[items[i].$1] != true),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: i == 0 ? null : const BoxDecoration(
                border: Border(top: BorderSide(color: DzColors.line))),
            child: Row(children: [
              Container(
                width: 17, height: 17, alignment: Alignment.center,
                decoration: map[items[i].$1] == true
                    ? BoxDecoration(color: DzColors.limeDim,
                        borderRadius: BorderRadius.circular(5))
                    : BoxDecoration(
                        border: Border.all(color: DzColors.mut2, width: 1.5),
                        borderRadius: BorderRadius.circular(5)),
                child: map[items[i].$1] == true
                    ? const Icon(Icons.check_rounded, size: 12, color: DzColors.inkOnLime)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(items[i].$2,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: map[items[i].$1] == true ? DzColors.txt2 : DzColors.mut))),
            ]),
          ),
        ),
    ]));
  }

  Widget _carteFactures() {
    final fs = (_factures ?? []).cast<Map>();
    return _carte('Tes factures', Column(children: [
      if (fs.isEmpty)
        const Text('Pas encore de facture — l’admin les génère quand ta valise est complète.',
            style: TextStyle(color: DzColors.mut, fontSize: 12))
      else ...[
        for (final f in fs)
          _ligne('Facture n° ${f['numero']} · ${_dateFr(f['date'])}',
              _n(f['total']) > 0
                  ? '${_n(f['total']).toStringAsFixed(2)} ${f['devise'] == 'EUR' ? '€' : '\$'}'
                  : ''),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _telechargerFactures,
          icon: const Icon(Icons.download_rounded, size: 15),
          label: const Text('Télécharger (PDF)', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 4),
        const Text('Imprime-les : ce sont elles que tu montres à la douane.',
            style: TextStyle(color: DzColors.mut2, fontSize: 10.5)),
      ],
    ]));
  }

  Widget _carteArrivee() {
    if (_m!['taxes_reelles'] != null) {
      final restes = _tranches.where((t) => '${t['motif']}' == 'reste').toList();
      return _carte('Arrivée — enregistrée', Column(children: [
        _ligne('Taxes payées à la douane', '${_f(_n(_m!['taxes_reelles']))} DA'),
        if (_n(_m!['frais_taxi']) > 0)
          _ligne('Frais de taxi', '${_f(_n(_m!['frais_taxi']))} DA'),
        for (final t in restes)
          _ligne('Restant · ${'${t['source'] ?? ''}'.isEmpty ? t['devise'] : t['source']}',
              '${_f(_n(t['usd']))} ${t['devise']}'),
        if ('${_m!['arrivee_note'] ?? ''}'.isNotEmpty)
          _ligne('Note', '${_m!['arrivee_note']}'),
        if (_m!['arrivee_photo'] == true)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.photo_camera_outlined, size: 14, color: DzColors.limeDim),
              SizedBox(width: 7),
              Text('Photo du bon de douane jointe ✓',
                  style: TextStyle(color: DzColors.limeDim, fontSize: 11.5)),
            ]),
          ),
      ]));
    }
    return _carte('Arrivée — à remplir à la douane', _FormArrivee(
      missionId: widget.id,
      produits: _affSoute,
      onFini: _load,
    ));
  }

  Widget _carteRecap() {
    final gain = _n(_m!['commission']) + _n(_m!['primes']);
    final restes = _tranches.where((t) => '${t['motif']}' == 'reste').toList();
    return _carte('Ton récap de mission', Column(children: [
      _ligne('Clôturée le', _dateFr(_m!['cloture_date'])),
      _ligne('Kilos ramenés', '${_n(_m!['kg_total']).toStringAsFixed(1)} kg'),
      const Divider(color: DzColors.line, height: 16),
      _ligne('Ta commission + primes', '${_f(gain)} DA', gras: true, c: DzColors.lime),
      _ligne(_m!['commission_versee'] == true ? 'Statut' : 'Statut',
          _m!['commission_versee'] == true ? 'reçue ✓' : 'à recevoir',
          c: _m!['commission_versee'] == true ? DzColors.limeDim : DzColors.amber),
      for (final t in restes)
        _ligne('Reste rendu · ${'${t['source'] ?? ''}'.isEmpty ? t['devise'] : t['source']}',
            '${_f(_n(t['usd']))} ${t['devise']}'),
    ]));
  }
}

class _Lab extends StatelessWidget {
  final String t;
  final bool droite;
  const _Lab(this.t, {this.droite = false});
  @override
  Widget build(BuildContext context) => Text(t.toUpperCase(),
      textAlign: droite ? TextAlign.right : TextAlign.left,
      style: const TextStyle(color: DzColors.mut, fontSize: 9.5,
          fontWeight: FontWeight.w700, letterSpacing: .8));
}

class _FormArrivee extends StatefulWidget {
  final int missionId;
  final List<Map> produits;
  final VoidCallback onFini;
  const _FormArrivee({required this.missionId, required this.produits, required this.onFini});

  @override
  State<_FormArrivee> createState() => _FormArriveeState();
}

class _FormArriveeState extends State<_FormArrivee> {
  final _taxes = TextEditingController();
  final _taxi = TextEditingController();
  final _note = TextEditingController();
  final _restes = <(double, String, double, String)>[];
  final _saisis = <int, double>{};
  (List<int>, String)? _photo;
  String? _photoNom;
  bool _envoi = false;

  double _n(String s) =>
      num.tryParse(s.replaceAll(' ', '').replaceAll(',', '.'))?.toDouble() ?? 0;
  String _f(num n) => n.round().toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _ajouterReste() async {
    final montant = TextEditingController();
    final taux = TextEditingController();
    final support = TextEditingController(text: 'cash');
    var devise = 'USD';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: DzColors.card,
        title: const Text('Argent restant', style: TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            for (final d in ['USD', 'EUR', 'RMB', 'DA'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setD(() => devise = d),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: devise == d ? DzColors.lime : DzColors.card2,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(d, style: TextStyle(
                        color: devise == d ? DzColors.inkOnLime : DzColors.txt2,
                        fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: montant, autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Montant restant')),
          if (devise != 'DA') ...[
            const SizedBox(height: 10),
            TextField(controller: taux,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Taux (DA / 1 $devise)')),
          ],
          const SizedBox(height: 10),
          TextField(controller: support,
              decoration: const InputDecoration(
                  labelText: 'Support (cash, Alipay, carte…)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final m = _n(montant.text);
              final t = devise == 'DA' ? 1.0 : _n(taux.text);
              if (m <= 0 || t <= 0) return;
              setState(() => _restes.add((m, devise, t, support.text.trim())));
              Navigator.pop(ctx);
            },
            child: const Text('Ajouter'),
          ),
        ],
      )),
    );
  }

  Future<void> _declarerSaisie() async {
    if (widget.produits.isEmpty) {
      _snack('Aucun produit dans la valise.');
      return;
    }
    Map sel = widget.produits.first;
    final qte = TextEditingController(text: '1');
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: DzColors.card,
        title: const Text('Saisie à la douane', style: TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            initialValue: sel['id'] as int,
            dropdownColor: DzColors.card2,
            decoration: const InputDecoration(labelText: 'Produit'),
            items: [
              for (final p in widget.produits)
                DropdownMenuItem(value: p['id'] as int,
                    child: Text('${p['produit']}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setD(() =>
                sel = widget.produits.firstWhere((p) => p['id'] == v)),
          ),
          const SizedBox(height: 10),
          TextField(controller: qte, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantité saisie')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final n = _n(qte.text);
              if (n <= 0) return;
              setState(() => _saisis[sel['id'] as int] = n);
              Navigator.pop(ctx);
            },
            child: const Text('Déclarer'),
          ),
        ],
      )),
    );
  }

  Future<void> _prendrePhoto() async {
    final img = await pickImage();
    if (img == null || !mounted) return;
    final (bytes, mime) = await compresserImage(img.$1, img.$2, maxCote: 1600);
    if (!mounted) return;
    setState(() {
      _photo = (bytes, mime);
      _photoNom = img.$3;
    });
  }

  Future<void> _enregistrer() async {
    final taxes = _n(_taxes.text);
    if (_taxes.text.trim().isEmpty) {
      _snack('Indique les taxes payées à la douane (mets 0 si aucune).');
      return;
    }
    setState(() => _envoi = true);
    try {
      for (final r in _restes) {
        await Api.post('/missions/${widget.missionId}/tranches', {
          'montant': r.$1, 'devise': r.$2, 'taux': r.$3,
          'motif': 'reste', 'source': r.$4,
        });
      }
      await Api.post('/missions/${widget.missionId}/arrivee', {
        'taxes_reelles': taxes,
        'frais_taxi': _n(_taxi.text),
        'note': _note.text.trim(),
        'saisis': [
          for (final e in _saisis.entries)
            {'affectation_id': e.key, 'quantite': e.value},
        ],
      });
      if (_photo != null) {
        await Api.post('/missions/${widget.missionId}/arrivee/photo', {
          'data': base64Encode(_photo!.$1),
          'mime': _photo!.$2,
        });
      }
      widget.onFini();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: TextField(controller: _taxes,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Taxes douane (DA)'))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _taxi,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Frais de taxi (DA)'))),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _note,
          decoration: const InputDecoration(labelText: 'Note (facultatif)')),
      const SizedBox(height: 12),
      if (_restes.isNotEmpty) ...[
        for (var i = 0; i < _restes.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(
                  'Restant · ${_restes[i].$4.isEmpty ? _restes[i].$2 : _restes[i].$4}',
                  style: const TextStyle(color: DzColors.mut, fontSize: 12))),
              Text('${_f(_restes[i].$1)} ${_restes[i].$2}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              IconButton(
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                onPressed: () => setState(() => _restes.removeAt(i)),
                icon: const Icon(Icons.close_rounded, size: 14, color: DzColors.mut),
              ),
            ]),
          ),
        const SizedBox(height: 6),
      ],
      for (final e in _saisis.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(
                'Saisie · ${widget.produits.firstWhere((p) => p['id'] == e.key, orElse: () => {'produit': '?'})['produit']}',
                style: const TextStyle(color: DzColors.red, fontSize: 12))),
            Text('${e.value.toStringAsFixed(0)} pc',
                style: const TextStyle(color: DzColors.red, fontSize: 12,
                    fontWeight: FontWeight.w600)),
            IconButton(
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              onPressed: () => setState(() => _saisis.remove(e.key)),
              icon: const Icon(Icons.close_rounded, size: 14, color: DzColors.mut),
            ),
          ]),
        ),
      Wrap(spacing: 8, runSpacing: 6, children: [
        OutlinedButton.icon(
          onPressed: _ajouterReste,
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.payments_outlined, size: 14),
          label: const Text('Argent restant', style: TextStyle(fontSize: 11.5)),
        ),
        OutlinedButton.icon(
          onPressed: _declarerSaisie,
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.warning_amber_rounded, size: 14),
          label: const Text('Déclarer une saisie', style: TextStyle(fontSize: 11.5)),
        ),
        OutlinedButton.icon(
          onPressed: _prendrePhoto,
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.photo_camera_outlined, size: 14),
          label: Text(_photo == null ? 'Photo du bon' : 'Photo ✓ ${_photoNom ?? ''}',
              style: const TextStyle(fontSize: 11.5)),
        ),
      ]),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _envoi ? null : _enregistrer,
        icon: _envoi
            ? const SizedBox(width: 15, height: 15,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check_rounded, size: 16),
        label: const Text('Enregistrer l’arrivée'),
      ),
      const SizedBox(height: 6),
      const Text('Tes saisies sont enregistrées directement et tracées — l’admin peut les ajuster.',
          style: TextStyle(color: DzColors.mut2, fontSize: 10)),
    ]);
  }
}
