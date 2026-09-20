import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/upload.dart';
import '../theme.dart';

String fmtDa(num n) => n.toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

double _num(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();

String _txt(double v, int d) {
  final s = v.toStringAsFixed(d);
  return s.contains('.') ? s.replaceAll(RegExp(r'\.?0+$'), '') : s;
}

class ProduitCtrl {
  ProduitCtrl();

  ProduitCtrl.depuis(Map l) {
    id = l['id'] is int ? l['id'] as int : int.tryParse('${l['id']}');
    produit.text = '${l['produit'] ?? ''}';
    qte.text = _txt(_num(l['quantite']), 2);
    basePoids = 'lot';
    kg.text = _txt(_num(l['poids_total']), 3);
    basePrix = '${l['mode']}' == 'piece' ? 'piece' : 'kg';
    prix.text = _txt(_num(l['prix']), 2);
    manqueDevise = '${l['manque_devise']}' == 'DA' ? 'DA' : 'RMB';
    manque.text = _txt(
        manqueDevise == 'DA' ? _num(l['manque_da']) : _num(l['manque_rmb']), 2);
  }

  int? id;
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
  bool photoModifiee = false;

  double _d(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
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
      };

  Map<String, dynamic> get bodyCreation => {
        ...body,
        if (photo != null) 'photo': base64Encode(photo!),
        if (photo != null) 'photo_mime': photoMime ?? 'image/jpeg',
      };

  void liberer() {
    produit.dispose();
    qte.dispose();
    kg.dispose();
    manque.dispose();
    prix.dispose();
  }
}

Widget pilule(String valeur, String actuel, String texte,
        void Function(String) onTap) =>
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
                fontSize: 11.5,
                fontWeight: FontWeight.w700)),
      ),
    );

Widget sousTitre(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(t.toUpperCase(),
          style: const TextStyle(
              color: DzColors.mut,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1)),
    );

Future<void> choisirPhotoProduit(
    BuildContext context, ProduitCtrl l, VoidCallback onChange) async {
  final img = await pickImage();
  if (img == null || !context.mounted) return;
  final (bytes, mime) =
      await compresserImage(img.$1, img.$2, maxCote: 1200, qualite: 0.72);
  if (!context.mounted) return;
  if (bytes.length > 3000000) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Photo trop lourde même compressée — choisis-en une autre.')));
    return;
  }
  l.photo = Uint8List.fromList(bytes);
  l.photoMime = mime;
  l.photoModifiee = true;
  onChange();
}

Widget produitForm(
  BuildContext context,
  ProduitCtrl l,
  VoidCallback onChange, {
  VoidCallback? onRemove,
  bool encadre = true,
}) {
  Widget champ(TextEditingController c, String label, {bool nombre = true}) =>
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

  final vignette = GestureDetector(
    onTap: () => choisirPhotoProduit(context, l, onChange),
    child: Container(
      width: 52,
      height: 52,
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
    margin: encadre ? const EdgeInsets.only(bottom: 10) : EdgeInsets.zero,
    padding: encadre
        ? const EdgeInsets.fromLTRB(12, 12, 12, 12)
        : EdgeInsets.zero,
    decoration: encadre
        ? BoxDecoration(
            color: DzColors.card2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: l.valide
                    ? DzColors.lime.withValues(alpha: .3)
                    : DzColors.line),
          )
        : null,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        vignette,
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
        Expanded(
            child: champ(
                l.kg,
                l.basePoids == 'lot'
                    ? 'Poids du lot (kg)'
                    : 'Poids d’une pièce (kg)')),
      ]),
      const SizedBox(height: 10),
      sousTitre('Le poids saisi est celui'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        pilule('lot', l.basePoids, 'du lot entier',
            (v) { l.basePoids = v; onChange(); }),
        pilule('piece', l.basePoids, 'd’une pièce',
            (v) { l.basePoids = v; onChange(); }),
      ]),
      const SizedBox(height: 16),
      champ(
          l.prix,
          switch (l.basePrix) {
            'kg' => 'Payé (DA par kg)',
            'lot' => 'Payé (DA pour tout le lot)',
            _ => 'Payé (DA par pièce)',
          }),
      const SizedBox(height: 10),
      sousTitre('Le prix saisi est'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        pilule('kg', l.basePrix, 'par kilo', (v) { l.basePrix = v; onChange(); }),
        pilule('piece', l.basePrix, 'par pièce',
            (v) { l.basePrix = v; onChange(); }),
        pilule('lot', l.basePrix, 'pour le lot',
            (v) { l.basePrix = v; onChange(); }),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: champ(
              l.manque,
              l.manqueDevise == 'RMB'
                  ? 'Manque (¥ par pièce)'
                  : 'Manque (DA par pièce)'),
        ),
        const SizedBox(width: 10),
        Wrap(spacing: 8, children: [
          pilule('RMB', l.manqueDevise, '¥',
              (v) { l.manqueDevise = v; onChange(); }),
          pilule('DA', l.manqueDevise, 'DA',
              (v) { l.manqueDevise = v; onChange(); }),
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
                    'gain ${fmtDa(l.gainPiece)} DA par pièce · '
                    '${fmtDa(l.gainKg)} DA/kg · ${fmtDa(l.gainTotal)} DA pour le lot',
                    style: const TextStyle(
                        color: DzColors.lime,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                    'manque ${fmtDa(l.manqueUnit)} '
                    '${l.manqueDevise == 'RMB' ? '¥' : 'DA'} par pièce',
                    style: const TextStyle(color: DzColors.amber, fontSize: 11.5)),
              ])
            : const Text('Remplis le produit, la quantité et le poids.',
                style: TextStyle(color: DzColors.mut, fontSize: 11.5)),
      ),
    ]),
  );
}

Widget _encart(String texte, Color couleur, IconData icone) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
          color: DzColors.card2, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 16, color: couleur),
        const SizedBox(width: 10),
        Expanded(
          child: Text(texte,
              style: TextStyle(color: couleur, fontSize: 11.5, height: 1.45)),
        ),
      ]),
    );

Future<bool> montrerEditionProduit(BuildContext context, Map ligne) async {
  final l = ProduitCtrl.depuis(ligne);
  final id = l.id;
  if (id == null) return false;

  if (ligne['a_photo'] == true) {
    try {
      l.photo = Uint8List.fromList(
          await Api.getBytes('/inventaire/lignes/$id/photo'));
    } catch (_) {}
  }
  if (!context.mounted) {
    l.liberer();
    return false;
  }

  final traces = (ligne['traces'] as List? ?? []);
  final cloturees =
      traces.where((t) => t['statut'] == 'cloturee').toList();
  final enCours = traces.where((t) => t['statut'] != 'cloturee').toList();
  final engage = traces.fold<double>(0, (s, t) => s + _num(t['quantite'])) +
      _num(ligne['rendu']);

  var enregistre = false;
  var occupe = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      Future<void> valider() async {
        if (!l.valide) return;
        if (l.q < engage) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text('${fmtDa(engage)} pièce(s) sont déjà en valise '
                  'ou rendues — la quantité ne peut pas descendre en dessous.')));
          return;
        }
        setSt(() => occupe = true);
        try {
          await Api.put('/inventaire/lignes/$id', l.body);
          if (l.photoModifiee && l.photo != null) {
            await Api.post('/inventaire/lignes/$id/photo', {
              'data': base64Encode(l.photo!),
              'mime': l.photoMime ?? 'image/jpeg',
            });
          }
          enregistre = true;
          if (ctx.mounted) Navigator.pop(ctx);
        } on ApiException catch (e) {
          setSt(() => occupe = false);
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx)
                .showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
      }

      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470, maxHeight: 700),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Modifier le produit',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            Text('Corrige le poids, le prix ou la quantité.',
                                style: TextStyle(
                                    color: DzColors.mut, fontSize: 11.5)),
                          ]),
                    ),
                    IconButton(
                      onPressed: occupe ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, size: 18, color: DzColors.mut),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  if (cloturees.isNotEmpty)
                    _encart(
                        'Ce produit est parti dans '
                        '${cloturees.map((t) => '${t['code']}').join(', ')} — '
                        'mission(s) déjà clôturée(s). Changer le poids ou le prix '
                        'recalculera leurs kilos et leur bénéfice. Les montants figés '
                        'à la clôture (commission, part de séjour, solde) ne bougeront pas.',
                        DzColors.red,
                        Icons.warning_amber_rounded),
                  if (enCours.isNotEmpty)
                    _encart(
                        'Déjà en valise sur '
                        '${enCours.map((t) => '${t['code']}').join(', ')}. '
                        'Les kilos et le bénéfice de ces missions seront recalculés.',
                        DzColors.amber,
                        Icons.flight_takeoff_outlined),
                  if (engage > 0)
                    _encart(
                        'Quantité minimale : ${fmtDa(engage)} pièce(s), '
                        'déjà en valise ou rendues.',
                        DzColors.mut,
                        Icons.lock_outline),
                  produitForm(ctx, l, () => setSt(() {}), encadre: false),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: occupe ? null : () => Navigator.pop(ctx),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: (!l.valide || occupe) ? null : valider,
                        child: Text(occupe ? 'Enregistrement…' : 'Enregistrer'),
                      ),
                    ),
                  ]),
                ]),
          ),
        ),
      );
    }),
  );

  l.liberer();
  return enregistre;
}

Future<bool> montrerRetourProduit(BuildContext context, Map ligne) async {
  final id = ligne['id'];
  final traces = (ligne['traces'] as List? ?? []);
  final cloturees = traces.where((t) => t['statut'] == 'cloturee').toList();
  final enCours = traces.where((t) => t['statut'] != 'cloturee').toList();
  final qteCloturee =
      cloturees.fold<double>(0, (s, t) => s + _num(t['quantite']));

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Rendre « ${ligne['produit']} »',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('à ${ligne['chambre_nom']}',
                    style: const TextStyle(color: DzColors.mut, fontSize: 12)),
                const SizedBox(height: 16),
                if (enCours.isNotEmpty)
                  _encart(
                      'Sera retiré des valises en cours : '
                      '${enCours.map((t) => '${t['code']}').join(', ')}.',
                      DzColors.amber,
                      Icons.luggage_outlined),
                if (cloturees.isEmpty)
                  _encart(
                      'Le produit sera entièrement supprimé de l’inventaire.',
                      DzColors.red,
                      Icons.delete_outline)
                else
                  _encart(
                      '${fmtDa(qteCloturee)} pièce(s) sont déjà parties dans '
                      '${cloturees.map((t) => '${t['code']}').join(', ')} — '
                      'elles ne peuvent pas revenir. Le produit sera conservé '
                      'avec cette quantité au lieu d’être supprimé.',
                      DzColors.txt2,
                      Icons.history),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: DzColors.red,
                          foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Confirmer'),
                    ),
                  ),
                ]),
              ]),
        ),
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;

  try {
    final r = await Api.delete('/inventaire/lignes/$id') as Map;
    if (context.mounted) {
      final n = (r['retirees'] as List? ?? []).length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['supprime'] == true
              ? 'Produit rendu et retiré de l’inventaire'
                  '${n > 0 ? ' · sorti de $n valise(s)' : ''}.'
              : 'Produit rendu · quantité ramenée à ${fmtDa(_num(r['quantite']))} '
                  'pièce(s) déjà parties.')));
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
}
