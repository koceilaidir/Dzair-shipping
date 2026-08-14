import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';

/// Détail d'une mission : dépenses, à préparer, devises, valise, checklists, clôture.
class MissionDetailScreen extends StatefulWidget {
  final int id;
  final bool embedded; // true : rendu dans la zone de contenu, la sidebar reste visible
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

  static const _itemsDepart = [
    ('passeport', 'Passeport valide en poche'),
    ('autorisations', 'Autorisations ANAE imprimées'),
    ('argent', 'Argent déposé dans le compte BEA'),
    ('carte_ae', 'Carte auto-entrepreneur'),
  ];
  static const _itemsRetour = [
    ('factures_anae', 'Factures chargées sur le site ANAE'),
    ('qr_colles', 'Codes QR imprimés et collés sur les valises'),
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
  double get _frais => _n(_m!['billet']) + _n(_m!['dem_cout']) + _perDiem +
      _n(_m!['bea']) + _n(_m!['douane']) + _n(_m!['autres']);
  double get _cap => _n(_m!['kg_soute']) + (_m!['cabine'] == true ? 10 : 0);
  double get _used =>
      (_m!['produits'] as List).fold(0.0, (s, p) => s + _n(p['kg']));
  double get _revenu => (_m!['produits'] as List)
      .fold(0.0, (s, p) => s + _n(p['kg']) * _n(p['prix_kg']));
  double get _benef => _revenu - _frais;
  double get _obj => _n(_m!['objectif']);
  double get _pkMin => _cap > 0 ? (_frais + _obj) / _cap : 0;
  double get _tranchesDA => ((_m!['tranches'] as List?) ?? [])
      .fold(0.0, (s, t) => s + _n(t['usd']) * _n(t['taux']));
  double? get _douaneDA =>
      _m!['val_declaree'] == null ? null : _n(_m!['val_declaree']) * 0.055;

  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  String _demLabel(dynamic t) => switch ('$t') {
        'premiere' => 'Première demande',
        'renouvellement' => 'Renouvellement',
        'visa_double' => 'Visa double entrée',
        _ => 'Visa multiple',
      };

  /* ---------- Actions ---------- */
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
    } on ApiException catch (e) {
      _snack(e.message);
    }
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
    setState(() => _m![champ] = cur); // réactif immédiatement
    try {
      await Api.put('/missions/${widget.id}',
          {champ: cur.map((k, v) => MapEntry(k, v == true))});
    } on ApiException catch (e) {
      _snack(e.message);
      _load();
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
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
            : _pret
                ? ('● Prêt', DzColors.lime)
                : ('● En cours', DzColors.amber);
    return Row(children: [
      Flexible(child: Text(title, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      const SizedBox(width: 10),
      if (_m != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
              color: col.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(99)),
          child: Text(label,
              style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
          child: Row(children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, color: DzColors.mut, size: 20),
              tooltip: 'Retour aux missions',
            ),
            const SizedBox(width: 4),
            Expanded(child: _titleRow),
          ]),
        ),
        Expanded(child: _statusChild),
      ]);
    }
    return Scaffold(
      appBar: AppBar(backgroundColor: DzColors.bg, title: _titleRow),
      body: _statusChild,
    );
  }

  Widget _body() {
    final m = _m!;
    final closed = m['statut'] == 'cloturee';
    final produits = m['produits'] as List;
    final over = m['val_declaree'] != null && _n(m['val_declaree']) > 1800000;
    final reste = _cap - _used;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 32), children: [
      Text('${m['vol'] ?? ''} · ${dateFr(m['depart'])} → ${dateFr(m['retour'])} · '
          '${m['jours']} j · per-diem ${_f(_n(m['budget_jour']))} DA/j',
          style: const TextStyle(color: DzColors.mut, fontSize: 12)),
      const SizedBox(height: 12),

      if (over)
        _banner(DzColors.red,
            '⚖ Valeur déclarée > 1 800 000 DA — mission illégale en l’état.'),

      // ---- KPIs ----
      Row(children: [
        _kpi('Total frais', _f(_frais), DzColors.txt),
        const SizedBox(width: 8),
        _kpi('Revenu projeté', _f(_revenu), DzColors.txt),
        const SizedBox(width: 8),
        _kpi('Bénéfice', '${_benef >= 0 ? '+' : ''}${_f(_benef)}',
            _benef >= _obj ? DzColors.lime : _benef >= 0 ? DzColors.amber : DzColors.red),
      ]),
      const SizedBox(height: 12),

      // ---- Dépenses du voyage ----
      _card(
        titre: 'Dépenses du voyage',
        action: closed ? null : IconButton(
          onPressed: _editFrais,
          icon: const Icon(Icons.edit_outlined, size: 17, color: DzColors.mut),
          tooltip: 'Modifier les frais',
        ),
        child: Column(children: [
          _ligne('Billet A/R', '${_f(_n(m['billet']))} DA'),
          _ligne('Démarches — ${_demLabel(m['dem_type'])}', '${_f(_n(m['dem_cout']))} DA'),
          _ligne('Argent de poche (${m['jours']} j × ${_f(_n(m['budget_jour']))})',
              '${_f(_perDiem)} DA'),
          _ligne('Frais carte BEA', '${_f(_n(m['bea']))} DA'),
          _ligne('Douane à l’arrivée', '${_f(_n(m['douane']))} DA'),
          _ligne('Autres frais', '${_f(_n(m['autres']))} DA'),
          const Divider(color: DzColors.line, height: 18),
          _ligne('Total', '${_f(_frais)} DA', gras: true),
        ]),
      ),
      const SizedBox(height: 12),

      // ---- À préparer ----
      _card(
        titre: 'À préparer',
        child: Column(children: [
          _ligne('À déposer dans le compte BEA',
              '${_f(_n(_reglages!['objectif_devises_usd']))} \$',
              gras: true),
          _ligne('Déjà constitué (tranches ci-dessous)', '${_f(_tranchesDA)} DA'),
          _ligne('Argent de poche à remettre', '${_f(_perDiem)} DA'),
          _ligne(
            'Dinars pour la douane (5 % + 0,5 % au taux officiel)',
            _douaneDA == null ? 'saisir la valeur déclarée' : '${_f(_douaneDA!)} DA',
            couleur: _douaneDA == null ? DzColors.mut : DzColors.amber,
            gras: _douaneDA != null,
          ),
        ]),
      ),
      const SizedBox(height: 12),

      // ---- Devises déposées ----
      _card(
        titre: 'Devises déposées',
        action: closed ? null : IconButton(
          onPressed: _addTranche,
          icon: const Icon(Icons.add_circle, size: 19, color: DzColors.lime),
          tooltip: 'Ajouter une tranche',
        ),
        child: Column(children: [
          for (final t in (m['tranches'] as List? ?? []))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Text('${_f(_n(t['usd']))} ${t['devise']} @ ${t['taux']}',
                      style: const TextStyle(fontSize: 12.5)),
                ),
                Text('${_f(_n(t['usd']) * _n(t['taux']))} DA',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                if (!closed)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      await Api.delete('/missions/${widget.id}/tranches/${t['id']}');
                      _load();
                    },
                    icon: const Icon(Icons.close, color: DzColors.red, size: 15),
                  ),
              ]),
            ),
          if ((m['tranches'] as List? ?? []).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Aucune tranche — ajoute ce que tu as acheté (RMB, €, \$).',
                  style: TextStyle(color: DzColors.mut, fontSize: 11.5)),
            ),
          if ((m['tranches'] as List? ?? []).isNotEmpty) ...[
            const Divider(color: DzColors.line, height: 16),
            _ligne('Total en dinars', '${_f(_tranchesDA)} DA', gras: true),
          ],
        ]),
      ),
      const SizedBox(height: 12),

      // ---- Objectif prix du kilo ----
      _card(
        titre: 'Prix du kilo minimum',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_f(_pkMin)} DA/kg',
              style: const TextStyle(color: DzColors.lime, fontSize: 24,
                  fontWeight: FontWeight.w800)),
          Text('(${_f(_frais)} frais + ${_f(_obj)} objectif) ÷ ${_cap.toStringAsFixed(0)} kg',
              style: const TextStyle(color: DzColors.mut, fontSize: 11)),
        ]),
      ),
      const SizedBox(height: 12),

      // ---- Valise ----
      _card(
        titre: 'Valise — ${_used.toStringAsFixed(1)} / ${_cap.toStringAsFixed(0)} kg'
            '${m['cabine'] == true ? ' (cabine)' : ''}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _cap > 0 ? (_used / _cap).clamp(0, 1).toDouble() : 0,
              minHeight: 8,
              backgroundColor: DzColors.card2,
              color: _used > _cap ? DzColors.red : DzColors.lime,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
                reste >= 0
                    ? 'reste ${reste.toStringAsFixed(1)} kg'
                    : 'dépassement ${(-reste).toStringAsFixed(1)} kg !',
                style: const TextStyle(color: DzColors.mut, fontSize: 11)),
          ),
          if (!closed)
            Row(children: [
              Expanded(flex: 4, child: TextField(controller: _nom,
                  decoration: const InputDecoration(labelText: 'Produit', isDense: true))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: _kg,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'kg', isDense: true))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: _prix,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'DA/kg', isDense: true))),
              const SizedBox(width: 4),
              IconButton(onPressed: _addProduit,
                  icon: const Icon(Icons.add_circle, color: DzColors.lime)),
            ]),
          const SizedBox(height: 6),
          ...produits.map((p) {
            final prix = _n(p['prix_kg']);
            final kgTxt = _n(p['kg']).toStringAsFixed(1);
            final ok = prix >= _pkMin;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(child: Text('${p['nom']}',
                    style: const TextStyle(fontSize: 12.5))),
                Text('$kgTxt kg  ',
                    style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                Text(_f(prix),
                    style: TextStyle(color: ok ? DzColors.lime : DzColors.txt,
                        fontSize: 12, fontWeight: FontWeight.w600)),
                if (!closed)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _delProduit(p['id']),
                    icon: const Icon(Icons.close, color: DzColors.red, size: 16),
                  ),
              ]),
            );
          }),
          if (produits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: Text('Valise vide — elle se remplit sur place.',
                  style: TextStyle(color: DzColors.mut, fontSize: 12))),
            ),
        ]),
      ),
      const SizedBox(height: 10),

      // ---- Statut projeté ----
      if (!closed && produits.isNotEmpty)
        _benef >= _obj
            ? _banner(DzColors.lime, '✓ Prêt — bénéfice projeté ${_f(_benef)} DA.')
            : reste > 0.5
                ? _banner(DzColors.amber,
                    '○ Il manque ${_f(_obj - _benef)} DA — vise ≥ ${_f((_obj - _benef) / reste)} DA/kg sur les ${reste.toStringAsFixed(1)} kg restants.')
                : _banner(DzColors.red,
                    '✕ Valise pleine, objectif non atteint (${_f(_obj - _benef)} DA manquants).'),

      if (!closed && !(m['cabine'] == true) && _benef < _obj && reste < 4)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: OutlinedButton(onPressed: _toggleCabine,
              child: const Text('+10 kg bagage cabine (dernier recours)')),
        ),
      const SizedBox(height: 12),

      // ---- Checklists ----
      if (!closed) ...[
        _checklist('Check avant le départ', 'check_depart', _itemsDepart),
        const SizedBox(height: 12),
        _checklist('Check avant le retour', 'check_retour', _itemsRetour),
        const SizedBox(height: 16),
        FilledButton(onPressed: _openCloture,
            child: const Text('■ Clôturer la mission')),
      ],

      if (closed) _clotureRecap(),
    ]);
  }

  /* ---------- Composants ---------- */
  Widget _card({required String titre, Widget? action, required Widget child}) =>
      Card(
        child: Padding(
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
        ),
      );

  Widget _ligne(String l, String v,
          {bool gras = false, Color couleur = DzColors.txt}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(l,
              style: const TextStyle(color: DzColors.mut, fontSize: 12.5))),
          Text(v, style: TextStyle(
              color: couleur, fontSize: 13,
              fontWeight: gras ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  Widget _checklist(String titre, String champ, List<(String, String)> items) {
    final etat = Map<String, dynamic>.from(_m![champ] as Map? ?? {});
    final faits = items.where((i) => etat[i.$1] == true).length;
    final complet = faits == items.length;
    return _card(
      titre: '$titre — $faits/${items.length}${complet ? ' ✓' : ''}',
      child: Column(children: [
        for (final (cle, label) in items)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: DzColors.lime,
            checkColor: DzColors.inkOnLime,
            controlAffinity: ListTileControlAffinity.leading,
            value: etat[cle] == true,
            onChanged: (v) => _toggleCheck(champ, cle, v ?? false),
            title: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: etat[cle] == true ? DzColors.mut : DzColors.txt,
                    decoration: etat[cle] == true
                        ? TextDecoration.lineThrough : null)),
          ),
      ]),
    );
  }

  Widget _kpi(String l, String v, Color c) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.toUpperCase(),
                  style: const TextStyle(color: DzColors.mut, fontSize: 8.5,
                      fontWeight: FontWeight.w700, letterSpacing: .8)),
              const SizedBox(height: 4),
              FittedBox(child: Text(v,
                  style: TextStyle(color: c, fontSize: 17, fontWeight: FontWeight.w800))),
            ]),
          ),
        ),
      );

  Widget _banner(Color c, String txt) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
            color: c.withValues(alpha: .08),
            border: Border.all(color: c.withValues(alpha: .4)),
            borderRadius: BorderRadius.circular(12)),
        child: Text(txt,
            style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );

  Widget _clotureRecap() {
    final m = _m!;
    final com = _n(m['commission']);
    final primes = _n(m['primes']);
    final paye = (m['paiements'] as List).fold<double>(0, (s, p) => s + _n(p['montant']));
    final solde = _n(m['attendu']) - paye;
    return _card(
      titre: 'Clôture & règlement',
      child: Column(children: [
        _ligne('Dépôt', '${m['depot'] ?? '—'}'),
        _ligne('Bénéfice mission', '${_f(_n(m['attendu']) - _frais)} DA'),
        _ligne('Commission voyageur (figée)', '${_f(com)} DA'),
        _ligne('Primes', '${_f(primes)} DA'),
        const Divider(color: DzColors.line, height: 16),
        _ligne(solde > 0 ? 'Reste à encaisser' : 'Soldé', '${_f(solde)} DA',
            gras: true, couleur: solde > 0 ? DzColors.amber : DzColors.lime),
      ]),
    );
  }

  /* ---------- Dialogues ---------- */
  Future<void> _editFrais() async {
    final m = _m!;
    final c = {
      for (final k in ['billet', 'dem_cout', 'jours', 'budget_jour', 'bea', 'douane',
        'autres', 'objectif', 'val_declaree'])
        k: TextEditingController(text: m[k] == null ? '' : '${_n(m[k]).toStringAsFixed(0)}'),
    };
    const labels = {
      'billet': 'Billet A/R (DA)', 'dem_cout': 'Démarches (DA)',
      'jours': 'Jours sur place', 'budget_jour': 'Budget / jour (DA)',
      'bea': 'Frais carte BEA (DA)', 'douane': 'Douane arrivée (DA)',
      'autres': 'Autres frais (DA)', 'objectif': 'Objectif bénéf (DA)',
      'val_declaree': 'Valeur déclarée (DA)',
    };
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          if (saving) return;
          setSt(() => saving = true);
          try {
            await Api.put('/missions/${widget.id}', {
              for (final e in c.entries)
                if (e.value.text.trim().isNotEmpty)
                  e.key: num.tryParse(e.value.text) ?? 0,
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx)
                  .showSnackBar(SnackBar(content: Text(e.message)));
            }
          }
        }

        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min, children: [
                  const Text('Modifier les frais',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  for (final k in labels.keys) ...[
                    TextField(controller: c[k],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: labels[k])),
                    const SizedBox(height: 14),
                  ],
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enregistrer'),
                  ),
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _addTranche() async {
    final montant = TextEditingController();
    final taux = TextEditingController();
    String devise = 'USD';
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          if (saving) return;
          setSt(() => saving = true);
          try {
            await Api.post('/missions/${widget.id}/tranches', {
              'montant': num.tryParse(montant.text) ?? 0,
              'devise': devise,
              'taux': num.tryParse(taux.text) ?? 0,
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx)
                  .showSnackBar(SnackBar(content: Text(e.message)));
            }
          }
        }

        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min, children: [
                const Text('Ajouter une tranche de devises',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: TextField(controller: montant,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Montant'))),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      initialValue: devise,
                      dropdownColor: DzColors.card2,
                      decoration: const InputDecoration(labelText: 'Devise'),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: Text('\$ USD')),
                        DropdownMenuItem(value: 'EUR', child: Text('€ EUR')),
                        DropdownMenuItem(value: 'RMB', child: Text('¥ RMB')),
                      ],
                      onChanged: (x) => setSt(() => devise = x ?? 'USD'),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                TextField(controller: taux,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Taux d’achat (DA pour 1 unité)')),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Ajouter'),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _openCloture() async {
    final depot = TextEditingController();
    final attendu = TextEditingController(text: _revenu.toStringAsFixed(0));
    final encaisse = TextEditingController(text: _revenu.toStringAsFixed(0));
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
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx)
                  .showSnackBar(SnackBar(content: Text(e.message)));
            }
          }
        }

        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min, children: [
                  Text('Clôturer ${_m!['code']}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Le voyage rembourse d’abord ses frais (${_f(_frais)} DA). '
                      'La commission du voyageur est figée maintenant.',
                      style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                  const SizedBox(height: 16),
                  TextField(controller: depot,
                      decoration: const InputDecoration(labelText: 'Dépôt / acheteur')),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: TextField(controller: attendu,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Attendu (DA)'))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: encaisse,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Encaissé maintenant'))),
                  ]),
                  const SizedBox(height: 16),
                  TextField(controller: primes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Primes économies (DA)')),
                  const SizedBox(height: 16),
                  TextField(controller: invendus,
                      decoration: const InputDecoration(
                          labelText: 'Invendus / prix renégociés')),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Clôturer la mission'),
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
