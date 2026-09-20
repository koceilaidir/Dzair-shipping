import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';

Future<bool> showInventairePicker(BuildContext context, {
  required int missionId,
  required double kgDispo,
  required double manqueDA,
  required double prixKiloMin,
  String emplacement = 'soute',
  Set<int> dejaValise = const {},
}) async {
  final main = emplacement == 'main';

  Future<Map?> charger() async {
    try {
      return await Api.get('/inventaire/stock?mission=$missionId') as Map;
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return null;
    }
  }

  final data = await charger();
  if (data == null || !context.mounted) return false;

  var lignes = _trier(data, main, dejaValise);
  final usdCny = _n(data['usd_cny']);
  final concurrents = (data['concurrents'] as List? ?? []).cast<Map>();

  final ctrls = <int, TextEditingController>{};
  final prixCtrls = <int, TextEditingController>{};
  void preparer() {
    for (final l in lignes) {
      final id = l['id'] as int;
      ctrls.putIfAbsent(id, () => TextEditingController());
      prixCtrls.putIfAbsent(
          id,
          () => TextEditingController(
              text: _n(l['prix_declare']) > 0
                  ? _n(l['prix_declare']).toStringAsFixed(2).replaceAll('.00', '')
                  : ''));
    }
  }

  preparer();

  var kgRestant = kgDispo;
  var kgAjoutes = 0.0, daAjoutes = 0.0;
  var nbAjoutes = 0;
  var saving = false;
  var ok = false;
  String? erreur;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      double kgChoisi = 0, daChoisi = 0, usdDeclare = 0;
      var choisis = 0, tropVariete = false;
      final sansPrix = <int>{};
      for (final l in lignes) {
        final id = l['id'] as int;
        final q = _d(ctrls[id]!);
        final px = _d(prixCtrls[id]!);
        if (q <= 0) continue;
        choisis += 1;
        kgChoisi += q * _n(l['poids_unit']);
        daChoisi += q * _n(l['gain_piece']);
        usdDeclare += q * px;
        if (!main && px <= 0) sansPrix.add(id);
        if (main && q > 2) tropVariete = true;
      }
      final depasse = kgChoisi > kgRestant + 1e-6;
      final bloque = saving || choisis <= 0 || depasse || sansPrix.isNotEmpty;
      final motif = choisis <= 0
          ? 'Mets une quantité sur les produits que tu veux charger — un seul suffit.'
          : depasse
              ? 'Tu dépasses de ${(kgChoisi - kgRestant).toStringAsFixed(1)} kg. Réduis les quantités.'
              : sansPrix.isNotEmpty
                  ? 'Prix déclaré manquant sur ${sansPrix.length} produit(s) — encadré(s) en rouge.'
                  : null;

      Future<void> ajouter() async {
        if (saving) return;
        setSt(() { saving = true; erreur = null; });

        var kgLot = 0.0, daLot = 0.0, nLot = 0;
        for (final l in List.of(lignes)) {
          final id = l['id'] as int;
          final q = _d(ctrls[id]!);
          if (q <= 0) continue;
          final px = _d(prixCtrls[id]!);
          try {
            await Api.post('/inventaire/affectations', {
              'mission_id': missionId, 'ligne_id': id, 'quantite': q,
              'emplacement': emplacement,
              if (!main) 'prix_declare': px,
            });
            ok = true;
            nLot += 1;
            kgLot += q * _n(l['poids_unit']);
            daLot += q * _n(l['gain_piece']);
            ctrls[id]!.clear();
          } on ApiException catch (e) {
            setSt(() { saving = false; erreur = '${l['produit']} · ${e.message}'; });
            return;
          } catch (e) {
            setSt(() { saving = false; erreur = '${l['produit']} · $e'; });
            return;
          }
        }

        final frais = await charger();
        if (!ctx.mounted) return;
        setSt(() {
          saving = false;
          nbAjoutes += nLot;
          kgAjoutes += kgLot;
          daAjoutes += daLot;
          kgRestant -= kgLot;
          if (frais != null) {
            lignes = _trier(frais, main, dejaValise);
            preparer();
          }
        });
      }

      return Dialog(
        backgroundColor: DzColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: 720, maxHeight: MediaQuery.of(ctx).size.height * .88),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(main ? 'Remplir le bagage à main — non déclaré' : 'Remplir la valise',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                      main
                          ? 'Jamais déclaré ni facturé. Anti-saisie : varie les produits, 2 pièces maximum par produit.'
                          : 'Mets une quantité et le prix déclaré sur ce que tu charges, puis « Ajouter ». '
                              'La liste se met à jour et tu peux continuer autant de fois que tu veux.',
                      style: TextStyle(
                          color: main ? DzColors.amber : DzColors.mut, fontSize: 11.5)),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: (depasse ? DzColors.red : DzColors.lime).withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: (depasse ? DzColors.red : DzColors.lime).withValues(alpha: .35)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${kgRestant.toStringAsFixed(1)} kg de place restante',
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w800, color: DzColors.txt)),
                          if (nbAjoutes > 0)
                            Text(
                                'déjà chargé ici : $nbAjoutes produit(s) · '
                                '${kgAjoutes.toStringAsFixed(1)} kg · +${_f0(daAjoutes)} DA',
                                style: const TextStyle(color: DzColors.lime, fontSize: 11)),
                        ]),
                      ),
                      if (choisis > 0)
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('en cours ${kgChoisi.toStringAsFixed(1)} kg · +${_f0(daChoisi)} DA',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: depasse ? DzColors.red : DzColors.lime)),
                          if (!main)
                            Text('déclaré ${usdDeclare.toStringAsFixed(2)} \$',
                                style: const TextStyle(fontSize: 10.5, color: DzColors.mut)),
                        ]),
                    ]),
                  ),

                  if (!main && concurrents.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          '${concurrents.map((c) => c['voyageur']).join(', ')} voyage(nt) aussi '
                          'sur cette mission — le stock est commun, le bénéfice aussi.',
                          style: const TextStyle(color: DzColors.mut, fontSize: 11)),
                    ),
                  if (tropVariete)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(Icons.warning_amber_rounded, size: 15, color: DzColors.amber),
                        SizedBox(width: 6),
                        Expanded(
                            child: Text(
                                'Plus de 2 pièces d’un même produit — risque de saisie en douane. '
                                'Varie plutôt les produits.',
                                style: TextStyle(color: DzColors.amber, fontSize: 11))),
                      ]),
                    ),
                  const SizedBox(height: 10),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      const Expanded(flex: 5, child: Text('PRODUIT', style: _entete)),
                      const Expanded(flex: 2,
                          child: Text('DA/KG', textAlign: TextAlign.right, style: _entete)),
                      const Expanded(flex: 2,
                          child: Text('DISPO', textAlign: TextAlign.right, style: _entete)),
                      const SizedBox(width: 82,
                          child: Text('QTÉ', textAlign: TextAlign.center, style: _entete)),
                      if (!main)
                        const SizedBox(width: 90,
                            child: Text('DÉCLARÉ \$/PC',
                                textAlign: TextAlign.center, style: _entete)),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: lignes.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(30),
                            child: Center(child: Text('Plus rien en stock.',
                                style: TextStyle(color: DzColors.mut))))
                        : ListView(shrinkWrap: true, children: [
                            for (final l in lignes)
                              _row(l, ctrls[l['id']]!, prixCtrls[l['id']]!, prixKiloMin,
                                  usdCny, main, main && dejaValise.contains(l['id'] as int),
                                  sansPrix.contains(l['id'] as int), () => setSt(() {})),
                          ]),
                  ),
                  const SizedBox(height: 10),

                  if (erreur != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                      decoration: BoxDecoration(
                          color: DzColors.red.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.error_outline, size: 16, color: DzColors.red),
                        const SizedBox(width: 9),
                        Expanded(child: Text(erreur!,
                            style: const TextStyle(color: DzColors.red, fontSize: 11.5))),
                      ]),
                    )
                  else if (motif != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        const Icon(Icons.info_outline, size: 15, color: DzColors.mut),
                        const SizedBox(width: 8),
                        Expanded(child: Text(motif,
                            style: const TextStyle(color: DzColors.mut, fontSize: 11.5))),
                      ]),
                    ),

                  Row(children: [
                    TextButton(
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      child: Text(nbAjoutes > 0 ? 'Terminer' : 'Annuler'),
                    ),
                    const Spacer(),
                    if (choisis > 0)
                      OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => setSt(() { for (final c in ctrls.values) { c.clear(); } }),
                        child: const Text('Vider'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: bloque ? null : ajouter,
                      child: saving
                          ? const SizedBox(height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(choisis > 0 ? 'Ajouter $choisis produit(s)' : 'Ajouter'),
                    ),
                  ]),
                ]),
          ),
        ),
      );
    }),
  );

  for (final c in ctrls.values) { c.dispose(); }
  for (final c in prixCtrls.values) { c.dispose(); }
  return ok;
}

List<dynamic> _trier(Map data, bool main, Set<int> dejaValise) {
  final l = (data['lignes'] as List).where((x) => _n(x['restant']) > 0).toList();
  l.sort((a, b) => _n(b['gain_kg']).compareTo(_n(a['gain_kg'])));
  if (main) {
    l.sort((a, b) {
      final va = dejaValise.contains(a['id'] as int) ? 1 : 0;
      final vb = dejaValise.contains(b['id'] as int) ? 1 : 0;
      if (va != vb) return va - vb;
      return _n(b['gain_kg']).compareTo(_n(a['gain_kg']));
    });
  }
  return l;
}

const _entete = TextStyle(
    color: DzColors.mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8);

Widget _row(Map l, TextEditingController c, TextEditingController px, double pkMin,
    double usdCny, bool main, bool enValise, bool prixManquant, VoidCallback onChange) {
  final gainKg = _n(l['gain_kg']);
  final bon = gainKg >= pkMin;
  final dispo = _n(l['restant']);
  final actif = _d(c) > 0;
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
        color: DzColors.card2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            width: prixManquant ? 1.4 : 1,
            color: prixManquant
                ? DzColors.red
                : actif
                    ? DzColors.lime.withValues(alpha: .5)
                    : enValise
                        ? DzColors.amber.withValues(alpha: .4)
                        : DzColors.line)),
    child: Row(children: [
      Expanded(flex: 5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${l['produit']}', overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
                '${l['chambre_nom']} · ${_n(l['poids_unit']).toStringAsFixed(2)} kg/pc · '
                '${l['mode'] == 'kg' ? '${_f0(_n(l['prix']))} DA/kg' : '${_f0(_n(l['prix']))} DA/pc'}'
                ' · manque ${l['manque_devise'] == 'DA' ? '${_f0(_n(l['manque_da']))} DA' : '${_f0(_n(l['manque_rmb']))} ¥'}'
                '${usdCny > 0 && l['manque_devise'] != 'DA' ? ' (≈ ${(_n(l['manque_rmb']) / usdCny).toStringAsFixed(2)} \$)' : ''}'
                '${enValise ? ' · ⚠ déjà dans la valise déclarée — risque de saisie' : ''}',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: enValise ? DzColors.amber : DzColors.mut, fontSize: 10.5)),
          ])),
      Expanded(flex: 2,
          child: Text(_f0(gainKg), textAlign: TextAlign.right,
              style: TextStyle(
                  color: bon ? DzColors.lime : DzColors.txt,
                  fontSize: 12.5, fontWeight: FontWeight.w700))),
      Expanded(flex: 2,
          child: Text('${_f0(dispo)} pc\n${(dispo * _n(l['poids_unit'])).toStringAsFixed(1)} kg',
              textAlign: TextAlign.right,
              style: const TextStyle(color: DzColors.mut, fontSize: 10.5, height: 1.3))),
      SizedBox(
        width: 82,
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: TextField(
            controller: c, keyboardType: TextInputType.number, textAlign: TextAlign.center,
            onChanged: (_) => onChange(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(isDense: true, hintText: '0',
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
          ),
        ),
      ),
      if (!main)
        SizedBox(
          width: 90,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextField(
              controller: px, keyboardType: TextInputType.number, textAlign: TextAlign.center,
              onChanged: (_) => onChange(),
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: DzColors.lime),
              decoration: InputDecoration(isDense: true,
                  hintText: prixManquant ? 'requis' : '\$',
                  hintStyle: prixManquant
                      ? const TextStyle(color: DzColors.red, fontSize: 11.5)
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
            ),
          ),
        ),
    ]),
  );
}

double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
double _d(TextEditingController c) =>
    double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
String _f0(num n) =>
    n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
