import 'dart:convert' show base64Encode;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';
import '../widgets/inventaire_picker.dart';
import '../widgets/factures_dialog.dart';
import '../services/download.dart';
import '../services/upload.dart';
import 'rapport_depots_screen.dart';

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

  bool _avantDepartRange = false;
  bool _rangeAuto = false;
  bool _formLibre = false;
  bool _valiseRange = false;
  bool? _volRange;
  List _factures = [];
  final _nom = TextEditingController();
  final _kg = TextEditingController();
  final _prix = TextEditingController();
  final _liquide = TextEditingController();

  static const _itemsDepart = [
    ('passeport', 'Passeport valide en poche', true),
    ('autorisations', 'Autorisations ANAE imprimées', false),
    ('carte_ae', 'Carte auto-entrepreneur', false),
    ('argent_depose', 'Argent déposé dans les cartes', false),
    ('enveloppe_douane', 'Enveloppe douane préparée (DA en liquide)', false),
    ('sim', 'Puce SIM emportée', false),
    ('vpn', 'VPN installé', false),
    ('wechat_alipay', 'WeChat + Alipay authentifiés', false),
    ('nourriture', 'Nourriture (5 jours)', false),
  ];
  static const _itemsRetour = [
    ('factures_dl', 'Factures téléchargées (PDF)', false),
    ('factures_cachet', 'Factures imprimées et cachetées', false),
    ('factures_scan', 'Factures scannées', false),
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
        Api.get('/factures?mission=${widget.id}'),
      ]);
      if (!mounted) return;
      setState(() {
        _m = res[0] as Map;
        _reglages = res[1] as Map;
        _factures = (res[2] as List?) ?? [];
        _liquide.text = _m!['liquide_remis'] == null
            ? _liquide.text : _n(_m!['liquide_remis']).toStringAsFixed(0);

        if (!_rangeAuto) {
          _rangeAuto = true;
          if (_departComplet && _m!['statut'] != 'cloturee') _avantDepartRange = true;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  List get _tr => (_m!['tranches'] as List?) ?? [];
  List get _trVoyage => _tr.where((t) => '${t['motif']}' == 'voyage').toList();
  List get _trPoche => _tr.where((t) => '${t['motif']}' == 'poche').toList();

  List get _trRestes => _tr.where((t) => '${t['motif']}' == 'reste').toList();
  double get _restesDA =>
      _trRestes.fold(0.0, (s, t) => s + _n(t['usd']) * _n(t['taux']));
  double get _perDiem => _n(_m!['jours']) * _n(_m!['budget_jour']);

  double get _pocheDA =>
      _trPoche.fold(0.0, (s, t) => s + _n(t['usd']) * _n(t['taux']));
  double get _poche {
    final brut = _pocheDA > 0 ? _pocheDA : _perDiem;
    return (brut - _restesDA).clamp(0, double.infinity);
  }

  double get _marchandiseDA =>
      _trVoyage.fold(0.0, (s, t) => s + _n(t['usd']) * _n(t['taux']));
  double get _marchandiseDevise => _trVoyage.fold(0.0, (s, t) => s + _n(t['usd']));

  double _rg(String cle) => _reglages == null ? 0 : _n(_reglages![cle]);
  double get _tauxMoyen {
    if (_marchandiseDevise > 0) return _marchandiseDA / _marchandiseDevise;
    final t = _rg('taux_officiel');
    return t > 0 ? t : 150;
  }

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

  double get _taxesCarte => (_facturee
          ? _n(_m!['factures_total']) : _marchandiseDevise) * _pctCarte * _tauxParallele;

  double get _declareTotal =>
      _affSoute.fold(0.0, (s, a) => s + _n(a['quantite']) * _n(a['prix_declare']));
  double get _baseDouane => _declareTotal > 0 ? _declareTotal : _marchandiseDevise;

  double get _basePrevision =>
      _declareTotal > 0 ? _declareTotal : _marchandiseDevise * (1 - _pctCarte);

  bool get _taxesReelles => _m!['taxes_reelles'] != null;

  bool get _marge30 {
    final v = _m!['ifu_marge'];
    if (v == null) return _rg('ifu_marge_30') > 0;
    return v == true || '$v' == 'true' || '$v' == '1';
  }
  double get _kIfu =>
      _m!['statut'] == 'cloturee' && !_taxesReelles ? (_marge30 ? 1.3 : 1.0) : 1.3;

  double get _douane => _taxesReelles
      ? _n(_m!['taxes_reelles'])
      : _m!['statut'] == 'cloturee'
          ? _n(_m!['douane'])
          : _basePrevision * _tauxOfficiel * (0.05 + 1.05 * _kIfu * 0.005);

  double get _taxeDouane5 => _douane * 0.05 / (0.05 + 1.05 * _kIfu * 0.005);
  double get _taxeIfu => _douane - _taxeDouane5;

  double get _valDeclaree => _facturee
      ? _n(_m!['val_declaree'])
      : _baseDouane * _tauxOfficiel;
  double get _frais => _n(_m!['billet']) + _n(_m!['dem_cout']) + _n(_m!['frais_visa']) +
      _poche + _douane + _taxesCarte + _n(_m!['autres']) + _n(_m!['manques_da']) +
      (_valiseSup ? _n(_m!['valise_sup_prix']) : 0) + _n(_m!['saisie_da']);

  bool get _valiseSup => _m!['valise_sup'] == true;
  bool get _bagMain => _m!['bagage_main'] == true;
  bool get _bagMainClose => _m!['bagage_main_close'] == true;
  double get _valiseSupKg { final k = _n(_m!['valise_sup_kg']); return k > 0 ? k : 23; }
  double get _bagMainKg { final k = _n(_m!['bagage_main_kg']); return k > 0 ? k : 8; }
  double get _capSoute => _n(_m!['kg_soute']) + (_valiseSup ? _valiseSupKg : 0);
  double get _cap => _capSoute + (_bagMain ? _bagMainKg : 0);

  bool get _tousBagagesClos => _valiseClose && (!_bagMain || _bagMainClose);

  List get _aff => (_m!['affectations'] as List?) ?? [];
  List get _affSoute => _aff.where((a) => '${a['emplacement'] ?? 'soute'}' != 'main').toList();
  List get _affMain => _aff.where((a) => '${a['emplacement']}' == 'main').toList();
  double get _usedMain =>
      _affMain.fold(0.0, (s, a) => s + _n(a['quantite']) * _n(a['poids_unit']));
  double get _usedSoute => (_m!['produits'] as List).fold(0.0, (s, p) => s + _n(p['kg'])) +
      _affSoute.fold(0.0, (s, a) => s + _n(a['quantite']) * _n(a['poids_unit']));
  double get _used => _usedSoute + _usedMain;

  double get _revenu => (_m!['produits'] as List)
      .fold(0.0, (s, p) => s + _n(p['kg']) * _n(p['prix_kg'])) +
      _aff.fold(0.0, (s, a) => s + (_n(a['quantite']) - _n(a['saisis'])) * _n(a['gain_piece']));
  double get _benef => _revenu - _frais;
  double get _obj => _n(_m!['objectif']);

  double get _pkMin => _cap > 0 ? (_frais + _obj) / _cap : 0;

  double get _aCouvrir => (_frais + _obj - _revenu) > 0 ? (_frais + _obj - _revenu) : 0;
  double get _kgLibre => (_cap - _used) > 0 ? (_cap - _used) : 0;
  double get _pkRestant => _kgLibre > 0 ? _aCouvrir / _kgLibre : 0;

  bool get _volPasse {
    final d = DateTime.tryParse('${_m!['depart'] ?? ''}'.substring(0, '${_m!['depart'] ?? ''}'.length >= 10 ? 10 : 0));
    if (d == null) return false;
    final now = DateTime.now();
    return !DateTime(now.year, now.month, now.day).isBefore(d);
  }
  int get _etape {
    if (_m!['statut'] == 'cloturee') return 5;
    if (_valiseClose) return 4;
    if (_departComplet && _volPasse) return 3;
    if (_departComplet) return 2;
    return 1;
  }
  String get _devise => '${_m!['v_devise'] ?? 'USD'}';
  double get _soldeDevises => _n(_m!['v_solde']);

  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  String _sym(String d) => d == 'EUR' ? '€' : d == 'RMB' ? '¥' : d == 'DA' ? 'DA' : '\$';

  String _mnt(num n, String devise) => '${_f(n)} ${_sym(devise)}';

  String _demLabel(dynamic t) => switch ('$t') {
        'premiere' => 'Première demande',
        'renouvellement' => 'Renouvellement',
        'visa_double' => 'Visa double entrée',
        _ => 'Visa multiple',
      };

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
    final fermer = !_valiseClose;
    try {
      await Api.put('/missions/${widget.id}', {'valise_close': fermer});
      await _load();

      if (fermer && mounted && _affNonFacturees.isNotEmpty) {
        _snack('Valise complète ✓ — ${_affNonFacturees.length} produit(s) pas encore facturé(s).');
      }

      if (fermer && mounted && (!_valiseSup || !_bagMain)) await _proposerBagages();
    } on ApiException catch (e) { _snack(e.message); }
  }

  Future<void> _proposerBagages() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DzColors.card,
        title: const Text('Ajouter des kilos ?', style: TextStyle(fontSize: 16)),
        content: const Text(
            'La valise est complète — tu peux encore acheter une 3e valise à la '
            'compagnie (déclarée, facturée) ou remplir le bagage à main '
            '(non déclaré, jamais facturé).',
            style: TextStyle(color: DzColors.mut, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Non merci')),
          if (!_valiseSup)
            TextButton(
              onPressed: () { Navigator.pop(ctx); _activerValiseSup(); },
              child: const Text('+ 3e valise', style: TextStyle(color: DzColors.lime)),
            ),
          if (!_bagMain)
            FilledButton(
              onPressed: () { Navigator.pop(ctx); _activerBagMain(); },
              child: const Text('+ Bagage à main'),
            ),
        ],
      ),
    );
  }

  Future<void> _activerValiseSup() async {
    final prix = TextEditingController(
        text: _n(_m!['valise_sup_prix']) > 0 ? _f(_n(_m!['valise_sup_prix'])).replaceAll(' ', '') : '');
    final kg = TextEditingController(text: _valiseSupKg.toStringAsFixed(0));
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DzColors.card,
        title: const Text('3e valise (compagnie)', style: TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Le prix de la valise est une dépense de la mission ; ses produits '
              'vont dans la valise normale (déclarés, facturés, taxés).',
              style: TextStyle(color: DzColors.mut, fontSize: 12)),
          const SizedBox(height: 14),
          TextField(controller: prix, keyboardType: TextInputType.number, autofocus: true,
              decoration: const InputDecoration(labelText: 'Prix de la valise (DA)')),
          const SizedBox(height: 12),
          TextField(controller: kg, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Poids (kg)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Api.put('/missions/${widget.id}', {
                  'valise_sup': true,
                  'valise_sup_prix': num.tryParse(prix.text.replaceAll(' ', '')) ?? 0,
                  'valise_sup_kg': num.tryParse(kg.text.replaceAll(',', '.')) ?? 23,
                });
                await _load();
              } on ApiException catch (e) { _snack(e.message); }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _retirerValiseSup() async {
    try {
      await Api.put('/missions/${widget.id}', {'valise_sup': false, 'valise_sup_prix': 0});
      await _load();
    } on ApiException catch (e) { _snack(e.message); }
  }

  Future<void> _valiseSupMenu() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DzColors.card,
        title: const Text('3e valise', style: TextStyle(fontSize: 16)),
        content: Text('${_valiseSupKg.toStringAsFixed(0)} kg · ${_f(_n(_m!['valise_sup_prix']))} DA',
            style: const TextStyle(color: DzColors.mut, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(onPressed: () { Navigator.pop(ctx); _activerValiseSup(); },
              child: const Text('Modifier')),
          TextButton(onPressed: () { Navigator.pop(ctx); _retirerValiseSup(); },
              child: const Text('Retirer', style: TextStyle(color: DzColors.red))),
        ],
      ),
    );
  }

  Future<void> _activerBagMain() async {
    final kg = TextEditingController(text: _bagMainKg.toStringAsFixed(0));
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DzColors.card,
        title: const Text('Bagage à main', style: TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Produits JAMAIS déclarés ni facturés — mais comptés dans le revenu, '
              'le prix du kilo et les bons de remise.',
              style: TextStyle(color: DzColors.mut, fontSize: 12)),
          const SizedBox(height: 14),
          TextField(controller: kg, keyboardType: TextInputType.number, autofocus: true,
              decoration: const InputDecoration(labelText: 'Kilos autorisés (souvent 8)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Api.put('/missions/${widget.id}', {
                  'bagage_main': true,
                  'bagage_main_kg': num.tryParse(kg.text.replaceAll(',', '.')) ?? 8,
                });
                await _load();
              } on ApiException catch (e) { _snack(e.message); }
            },
            child: const Text('Activer'),
          ),
        ],
      ),
    );
  }

  Future<void> _bagMainMenu() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DzColors.card,
        title: const Text('Bagage à main', style: TextStyle(fontSize: 16)),
        content: Text('${_bagMainKg.toStringAsFixed(0)} kg · ${_affMain.length} produit(s)',
            style: const TextStyle(color: DzColors.mut, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(onPressed: () { Navigator.pop(ctx); _activerBagMain(); },
              child: const Text('Modifier les kilos')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (_affMain.isNotEmpty) {
                _snack('Vide d’abord le bagage à main (remets ses produits en stock).');
                return;
              }
              try {
                await Api.put('/missions/${widget.id}',
                    {'bagage_main': false, 'bagage_main_close': false});
                await _load();
              } on ApiException catch (e) { _snack(e.message); }
            },
            child: const Text('Retirer', style: TextStyle(color: DzColors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBagMainClose() async {
    try {
      await Api.put('/missions/${widget.id}', {'bagage_main_close': !_bagMainClose});
      await _load();
    } on ApiException catch (e) { _snack(e.message); }
  }

  int? _factureDe(dynamic affId) {
    for (final f in _factures) {
      for (final l in (f['lignes'] as List? ?? [])) {
        final id = l['affectation_id'];
        final n = id is int ? id : int.tryParse('$id');
        if (n == affId) return f['numero'] is int ? f['numero'] : int.tryParse('${f['numero']}');
      }
    }
    return null;
  }

  List get _affNonFacturees {
    final deja = <int>{};
    for (final f in _factures) {
      for (final l in (f['lignes'] as List? ?? [])) {
        final id = l['affectation_id'];
        if (id != null) deja.add(id is int ? id : int.tryParse('$id') ?? -1);
      }
    }
    return _affSoute.where((a) => !deja.contains(a['id'])).toList();
  }

  Future<void> _facturer() async {
    final reste = _affNonFacturees;
    if (reste.isEmpty) return;
    final ok = await showFacturesDialog(context,
        missionId: widget.id, affectations: reste,
        depart: _m!['depart']?.toString().substring(0, 10), retour: _m!['retour']?.toString().substring(0, 10));
    if (ok) _load();
  }

  Future<void> _telechargerFacture(Map f) async {
    try {
      final bytes = await Api.getBytes('/factures/${f['id']}/pdf');
      await saveFile('facture-${_m!['code']}-${f['numero']}.pdf', bytes);
    } catch (e) { _snack('$e'); }
  }

  Future<void> _telechargerToutes() async {
    try {
      final bytes = await Api.getBytes('/factures/mission/${widget.id}/pdf');
      await saveFile('factures-${_m!['code']}.pdf', bytes);
    } catch (e) { _snack('$e'); }
  }

  Future<void> _annulerFacture(Map f) async {
    try {
      await Api.delete('/factures/${f['id']}');
      _load();
    } on ApiException catch (e) { _snack(e.message); }
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

      if (res is Map && res['supprimee'] == false) {
        _snack('${res['message'] ?? 'En attente de validation de l’autre admin.'}');
        return;
      }
      widget.embedded ? widget.onBack?.call() : Navigator.pop(context);
    } on ApiException catch (e) { _snack(e.message); }
  }

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
            : switch (_etape) {
                1 => ('● Préparation', DzColors.amber),
                2 => ('● Vol aller', DzColors.amber),
                3 => _pret ? ('● Sur place · prêt', DzColors.lime) : ('● Sur place', DzColors.amber),
                _ => ('● Retour', DzColors.lime),
              };
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

    final e = _etape;
    final volRange = _volRange ?? (e >= 3);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 32), children: [
      Text('${m['vol'] ?? ''} · ${dateFr(m['depart'])} → ${dateFr(m['retour'])} · '
          '${m['jours']} j · compte ${_devise}',
          style: const TextStyle(color: DzColors.mut, fontSize: 12)),
      const SizedBox(height: 12),

      if (over)
        _banner(DzColors.red, '⚖ Valeur déclarée > 1 800 000 DA — mission illégale en l’état.'),

      _timeline(wide),
      const SizedBox(height: 12),

      _kpiRow(),
      const SizedBox(height: 12),

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

      if (volRange) _volResume() else _sectionVol(closed),
      const SizedBox(height: 12),

      if (_valiseClose && _valiseRange)
        _valiseResume()
      else if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 11, child: _sectionValise(closed)),
          const SizedBox(width: 12),
          Expanded(flex: 9, child: _sectionFactures(closed)),
        ])
      else ...[
        _sectionValise(closed),
        const SizedBox(height: 12),
        _sectionFactures(closed),
      ],
      const SizedBox(height: 12),

      if (_bagMain) ...[
        _sectionBagageMain(closed),
        const SizedBox(height: 12),
      ],

      if (!closed && !_taxesReelles && _tousBagagesClos) ...[
        _sectionEnveloppe(),
        const SizedBox(height: 12),
      ],

      Opacity(
        opacity: (_valiseClose || closed) ? 1 : .55,
        child: _checklist('Check avant le retour', 'check_retour', _itemsRetour),
      ),
      const SizedBox(height: 12),

      if (_taxesReelles || (_valiseClose && !closed)) ...[
        _sectionArrivee(closed),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 4),

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

  Widget _timeline(bool wide) {
    final e = _etape;
    final m = _m!;
    final (f, t) = _avancement('check_depart', _itemsDepart, _autoDepart());
    final steps = [
      ('Préparer', 'dépenses · BEA · check $f/$t'),
      ('Vol aller', '${m['vol'] ?? ''} · ${dateFr(m['depart'])}${(m['heure_arrivee'] ?? '').toString().isNotEmpty ? ' · arrivée ${m['heure_arrivee']}' : ''}'),
      ('Sur place', 'valise ${_used.toStringAsFixed(1)} / ${_cap.toStringAsFixed(0)} kg · ${_factures.length} facture${_factures.length > 1 ? 's' : ''}'),
      ('Retour', m['statut'] == 'cloturee' ? 'clôturée' : 'check retour · clôture'),
    ];
    Widget dot(int i) {
      final done = e > i + 1, now = e == i + 1;
      return Container(
        width: 26, height: 26, alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? DzColors.lime : Colors.transparent,
          border: Border.all(color: (done || now) ? DzColors.lime : DzColors.line, width: 2),
          boxShadow: now ? [BoxShadow(color: DzColors.lime.withValues(alpha: .18), spreadRadius: 4)] : null,
        ),
        child: done
            ? const Icon(Icons.check, size: 14, color: DzColors.inkOnLime)
            : Text('${i + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: now ? DzColors.lime : DzColors.mut)),
      );
    }
    Widget label(int i) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(steps[i].$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: e >= i + 1 ? DzColors.txt : DzColors.mut)),
          Text(steps[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: DzColors.mut)),
        ]);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 14, vertical: 14),
      decoration: BoxDecoration(color: DzColors.card, borderRadius: BorderRadius.circular(16)),
      child: wide
          ? Row(children: [
              for (var i = 0; i < 4; i++) ...[
                dot(i), const SizedBox(width: 10), Expanded(child: label(i)),
                if (i < 3) Container(width: 40, height: 2, margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: e > i + 1 ? DzColors.lime : DzColors.line),
              ],
            ])
          : Column(children: [
              for (var i = 0; i < 4; i++)
                Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [dot(i), const SizedBox(width: 10), Expanded(child: label(i))])),
            ]),
    );
  }

  Widget _volResume() {
    final m = _m!;
    final hd = '${m['heure_depart'] ?? ''}', ha = '${m['heure_arrivee'] ?? ''}';
    return _ligneRangee(
      Icons.flight_takeoff_outlined,
      '② Vol aller — ${m['vol'] ?? ''} · départ ${dateFr(m['depart'])}${hd.isNotEmpty ? ' $hd' : ''}'
      ' → arrivée${ha.isNotEmpty ? ' $ha' : ''} · retour ${dateFr(m['retour'])}',
      onDerouler: () => setState(() => _volRange = false),
    );
  }

  Widget _ligneRangee(IconData ic, String texte, {required VoidCallback onDerouler}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: DzColors.card, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.check_circle, size: 14, color: DzColors.lime),
          const SizedBox(width: 9),
          Expanded(child: Text(texte, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DzColors.mut))),
          TextButton.icon(
            onPressed: onDerouler,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.unfold_more, size: 15),
            label: const Text('Dérouler', style: TextStyle(fontSize: 12)),
          ),
        ]),
      );

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

        InkWell(
          onTap: closed ? null : () => _gererTranches(poche: true),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Text(
                    (_pocheDA > 0
                        ? 'Argent de poche · ${_trPoche.length} tranche${_trPoche.length > 1 ? 's' : ''}'
                        : 'Argent de poche · prévision ${m['jours']} j') +
                        (_restesDA > 0 ? ' · rendu ${_f(_restesDA)} DA' : ''),
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
        if (_taxesReelles)
          _ligne('Taxes douane + IFU (réelles — payées à l’arrivée)', '${_f(_douane)} DA')
        else ...[
          _ligne(
              douaneReelle
                  ? 'Douane 5 % (réelle, factures)'
                  : 'Douane 5 % — avance (${_declareTotal > 0 ? 'prix déclarés' : 'dépôt − taxes carte'})',
              '${_f(_taxeDouane5)} DA'),
          _ligne(
              m['statut'] == 'cloturee'
                  ? 'Taxe IFU 0,5 %${_marge30 ? ' — marge douane +30 %' : ''}'
                  : 'Taxe IFU 0,5 % — marge 30 % comptée (au cas où)',
              '${_f(_taxeIfu)} DA'),
        ],
        _ligne(
            _facturee
                ? 'Taxes carte (réelles, factures)'
                : 'Taxes carte — si tout le dépôt est retiré',
            '${_f(_taxesCarte)} DA'),
        if (_valiseSup)
          _ligne('3e valise (compagnie, ${_valiseSupKg.toStringAsFixed(0)} kg)',
              '${_f(_n(m['valise_sup_prix']))} DA'),
        if (_n(m['saisie_da']) > 0)
          _ligne('Saisie douanière (remboursée aux chambres)',
              '${_f(_n(m['saisie_da']))} DA', couleur: DzColors.red),
        _ligne('Autres frais', '${_f(_n(m['autres']))} DA'),
        const Divider(color: DzColors.line, height: 18),
        _ligne('Total dépenses', '${_f(_frais)} DA', gras: true),
      ]),
    );
  }

  Future<void> _gererTranches({required bool poche, bool restes = false}) async {
    final montant = TextEditingController();
    final taux = TextEditingController();
    String devise = restes ? 'DA' : (poche ? 'EUR' : _devise);
    String mode = 'Cash';
    bool saving = false;
    const modes = ['Cash', 'Carte', 'RMB Alipay'];
    final libre = poche || restes;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        final tranches = restes ? _trRestes : (poche ? _trPoche : _trVoyage);
        final totalDevise = libre ? null : _marchandiseDevise;
        final totalDA = restes ? _restesDA : (poche ? _pocheDA : _marchandiseDA);
        Future<void> add() async {
          if (saving) return;
          setSt(() => saving = true);
          try {
            await Api.post('/missions/${widget.id}/tranches', {
              'montant': num.tryParse(montant.text) ?? 0,
              'devise': devise,
              if (devise != 'DA') 'taux': num.tryParse(taux.text) ?? 0,
              'motif': restes ? 'reste' : (poche ? 'poche' : 'voyage'),
              if (libre) 'source': devise == 'RMB' ? 'RMB Alipay' : mode,
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
                  Text(restes ? 'Argent rendu au retour — restes'
                      : poche ? 'Argent de poche — tranches'
                             : 'Argent déposé · compte ${_devise}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(restes
                          ? 'Ce qui REVIENT à l’agence : cash DA / € / \$, RMB Alipay… '
                            'La dépense de poche réelle devient donné − rendu.'
                          : poche
                          ? 'Cash € / \$, devise en carte, RMB Alipay… plusieurs à la fois.'
                          : 'Chaque dépôt sur la carte, au taux réel du jour.',
                      style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                  const SizedBox(height: 14),

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

                  if (libre) ...[
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
                            labelText: 'Montant (${_sym(libre ? devise : _devise)})', isDense: true))),
                    if (!libre || devise != 'DA') ...[
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

  Widget _sectionVol(bool closed) {
    final m = _m!;
    final hd = '${m['heure_depart'] ?? ''}';
    final ha = '${m['heure_arrivee'] ?? ''}';
    return _card(
      titre: '② Vol aller',
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_etape >= 3)
          TextButton.icon(
            onPressed: () => setState(() => _volRange = true),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.unfold_less, size: 15),
            label: const Text('Ranger', style: TextStyle(fontSize: 12)),
          ),
        if (!closed) IconButton(
          onPressed: _editVol,
          icon: const Icon(Icons.edit_outlined, size: 17, color: DzColors.mut),
          tooltip: 'Heures du vol',
        ),
      ]),
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

  Widget _sectionValise(bool closed) {
    final m = _m!;
    final produits = m['produits'] as List;

    final reste = _capSoute - _usedSoute;
    final vClose = _valiseClose;
    return _card(
      titre: 'Valise — ${_usedSoute.toStringAsFixed(1)} / ${_capSoute.toStringAsFixed(0)} kg'
          '${_valiseSup ? ' (3 valises)' : ''}${vClose ? ' · complète ✓' : ''}',

      action: (produits.isEmpty && _aff.isEmpty) ? null : Row(mainAxisSize: MainAxisSize.min, children: [
        if (vClose)
          TextButton.icon(
            onPressed: () => setState(() => _valiseRange = true),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.unfold_less, size: 15),
            label: const Text('Ranger', style: TextStyle(fontSize: 12)),
          ),
        if (!closed)
          TextButton.icon(
            onPressed: _toggleValiseClose,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
                foregroundColor: vClose ? DzColors.mut : DzColors.lime),
            icon: Icon(vClose ? Icons.lock_open_outlined : Icons.lock_outline, size: 15),
            label: Text(vClose ? 'Rouvrir' : 'Valise complète', style: const TextStyle(fontSize: 12)),
          ),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: (_aCouvrir <= 0 ? DzColors.lime : DzColors.amber).withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: (_aCouvrir <= 0 ? DzColors.lime : DzColors.amber).withValues(alpha: .35)),
          ),
          child: _aCouvrir <= 0
              ? Row(children: [
                  const Icon(Icons.check_circle, size: 16, color: DzColors.lime),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Objectif couvert — tout ce que tu ajoutes est du bénéfice (${_kgLibre.toStringAsFixed(1)} kg libres).',
                      style: const TextStyle(color: DzColors.lime, fontSize: 12, fontWeight: FontWeight.w600))),
                ])
              : Row(children: [
                  const Icon(Icons.speed_outlined, size: 16, color: DzColors.amber),
                  const SizedBox(width: 8),
                  Expanded(child: Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Prix min. restant  ', style: TextStyle(color: DzColors.mut, fontSize: 11.5)),
                    TextSpan(text: '${_f(_pkRestant)} DA/kg', style: const TextStyle(color: DzColors.amber, fontSize: 14, fontWeight: FontWeight.w800)),
                    TextSpan(text: '   ·  reste ${_kgLibre.toStringAsFixed(1)} kg · ${_f(_aCouvrir)} DA à couvrir',
                        style: const TextStyle(color: DzColors.mut, fontSize: 11)),
                    if (_pkRestant < _pkMin - 1)
                      TextSpan(text: '   (était ${_f(_pkMin)})', style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
                  ]))),
                ]),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _capSoute > 0 ? (_usedSoute / _capSoute).clamp(0, 1).toDouble() : 0,
            minHeight: 8, backgroundColor: DzColors.card2,
            color: _usedSoute > _capSoute ? DzColors.red : DzColors.lime,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(reste >= 0
              ? 'reste ${reste.toStringAsFixed(1)} kg en soute'
              : 'dépassement ${(-reste).toStringAsFixed(1)} kg !',
              style: const TextStyle(color: DzColors.mut, fontSize: 11)),
        ),

        if (!closed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilterChip(
                selected: _valiseSup,
                onSelected: (v) => v ? _activerValiseSup() : _valiseSupMenu(),
                label: Text(_valiseSup
                    ? '3e valise · ${_valiseSupKg.toStringAsFixed(0)} kg · ${_f(_n(m['valise_sup_prix']))} DA'
                    : '3e valise (compagnie)', style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              ),
              FilterChip(
                selected: _bagMain,
                onSelected: (v) => v ? _activerBagMain() : _bagMainMenu(),
                label: Text(_bagMain
                    ? 'Bagage à main · ${_bagMainKg.toStringAsFixed(0)} kg (non déclaré)'
                    : 'Bagage à main (non déclaré)', style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              ),
              const Text('comptés dans le prix du kilo', style: TextStyle(color: DzColors.mut, fontSize: 10)),
            ]),
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
                      manqueDA: _aCouvrir, prixKiloMin: _pkRestant);
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

        ..._affSoute.map((a) {
          final q = _n(a['quantite']), pu = _n(a['poids_unit']), gp = _n(a['gain_piece']);
          final gainKg = pu > 0 ? gp / pu : 0.0;
          final ok = gainKg >= _pkMin;
          final numFact = _factureDe(a['id']);
          final verrou = numFact != null;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [

              Tooltip(
                message: verrou ? 'Sur la facture n° $numFact' : 'Pas encore facturé',
                child: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: verrou ? DzColors.lime : DzColors.amber,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['produit']}', style: const TextStyle(fontSize: 12.5)),
                Text('${a['chambre_nom']} · ${_f(q)} pc · déclaré ${_n(a['prix_declare']).toStringAsFixed(2)} \$/pc',
                    style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
              ])),
              Text('${(q * pu).toStringAsFixed(1)} kg  ', style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
              Text('${_f(q * gp)} DA', style: TextStyle(color: ok ? DzColors.lime : DzColors.txt,
                  fontSize: 12, fontWeight: FontWeight.w600)),
              if (!closed && !vClose && !verrou)
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    tooltip: 'Remettre en stock',
                    onPressed: () => _delAffectation(a['id']),
                    icon: const Icon(Icons.close, color: DzColors.red, size: 16)),
            ]),
          );
        }),

        if (_affSoute.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: DzColors.lime)),
              const SizedBox(width: 5),
              const Text('facturé', style: TextStyle(color: DzColors.mut, fontSize: 10)),
              const SizedBox(width: 12),
              Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: DzColors.amber)),
              const SizedBox(width: 5),
              const Text('à facturer', style: TextStyle(color: DzColors.mut, fontSize: 10)),
            ]),
          ),

        if (!closed && _affNonFacturees.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              FilledButton.icon(
                onPressed: _facturer,
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: Text('Facturer ${_affNonFacturees.length} produit(s) non facturé(s)'),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('date proposée : aujourd’hui (jour du paiement carte)',
                  style: TextStyle(color: DzColors.mut, fontSize: 10.5))),
            ]),
          ),
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
        if (produits.isEmpty && _affSoute.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: Text('Valise vide — elle se remplit sur place, depuis l’inventaire.',
                  style: TextStyle(color: DzColors.mut, fontSize: 12)))),
        if (!closed && (produits.isNotEmpty || _aff.isNotEmpty))
          Padding(padding: const EdgeInsets.only(top: 8), child:
            _benef >= _obj
                ? _bannerInline(DzColors.lime, '✓ Prêt — bénéfice projeté ${_f(_benef)} DA.')
                : _kgLibre > 0.5
                    ? _bannerInline(DzColors.amber,
                        '○ Il manque ${_f(_obj - _benef)} DA — vise ≥ ${_f((_obj - _benef) / _kgLibre)} DA/kg '
                        '(${_kgLibre.toStringAsFixed(1)} kg libres, bagage à main inclus).')
                    : _bannerInline(DzColors.red,
                        '✕ Bagages pleins, objectif non atteint (${_f(_obj - _benef)} DA).')),
      ]),
    );
  }

  Widget _valiseResume() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(color: DzColors.card, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.luggage_outlined, size: 16, color: DzColors.lime),
          const SizedBox(width: 9),
          Expanded(child: Text(
              'Valise complète ✓ · ${_usedSoute.toStringAsFixed(1)} / ${_capSoute.toStringAsFixed(0)} kg · '
              '${_affSoute.length + (_m!['produits'] as List).length} produit(s) · revenu ${_f(_revenu)} DA · '
              '${_factures.length} facture${_factures.length > 1 ? 's' : ''}'
              '${_affNonFacturees.isNotEmpty ? ' · ${_affNonFacturees.length} à facturer' : ''}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          TextButton.icon(
            onPressed: () => setState(() => _valiseRange = false),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.unfold_more, size: 15),
            label: const Text('Dérouler', style: TextStyle(fontSize: 12)),
          ),
        ]),
      );

  Widget _sectionBagageMain(bool closed) {
    final complet = _bagMainClose;
    return _card(
      titre: 'Bagage à main — ${_usedMain.toStringAsFixed(1)} / ${_bagMainKg.toStringAsFixed(0)} kg'
          '${complet ? ' · complet ✓' : ''}',
      action: closed ? null : TextButton.icon(
        onPressed: _toggleBagMainClose,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
            foregroundColor: complet ? DzColors.mut : DzColors.lime),
        icon: Icon(complet ? Icons.lock_open_outlined : Icons.lock_outline, size: 15),
        label: Text(complet ? 'Rouvrir' : 'Bagage complet', style: const TextStyle(fontSize: 12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _bannerInline(DzColors.amber,
            'Non déclaré : jamais sur les factures, jamais dans la douane/IFU, rien via la '
            'carte BEA — mais compté dans le revenu, le prix du kilo et les bons de remise.'),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _bagMainKg > 0 ? (_usedMain / _bagMainKg).clamp(0, 1).toDouble() : 0,
            minHeight: 8, backgroundColor: DzColors.card2,
            color: _usedMain > _bagMainKg ? DzColors.red : DzColors.lime,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text('reste ${(_bagMainKg - _usedMain).clamp(0, 999).toStringAsFixed(1)} kg',
              style: const TextStyle(color: DzColors.mut, fontSize: 11)),
        ),
        if (!closed && !complet)
          FilledButton.icon(
            onPressed: () async {
              final reste = _bagMainKg - _usedMain;
              final ok = await showInventairePicker(context,
                  missionId: widget.id, kgDispo: reste > 0 ? reste : 0,
                  manqueDA: _aCouvrir, prixKiloMin: _pkRestant,
                  emplacement: 'main',
                  dejaValise: {
                    for (final a in _affSoute)
                      if (a['ligne_id'] != null)
                        a['ligne_id'] is int ? a['ligne_id'] as int : int.tryParse('${a['ligne_id']}') ?? -1,
                  });
              if (ok) _load();
            },
            icon: const Icon(Icons.backpack_outlined, size: 16),
            label: const Text('Remplir le bagage à main'),
          ),
        const SizedBox(height: 6),
        ..._affMain.map((a) {
          final q = _n(a['quantite']), pu = _n(a['poids_unit']), gp = _n(a['gain_piece']);
          final saisis = _n(a['saisis']);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              const Icon(Icons.backpack_outlined, size: 12, color: DzColors.mut),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['produit']}', style: const TextStyle(fontSize: 12.5)),
                Text('${a['chambre_nom']} · ${_f(q)} pc — non déclaré'
                    '${saisis > 0 ? ' · ⚠ $saisis saisie(s)' : ''}',
                    style: TextStyle(color: saisis > 0 ? DzColors.red : DzColors.mut, fontSize: 10.5)),
              ])),
              Text('${(q * pu).toStringAsFixed(1)} kg  ', style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
              Text('${_f((q - saisis) * gp)} DA',
                  style: const TextStyle(color: DzColors.lime, fontSize: 12, fontWeight: FontWeight.w600)),
              if (!closed && !complet)
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    tooltip: 'Remettre en stock',
                    onPressed: () => _delAffectation(a['id']),
                    icon: const Icon(Icons.close, color: DzColors.red, size: 16)),
            ]),
          );
        }),
        if (_affMain.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: Text('Bagage à main vide — varie les produits, 2 pièces max par produit.',
                  style: TextStyle(color: DzColors.mut, fontSize: 12)))),
      ]),
    );
  }

  Widget _sectionEnveloppe() {
    final liquide = _n(_m!['liquide_remis']);
    return _card(
      titre: 'Enveloppe douane — à préparer en liquide (DA)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Tous les bagages sont clos : prépare le dinar dans une enveloppe à remettre '
            'directement aux douaniers à l’arrivée.',
            style: TextStyle(color: DzColors.mut, fontSize: 11.5)),
        const SizedBox(height: 10),
        _ligne('Douane 5 % (${_declareTotal > 0 ? 'prix déclarés' : 'dépôt − taxes carte'})',
            '${_f(_taxeDouane5)} DA'),
        _ligne('Taxe IFU 0,5 % — marge 30 % comptée (au cas où)', '${_f(_taxeIfu)} DA'),
        const Divider(color: DzColors.line, height: 18),
        _ligne('Enveloppe à préparer', '${_f(_douane)} DA', gras: true),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(
            controller: _liquide, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Liquide remis au voyageur (DA)', isDense: true),
          )),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () async {
              try {
                await Api.put('/missions/${widget.id}',
                    {'liquide_remis': num.tryParse(_liquide.text.replaceAll(' ', '')) ?? 0});
                await _load();
              } on ApiException catch (e) { _snack(e.message); }
            },
            child: const Text('OK'),
          ),
        ]),
        if (liquide > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ligne('Reste pour le voyageur (taxi retour · imprévu douane)',
                '${_f((liquide - _douane).clamp(0, double.infinity))} DA',
                couleur: liquide >= _douane ? DzColors.lime : DzColors.red),
          ),
        if (liquide > 0 && liquide < _douane)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('⚠ Le liquide remis ne couvre pas l’enveloppe prévue.',
                style: TextStyle(color: DzColors.red, fontSize: 11)),
          ),
      ]),
    );
  }

  Widget _sectionArrivee(bool closed) {
    if (!_taxesReelles) {
      return _card(
        titre: 'Arrivée en Algérie — douane',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Après le passage en douane : saisis les taxes exactement payées (elles '
              'remplacent la prévision dans toute la compta), la photo du bon des douaniers '
              'si disponible, et la saisie s’il y en a eu.',
              style: TextStyle(color: DzColors.mut, fontSize: 11.5)),
          const SizedBox(height: 10),
          Row(children: [
            FilledButton.icon(
              onPressed: _openArrivee,
              icon: const Icon(Icons.flight_land, size: 16),
              label: const Text('Saisir les taxes payées'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _gererTranches(poche: true, restes: true),
              icon: const Icon(Icons.savings_outlined, size: 15),
              label: Text(_restesDA > 0
                  ? 'Argent rendu · ${_f(_restesDA)} DA' : 'Argent rendu (restes)',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ]),
      );
    }
    final ecart = _n(_m!['taxes_reelles']) - _basePrevision * _tauxOfficiel * (0.05 + 1.05 * 1.3 * 0.005);
    return _card(
      titre: 'Arrivée en Algérie — douane ✓',
      action: closed ? null : TextButton(
        onPressed: _openArrivee,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact),
        child: const Text('Modifier', style: TextStyle(fontSize: 12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _ligne('Taxes payées aux douaniers (réelles)', '${_f(_n(_m!['taxes_reelles']))} DA', gras: true),
        if (ecart.abs() > 1)
          _ligne(ecart > 0 ? 'Écart vs prévision (payé en plus)' : 'Écart vs prévision (payé en moins)',
              '${_f(ecart.abs())} DA', couleur: ecart > 0 ? DzColors.red : DzColors.lime),
        if (_n(_m!['saisie_da']) > 0)
          _ligne('Saisie douanière — remboursée aux chambres', '${_f(_n(_m!['saisie_da']))} DA',
              couleur: DzColors.red),
        if (_restesDA > 0)
          _ligne('Argent rendu par le voyageur (restes)', '${_f(_restesDA)} DA',
              couleur: DzColors.lime),
        if ('${_m!['arrivee_note'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Note : ${_m!['arrivee_note']}',
                style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (_m!['arrivee_photo'] == true)
            OutlinedButton.icon(
              onPressed: _voirPhotoDouane,
              icon: const Icon(Icons.image_outlined, size: 15),
              label: const Text('Photo du bon', style: TextStyle(fontSize: 12)),
            ),
          if (!closed)
            OutlinedButton.icon(
              onPressed: () => _gererTranches(poche: true, restes: true),
              icon: const Icon(Icons.savings_outlined, size: 15),
              label: const Text('Argent rendu', style: TextStyle(fontSize: 12)),
            ),
          OutlinedButton.icon(
            onPressed: _ouvrirRapportDepots,
            icon: const Icon(Icons.warehouse_outlined, size: 15),
            label: const Text('Rapport dépôts', style: TextStyle(fontSize: 12)),
          ),
          const Text('Mission terminée pour le voyageur — reste la remise aux dépôts et la clôture.',
              style: TextStyle(color: DzColors.mut, fontSize: 10.5)),
        ]),
      ]),
    );
  }

  void _ouvrirRapportDepots() {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => RapportDepotsScreen(missionId: widget.id, code: '${_m!['code']}')));
  }

  Future<void> _voirPhotoDouane() async {
    try {
      final bytes = await Api.getBytes('/missions/${widget.id}/arrivee/photo');
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: DzColors.card,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: InteractiveViewer(
                child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain)),
          ),
        ),
      );
    } catch (e) { _snack('Photo indisponible.'); }
  }

  Future<void> _openArrivee() async {
    final taxes = TextEditingController(
        text: _taxesReelles ? _f(_n(_m!['taxes_reelles'])).replaceAll(' ', '') : _douane.round().toString());
    final note = TextEditingController(text: '${_m!['arrivee_note'] ?? ''}');
    final saisis = {for (final a in _aff) a['id']: TextEditingController(
        text: _n(a['saisis']) > 0 ? _f(_n(a['saisis'])) : '')};
    (Uint8List, String, String)? photo;
    bool montrerSaisie = _aff.any((a) => _n(a['saisis']) > 0);
    bool saving = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          if (saving) return;
          setSt(() => saving = true);
          try {
            await Api.post('/missions/${widget.id}/arrivee', {
              'taxes_reelles': num.tryParse(taxes.text.replaceAll(' ', '')) ?? 0,
              'note': note.text.trim(),
              'saisis': [
                for (final e in saisis.entries)
                  {'affectation_id': e.key, 'quantite': num.tryParse(e.value.text) ?? 0},
              ],
            });
            if (photo != null) {
              await Api.post('/missions/${widget.id}/arrivee/photo',
                  {'data': base64Encode(photo!.$1), 'mime': photo!.$2});
            }
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
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Arrivée — douane · ${_m!['code']}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('Les taxes exactes remplacent la prévision dans toute la compta.',
                      style: TextStyle(color: DzColors.mut, fontSize: 11.5)),
                  const SizedBox(height: 16),
                  TextField(controller: taxes, keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Taxes payées (DA)',
                          helperText: 'prévision : ${_f(_douane)} DA', helperStyle: const TextStyle(fontSize: 10.5))),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Text(photo == null ? 'Photo du bon des douaniers (si disponible)' : '📷 ${photo!.$3}',
                        style: const TextStyle(color: DzColors.mut, fontSize: 12), overflow: TextOverflow.ellipsis)),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final p = await pickImage();
                          if (p != null) setSt(() => photo = p);
                        } catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e'))); }
                      },
                      icon: const Icon(Icons.photo_camera_outlined, size: 15),
                      label: Text(photo == null ? 'Choisir' : 'Changer', style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: note,
                      decoration: const InputDecoration(labelText: 'Note (contrôle, remarques…)')),
                  const SizedBox(height: 12),
                  if (!montrerSaisie)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setSt(() => montrerSaisie = true),
                        icon: const Icon(Icons.report_gmailerrorred_outlined, size: 15, color: DzColors.amber),
                        label: const Text('Il y a eu une saisie de produits',
                            style: TextStyle(color: DzColors.amber, fontSize: 12)),
                      ),
                    )
                  else if (_aff.isNotEmpty) ...[
                    const Text('PIÈCES SAISIES PAR LA DOUANE (remboursées aux chambres au prix du manque)',
                        style: TextStyle(color: DzColors.amber, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    for (final a in _aff)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(child: Text(
                              '${a['produit']} · ${_f(_n(a['quantite']))} pc'
                              '${'${a['emplacement']}' == 'main' ? ' · bagage à main' : ''}',
                              style: const TextStyle(fontSize: 12, color: DzColors.mut))),
                          SizedBox(width: 80, child: TextField(controller: saisis[a['id']],
                              keyboardType: TextInputType.number, textAlign: TextAlign.center,
                              decoration: const InputDecoration(isDense: true, hintText: '0',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)))),
                        ]),
                      ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enregistrer l’arrivée'),
                  ),
                ]),
              )),
          ),
        );
      }),
    );
  }

  Widget _sectionFactures(bool closed) {
    final reste = _affNonFacturees;
    String dateCn(dynamic d) {
      final s = '$d'.substring(0, 10);
      return '${s.substring(0, 4)}年${s.substring(5, 7)}月${s.substring(8, 10)}日';
    }
    return _card(
      titre: 'Factures — ${_factures.length}',

      action: _factures.isEmpty ? null : TextButton.icon(
        onPressed: _telechargerToutes,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.download_outlined, size: 15),
        label: const Text('Tout télécharger', style: TextStyle(fontSize: 12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_factures.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(reste.isEmpty
                    ? 'Aucune facture pour l’instant — elles se créent au fil des paiements carte, depuis la valise.'
                    : 'Aucune facture pour l’instant — « Facturer » pour les ${reste.length} produit(s) en valise.',
                style: const TextStyle(color: DzColors.mut, fontSize: 12)),
          ),
        for (final f in _factures)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
            decoration: BoxDecoration(color: DzColors.card2, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(width: 34, height: 34, alignment: Alignment.center,
                  decoration: BoxDecoration(color: DzColors.lime.withValues(alpha: .12), borderRadius: BorderRadius.circular(9)),
                  child: Text('${f['numero']}', style: const TextStyle(color: DzColors.lime, fontSize: 12.5, fontWeight: FontWeight.w800))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('发票 ${f['numero']} · ${dateCn(f['date'])}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(((f['lignes'] as List?) ?? []).map((l) => '${l['produit']} ×${_f(_n(l['quantite']))}').join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${_n(f['total']).toStringAsFixed(2)} \$', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                Text('${_f(_n(f['total_rmb']))} RMB', style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
              ]),
              IconButton(tooltip: 'PDF', onPressed: () => _telechargerFacture(f),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: DzColors.lime)),
              if (!closed)
                IconButton(tooltip: 'Annuler la facture', padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    onPressed: () => _annulerFacture(f),
                    icon: const Icon(Icons.close, size: 15, color: DzColors.red)),
            ]),
          ),
        if (_factures.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Une facture par paiement carte, à la date du paiement. Les produits facturés sont '
                'verrouillés dans la valise ; annuler la facture les libère.',
                style: TextStyle(color: DzColors.mut, fontSize: 10.5)),
          ),
          if (reste.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('⚠ ${reste.length} produit(s) en valise pas encore facturé(s).',
                  style: const TextStyle(color: DzColors.amber, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Total déclaré : ${_factures.fold(0.0, (s, f) => s + _n(f['total'])).toStringAsFixed(2)} \$ '
                '— sert à la douane et aux taxes de carte à la clôture.',
                style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
          ),
        ],
      ]),
    );
  }

  Widget _card({required String titre, Widget? action, required Widget child}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 30,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 6),
              child: Row(children: [
                Expanded(child: Text(titre.toUpperCase(),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: DzColors.mut, fontSize: 11,
                        fontWeight: FontWeight.w700, letterSpacing: .8))),
                if (action != null) action,
              ]),
            ),
          ),
          Container(
        decoration: BoxDecoration(
          color: DzColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              child,
            ]),
          ),
        ],
      );

  Widget _ligne(String l, String v, {bool gras = false, Color couleur = DzColors.txt}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(l, style: const TextStyle(color: DzColors.mut, fontSize: 12.5))),
          Text(v, style: TextStyle(color: couleur, fontSize: 13,
              fontWeight: gras ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  Map<String, bool> _autoDepart() => {
        'billet_ok': _n(_m!['billet']) > 0 && _m!['depart'] != null,
        'argent_depose': _marchandiseDA > 0,
      };

  (int, int) _avancement(String champ, List items, Map<String, bool> auto) {
    final etat = Map<String, dynamic>.from(_m![champ] as Map? ?? {});
    bool val(String cle) => etat[cle] == true || auto[cle] == true;
    final total = items.length + (champ == 'check_depart' ? 1 : 0);
    var faits = items.where((i) => val(i.$1 as String)).length;
    if (champ == 'check_depart' && (auto['billet_ok'] ?? false)) faits += 1;
    return (faits, total);
  }

  bool get _departComplet {
    final (f, t) = _avancement('check_depart', _itemsDepart, _autoDepart());
    return f >= t;
  }

  bool get _valiseClose => _m!['valise_close'] == true;

  Widget _avantDepartRangeRow(bool wide) {
    Widget resume(IconData ic, String titre, String valeur, {Color col = DzColors.txt}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: DzColors.card,
            borderRadius: BorderRadius.circular(14),
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
        Expanded(child: Text('① Préparer — tout est prêt · prix du kilo de départ ${_f(_pkMin)} DA/kg',
            style: const TextStyle(color: DzColors.lime, fontSize: 11.5, fontWeight: FontWeight.w700))),
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

    final verrou = champ == 'check_retour' && !_valiseClose && !closed;
    return _card(
      titre: '$titre — $faits/$total${complet ? ' ✓' : ''}',

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
        if (_restesDA > 0)
          _ligne('Argent rendu par le voyageur (restes)', '${_f(_restesDA)} DA',
              couleur: DzColors.lime),
        const Divider(color: DzColors.line, height: 16),
        _ligne(solde > 0 ? 'Reste à encaisser' : 'Soldé', '${_f(solde)} DA',
            gras: true, couleur: solde > 0 ? DzColors.amber : DzColors.lime),
        const SizedBox(height: 10),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _ouvrirRapportDepots,
            icon: const Icon(Icons.warehouse_outlined, size: 15),
            label: const Text('Rapport dépôts & encaissements', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Le suivi des versements continue dans Créances.',
              style: TextStyle(color: DzColors.mut, fontSize: 10.5))),
        ]),
      ]),
    );
  }

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

    final ctrls = {
      for (final k in ['billet', 'dem_cout', 'frais_visa', 'budget_jour',
        'autres', 'objectif'])
        k: TextEditingController(text: m[k] == null ? '' : _n(m[k]).toStringAsFixed(0)),
    };

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
    final declTotal = _declareTotal;
    final factures = TextEditingController(text: declTotal > 0 ? declTotal.toStringAsFixed(2) : '');
    final primes = TextEditingController(text: '0');
    final invendus = TextEditingController();

    final manquants = {for (final a in _aff) a['id']: TextEditingController()};

    bool ifuMarge = _marge30;
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
              'ifu_marge': ifuMarge,
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
                  Text('Douane 5 % + IFU 0,5 % et taxes de carte recalculées sur les '
                      'factures réelles, reste des devises reporté sur son compte.',
                      style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                  const SizedBox(height: 16),
                  TextField(controller: depot, decoration: const InputDecoration(labelText: 'Dépôt / acheteur')),
                  const SizedBox(height: 14),
                  TextField(controller: factures, keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Total des factures (${_sym(_devise)})')),
                  const SizedBox(height: 8),

                  if (_taxesReelles)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('Taxes d’arrivée réelles : ${_f(_n(_m!['taxes_reelles']))} DA '
                          '(saisies à l’arrivée — elles priment sur tout calcul).',
                          style: const TextStyle(color: DzColors.lime, fontSize: 11.5)),
                    )
                  else
                    InkWell(
                      onTap: () => setSt(() => ifuMarge = !ifuMarge),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          SizedBox(height: 22, width: 22, child: Checkbox(
                              value: ifuMarge,
                              onChanged: (v) => setSt(() => ifuMarge = v ?? false))),
                          const SizedBox(width: 10),
                          const Expanded(child: Text(
                              'La douane a appliqué sa marge de 30 % avant l’IFU',
                              style: TextStyle(fontSize: 12.5))),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 10),
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
                        style: TextStyle(color: DzColors.mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
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
