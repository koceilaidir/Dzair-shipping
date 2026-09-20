import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/upload.dart';
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
    final kgTot = valides.fold(0.0, (s, l) => s + l.poidsTotal);
    final gainTot = valides.fold(0.0, (s, l) => s + l.gainTotal);
    final manqueRmb = valides
        .where((l) => l.manqueDevise == 'RMB')
        .fold(0.0, (s, l) => s + l.manqueTotal);
    final manqueDa = valides
        .where((l) => l.manqueDevise == 'DA')
        .fold(0.0, (s, l) => s + l.manqueTotal);

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
            Text('${valides.length} produit(s) · ${kgTot.toStringAsFixed(1)} kg'
                '${manqueRmb > 0 ? ' · manque ${_f(manqueRmb)} ¥' : ''}'
                '${manqueDa > 0 ? ' · manque ${_f(manqueDa)} DA' : ''}',
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

  Future<void> _choisirPhoto(_LigneCtrl l, VoidCallback onChange) async {
    final img = await pickImage();
    if (img == null || !mounted) return;
    final (bytes, mime) =
        await compresserImage(img.$1, img.$2, maxCote: 1200, qualite: 0.72);
    if (!mounted) return;
    if (bytes.length > 3000000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Photo trop lourde même compressée — choisis-en une autre.')));
      return;
    }
    l.photo = Uint8List.fromList(bytes);
    l.photoMime = mime;
    onChange();
  }

  Widget _choix(String valeur, String actuel, String texte, void Function(String) onTap) =>
      GestureDetector(
        onTap: () => onTap(valeur),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: valeur == actuel ? DzColors.lime : DzColors.card,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(texte,
              style: TextStyle(
                  color: valeur == actuel ? DzColors.inkOnLime : DzColors.mut,
                  fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _sousTitre(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: DzColors.mut, fontSize: 9.5,
                fontWeight: FontWeight.w700, letterSpacing: 1)),
      );

  Widget _ligneForm(int i, _LigneCtrl l, VoidCallback onChange, VoidCallback? onRemove) {
    final etroit = MediaQuery.of(context).size.width < 760;

    Widget champ(TextEditingController c, String label,
            {bool nombre = true, int flex = 1}) =>
        TextField(
          controller: c,
          keyboardType: nombre
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          textCapitalization:
              nombre ? TextCapitalization.none : TextCapitalization.sentences,
          onChanged: (_) => onChange(),
          decoration: InputDecoration(labelText: label, isDense: true),
        );

    final photo = GestureDetector(
      onTap: () => _choisirPhoto(l, onChange),
      child: Container(
        width: 52, height: 52,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: DzColors.card, borderRadius: BorderRadius.circular(12)),
        child: l.photo != null
            ? Image.memory(l.photo!, width: 52, height: 52, fit: BoxFit.cover)
            : const Icon(Icons.add_a_photo_outlined, size: 19, color: DzColors.mut),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: DzColors.card2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: l.valide ? DzColors.lime.withValues(alpha: .3) : DzColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          photo,
          const SizedBox(width: 10),
          Expanded(child: champ(l.produit, 'Produit', nombre: false)),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 17, color: DzColors.red),
            ),
        ]),
        const SizedBox(height: 14),

        Row(children: [
          Expanded(child: champ(l.qte, 'Quantité (pièces)')),
          const SizedBox(width: 10),
          Expanded(child: champ(l.kg, l.basePoids == 'lot'
              ? 'Poids du lot (kg)' : 'Poids d’une pièce (kg)')),
        ]),
        const SizedBox(height: 10),
        _sousTitre('Le poids saisi est celui'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _choix('lot', l.basePoids, 'du lot entier',
              (v) { l.basePoids = v; onChange(); }),
          _choix('piece', l.basePoids, 'd’une pièce',
              (v) { l.basePoids = v; onChange(); }),
        ]),
        const SizedBox(height: 16),

        champ(l.prix, switch (l.basePrix) {
          'kg' => 'Payé (DA par kg)',
          'lot' => 'Payé (DA pour tout le lot)',
          _ => 'Payé (DA par pièce)',
        }),
        const SizedBox(height: 10),
        _sousTitre('Le prix saisi est'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _choix('kg', l.basePrix, 'par kilo', (v) { l.basePrix = v; onChange(); }),
          _choix('piece', l.basePrix, 'par pièce', (v) { l.basePrix = v; onChange(); }),
          _choix('lot', l.basePrix, 'pour le lot', (v) { l.basePrix = v; onChange(); }),
        ]),
        const SizedBox(height: 16),

        Row(children: [
          Expanded(
            child: champ(l.manque, l.manqueDevise == 'RMB'
                ? 'Manque (¥ par pièce)' : 'Manque (DA par pièce)'),
          ),
          const SizedBox(width: 10),
          Wrap(spacing: 8, children: [
            _choix('RMB', l.manqueDevise, '¥', (v) { l.manqueDevise = v; onChange(); }),
            _choix('DA', l.manqueDevise, 'DA', (v) { l.manqueDevise = v; onChange(); }),
          ]),
        ]),

        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
              color: DzColors.card, borderRadius: BorderRadius.circular(12)),
          child: l.valide
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      '${l.poidsTotal.toStringAsFixed(1)} kg au total · '
                      '${l.poidsUnit.toStringAsFixed(2)} kg par pièce',
                      style: const TextStyle(color: DzColors.txt2, fontSize: 11.5)),
                  const SizedBox(height: 3),
                  Text(
                      'gain ${_f(l.gainPiece)} DA par pièce · '
                      '${_f(l.gainKg)} DA/kg · ${_f(l.gainTotal)} DA pour le lot',
                      style: const TextStyle(color: DzColors.lime,
                          fontSize: 11.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                      'manque ${_f(l.manqueUnit)} '
                      '${l.manqueDevise == 'RMB' ? '¥' : 'DA'} par pièce',
                      style: const TextStyle(color: DzColors.amber, fontSize: 11.5)),
                ])
              : const Text('Remplis le produit, la quantité et le poids.',
                  style: TextStyle(color: DzColors.mut, fontSize: 11.5)),
        ),
        if (etroit) const SizedBox(height: 2),
      ]),
    );
  }
}

class _LigneCtrl {
  final produit = TextEditingController();
  final qte = TextEditingController();
  final kg = TextEditingController();
  final manque = TextEditingController(text: '0');
  final prix = TextEditingController();

  String basePrix = 'kg';
  String basePoids = 'lot';
  String manqueDevise = 'RMB';
  Uint8List? photo;
  String? photoMime;

  double _d(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
  double get q => _d(qte);

  double get poidsTotal => basePoids == 'lot' ? _d(kg) : _d(kg) * q;
  double get poidsUnit => q > 0 ? poidsTotal / q : 0;

  String get mode => basePrix == 'kg' ? 'kg' : 'piece';
  double get prixUnitaire => switch (basePrix) {
        'kg' => _d(prix),
        'lot' => q > 0 ? _d(prix) / q : 0,
        _ => _d(prix),
      };

  double get gainPiece =>
      basePrix == 'kg' ? prixUnitaire * poidsUnit : prixUnitaire;
  double get gainTotal => gainPiece * q;
  double get gainKg => poidsUnit > 0 ? gainPiece / poidsUnit : 0;

  double get manqueUnit => _d(manque);
  double get manqueTotal => manqueUnit * q;

  bool get valide => produit.text.trim().isNotEmpty && q > 0 && poidsTotal > 0;

  Map<String, dynamic> get body => {
        'produit': produit.text.trim(),
        'quantite': q,
        'poids_total': poidsTotal,
        'mode': mode,
        'prix': prixUnitaire,
        'manque_devise': manqueDevise,
        'manque_rmb': manqueDevise == 'RMB' ? manqueUnit : 0,
        if (manqueDevise == 'DA') 'manque_da': manqueUnit,
        if (photo != null) 'photo': base64Encode(photo!),
        if (photo != null) 'photo_mime': photoMime ?? 'image/jpeg',
      };
}
