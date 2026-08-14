import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';

/// Détail d'une mission — structure v4 :
/// KPIs · (Dépenses avant départ ‖ Check départ) · Statut de vol · Prix du kilo ·
/// Valise · Check retour · Clôture.
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
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /* ---------- Calculs ---------- */
  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  double get _perDiem => _n(_m!['jours']) * _n(_m!['budget_jour']);
  double get _marchandiseDA => ((_m!['tranches'] as List?) ?? [])
      .fold(0.0, (s, t) => s + _n(t['usd']) * _n(t['taux']));
  // IDENTIQUE au calcul serveur (frais() dans missions.js) — inclut les frais de carte.
  double get _frais => _n(_m!['billet']) + _n(_m!['dem_cout']) + _n(_m!['frais_visa']) +
      _perDiem + _n(_m!['bea']) + _n(_m!['douane']) + _n(_m!['autres']) +
      _n(_m!['poche_frais_carte']);
  double get _cap => _n(_m!['kg_soute']) + (_m!['cabine'] == true ? 10 : 0);
  double get _used => (_m!['produits'] as List).fold(0.0, (s, p) => s + _n(p['kg']));
  double get _revenu => (_m!['produits'] as List)
      .fold(0.0, (s, p) => s + _n(p['kg']) * _n(p['prix_kg']));
  double get _benef => _revenu - _frais - _marchandiseDA;
  double get _obj => _n(_m!['objectif']);
  double get _pkMin => _cap > 0 ? (_frais + _obj) / _cap : 0;
  String get _devise => '${_m!['v_devise'] ?? 'USD'}';
  double get _soldeDevises => _n(_m!['v_solde']);

  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  String _sym(String d) => d == 'EUR' ? '€' : d == 'RMB' ? '¥' : '\$';

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
    final over = m['val_declaree'] != null && _n(m['val_declaree']) > 1800000;
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

      // ---- Dépenses avant départ  ‖  Check départ ----
      // Pas d'IntrinsicHeight : chaque carte épouse son contenu (pas de vide en bas).
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _sectionDepenses(closed)),
          const SizedBox(width: 12),
          Expanded(child: _checklist('Check avant le départ', 'check_depart',
              _itemsDepart, auto: _autoDepart())),
        ])
      else ...[
        _sectionDepenses(closed),
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

      if (!closed)
        FilledButton(onPressed: _openCloture, child: const Text('■ Clôturer la mission')),
      if (closed) _clotureRecap(),
    ]);
  }

  /* ---------- KPIs ---------- */
  Widget _kpiRow() {
    final data = [
      ('Total frais', _f(_frais), DzColors.txt, Icons.receipt_long_outlined),
      ('Revenu projeté', _f(_revenu), DzColors.txt, Icons.trending_up),
      ('Bénéfice', '${_benef >= 0 ? '+' : ''}${_f(_benef)}',
          _benef >= _obj ? DzColors.lime : _benef >= 0 ? DzColors.amber : DzColors.red,
          Icons.savings_outlined),
    ];
    return Row(children: [
      for (var i = 0; i < data.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: DzColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DzColors.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(data[i].$4, size: 14, color: data[i].$3.withValues(alpha: .8)),
                const SizedBox(width: 6),
                Expanded(child: Text(data[i].$1.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: DzColors.mut, fontSize: 8.5,
                        fontWeight: FontWeight.w700, letterSpacing: .6))),
              ]),
              const SizedBox(height: 8),
              FittedBox(child: Text('${data[i].$2} ',
                  style: TextStyle(color: data[i].$3, fontSize: 20, fontWeight: FontWeight.w800))),
              const Text('DA', style: TextStyle(color: DzColors.mut, fontSize: 9)),
            ]),
          ),
        ),
      ],
    ]);
  }

  /* ---------- Dépenses avant départ ---------- */
  double get _marchandiseDevise =>
      ((_m!['tranches'] as List?) ?? []).fold(0.0, (s, t) => s + _n(t['usd']));

  static const _pocheLabels = {
    'cash_da': 'Cash (DA)', 'rmb_alipay': 'RMB via Alipay',
    'cash_devise': 'Cash devise', 'carte': 'Dans la carte',
  };

  Widget _sectionDepenses(bool closed) {
    final m = _m!;
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
        // Argent de poche : mode remis (tap pour changer)
        InkWell(
          onTap: closed ? null : _choisirPocheMode,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text('Argent de poche · ${_pocheLabels[m['poche_mode']] ?? 'Cash (DA)'}',
                  style: const TextStyle(color: DzColors.mut, fontSize: 12.5))),
              Text('${_f(_perDiem)} DA',
                  style: const TextStyle(color: DzColors.txt, fontSize: 13, fontWeight: FontWeight.w600)),
              if (!closed) const Icon(Icons.expand_more, size: 15, color: DzColors.mut),
            ]),
          ),
        ),
        if (_n(m['poche_frais_carte']) > 0)
          _ligne('  ↳ frais de carte', '${_f(_n(m['poche_frais_carte']))} DA', couleur: DzColors.mut),
        _ligne('Frais carte BEA', '${_f(_n(m['bea']))} DA'),
        _ligne('Autres frais', '${_f(_n(m['autres']))} DA'),
        // Argent marchandise : TOTAL EN DEVISE seulement ; l'historique s'ouvre au +
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            const Expanded(child: Text('Argent déposé (marchandise)',
                style: TextStyle(color: DzColors.mut, fontSize: 12.5))),
            Text('${_sym(_devise)} ${_f(_marchandiseDevise)}',
                style: const TextStyle(color: DzColors.txt, fontSize: 13, fontWeight: FontWeight.w700)),
            if (!closed)
              IconButton(
                padding: const EdgeInsets.only(left: 4), constraints: const BoxConstraints(),
                onPressed: _gererTranches,
                icon: const Icon(Icons.add_circle, color: DzColors.lime, size: 19),
                tooltip: 'Gérer les tranches',
              ),
          ]),
        ),
        if (_soldeDevises > 0)
          _ligne('Reste du compte (voyages passés)',
              '${_sym(_devise)} ${_f(_soldeDevises)}', couleur: DzColors.mut),
        const Divider(color: DzColors.line, height: 18),
        _ligne('Total frais', '${_f(_frais + _marchandiseDA)} DA', gras: true),
      ]),
    );
  }

  Future<void> _choisirPocheMode() async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DzColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(16),
            child: Text('Argent de poche remis en…',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        for (final e in _pocheLabels.entries)
          ListTile(
            title: Text(e.value),
            trailing: _m!['poche_mode'] == e.key
                ? const Icon(Icons.check, color: DzColors.lime) : null,
            onTap: () => Navigator.pop(context, e.key),
          ),
        const SizedBox(height: 8),
      ])),
    );
    if (choix != null) {
      await Api.put('/missions/${widget.id}', {'poche_mode': choix});
      _load();
    }
  }

  /// Dialogue de gestion des tranches : liste (devise · DA · taux) + champ d'ajout.
  Future<void> _gererTranches() async {
    final montant = TextEditingController();
    final taux = TextEditingController();
    bool saving = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        final tranches = (_m!['tranches'] as List?) ?? [];
        Future<void> add() async {
          if (saving) return;
          setSt(() => saving = true);
          try {
            await Api.post('/missions/${widget.id}/tranches', {
              'montant': num.tryParse(montant.text) ?? 0,
              'devise': _devise,
              'taux': num.tryParse(taux.text) ?? 0,
            });
            montant.clear(); taux.clear();
            await _load();
            setSt(() => saving = false);
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Argent déposé · compte ${_devise}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  // Historique
                  if (tranches.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Aucune tranche.', style: TextStyle(color: DzColors.mut, fontSize: 12.5)))
                  else
                    for (final t in tranches)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          Expanded(child: Text('${_sym('${t['devise']}')} ${_f(_n(t['usd']))}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                          Text('taux ${t['taux']}  ',
                              style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                          Text('${_f(_n(t['usd']) * _n(t['taux']))} DA',
                              style: const TextStyle(fontSize: 12.5)),
                          IconButton(
                            padding: const EdgeInsets.only(left: 6), constraints: const BoxConstraints(),
                            onPressed: () async {
                              await Api.delete('/missions/${widget.id}/tranches/${t['id']}');
                              await _load(); setSt(() {});
                            },
                            icon: const Icon(Icons.close, color: DzColors.red, size: 15),
                          ),
                        ]),
                      ),
                  const Divider(color: DzColors.line, height: 20),
                  // Ajout
                  Row(children: [
                    Expanded(child: TextField(controller: montant, keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Montant (${_sym(_devise)})', isDense: true))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: taux, keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Taux (DA)', isDense: true))),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: saving ? null : add,
                      child: saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Ajouter la tranche')),
                  const SizedBox(height: 6),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
                ]),
            ),
          ),
        );
      }),
    );
  }

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
          Text('(${_f(_frais)} frais + ${_f(_obj)} objectif) ÷ ${_cap.toStringAsFixed(0)} kg',
              style: const TextStyle(color: DzColors.mut, fontSize: 11)),
        ]),
      );

  /* ---------- Valise ---------- */
  Widget _sectionValise(bool closed) {
    final m = _m!;
    final produits = m['produits'] as List;
    final reste = _cap - _used;
    return _card(
      titre: 'Valise — ${_used.toStringAsFixed(1)} / ${_cap.toStringAsFixed(0)} kg'
          '${m['cabine'] == true ? ' (cabine)' : ''}',
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
        if (!closed)
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
        const SizedBox(height: 6),
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
              if (!closed)
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    onPressed: () => _delProduit(p['id']),
                    icon: const Icon(Icons.close, color: DzColors.red, size: 16)),
            ]),
          );
        }),
        if (produits.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: Text('Valise vide — elle se remplit sur place.',
                  style: TextStyle(color: DzColors.mut, fontSize: 12)))),
        if (!closed && produits.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child:
            _benef >= _obj
                ? _bannerInline(DzColors.lime, '✓ Prêt — bénéfice projeté ${_f(_benef)} DA.')
                : reste > 0.5
                    ? _bannerInline(DzColors.amber,
                        '○ Il manque ${_f(_obj - _benef)} DA — vise ≥ ${_f((_obj - _benef) / reste)} DA/kg.')
                    : _bannerInline(DzColors.red,
                        '✕ Valise pleine, objectif non atteint (${_f(_obj - _benef)} DA).')),
        if (!closed && !(m['cabine'] == true) && _benef < _obj && reste < 4)
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
          Row(children: [
            Expanded(child: Text(titre,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
            if (action != null) action,
          ]),
          const SizedBox(height: 6),
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

  Widget _checklist(String titre, String champ, List items, {Map<String, bool> auto = const {}}) {
    final closed = _m!['statut'] == 'cloturee';
    final etat = Map<String, dynamic>.from(_m![champ] as Map? ?? {});
    bool val(String cle) => etat[cle] == true || auto[cle] == true;
    final total = items.length + (champ == 'check_depart' ? 1 : 0); // +1 : billet auto
    var faits = items.where((i) => val(i.$1 as String)).length;
    if (champ == 'check_depart' && (auto['billet_ok'] ?? false)) faits += 1;
    final complet = faits >= total;
    return _card(
      titre: '$titre — $faits/$total${complet ? ' ✓' : ''}',
      child: Column(children: [
        if (champ == 'check_depart')
          _checkTile('Billet réservé (auto)', val('billet_ok'), null, locked: true),
        for (final it in items)
          _checkTile(it.$2 as String, val(it.$1 as String),
              closed ? null : (v) => _toggleCheck(champ, it.$1 as String, v)),
      ]),
    );
  }

  Widget _checkTile(String label, bool value, ValueChanged<bool>? onChanged, {bool locked = false}) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        activeColor: DzColors.lime,
        checkColor: DzColors.inkOnLime,
        controlAffinity: ListTileControlAffinity.leading,
        value: value,
        onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
        title: Text(label, style: TextStyle(
            fontSize: 12.5,
            color: value ? DzColors.mut : DzColors.txt,
            decoration: value ? TextDecoration.lineThrough : null)),
        secondary: locked ? const Icon(Icons.lock_outline, size: 14, color: DzColors.mut) : null,
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
    // Bénéfice réel = attendu (après invendus) − frais − marchandise (identique au serveur).
    final benefReel = _n(m['attendu']) - _frais - _marchandiseDA;
    return _card(
      titre: 'Clôture & règlement',
      child: Column(children: [
        _ligne('Dépôt', '${m['depot'] ?? '—'}'),
        _ligne('Douane payée (réelle)', '${_f(_n(m['douane']))} DA'),
        _ligne('Bénéfice mission', '${_f(benefReel)} DA'),
        _ligne('Commission voyageur (figée)', '${_f(com)} DA'),
        _ligne('Primes', '${_f(primes)} DA'),
        if (_soldeDevises > 0)
          _ligne('Reste dans son compte', '${_sym(_devise)} ${_f(_soldeDevises)}',
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
      for (final k in ['billet', 'dem_cout', 'frais_visa', 'budget_jour', 'bea',
        'autres', 'objectif', 'val_declaree'])
        k: TextEditingController(text: m[k] == null ? '' : _n(m[k]).toStringAsFixed(0)),
    };
    const labels = {
      'billet': 'Billet A/R (DA)', 'dem_cout': 'Démarches (DA)', 'frais_visa': 'Frais dépôt visa (DA)',
      'budget_jour': 'Argent de poche / jour (DA)',
      'bea': 'Frais carte BEA (DA)', 'autres': 'Autres frais (DA)',
      'objectif': 'Objectif bénéf (DA)', 'val_declaree': 'Valeur déclarée (DA)',
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
                  Text('La douane sera recalculée (5,5 % des factures au taux officiel) '
                      'et le reste des devises reporté sur son compte.',
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
