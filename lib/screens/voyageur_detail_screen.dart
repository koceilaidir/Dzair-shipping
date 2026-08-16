import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';

/// Fiche voyageur en page : mini-dashboard, statut, validités, dette, édition.
class VoyageurDetailScreen extends StatefulWidget {
  final int id;
  final bool embedded;
  final VoidCallback? onBack;
  const VoyageurDetailScreen(
      {super.key, required this.id, this.embedded = false, this.onBack});

  @override
  State<VoyageurDetailScreen> createState() => _VoyageurDetailScreenState();
}

class _VoyageurDetailScreenState extends State<VoyageurDetailScreen> {
  Map? _v;
  List<dynamic> _missions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([
        Api.get('/voyageurs'),
        Api.get('/missions'),
      ]);
      if (!mounted) return;
      final v = (res[0] as List).firstWhere((x) => x['id'] == widget.id, orElse: () => null);
      setState(() {
        _v = v as Map?;
        _missions = (res[1] as List).where((m) => m['voyageur_id'] == widget.id).toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  String _moisCourant() => DateTime.now().toIso8601String().substring(0, 7);
  int get _missionsMois => _missions
      .where((m) => '${m['depart'] ?? ''}'.startsWith(_moisCourant()) && m['statut'] != 'annulee')
      .length;
  int get _missionsTotal => _missions.where((m) => m['statut'] != 'annulee').length;
  double get _gainsCumules => _missions
      .where((m) => m['statut'] == 'cloturee')
      .fold(0.0, (s, m) => s + _n(m['commission']) + _n(m['primes']));

  @override
  Widget build(BuildContext context) {
    final content = _error != null
        ? Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)))
        : _v == null
            ? const Center(child: CircularProgressIndicator(color: DzColors.lime))
            : _body();

    if (widget.embedded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
          child: Row(children: [
            IconButton(onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back, color: DzColors.mut, size: 20)),
            const SizedBox(width: 4),
            Text(_v?['nom'] ?? 'Voyageur',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        ),
        Expanded(child: content),
      ]);
    }
    return Scaffold(
      appBar: AppBar(backgroundColor: DzColors.bg,
          title: Text(_v?['nom'] ?? 'Voyageur',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      body: content,
    );
  }

  Widget _body() {
    final v = _v!;
    final dette = v['dette_active'] == true
        ? (_n(v['dette_montant']) - _n(v['dette_rembourse'])) : 0.0;
    final (sLabel, sColor) = switch (v['statut_dispo']) {
      'indisponible' => ('Indisponible', DzColors.red),
      'limite' => ('Limite atteinte', DzColors.amber),
      _ => ('Disponible', DzColors.lime),
    };

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // En-tête statut
          Row(children: [
            _statutChip(sLabel, sColor),
            const Spacer(),
            OutlinedButton.icon(onPressed: _editForm,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Modifier')),
          ]),
          const SizedBox(height: 14),

          // Mini-dashboard
          Row(children: [
            _stat('Missions ce mois', '$_missionsMois / 2', DzColors.txt),
            const SizedBox(width: 10),
            _stat('Total missions', '$_missionsTotal', DzColors.txt),
            const SizedBox(width: 10),
            _stat('Gains cumulés', '${_f(_gainsCumules)} DA', DzColors.lime),
          ]),
          const SizedBox(height: 10),

          // Infos
          _card('Infos', [
            _row('Commission', _commLabel(v)),
            _row('Compte BEA', '${v['devise_compte'] ?? 'USD'}'),
            _row('Valises', '${v['bagages']}'),
            _row('Membre depuis', '${v['depuis'] ?? '—'}'),
            if (_n(v['solde_devises']) > 0)
              _row('Solde du compte', '${_f(_n(v['solde_devises']))} ${v['devise_compte']}',
                  couleur: DzColors.lime),
          ]),
          const SizedBox(height: 10),

          // Validités
          _card('Validités & allocation', [
            _row('Passeport', dateFr(v['passeport_expire'])),
            _row('Autorisation ANAE', dateFr(v['autorisation_expire'])),
            _row('Allocation touristique',
                v['allocation_eligible'] == true
                    ? (_allocDispo(v) ? 'Disponible' : 'Utilisée cette année')
                    : 'Non éligible',
                couleur: v['allocation_eligible'] == true && _allocDispo(v)
                    ? DzColors.lime : DzColors.mut),
          ]),
          const SizedBox(height: 10),

          if (v['dette_active'] == true)
            _card('Dette dépôt 1 100 \$', [
              _row('Montant', '${_f(_n(v['dette_montant']))} DA'),
              _row('Remboursé', '${_f(_n(v['dette_rembourse']))} DA'),
              _row('Reste', '${_f(dette)} DA',
                  couleur: dette > 0 ? DzColors.amber : DzColors.lime),
            ]),
          const SizedBox(height: 10),

          // Historique missions
          _card('Ses missions', [
            if (_missions.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Aucune mission.',
                      style: TextStyle(color: DzColors.mut, fontSize: 12.5))),
            for (final m in _missions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text('${m['code']} · ${dateFr(m['depart'])}',
                      style: const TextStyle(fontSize: 12.5))),
                  Text(m['statut'] == 'cloturee' ? 'Clôturée' : 'En cours',
                      style: TextStyle(fontSize: 11,
                          color: m['statut'] == 'cloturee' ? DzColors.mut : DzColors.lime)),
                ]),
              ),
          ]),
        ]),
      ),
    ]);
  }

  bool _allocDispo(Map v) {
    final d = v['allocation_derniere'];
    if (d == null) return true;
    final der = DateTime.tryParse('$d'.substring(0, 10));
    return der == null || DateTime.now().difference(der).inDays >= 365;
  }

  String _commLabel(Map v) {
    final val = _n(v['comm_val']);
    return switch (v['comm_mode']) {
      'kg' => '${val.toStringAsFixed(0)} DA/kg',
      'fixe' => '${val.toStringAsFixed(0)} DA fixe',
      _ => '${val.toStringAsFixed(0)} % du bénéfice',
    };
  }

  Widget _statutChip(String label, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _stat(String l, String v, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
              color: DzColors.card, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DzColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.toUpperCase(), style: const TextStyle(color: DzColors.mut, fontSize: 8.5,
                fontWeight: FontWeight.w700, letterSpacing: .6)),
            const SizedBox(height: 8),
            FittedBox(child: Text(v,
                style: TextStyle(color: c, fontSize: 19, fontWeight: FontWeight.w800))),
          ]),
        ),
      );

  Widget _card(String titre, List<Widget> children) => Container(
        decoration: BoxDecoration(
            color: DzColors.card, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DzColors.line)),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  Widget _row(String l, String v, {Color couleur = DzColors.txt}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(l, style: const TextStyle(color: DzColors.mut, fontSize: 12.5))),
          Text(v, style: TextStyle(color: couleur, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );

  /* ---------- Édition ---------- */
  Future<void> _editForm() async {
    final v = _v!;
    final nom = TextEditingController(text: v['nom']);
    final tel = TextEditingController(text: v['tel'] ?? '');
    final commVal = TextEditingController(text: '${_n(v['comm_val']).toStringAsFixed(0)}');
    final bagages = TextEditingController(text: '${v['bagages']}');
    final depuis = TextEditingController(text: v['depuis'] ?? '');
    final detteMontant = TextEditingController(text: '${_n(v['dette_montant']).toStringAsFixed(0)}');
    String commMode = v['comm_mode'] ?? 'pct';
    String deviseCompte = v['devise_compte'] ?? 'USD';
    // « limite » est automatique — on ne l'édite pas, on repart de « disponible ».
    String statut = v['statut_dispo'] == 'limite' ? 'disponible' : (v['statut_dispo'] ?? 'disponible');
    bool allocationEligible = v['allocation_eligible'] ?? true;
    bool detteActive = v['dette_active'] == true;
    DateTime? passExp = v['passeport_expire'] == null ? null
        : DateTime.tryParse('${v['passeport_expire']}'.substring(0, 10));
    DateTime? autExp = v['autorisation_expire'] == null ? null
        : DateTime.tryParse('${v['autorisation_expire']}'.substring(0, 10));
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          if (nom.text.trim().length < 2 || saving) return;
          setSt(() => saving = true);
          try {
            await Api.put('/voyageurs/${v['id']}', {
              'nom': nom.text.trim(), 'tel': tel.text.trim(),
              'comm_mode': commMode, 'comm_val': num.tryParse(commVal.text) ?? 0,
              'bagages': int.tryParse(bagages.text) ?? 2, 'depuis': depuis.text.trim(),
              'statut_dispo': statut,
              'devise_compte': deviseCompte, 'allocation_eligible': allocationEligible,
              'dette_active': detteActive, 'dette_montant': num.tryParse(detteMontant.text) ?? 0,
              'passeport_expire': passExp == null ? null : isoDate(passExp!),
              'autorisation_expire': autExp == null ? null : isoDate(autExp!),
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
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min, children: [
                  const Text('Modifier le voyageur',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 18),
                  TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom complet')),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: TextField(controller: tel,
                        decoration: const InputDecoration(labelText: 'Téléphone'))),
                    const SizedBox(width: 12),
                    // « Limite » n'est jamais choisi à la main : il se pose et se lève
                    // automatiquement selon les missions du mois (2 max).
                    Expanded(child: DropdownButtonFormField<String>(
                      initialValue: statut == 'limite' ? 'disponible' : statut,
                      dropdownColor: DzColors.card2,
                      decoration: const InputDecoration(
                          labelText: 'Statut',
                          helperText: '« Limite » se pose tout seul (2 missions/mois)',
                          helperStyle: TextStyle(color: DzColors.mut, fontSize: 10)),
                      items: const [
                        DropdownMenuItem(value: 'disponible', child: Text('Disponible')),
                        DropdownMenuItem(value: 'indisponible', child: Text('Indisponible')),
                      ],
                      onChanged: (x) => setSt(() => statut = x ?? 'disponible'),
                    )),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: DropdownButtonFormField<String>(
                      initialValue: commMode, dropdownColor: DzColors.card2,
                      decoration: const InputDecoration(labelText: 'Commission'),
                      items: const [
                        DropdownMenuItem(value: 'pct', child: Text('% du bénéfice')),
                        DropdownMenuItem(value: 'kg', child: Text('DA / kg')),
                        DropdownMenuItem(value: 'fixe', child: Text('Montant fixe')),
                      ],
                      onChanged: (x) => setSt(() => commMode = x ?? 'pct'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: commVal, keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Valeur'))),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: TextField(controller: bagages, keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Valises'))),
                    const SizedBox(width: 12),
                    Expanded(child: DropdownButtonFormField<String>(
                      initialValue: deviseCompte, dropdownColor: DzColors.card2,
                      decoration: const InputDecoration(labelText: 'Compte BEA'),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: Text('\$ Dollars')),
                        DropdownMenuItem(value: 'EUR', child: Text('€ Euros')),
                      ],
                      onChanged: (x) => setSt(() => deviseCompte = x ?? 'USD'),
                    )),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: DzDateField(label: 'Passeport jusqu’au', value: passExp,
                        futureYears: 11, onChanged: (d) => setSt(() => passExp = d))),
                    const SizedBox(width: 12),
                    Expanded(child: DzDateField(label: 'Autorisation jusqu’au', value: autExp,
                        futureYears: 3, onChanged: (d) => setSt(() => autExp = d))),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero, activeThumbColor: DzColors.lime,
                    title: const Text('Éligible à l’allocation touristique', style: TextStyle(fontSize: 13.5)),
                    value: allocationEligible,
                    onChanged: (x) => setSt(() => allocationEligible = x),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero, activeThumbColor: DzColors.lime,
                    title: const Text('Dépôt 1 100 \$ avancé par l’agence', style: TextStyle(fontSize: 13.5)),
                    value: detteActive,
                    onChanged: (x) => setSt(() => detteActive = x),
                  ),
                  if (detteActive)
                    TextField(controller: detteMontant, keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Dette initiale (DA)')),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: saving ? null : save,
                      child: saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Enregistrer')),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: saving ? null : () async {
                      final ok = await showDialog<bool>(context: ctx, builder: (c2) => AlertDialog(
                        backgroundColor: DzColors.card,
                        title: const Text('Supprimer ce voyageur ?', style: TextStyle(fontSize: 16)),
                        content: const Text('Impossible s’il a des missions enregistrées.',
                            style: TextStyle(color: DzColors.mut, fontSize: 13)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Annuler')),
                          TextButton(onPressed: () => Navigator.pop(c2, true),
                              child: const Text('Supprimer', style: TextStyle(color: DzColors.red))),
                        ],
                      ));
                      if (ok != true) return;
                      try {
                        await Api.delete('/voyageurs/${v['id']}');
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) widget.embedded ? widget.onBack?.call() : Navigator.pop(context);
                      } on ApiException catch (e) {
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(e.message), backgroundColor: const Color(0xFF3A1512)));
                      }
                    },
                    icon: const Icon(Icons.delete_outline, color: DzColors.red, size: 17),
                    label: const Text('Supprimer ce voyageur',
                        style: TextStyle(color: DzColors.red, fontSize: 13)),
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
