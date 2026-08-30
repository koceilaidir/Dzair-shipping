import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';
import 'chambres_screen.dart' show showChambreForm;

class BonScreen extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onBack;
  const BonScreen({super.key, this.embedded = false, this.onBack});
  @override
  State<BonScreen> createState() => _BonScreenState();
}

class _BonScreenState extends State<BonScreen> {
  List<dynamic>? _chambres;
  String? _error;
  Map? _chambre;
  int? _bonOuvertId;
  String? _bonOuvertDate;
  bool _ajouterAuBon = true;
  final _recherche = TextEditingController();
  DateTime _date = DateTime.now();
  final _note = TextEditingController();
  final _lignes = <_LigneCtrl>[_LigneCtrl()];
  bool _saving = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('/inventaire/chambres');
      if (mounted) setState(() { _chambres = d as List; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  List<_LigneCtrl> get _valides => _lignes.where((l) => l.valide).toList();

  void _choisirChambre(Map c) {
    int? bonId; String? bonDate;
    final der = c['dernier_bon'];
    if (der != null && c['dernier_bon_id'] != null) {
      final d = DateTime.tryParse('$der'.substring(0, 10));
      if (d != null && DateTime.now().difference(d).inDays <= 15) {
        bonId = c['dernier_bon_id'] is int ? c['dernier_bon_id'] : int.tryParse('${c['dernier_bon_id']}');
        bonDate = '$der';
      }
    }
    setState(() { _chambre = c; _bonOuvertId = bonId; _bonOuvertDate = bonDate; _ajouterAuBon = true; });
  }

  void _fermer() => widget.embedded ? widget.onBack?.call() : Navigator.pop(context);

  Future<void> _save() async {
    if (_chambre == null || _valides.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await Api.post('/inventaire/bons', {
        'chambre_id': _chambre!['id'], 'date': isoDate(_date), 'note': _note.text.trim(),
        if (_bonOuvertId != null && _ajouterAuBon) 'bon_id': _bonOuvertId,
        'lignes': [for (final l in _valides) l.body],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_bonOuvertId != null && _ajouterAuBon
              ? '${_valides.length} produit(s) ajoutés au bon du ${dateFr(_bonOuvertDate)} ✓'
              : 'Bon enregistré — ${_valides.length} produit(s) en stock ✓'),
          backgroundColor: const Color(0xFF1E2A12)));
      _fermer();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _error != null
        ? Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)))
        : _chambres == null
            ? const Center(child: CircularProgressIndicator(color: DzColors.lime))
            : _body();
    if (widget.embedded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
          child: Row(children: [
            IconButton(onPressed: _fermer, icon: const Icon(Icons.arrow_back, color: DzColors.mut, size: 20)),
            const SizedBox(width: 4),
            const Expanded(child: Text('Nouveau bon de récupération',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ]),
        ),
        Expanded(child: body),
      ]);
    }
    return Scaffold(
      appBar: AppBar(backgroundColor: DzColors.bg, title: const Text('Nouveau bon')),
      body: body,
    );
  }

  Widget _body() {
    final f = _recherche.text.trim().toLowerCase();
    final sugg = f.isEmpty ? _chambres!.take(8).toList()
        : _chambres!.where((c) => '${c['nom']} ${c['depot_wilaya'] ?? ''}'.toLowerCase().contains(f)).take(8).toList();
    final valides = _valides;
    final kgTot = valides.fold(0.0, (s, l) => s + l.poids);
    final gainTot = valides.fold(0.0, (s, l) => s + l.gainTotal);
    final manqueTot = valides.fold(0.0, (s, l) => s + l.manqueTotal);

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 16), children: [

          _card('1 · Chambre', child: _chambre != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: DzColors.lime.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: DzColors.lime.withValues(alpha: .4))),
                  child: Row(children: [
                    const Icon(Icons.storefront_outlined, color: DzColors.lime, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_chambre!['nom']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      Text('dépôt ${_chambre!['depot_wilaya'] ?? '—'} · '
                          '${((_chambre!['contacts'] as List?) ?? []).map((k) => k['nom']).join(', ')}',
                          style: const TextStyle(color: DzColors.mut, fontSize: 11)),
                    ])),
                    TextButton(onPressed: () => setState(() { _chambre = null; _bonOuvertId = null; }),
                        child: const Text('Changer')),
                  ]),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(textCapitalization: TextCapitalization.words, 
                    controller: _recherche, onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Nom ou n° de la chambre',
                        prefixIcon: Icon(Icons.search, size: 18)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final c in sugg)
                      ActionChip(
                        label: Text('${c['nom']}${(c['depot_wilaya'] ?? '').toString().isNotEmpty ? ' · ${c['depot_wilaya']}' : ''}'),
                        backgroundColor: DzColors.card2, side: const BorderSide(color: DzColors.line),
                        onPressed: () => _choisirChambre(c as Map),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 15, color: DzColors.inkOnLime),
                      label: Text(f.isEmpty ? 'Nouvelle chambre' : 'Créer « ${_recherche.text.trim()} »'),
                      backgroundColor: DzColors.lime,
                      labelStyle: const TextStyle(color: DzColors.inkOnLime, fontWeight: FontWeight.w700),
                      onPressed: () async {
                        final c = await showChambreForm(context, nomInitial: _recherche.text.trim());
                        if (c != null && mounted) { setState(() => _chambres = [..._chambres!, c]); _choisirChambre(c); }
                      },
                    ),
                  ]),
                ])),

          if (_chambre != null && _bonOuvertId != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: DzColors.amber.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DzColors.amber.withValues(alpha: .35)),
              ),
              child: Row(children: [
                const Icon(Icons.history, size: 16, color: DzColors.amber),
                const SizedBox(width: 10),
                Expanded(child: Text(
                    'Un bon est déjà ouvert pour cette chambre (${dateFr(_bonOuvertDate)}).',
                    style: const TextStyle(fontSize: 12))),
                SegmentedButton<bool>(
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: WidgetStateProperty.resolveWith((st) =>
                        st.contains(WidgetState.selected) ? DzColors.lime : DzColors.card),
                    foregroundColor: WidgetStateProperty.resolveWith((st) =>
                        st.contains(WidgetState.selected) ? DzColors.inkOnLime : DzColors.mut),
                    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Ajouter au bon')),
                    ButtonSegment(value: false, label: Text('Nouveau bon')),
                  ],
                  selected: {_ajouterAuBon},
                  onSelectionChanged: (st) => setState(() => _ajouterAuBon = st.first),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: DzDateField(label: 'Date', value: _date, onChanged: (d) => setState(() => _date = d))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: TextField(textCapitalization: TextCapitalization.sentences, controller: _note,
                decoration: const InputDecoration(labelText: 'Note (facultatif)'))),
          ]),
          const SizedBox(height: 12),

          _card('2 · Produits récupérés',
              action: TextButton.icon(onPressed: () => setState(() => _lignes.add(_LigneCtrl())),
                  icon: const Icon(Icons.add, size: 15), label: const Text('Ligne', style: TextStyle(fontSize: 12))),
              child: Column(children: [
                for (var i = 0; i < _lignes.length; i++)
                  _ligneForm(i, _lignes[i], () => setState(() {}),
                      _lignes.length == 1 ? null : () => setState(() => _lignes.removeAt(i))),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(onPressed: () => setState(() => _lignes.add(_LigneCtrl())),
                      icon: const Icon(Icons.add, size: 15), label: const Text('Ajouter une ligne', style: TextStyle(fontSize: 12))),
                ),
              ])),
        ]),
      ),

      Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(color: DzColors.panel, border: Border(top: BorderSide(color: DzColors.line))),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${valides.length} produit(s) · ${kgTot.toStringAsFixed(1)} kg · manque ${_f(manqueTot)} ¥',
                style: const TextStyle(color: DzColors.mut, fontSize: 12)),
            Text.rich(TextSpan(children: [
              TextSpan(text: '${_f(gainTot)} DA', style: const TextStyle(color: DzColors.lime, fontSize: 16, fontWeight: FontWeight.w800)),
              if (kgTot > 0) TextSpan(text: '  (${_f(gainTot / kgTot)} DA/kg)', style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
            ])),
          ])),
          TextButton(onPressed: _fermer, child: const Text('Annuler')),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: (_chambre == null || valides.isEmpty || _saving) ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_chambre == null ? 'Choisis la chambre' : valides.isEmpty ? 'Ajoute un produit' : 'Enregistrer le bon'),
          ),
        ]),
      ),
    ]);
  }

  Widget _card(String titre, {Widget? action, required Widget child}) => Container(
        decoration: BoxDecoration(color: DzColors.card, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 40, child: Row(children: [
            Expanded(child: Text(titre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
            if (action != null) action,
          ])),
          const SizedBox(height: 4),
          child,
        ]),
      );

  Widget _ligneForm(int i, _LigneCtrl l, VoidCallback onChange, VoidCallback? onRemove) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(color: DzColors.card2, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: l.valide ? DzColors.lime.withValues(alpha: .3) : DzColors.line)),
        child: Column(children: [
          Row(children: [
            Container(width: 22, height: 22, alignment: Alignment.center,
                decoration: BoxDecoration(color: DzColors.card, borderRadius: BorderRadius.circular(6)),
                child: Text('${i + 1}', style: const TextStyle(color: DzColors.mut, fontSize: 10.5, fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            Expanded(flex: 4, child: TextField(textCapitalization: TextCapitalization.sentences, controller: l.produit, onChanged: (_) => onChange(),
                decoration: const InputDecoration(labelText: 'Produit', isDense: true))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(controller: l.qte, keyboardType: TextInputType.number, onChanged: (_) => onChange(),
                decoration: const InputDecoration(labelText: 'Qté (pcs)', isDense: true))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(controller: l.kg, keyboardType: TextInputType.number, onChanged: (_) => onChange(),
                decoration: const InputDecoration(labelText: 'Poids total kg', isDense: true))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(controller: l.manque, keyboardType: TextInputType.number, onChanged: (_) => onChange(),
                decoration: const InputDecoration(labelText: 'Manque ¥/pc', isDense: true))),
            IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                onPressed: onRemove, icon: const Icon(Icons.close, size: 15, color: DzColors.red)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const SizedBox(width: 30),
            SegmentedButton<String>(
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                backgroundColor: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.selected) ? DzColors.lime : DzColors.card),
                foregroundColor: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.selected) ? DzColors.inkOnLime : DzColors.mut),
                textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'kg', label: Text('KG')),
                ButtonSegment(value: 'piece', label: Text('PCS')),
              ],
              selected: {l.mode},
              onSelectionChanged: (s) { l.mode = s.first; onChange(); },
            ),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: TextField(controller: l.prix, keyboardType: TextInputType.number, onChanged: (_) => onChange(),
                decoration: InputDecoration(labelText: l.mode == 'kg' ? 'Payé DA/kg' : 'Payé DA/pc', isDense: true))),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: Text(
              l.valide
                  ? '${l.poidsUnit.toStringAsFixed(2)} kg/pc · ${_f(l.gainKg)} DA/kg\n'
                    'gain ${_f(l.gainTotal)} DA · manque ${_f(l.manqueTotal)} ¥'
                  : 'remplis produit, qté, poids',
              style: TextStyle(color: l.valide ? DzColors.txt : DzColors.mut, fontSize: 11, height: 1.4),
            )),
          ]),
        ]),
      );
}

class _LigneCtrl {
  final produit = TextEditingController();
  final qte = TextEditingController();
  final kg = TextEditingController();
  final manque = TextEditingController(text: '0');
  final prix = TextEditingController();
  String mode = 'kg';

  double _d(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
  double get q => _d(qte);
  double get poids => _d(kg);
  double get poidsUnit => q > 0 ? poids / q : 0;
  double get gainPiece => mode == 'kg' ? _d(prix) * poidsUnit : _d(prix);
  double get gainTotal => gainPiece * q;
  double get gainKg => poidsUnit > 0 ? gainPiece / poidsUnit : 0;
  double get manqueTotal => _d(manque) * q;
  bool get valide => produit.text.trim().isNotEmpty && q > 0 && poids > 0;
  Map<String, dynamic> get body => {
        'produit': produit.text.trim(), 'quantite': q, 'poids_total': poids,
        'manque_rmb': _d(manque), 'mode': mode, 'prix': _d(prix),
      };
}
