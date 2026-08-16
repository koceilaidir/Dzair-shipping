import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';
import '../widgets/inventaire_picker.dart';

/// Détail d'une mission — structure v7 :
/// KPIs · ((Dépenses + Argent déposé BEA) ‖ Check départ) · Statut de vol ·
/// Prix du kilo · Valise · Check retour · Clôture.
/// La marchandise n'est JAMAIS une dépense (argent déplacé puis revendu) ;
/// ses seules dépenses = ses taxes de déplacement : douane (avance 5,5 %)
/// + taxes de carte au retrait (potentielles = tout le dépôt retiré).
class MissionDetailScreen extends StatefulWidget {
  final int id;
  final bool embedded;
  final VoidCallback? onBack;
  const MissionDetailScreen(
      {super.key, required this.id, this.embedded = false, this.onBack});

  @override
  State<MissionDetailScreen> createState() => _MissionDetailScreenState();
}

class _MissionDetailScreenState extends State<MissionDetailScreen> {
  Map? _m;
  Map? _reglages;
  String? _error;
  // Cartes « avant le départ » rangées (repliées) — possible dès que le check est complet.
  bool _avantDepartRange = false;
  bool _rangeAuto = false; // on replie automatiquement une seule fois, au 1er chargement prêt
  bool _formLibre = false; // formulaire « produit hors inventaire » déplié
  final _nom = TextEditingController();
  final _kg = TextEditingController();
  final _prix = TextEditingController();

  // Check départ = documents/argent + rappels matériels ; certains cochés automatiquement.
  static const _itemsDepart = [
    ('passeport', 'Passeport valide en poche', true),
    ('autorisations', 'Autorisations ANAE imprimées', false),
    ('carte_ae', 'Carte auto-entrepreneur', false),
    ('argent_depose', 'Argent déposé dans les cartes', false),
    ('sim', 'Puce SIM emportée', false),
    ('vpn', 'VPN installé', false),
    ('wechat_alipay', 'WeChat + Alipay authentifiés', false),
    ('nourriture', 'Nourriture (5 jours)', false),
  ];
  static const _itemsRetour = [
    ('factures_anae', 'Factures chargées sur le site ANAE', false),
    ('qr_colles', 'Codes QR imprimés et collés sur les valises', false),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([
        Api.get('/missions/${widget.id}'),
        Api.get('/reglages'),
      ]);
      if (!mounted) return;
      setState(() {
        _m = res[0] as Map;
        _reglages = res[1] as Map;
        // 1er chargement d'une fiche déjà prête → cartes avant-départ rangées d'office.
        if (!_rangeAuto) {
          _rangeAuto = true;
          if (_departComplet && _m!['statut'] != 'cloturee') _avantDepartRange = true;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /* ---------- Calculs — IDENTIQUES au serveur (missions.js) ---------- */
  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  List get _tr => (_m!['tranches'] as List?) ?? [];
  List get _trVoyage => _tr.where((t) => '${t['motif']}' != 'poche').toList();
  List get _trPoche => _tr.where((t) => '${t['motif']}' == 'poche').toList();
  double get _perDiem => _n(_m!['jours']) * _n(_m!['budget_jour']);
  // Argent de poche réel (tranches) — remplace la prévision jours × budget dès qu'il existe.
  double get _pocheDA =>
      _trPoche.fold(0.0, (s, t) => s + _n(t['usd']) * _n(t['taux']));
  double get _poche => _pocheDA > 0 ? _pocheDA : _perDiem;
  // Marchandise (motif 'voyage') : de l'argent DÉPLACÉ, jamais une dépense.
  // Ses seules dépenses = ses taxes de déplacement (douane + taxes de carte).
  double get _marchandiseDA =>
      _trVoyage.fold(0.0, (s, t) => s + _n(t['usd']) * _n(t['taux']));
  double get _marchandiseDevise => _trVoyage.fold(0.0, (s, t) => s + _n(t['usd']));
  // Lecture d'un réglage (0 si absent) — sans `?[` : ambigu pour le parseur
  // Dart à l'intérieur d'un ternaire.
  double _rg(String cle) => _reglages == null ? 0 : _n(_reglages![cle]);
  double get _tauxMoyen {
    if (_marchandiseDevise > 0) return _marchandiseDA / _marchandiseDevise;
    final t = _rg('taux_officiel');
    return t > 0 ? t : 150;
  }
  // Taux du marché PARALLÈLE (réglages) pour la devise du compte — c'est à ce taux
  // que les taxes de carte coûtent vraiment. Repli : taux moyen des tranches.
  double get _tauxParallele {
    final t = _rg(_devise == 'EUR' ? 'taux_parallele_eur' : 'taux_parallele_usd');
    return t > 0 ? t : _tauxMoyen;
  }
  double get _pctCarte => _rg('frais_carte_pct') / 100;
  bool get _facturee => _m!['statut'] == 'cloturee' && _m!['factures_total'] != null;
  double get _tauxOfficiel {
    final t = _rg('taux_officiel');
    return t > 0 ? t : 135;
  }
  // Taxes de carte (= « frais de carte », une seule et même chose) :
  // potentielles = si TOUT le dépôt est retiré — réelles sur factures à la clôture.
  double get _taxesCarte => (_facturee
          ? _n(_m!['factures_total']) : _marchandiseDevise) * _pctCarte * _tauxParallele;
  // Douane calculée EN DIRECT sur le dépôt carte (5,5 % au taux officiel) tant que la
  // mission n'est pas clôturée — jamais dépendante d'une vieille valeur stockée.
  double get _douane => _m!['statut'] == 'cloturee'
      ? _n(_m!['douane'])
      : _marchandiseDevise * _tauxOfficiel * 0.055;
  // Valeur déclarée en douane : automatique — factures × taux officiel à la clôture,
  // sinon estimation sur le dépôt carte.
  double get _valDeclaree => _facturee
      ? _n(_m!['val_declaree'])
      : _marchandiseDevise * _tauxOfficiel;
  double get _frais => _n(_m!['billet']) + _n(_m!['dem_cout']) + _n(_m!['frais_visa']) +
      _poche + _douane + _taxesCarte + _n(_m!['autres']) + _n(_m!['manques_da']);
  double get _cap => _n(_m!['kg_soute']) + (_m!['cabine'] == true ? 10 : 0);
  // Valise = produits libres + produits venus de l'inventaire (affectations).
  List get _aff => (_m!['affectations'] as List?) ?? [];
  double get _used => (_m!['produits'] as List).fold(0.0, (s, p) => s + _n(p['kg'])) +
      _aff.fold(0.0, (s, a) => s + _n(a['quantite']) * _n(a['poids_unit']));
  double get _revenu => (_m!['produits'] as List)
      .fold(0.0, (s, p) => s + _n(p['kg']) * _n(p['prix_kg'])) +
      _aff.fold(0.0, (s, a) => s + _n(a['quantite']) * _n(a['gain_piece']));
  double get _benef => _revenu - _frais;
  double get _obj => _n(_m!['objectif']);
  // Le kilo couvre les dépenses (taxes de déplacement incluses) + l'objectif —
  // JAMAIS l'argent de la marchandise lui-même.
  double get _pkMin => _cap > 0 ? (_frais + _obj) / _cap : 0;
  String get _devise => '${_m!['v_devise'] ?? 'USD'}';
  double get _soldeDevises => _n(_m!['v_solde']);

  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  String _sym(String d) => d == 'EUR' ? '€' : d == 'RMB' ? '¥' : d == 'DA' ? 'DA' : '\$';
  // Format des montants : le total D'ABORD, la devise APRÈS (2 000 $, pas $ 2 000).
  String _mnt(num n, String devise) => '${_f(n)} ${_sym(devise)}';

  String _demLabel(dynamic t) => switch ('$t') {
        'premiere' => 'Première demande',
        'renouvellement' => 'Renouvellement',
        'visa_double' => 'Visa double entrée',
        _ => 'Visa multiple',
      };

  /* ---------- Actions valise ---------- */
  Future<void> _addProduit() async {
    final nom = _nom.text.trim();
    final kg = num.tryParse(_kg.text);
    final prix = num.tryParse(_prix.text);
    if (nom.isEmpty || kg == null || prix == null) return;
    try {
      await Api.post('/missions/${widget.id}/produits',
          {'nom': nom, 'kg': kg, 'prix_kg': prix});
      _nom.clear(); _kg.clear(); _prix.clear();
      _load();
    } on ApiException catch (e) { _snack(e.message); }
  }

  Future<void> _delProduit(int pid) async {
    await Api.delete('/missions/${widget.id}/produits/$pid');
    _load();
  }

  Future<void> _delAffectation(dynamic id) async {
    try {
      await Api.delete('/inventaire/affectations/$id');
      _load();
    } on ApiException catch (e) { _snack(e.message); }
  }

  Future<void> _toggleValiseClose() async {
    try {
      await Api.put('/missions/${widget.id}', {'valise_close': !_valiseClose});
      _load();
    } on ApiException catch (e) { _snack(e.message); }
  }

  Future<void> _toggleCabine() async {
    await Api.put('/missions/${widget.id}', {'cabine': _m!['cabine'] != true});
    _load();
  }

  Future<void> _toggleCheck(String champ, String cle, bool val) async {
    final cur = Map<String, dynamic>.from(_m![champ] as Map? ?? {});
    cur[cle] = val;
    setState(() => _m![champ] = cur);
    try {
      await Api.put('/missions/${widget.id}',
          {champ: cur.map((k, v) => MapEntry(k, v == true))});
    } on ApiException catch (e) { _snack(e.message); _load(); }
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _supprimer() async {
    final closed = _m!['statut'] == 'cloturee';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c2) => AlertDialog(
        backgroundColor: DzColors.card,
        title: Text('Supprimer ${_m!['code']} ?', style: const TextStyle(fontSize: 16)),
        content: Text(
            closed
                ? '⚠ Cette mission est CLÔTURÉE : son bénéfice, ses paiements et sa '
                  'commission disparaîtront de toute la comptabilité, définitivement.'
                : 'La mission et sa valise seront supprimées définitivement, '
                  'sans laisser de trace dans la compta.',
            style: const TextStyle(color: DzColors.mut, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c2, true),
              child: const Text('Supprimer', style: TextStyle(color: DzColors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await Api.delete('/missions/${widget.id}');
      if (!mounted) return;
      // Mission clôturée : peut nécessiter l'accord de l'autre admin.
      if (res is Map && res['supprimee'] == false) {
        _snack('${res['message'] ?? 'En attente de validation de l’autre admin.'}');
        return;
      }
      widget.embedded ? widget.onBack?.call() : Navigator.pop(context);
    } on ApiException catch (e) { _snack(e.message); }
  }

  /* ---------- Structure ---------- */
  bool get _pret {
    if (_m == null || _m!['statut'] == 'cloturee') return false;
    return (_m!['produits'] as List).isNotEmpty && _benef >= _obj && _used <= _cap;
  }

  Widget get _statusChild => _error != null
      ? Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)))
      : (_m == null || _reglages == null)
          ? const Center(child: CircularProgressIndicator(color: DzColors.lime))
          : _body();

  Widget get _titleRow {
    final title = _m == null ? 'Mission' : '${_m!['code']} · ${_m!['voyageur_nom']}';
    final closed = _m?['statut'] == 'cloturee';
    final (label, col) = closed
        ? ('✓ Clôturée', DzColors.mut)
        : _m == null
            ? ('…', DzColors.mut)
            : _pret ? ('● Prêt', DzColors.lime) : ('● En cours', DzColors.amber);
    return Row(children: [
      Flexible(child: Text(title, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      const SizedBox(width: 10),
      if (_m != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
              color: col.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)),
          child: Text(label, style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
    ]);
  }

  Widget? get _deleteButton => _m == null ? null : IconButton(
        onPressed: _supprimer,
        tooltip: 'Supprimer la mission',
        icon: const Icon(Icons.delete_outline, color: DzColors.red, size: 19),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
          child: Row(children: [
            IconButton(onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back, color: DzColors.mut, size: 20)),
            const SizedBox(width: 4),
            Expanded(child: _titleRow),
            if (_deleteButton != null) _deleteButton!,
          ]),
        ),
        Expanded(child: _statusChild),
      ]);
    }
    return Scaffold(
      appBar: AppBar(backgroundColor: DzColors.bg, title: _titleRow,
          actions: [if (_deleteButton != null) _deleteButton!, const SizedBox(width: 6)]),
      body: _statusChild,
    );
  }

  Widget _body() {
    final m = _m!;
    final closed = m['statut'] == 'cloturee';
    final over = _valDeclaree > 1800000;
    final wide = MediaQuery.of(context).size.width >= 850;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 32), children: [
      Text('${m['vol'] ?? ''} · ${dateFr(m['depart'])} → ${dateFr(m['retour'])} · '
          '${m['jours']} j · compte ${_devise}',
          style: const TextStyle(color: DzColors.mut, fontSize: 12)),
      const SizedBox(height: 12),

      if (over)
        _banner(DzColors.red, '⚖ Valeur déclarée > 1 800 000 DA — mission illégale en l’état.'),

      // ---- KPIs raffinés ----
      _kpiRow(),
      const SizedBox(height: 12),

      // ---- (Dépenses ↑ + Argent déposé BEA ↓) ‖ Check départ ----
      // IntrinsicHeight + stretch : le check s'étire à la hauteur de la colonne de gauche.
      // Dès que le check départ est complet, les trois cartes peuvent se RANGER
      // (repliées sur une ligne de résumé) pour laisser la place à la suite.
      if (_avantDepartRange)
        _avantDepartRangeRow(wide)
      else if (wide)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Column(children: [
                _sectionDepenses(closed),
                const SizedBox(height: 12),
                Expanded(child: _sectionBea(closed)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(child: _checklist('Check avant le départ', 'check_depart',
                _itemsDepart, auto: _autoDepart())),
          ]),
        )
      else ...[
        _sectionDepenses(closed),
        const SizedBox(height: 12),
        _sectionBea(closed),
        const SizedBox(height: 12),
        _checklist('Check avant le départ', 'check_depart', _itemsDepart, auto: _autoDepart()),
      ],
      const SizedBox(height: 12),

      // ---- Statut du vol ----
      _sectionVol(closed),
      const SizedBox(height: 12),

      // ---- Prix du kilo minimum ----
      _sectionPrixKilo(),
      const SizedBox(height: 12),

      // ---- Valise ----
      _sectionValise(closed),
      const SizedBox(height: 12),

      // ---- Check avant le retour ----
      _checklist('Check avant le retour', 'check_retour', _itemsRetour),
      const SizedBox(height: 16),

      if (!closed) ...[
        FilledButton(onPressed: _valiseClose ? _openCloture : null,
            child: const Text('■ Clôturer la mission')),
        if (!_valiseClose)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Center(child: Text('Déclare la valise complète pour pouvoir clôturer.',
                style: TextStyle(color: DzColors.mut, fontSize: 11))),
          ),
      ],
      if (closed) _clotureRecap(),
    ]);
  }

  /* ---------- KPIs : dépenses · marchandise · revenu · bénéfice ----------
     Design : icône dans une pastille teintée, grande valeur avec l'unité en
     retrait, libellé discret. La carte Bénéfice — LA carte importante — est
     teintée à sa couleur et porte une mini-jauge vers l'objectif. */
  Widget _kpiRow() {
    final colBenef =
        _benef >= _obj ? DzColors.lime : _benef >= 0 ? DzColors.amber : DzColors.red;

    Widget kpi({
      required String label,
      required String valeur,
      required String unite,
      required IconData icone,
      Color accent = DzColors.mut,
      Color valCol = DzColors.txt,
      bool hero = false,
      double? jauge,
      String? sousLabel,
    }) =>
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: hero ? Color.alphaBlend(accent.withValues(alpha: .07), DzColors.card)
                        : DzColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: hero ? accent.withValues(alpha: .38) : DzColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 28, height: 28, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: hero ? .16 : .10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icone, size: 15,
                    color: hero ? accent : DzColors.mut),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(label.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: DzColors.mut, fontSize: 8.5,
                        fontWeight: FontWeight.w700, letterSpacing: .8)),
              ),
            ]),
            const SizedBox(height: 12),
            FittedBox(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: valeur,
                    style: TextStyle(color: valCol, fontSize: 21,
                        fontWeight: FontWeight.w800, height: 1)),
                TextSpan(text: '  $unite',
                    style: const TextStyle(color: DzColors.mut, fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ])),
            ),
            if (sousLabel != null) ...[
              const SizedBox(height: 3),
              Text(sousLabel,
                  style: const TextStyle(color: DzColors.mut, fontSize: 9.5)),
            ],
            if (jauge != null) ...[
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: jauge.clamp(0, 1).toDouble(),
                  minHeight: 3.5,
                  backgroundColor: DzColors.card2,
                  color: accent,
                ),
              ),
            ],
          ]),
        );

    final cards = [
      kpi(label: 'Dépenses', valeur: _f(_frais), unite: 'DA',
          icone: Icons.receipt_long_outlined),
      kpi(label: 'Marchandise', valeur: _mnt(_marchandiseDevise, _devise),
          unite: '', sousLabel: 'déplacée · ${_f(_marchandiseDA)} DA',
          icone: Icons.inventory_2_outlined),
      kpi(label: 'Revenu projeté', valeur: _f(_revenu), unite: 'DA',
          icone: Icons.trending_up),
      kpi(label: 'Bénéfice', valeur: '${_benef >= 0 ? '+' : ''}${_f(_benef)}',
          unite: 'DA', icone: Icons.savings_outlined,
          accent: colBenef, valCol: colBenef, hero: true,
          jauge: _obj > 0 ? _benef / _obj : null,
          sousLabel: 'objectif ${_f(_obj)} DA'),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 660) {
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: cards[i]),
            ],
          ]),
        );
      }
      return Column(children: [
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: cards[0]), const SizedBox(width: 10),
                Expanded(child: cards[1])])),
        const SizedBox(height: 10),
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: cards[2]), const SizedBox(width: 10),
                Expanded(child: cards[3])])),
      ]);
    });
  }

  /* ---------- Argent déposé — carte BEA (marchandise) ----------
     Ce n'est PAS une dépense : l'argent est déplacé puis revendu. Ses seules
     dépenses = ses taxes de déplacement (douane 5,5 % + taxes de carte au retrait),
     déjà comptées dans la section Dépenses. */
  Widget _sectionBea(bool closed) {
    return _card(
      titre: 'Argent déposé · carte BEA',
      action: closed ? null : IconButton(
        onPressed: () => _gererTranches(poche: false),
        icon: const Icon(Icons.add_circle, color: DzColors.lime, size: 20),
        tooltip: 'Ajouter une tranche',
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_trVoyage.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Aucune tranche déposée pour l’instant.',
                  style: TextStyle(color: DzColors.mut, fontSize: 12))),
        for (final t in _trVoyage) _trancheLigne(t, closed),
        const Divider(color: DzColors.line, height: 18),
        // Format : « 2 000 $ (270 000 DA) » — le montant d'abord, la devise collée,
        // la contre-valeur DA entre parenthèses.
        Row(children: [
          const Expanded(child: Text('Total déposé',
              style: TextStyle(color: DzColors.mut, fontSize: 12.5))),
          Text(_mnt(_marchandiseDevise, _devise),
              style: const TextStyle(color: DzColors.lime, fontSize: 15, fontWeight: FontWeight.w800)),
          Text('  (${_f(_marchandiseDA)} DA)',
              style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
        ]),
        const SizedBox(height: 2),
        Text('Argent déplacé, pas dépensé — taxes comptées dans les dépenses : '
            'douane + carte ${_f(_taxesCarte + _douane)} DA.',
            style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
        if (_marchandiseDevise > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _ligne(
                _facturee
                    ? 'Valeur déclarée en douane (factures)'
                    : 'Valeur en douane estimée (max 1,8 M DA)',
                '${_f(_valDeclaree)} DA',
                couleur: _valDeclaree > 1800000 ? DzColors.red : DzColors.mut),
          ),
        if (_soldeDevises > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _ligne('Reste du compte (voyages passés)',
                _mnt(_soldeDevises, _devise), couleur: DzColors.mut),
          ),
      ]),
    );
  }

  /// Une tranche : montant devise · taux · contre-valeur DA (+ suppression).
  Widget _trancheLigne(Map t, bool closed) {
    final src = '${t['source'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: _mnt(_n(t['usd']), '${t['devise']}'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            if (src.isNotEmpty)
              TextSpan(text: '  ·  $src',
                  style: const TextStyle(color: DzColors.mut, fontSize: 11)),
          ])),
        ),
        Text('× ${t['taux']}  ',
            style: const TextStyle(color: DzColors.mut, fontSize: 11)),
        Text('${_f(_n(t['usd']) * _n(t['taux']))} DA',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        if (!closed)
          IconButton(
            padding: const EdgeInsets.only(left: 8), constraints: const BoxConstraints(),
            onPressed: () async {
              try {
                await Api.delete('/missions/${widget.id}/tranches/${t['id']}');
                await _load();
              } on ApiException catch (e) { _snack(e.message); }
            },
            icon: const Icon(Icons.close, color: DzColors.red, size: 15),
          ),
      ]),
    );
  }

  /* ---------- Dépenses avant le départ (les VRAIS frais) ---------- */
  Widget _sectionDepenses(bool closed) {
    final m = _m!;
    final douaneReelle = closed && m['factures_total'] != null;
    return _card(
      titre: 'Dépenses avant le départ',
      action: closed ? null : IconButton(
        onPressed: _editFrais,
        icon: const Icon(Icons.edit_outlined, size: 17, color: DzColors.mut),
        tooltip: 'Modifier les frais',
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _ligne('Billet A/R', '${_f(_n(m['billet']))} DA'),
        _ligne('Démarches — ${_demLabel(m['dem_type'])}', '${_f(_n(m['dem_cout']))} DA'),
        _ligne('Frais de dépôt visa', '${_f(_n(m['frais_visa']))} DA'),
        // Argent de poche : tranches réelles (cash €/$, carte, RMB Alipay…) — sinon prévision.
        InkWell(
          onTap: closed ? null : () => _gererTranches(poche: true),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Text(
                    _pocheDA > 0
                        ? 'Argent de poche · ${_trPoche.length} tranche${_trPoche.length > 1 ? 's' : ''}'
                        : 'Argent de poche · prévision ${m['jours']} j',
                    style: const TextStyle(color: DzColors.mut, fontSize: 12.5)),
              ),
              Text('${_f(_poche)} DA',
                  style: const TextStyle(color: DzColors.txt, fontSize: 13, fontWeight: FontWeight.w600)),
              if (!closed)
                const Padding(padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.add_circle_outline, size: 15, color: DzColors.lime)),
            ]),
          ),
        ),
        _ligne(
            douaneReelle
                ? 'Douane (réelle, factures)'
                : 'Douane — avance (5,5 % du dépôt carte)',
            '${_f(_douane)} DA'),
        _ligne(
            _facturee
                ? 'Taxes carte (réelles, factures)'
                : 'Taxes carte — si tout le dépôt est retiré',
            '${_f(_taxesCarte)} DA'),
        _ligne('Autres frais', '${_f(_n(m['autres']))} DA'),
        const Divider(color: DzColors.line, height: 18),
        _ligne('Total dépenses', '${_f(_frais)} DA', gras: true),
        const SizedBox(height: 2),
        const Text('La marchandise n’est pas une dépense : l’argent est déplacé — '
            'seules ses taxes (douane + carte) comptent.',
            style: TextStyle(color: DzColors.mut, fontSize: 10.5)),
      ]),
    );
  }

  /* ---------- Dialogue tranches (marchandise OU argent de poche) ---------- */
  Future<void> _gererTranches({required bool poche}) async {
    final montant = TextEditingController();
    final taux = TextEditingController();
    String devise = poche ? 'EUR' : _devise;
    String mode = 'Cash';
    bool saving = false;
    const modes = ['Cash', 'Carte', 'RMB Alipay'];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        final tranches = poche ? _trPoche : _trVoyage;
        final totalDevise = poche ? null : _marchandiseDevise;
        final totalDA = poche ? _pocheDA : _marchandiseDA;
        Future<void> add() async {
          if (saving) return;
          setSt(() => saving = true);
          try {
            await Api.post('/missions/${widget.id}/tranches', {
              'montant': num.tryParse(montant.text) ?? 0,
              'devise': devise,
              if (devise != 'DA') 'taux': num.tryParse(taux.text) ?? 0,
              'motif': poche ? 'poche' : 'voyage',
              if (poche) 'source': devise == 'RMB' ? 'RMB Alipay' : mode,
            });
            montant.clear(); taux.clear();
            await _load();
            setSt(() => saving = false);
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
        Future<void> del(dynamic tid) async {
          try {
            await Api.delete('/missions/${widget.id}/tranches/$tid');
            await _load();
            setSt(() {});
          } on ApiException catch (e) {
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
                children: [
                  Text(poche ? 'Argent de poche — tranches'
                             : 'Argent déposé · compte ${_devise}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(poche
                          ? 'Cash € / \$, devise en carte, RMB Alipay… plusieurs à la fois.'
                          : 'Chaque dépôt sur la carte, au taux réel du jour.',
                      style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                  const SizedBox(height: 14),
                  // Historique
                  if (tranches.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Aucune tranche.',
                            style: TextStyle(color: DzColors.mut, fontSize: 12.5)))
                  else ...[
                    for (final t in tranches)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(
                            child: Text.rich(TextSpan(children: [
                              TextSpan(text: _mnt(_n(t['usd']), '${t['devise']}'),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              if ('${t['source'] ?? ''}'.isNotEmpty)
                                TextSpan(text: '  ·  ${t['source']}',
                                    style: const TextStyle(color: DzColors.mut, fontSize: 11)),
                            ])),
                          ),
                          Text('× ${t['taux']}  ',
                              style: const TextStyle(color: DzColors.mut, fontSize: 11)),
                          Text('${_f(_n(t['usd']) * _n(t['taux']))} DA',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          IconButton(
                            padding: const EdgeInsets.only(left: 8), constraints: const BoxConstraints(),
                            onPressed: () => del(t['id']),
                            icon: const Icon(Icons.close, color: DzColors.red, size: 15),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Expanded(child: Text('Total',
                          style: TextStyle(color: DzColors.mut, fontSize: 12))),
                      if (totalDevise != null)
                        Text('${_mnt(totalDevise, _devise)}  ',
                            style: const TextStyle(color: DzColors.lime,
                                fontSize: 13.5, fontWeight: FontWeight.w800)),
                      Text(totalDevise != null ? '(${_f(totalDA)} DA)' : '${_f(totalDA)} DA',
                          style: totalDevise != null
                              ? const TextStyle(color: DzColors.mut, fontSize: 11.5)
                              : const TextStyle(color: DzColors.lime,
                                  fontSize: 13.5, fontWeight: FontWeight.w800)),
                    ]),
                  ],
                  const Divider(color: DzColors.line, height: 22),
                  // Ajout
                  if (poche) ...[
                    Row(children: [
                      for (final d in ['EUR', 'USD', 'RMB', 'DA']) ...[
                        Expanded(child: _chip(d, devise == d, () => setSt(() => devise = d))),
                        if (d != 'DA') const SizedBox(width: 6),
                      ],
                    ]),
                    const SizedBox(height: 10),
                    if (devise != 'DA' && devise != 'RMB')
                      Row(children: [
                        for (final mo in modes.sublist(0, 2)) ...[
                          Expanded(child: _chip(mo, mode == mo, () => setSt(() => mode = mo))),
                          if (mo != 'Carte') const SizedBox(width: 6),
                        ],
                      ]),
                    if (devise != 'DA' && devise != 'RMB') const SizedBox(height: 12),
                  ],
                  Row(children: [
                    Expanded(child: TextField(controller: montant, keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: 'Montant (${_sym(poche ? devise : _devise)})', isDense: true))),
                    if (!poche || devise != 'DA') ...[
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: taux, keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Taux (DA)', isDense: true))),
                    ],
                  ]),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: saving ? null : add,
                      child: saving
                          ? const SizedBox(height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Ajouter la tranche')),
                  const SizedBox(height: 4),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
                ]),
              )),
          ),
        );
      }),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) => Material(
        color: sel ? DzColors.lime : DzColors.card2,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: sel ? DzColors.lime : DzColors.line),
            ),
            child: Text(label, style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700,
                color: sel ? DzColors.inkOnLime : DzColors.mut)),
          ),
        ),
      );

  /* ---------- Statut du vol ---------- */
  Widget _sectionVol(bool closed) {
    final m = _m!;
    final hd = '${m['heure_depart'] ?? ''}';
    final ha = '${m['heure_arrivee'] ?? ''}';
    return _card(
      titre: 'Statut du vol',
      action: closed ? null : IconButton(
        onPressed: _editVol,
        icon: const Icon(Icons.edit_outlined, size: 17, color: DzColors.mut),
        tooltip: 'Heures du vol',
      ),
      child: Row(children: [
        _volCol('Départ', hd.isEmpty ? '—' : hd, dateFr(m['depart'])),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(children: [
              const Icon(Icons.flight, color: DzColors.lime, size: 20),
              const SizedBox(height: 2),
              Text(m['vol'] ?? '', style: const TextStyle(color: DzColors.mut, fontSize: 10)),
            ]),
          ),
        ),
        _volCol('Arrivée', ha.isEmpty ? '—' : ha, dateFr(m['retour'])),
      ]),
    );
  }

  Widget _volCol(String l, String heure, String date) => Column(children: [
        Text(l.toUpperCase(), style: const TextStyle(color: DzColors.mut, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: .6)),
        const SizedBox(height: 3),
        Text(heure, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(date, style: const TextStyle(color: DzColors.mut, fontSize: 10)),
      ]);

  /* ---------- Prix du kilo ---------- */
  Widget _sectionPrixKilo() => _card(
        titre: 'Prix du kilo minimum',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_f(_pkMin)} DA/kg',
              style: const TextStyle(color: DzColors.lime, fontSize: 24, fontWeight: FontWeight.w800)),
          Text('(${_f(_frais)} dépenses, taxes incluses + ${_f(_obj)} objectif) '
              '÷ ${_cap.toStringAsFixed(0)} kg — sans l’argent de la marchandise',
              style: const TextStyle(color: DzColors.mut, fontSize: 11)),
        ]),
      );

  /* ---------- Valise ---------- */
  Widget _sectionValise(bool closed) {
    final m = _m!;
    final produits = m['produits'] as List;
    final reste = _cap - _used;
    final vClose = _valiseClose;
    return _card(
      titre: 'Valise — ${_used.toStringAsFixed(1)} / ${_cap.toStringAsFixed(0)} kg'
          '${m['cabine'] == true ? ' (cabine)' : ''}${vClose ? ' · complète ✓' : ''}',
      // Valise complète (même non pleine) → verrouille l'ajout, ouvre le check retour.
      action: closed || (produits.isEmpty && _aff.isEmpty) ? null : TextButton.icon(
        onPressed: _toggleValiseClose,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
            foregroundColor: vClose ? DzColors.mut : DzColors.lime),
        icon: Icon(vClose ? Icons.lock_open_outlined : Icons.lock_outline, size: 15),
        label: Text(vClose ? 'Rouvrir' : 'Valise complète', style: const TextStyle(fontSize: 12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _cap > 0 ? (_used / _cap).clamp(0, 1).toDouble() : 0,
            minHeight: 8, backgroundColor: DzColors.card2,
            color: _used > _cap ? DzColors.red : DzColors.lime,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(reste >= 0
              ? 'reste ${reste.toStringAsFixed(1)} kg'
              : 'dépassement ${(-reste).toStringAsFixed(1)} kg !',
              style: const TextStyle(color: DzColors.mut, fontSize: 11)),
        ),
        if (!closed && vClose)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _bannerInline(DzColors.lime,
                '✓ Valise déclarée complète — le check avant le retour est ouvert. '
                '« Rouvrir » pour ajouter un produit.'),
          ),
        if (!closed && !vClose) ...[
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final ok = await showInventairePicker(context,
                      missionId: widget.id, kgDispo: reste > 0 ? reste : 0,
                      manqueDA: (_obj - _benef) > 0 ? (_obj - _benef) : 0, prixKiloMin: _pkMin);
                  if (ok) _load();
                },
                icon: const Icon(Icons.inventory_2_outlined, size: 16),
                label: const Text('Ajouter depuis l’inventaire'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() => _formLibre = !_formLibre),
              child: Text(_formLibre ? 'Masquer' : 'Hors inventaire', style: const TextStyle(fontSize: 12)),
            ),
          ]),
          if (_formLibre) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(flex: 4, child: TextField(controller: _nom,
                  decoration: const InputDecoration(labelText: 'Produit', isDense: true))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: _kg, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'kg', isDense: true))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: _prix, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'DA/kg', isDense: true))),
              const SizedBox(width: 4),
              IconButton(onPressed: _addProduit, icon: const Icon(Icons.add_circle, color: DzColors.lime)),
            ]),
          ],
        ],
        const SizedBox(height: 6),
        // Produits venus de l'inventaire
        ..._aff.map((a) {
          final q = _n(a['quantite']), pu = _n(a['poids_unit']), gp = _n(a['gain_piece']);
          final gainKg = pu > 0 ? gp / pu : 0.0;
          final ok = gainKg >= _pkMin;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['produit']}', style: const TextStyle(fontSize: 12.5)),
                Text('${a['chambre_nom']} · ${_f(q)} pc · manque ${_f(_n(a['manque_rmb']))} ¥/pc',
                    style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
              ])),
              Text('${(q * pu).toStringAsFixed(1)} kg  ', style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
              Text('${_f(q * gp)} DA', style: TextStyle(color: ok ? DzColors.lime : DzColors.txt,
                  fontSize: 12, fontWeight: FontWeight.w600)),
              if (!closed && !vClose)
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    tooltip: 'Remettre en stock',
                    onPressed: () => _delAffectation(a['id']),
                    icon: const Icon(Icons.close, color: DzColors.red, size: 16)),
            ]),
          );
        }),
        ...produits.map((p) {
          final prix = _n(p['prix_kg']);
          final kgTxt = _n(p['kg']).toStringAsFixed(1);
          final ok = prix >= _pkMin;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Text('${p['nom']}', style: const TextStyle(fontSize: 12.5))),
              Text('$kgTxt kg  ', style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
              Text(_f(prix), style: TextStyle(color: ok ? DzColors.lime : DzColors.txt,
                  fontSize: 12, fontWeight: FontWeight.w600)),
              if (!closed && !vClose)
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    onPressed: () => _delProduit(p['id']),
                    icon: const Icon(Icons.close, color: DzColors.red, size: 16)),
            ]),
          );
        }),
        if (produits.isEmpty && _aff.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: Text('Valise vide — elle se remplit sur place, depuis l’inventaire.',
                  style: TextStyle(color: DzColors.mut, fontSize: 12)))),
        if (!closed && (produits.isNotEmpty || _aff.isNotEmpty))
          Padding(padding: const EdgeInsets.only(top: 8), child:
            _benef >= _obj
                ? _bannerInline(DzColors.lime, '✓ Prêt — bénéfice projeté ${_f(_benef)} DA.')
                : reste > 0.5
                    ? _bannerInline(DzColors.amber,
                        '○ Il manque ${_f(_obj - _benef)} DA — vise ≥ ${_f((_obj - _benef) / reste)} DA/kg.')
                    : _bannerInline(DzColors.red,
                        '✕ Valise pleine, objectif non atteint (${_f(_obj - _benef)} DA).')),
        if (!closed && !vClose && !(m['cabine'] == true) && _benef < _obj && reste < 4)
          Padding(padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton(onPressed: _toggleCabine,
                  child: const Text('+10 kg bagage cabine (dernier recours)'))),
      ]),
    );
  }

  /* ---------- Composants ---------- */
  Widget _card({required String titre, Widget? action, required Widget child}) => Container(
        decoration: BoxDecoration(
          color: DzColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DzColors.line),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Hauteur de titre FIXE (40 px) : avec ou sans bouton d'action à droite,
          // le contenu de toutes les cartes démarre exactement à la même hauteur.
          SizedBox(
            height: 40,
            child: Row(children: [
              Expanded(child: Text(titre,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
              if (action != null) action,
            ]),
          ),
          const SizedBox(height: 4),
          child,
        ]),
      );

  Widget _ligne(String l, String v, {bool gras = false, Color couleur = DzColors.txt}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(l, style: const TextStyle(color: DzColors.mut, fontSize: 12.5))),
          Text(v, style: TextStyle(color: couleur, fontSize: 13,
              fontWeight: gras ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  /// Coche automatique de certains items du départ (billet saisi, argent chargé…).
  Map<String, bool> _autoDepart() => {
        'billet_ok': _n(_m!['billet']) > 0 && _m!['depart'] != null,
        'argent_depose': _marchandiseDA > 0,
      };

  /// (faits, total) d'une checklist — items auto compris.
  (int, int) _avancement(String champ, List items, Map<String, bool> auto) {
    final etat = Map<String, dynamic>.from(_m![champ] as Map? ?? {});
    bool val(String cle) => etat[cle] == true || auto[cle] == true;
    final total = items.length + (champ == 'check_depart' ? 1 : 0); // +1 : billet auto
    var faits = items.where((i) => val(i.$1 as String)).length;
    if (champ == 'check_depart' && (auto['billet_ok'] ?? false)) faits += 1;
    return (faits, total);
  }

  bool get _departComplet {
    final (f, t) = _avancement('check_depart', _itemsDepart, _autoDepart());
    return f >= t;
  }

  bool get _valiseClose => _m!['valise_close'] == true;

  /// Les 3 cartes « avant le départ » rangées : une ligne de résumé chacune.
  Widget _avantDepartRangeRow(bool wide) {
    Widget resume(IconData ic, String titre, String valeur, {Color col = DzColors.txt}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: DzColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DzColors.line),
          ),
          child: Row(children: [
            Icon(ic, size: 15, color: DzColors.lime),
            const SizedBox(width: 9),
            Expanded(child: Text(titre,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: DzColors.mut, fontSize: 12, fontWeight: FontWeight.w600))),
            Text(valeur, style: TextStyle(color: col, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        );
    final (f, t) = _avancement('check_depart', _itemsDepart, _autoDepart());
    final cards = [
      resume(Icons.receipt_long_outlined, 'Dépenses avant le départ', '${_f(_frais)} DA'),
      resume(Icons.credit_card_outlined, 'Argent déposé · carte BEA',
          '${_mnt(_marchandiseDevise, _devise)} (${_f(_marchandiseDA)} DA)'),
      resume(Icons.checklist_rounded, 'Check avant le départ', '$f/$t ✓', col: DzColors.lime),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.check_circle, size: 14, color: DzColors.lime),
        const SizedBox(width: 6),
        const Expanded(child: Text('Avant le départ — tout est prêt',
            style: TextStyle(color: DzColors.lime, fontSize: 11.5, fontWeight: FontWeight.w700))),
        TextButton.icon(
          onPressed: () => setState(() => _avantDepartRange = false),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.unfold_more, size: 15),
          label: const Text('Dérouler', style: TextStyle(fontSize: 12)),
        ),
      ]),
      const SizedBox(height: 6),
      if (wide)
        Row(children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: cards[i]),
          ],
        ])
      else
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          cards[i],
        ],
    ]);
  }

  Widget _checklist(String titre, String champ, List items, {Map<String, bool> auto = const {}}) {
    final closed = _m!['statut'] == 'cloturee';
    final etat = Map<String, dynamic>.from(_m![champ] as Map? ?? {});
    bool val(String cle) => etat[cle] == true || auto[cle] == true;
    final (faits, total) = _avancement(champ, items, auto);
    final complet = faits >= total;
    // Check retour : verrouillé tant que la valise n'est pas déclarée complète.
    final verrou = champ == 'check_retour' && !_valiseClose && !closed;
    return _card(
      titre: '$titre — $faits/$total${complet ? ' ✓' : ''}',
      // Check départ complet → bouton « Ranger » les 3 cartes avant-départ.
      action: (champ == 'check_depart' && complet)
          ? TextButton.icon(
              onPressed: () => setState(() => _avantDepartRange = true),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.unfold_less, size: 15),
              label: const Text('Ranger', style: TextStyle(fontSize: 12)),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (verrou)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: _bannerInline(DzColors.amber,
                '🔒 Déclare d’abord la valise complète (section Valise) pour ouvrir ce check.'),
          ),
        if (champ == 'check_depart') ...[
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 10),
            child: Text(
              'Vérifie que TOUT est coché avant le départ — une mission bien préparée '
              'se passe sans mauvaise surprise. Et rappelle-toi : factures, déclarations '
              'et règles respectées, sinon les autorisations ne seront pas renouvelées '
              'l’année prochaine.',
              style: TextStyle(color: DzColors.mut, fontSize: 11, height: 1.5),
            ),
          ),
        ],
        if (champ == 'check_depart')
          _checkTile('Billet réservé (auto)', val('billet_ok'), null, locked: true),
        for (final it in items)
          _checkTile(it.$2 as String, val(it.$1 as String),
              (closed || verrou) ? null : (v) => _toggleCheck(champ, it.$1 as String, v)),
      ]),
    );
  }

  /// Ligne de check compacte — même rythme vertical que les `_ligne` des autres
  /// cartes (CheckboxListTile impose 48 px de haut + un vide interne : moche à côté).
  Widget _checkTile(String label, bool value, ValueChanged<bool>? onChanged, {bool locked = false}) =>
      InkWell(
        onTap: onChanged == null ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 22, height: 22,
              child: Checkbox(
                value: value,
                onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
                activeColor: DzColors.lime,
                checkColor: DzColors.inkOnLime,
                side: const BorderSide(color: DzColors.mut, width: 1.4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: TextStyle(
                  fontSize: 12.5,
                  color: value ? DzColors.mut : DzColors.txt,
                  decoration: value ? TextDecoration.lineThrough : null)),
            ),
            if (locked) const Icon(Icons.lock_outline, size: 14, color: DzColors.mut),
          ]),
        ),
      );

  Widget _banner(Color c, String txt) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
            color: c.withValues(alpha: .08), border: Border.all(color: c.withValues(alpha: .4)),
            borderRadius: BorderRadius.circular(12)),
        child: Text(txt, style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );

  Widget _bannerInline(Color c, String txt) => Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
            color: c.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)),
        child: Text(txt, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _clotureRecap() {
    final m = _m!;
    final com = _n(m['commission']);
    final primes = _n(m['primes']);
    final paye = (m['paiements'] as List).fold<double>(0, (s, p) => s + _n(p['montant']));
    final solde = _n(m['attendu']) - paye;
    // Bénéfice réel = attendu (après invendus) − dépenses (douane et taxes carte
    // réelles incluses) — la marchandise est déplacée, jamais déduite (serveur idem).
    final benefReel = _n(m['attendu']) - _frais;
    final netAgence = benefReel - com - primes;
    return _card(
      titre: 'Clôture & règlement',
      child: Column(children: [
        _ligne('Dépôt', '${m['depot'] ?? '—'}'),
        _ligne('Revente (attendu)', '${_f(_n(m['attendu']))} DA'),
        _ligne('− Dépenses (douane + taxes carte réelles)', '${_f(_frais)} DA'),
        if (_n(m['manques_da']) > 0)
          _ligne('   dont pièces manquantes remboursées', '${_f(_n(m['manques_da']))} DA', couleur: DzColors.red),
        const Divider(color: DzColors.line, height: 14),
        _ligne('Bénéfice mission', '${_f(benefReel)} DA', gras: true,
            couleur: benefReel >= 0 ? DzColors.lime : DzColors.red),
        _ligne('− Commission voyageur (figée)', '${_f(com)} DA'),
        _ligne('− Primes', '${_f(primes)} DA'),
        _ligne('Net agence', '${_f(netAgence)} DA', gras: true,
            couleur: netAgence >= 0 ? DzColors.lime : DzColors.red),
        if (_soldeDevises > 0)
          _ligne('Reste dans son compte (reporté)', _mnt(_soldeDevises, _devise),
              couleur: DzColors.lime),
        const Divider(color: DzColors.line, height: 16),
        _ligne(solde > 0 ? 'Reste à encaisser' : 'Soldé', '${_f(solde)} DA',
            gras: true, couleur: solde > 0 ? DzColors.amber : DzColors.lime),
      ]),
    );
  }

  /* ---------- Dialogues ---------- */
  Future<void> _editVol() async {
    final hd = TextEditingController(text: '${_m!['heure_depart'] ?? ''}');
    final ha = TextEditingController(text: '${_m!['heure_arrivee'] ?? ''}');
    await _simpleDialog('Heures du vol', [
      ('heure_depart', 'Heure de départ (ex. 12:10)', hd),
      ('heure_arrivee', 'Heure d’arrivée (ex. 18:40)', ha),
    ], (body) => Api.put('/missions/${widget.id}', body));
  }

  Future<void> _editFrais() async {
    final m = _m!;
    // Les jours sont déduits du billet (départ→retour) — pas éditables ici.
    final ctrls = {
      for (final k in ['billet', 'dem_cout', 'frais_visa', 'budget_jour',
        'autres', 'objectif'])
        k: TextEditingController(text: m[k] == null ? '' : _n(m[k]).toStringAsFixed(0)),
    };
    // La valeur déclarée en douane n'est plus saisie : automatique
    // (factures × taux officiel à la clôture, estimée sur le dépôt avant).
    const labels = {
      'billet': 'Billet A/R (DA)', 'dem_cout': 'Démarches (DA)', 'frais_visa': 'Frais dépôt visa (DA)',
      'budget_jour': 'Argent de poche / jour (DA)',
      'autres': 'Autres frais (DA)',
      'objectif': 'Objectif bénéf (DA)',
    };
    await _simpleDialog('Modifier les frais',
        [for (final k in labels.keys) (k, labels[k]!, ctrls[k]!)],
        (body) => Api.put('/missions/${widget.id}', body), numeric: true);
  }

  /// Petit dialogue générique champ→valeur (numérique ou texte).
  Future<void> _simpleDialog(String titre, List<(String, String, TextEditingController)> fields,
      Future<void> Function(Map<String, dynamic>) onSave, {bool numeric = false}) async {
    bool saving = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          if (saving) return;
          setSt(() => saving = true);
          try {
            await onSave({
              for (final f in fields)
                if (f.$3.text.trim().isNotEmpty)
                  f.$1: numeric ? (num.tryParse(f.$3.text) ?? 0) : f.$3.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
                children: [
                  Text(titre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  for (final f in fields) ...[
                    TextField(controller: f.$3,
                        keyboardType: numeric ? TextInputType.number : TextInputType.text,
                        decoration: InputDecoration(labelText: f.$2)),
                    const SizedBox(height: 14),
                  ],
                  FilledButton(onPressed: saving ? null : save,
                      child: saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Enregistrer')),
                ]),
              )),
          ),
        );
      }),
    );
  }

  Future<void> _openCloture() async {
    final depot = TextEditingController();
    final attendu = TextEditingController(text: _revenu.toStringAsFixed(0));
    final encaisse = TextEditingController(text: _revenu.toStringAsFixed(0));
    final factures = TextEditingController();
    final primes = TextEditingController(text: '0');
    final invendus = TextEditingController();
    // Pièces manquantes par produit d'inventaire (remboursées au prix du manque en RMB).
    final manquants = {for (final a in _aff) a['id']: TextEditingController()};
    bool saving = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          if (saving) return;
          setSt(() => saving = true);
          try {
            await Api.post('/missions/${widget.id}/cloture', {
              'depot': depot.text.trim(),
              'attendu': num.tryParse(attendu.text) ?? 0,
              'encaisse': num.tryParse(encaisse.text) ?? 0,
              'primes': num.tryParse(primes.text) ?? 0,
              'invendus': invendus.text.trim(),
              if (factures.text.trim().isNotEmpty) 'factures_total': num.tryParse(factures.text) ?? 0,
              'manquants': [
                for (final e in manquants.entries)
                  if ((num.tryParse(e.value.text) ?? 0) > 0)
                    {'affectation_id': e.key, 'quantite': num.tryParse(e.value.text) ?? 0},
              ],
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Clôturer ${_m!['code']}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Douane et taxes de carte recalculées sur les factures réelles, '
                      'reste des devises reporté sur son compte.',
                      style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                  const SizedBox(height: 16),
                  TextField(controller: depot, decoration: const InputDecoration(labelText: 'Dépôt / acheteur')),
                  const SizedBox(height: 14),
                  TextField(controller: factures, keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Total des factures (${_sym(_devise)})')),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: TextField(controller: attendu, keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Attendu (DA)'))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: encaisse, keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Encaissé'))),
                  ]),
                  const SizedBox(height: 14),
                  TextField(controller: primes, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Primes économies (DA)')),
                  const SizedBox(height: 14),
                  TextField(controller: invendus,
                      decoration: const InputDecoration(labelText: 'Invendus / prix renégociés')),
                  if (_aff.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text('PIÈCES MANQUANTES (remboursées au prix du manque, RMB)',
                        style: TextStyle(color: DzColors.lime, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    for (final a in _aff)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(child: Text('${a['produit']}  ·  ${_f(_n(a['quantite']))} pc · ${_f(_n(a['manque_rmb']))} ¥/pc',
                              style: const TextStyle(fontSize: 12, color: DzColors.mut))),
                          SizedBox(width: 90, child: TextField(controller: manquants[a['id']],
                              keyboardType: TextInputType.number, textAlign: TextAlign.center,
                              decoration: const InputDecoration(isDense: true, hintText: '0',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)))),
                        ]),
                      ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(onPressed: saving ? null : save,
                      child: saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Clôturer la mission')),
                ]),
              )),
          ),
        );
      }),
    );
  }
}
