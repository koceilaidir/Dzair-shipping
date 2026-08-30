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
  Map data;
  try { data = await Api.get('/inventaire/stock?mission=$missionId') as Map; }
  on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
  if (!context.mounted) return false;
  final lignes = ((data['lignes'] as List).where((l) => _n(l['restant']) > 0).toList())
    ..sort((a, b) => _n(b['gain_kg']).compareTo(_n(a['gain_kg'])));

  bool enValise(Map l) => main && dejaValise.contains(l['id'] as int);
  if (main) {
    lignes.sort((a, b) {
      final va = enValise(a) ? 1 : 0, vb = enValise(b) ? 1 : 0;
      if (va != vb) return va - vb;
      return _n(b['gain_kg']).compareTo(_n(a['gain_kg']));
    });
  }
  final concurrents = (data['concurrents'] as List).cast<Map>();

  final usdCny = _n(data['usd_cny']);

  final reserve = <int, double>{};
  final reservePar = <int, String>{};
  final libre = {for (final l in lignes) l['id'] as int: _n(l['restant'])};
  for (final c in concurrents) {
    var besoinDA = _n(c['manque_da']);
    var placeKg = _n(c['kg_dispo']);
    if (besoinDA <= 0 || placeKg <= 0) continue;
    for (final l in lignes) {
      if (besoinDA <= 0 || placeKg <= 0) break;
      final id = l['id'] as int;
      final gp = _n(l['gain_piece']), pu = _n(l['poids_unit']);
      if (gp <= 0 || pu <= 0 || libre[id]! <= 0) continue;
      final maxPcs = [libre[id]!, (besoinDA / gp).ceilToDouble(), (placeKg / pu).floorToDouble()]
          .reduce((a, b) => a < b ? a : b);
      if (maxPcs <= 0) continue;
      reserve[id] = (reserve[id] ?? 0) + maxPcs;
      reservePar[id] = '${c['voyageur']}';
      libre[id] = libre[id]! - maxPcs;
      besoinDA -= maxPcs * gp;
      placeKg -= maxPcs * pu;
    }
  }

  final sugg = <int, double>{};
  if (main) {
    var place = kgDispo;
    for (final l in lignes) {
      if (place <= 0) break;
      if (enValise(l)) continue;
      final id = l['id'] as int;
      final pu = _n(l['poids_unit']);
      final dispo = libre[id]!;
      if (pu <= 0 || dispo <= 0) continue;
      final pcs = [2.0, dispo, (place / pu).floorToDouble()].reduce((a, b) => a < b ? a : b);
      if (pcs <= 0) continue;
      sugg[id] = pcs;
      place -= pcs * pu;
    }
  } else {
    var besoin = manqueDA, place = kgDispo;
    for (final l in lignes) {
      if (besoin <= 0 || place <= 0) break;
      final id = l['id'] as int;
      final gp = _n(l['gain_piece']), pu = _n(l['poids_unit']);
      final dispo = libre[id]!;
      if (gp <= 0 || pu <= 0 || dispo <= 0) continue;
      final pcs = [dispo, (besoin / gp).ceilToDouble(), (place / pu).floorToDouble()].reduce((a, b) => a < b ? a : b);
      if (pcs <= 0) continue;
      sugg[id] = pcs; besoin -= pcs * gp; place -= pcs * pu;
    }
    for (final l in lignes.reversed) {
      if (place <= 0) break;
      final id = l['id'] as int;
      final pu = _n(l['poids_unit']);
      final dispo = libre[id]! - (sugg[id] ?? 0);
      if (pu <= 0 || dispo <= 0) continue;
      final pcs = [dispo, (place / pu).floorToDouble()].reduce((a, b) => a < b ? a : b);
      if (pcs <= 0) continue;
      sugg[id] = (sugg[id] ?? 0) + pcs; place -= pcs * pu;
    }
  }

  final ctrls = {for (final l in lignes) l['id'] as int: TextEditingController(
      text: (sugg[l['id'] as int] ?? 0) > 0 ? _f0(sugg[l['id'] as int]!) : '')};

  final prixCtrls = {for (final l in lignes) l['id'] as int: TextEditingController(
      text: _n(l['prix_declare']) > 0 ? _n(l['prix_declare']).toStringAsFixed(2).replaceAll('.00', '') : '')};
  bool saving = false;
  bool ok = false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      double kgChoisi = 0, daChoisi = 0, usdDeclare = 0;
      var prixManquant = false, tropVariete = false;
      for (final l in lignes) {
        final q = double.tryParse(ctrls[l['id']]!.text.replaceAll(',', '.')) ?? 0;
        final px = double.tryParse(prixCtrls[l['id']]!.text.replaceAll(',', '.')) ?? 0;
        kgChoisi += q * _n(l['poids_unit']);
        daChoisi += q * _n(l['gain_piece']);
        usdDeclare += q * px;
        if (!main && q > 0 && px <= 0) prixManquant = true;
        if (main && q > 2) tropVariete = true;
      }
      final depasse = kgChoisi > kgDispo + 1e-6;

      Future<void> save() async {
        if (saving) return;
        setSt(() => saving = true);
        try {
          for (final l in lignes) {
            final q = double.tryParse(ctrls[l['id']]!.text.replaceAll(',', '.')) ?? 0;
            if (q <= 0) continue;
            final px = double.tryParse(prixCtrls[l['id']]!.text.replaceAll(',', '.')) ?? 0;
            await Api.post('/inventaire/affectations', {
              'mission_id': missionId, 'ligne_id': l['id'], 'quantite': q,
              'emplacement': emplacement,
              if (!main) 'prix_declare': px,
            });
            ok = true;
          }
          if (ctx.mounted) Navigator.pop(ctx);
        } on ApiException catch (e) {
          setSt(() => saving = false);
          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }

      return Dialog(
        backgroundColor: DzColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: Padding(padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(main ? 'Remplir le bagage à main — 8 kg, non déclaré' : 'Ajouter depuis l’inventaire',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(main
                      ? 'Jamais déclaré ni facturé. Anti-saisie : varie les produits — 2 pièces max par '
                        'produit, et rien de ce qui est déjà dans la valise déclarée (la suggestion '
                        'respecte ces règles ; tu peux forcer à la main si tu n’as pas le choix).'
                      : concurrents.isEmpty
                          ? 'Personne d’autre en mission sur ce séjour — tout le stock est pour cette valise.'
                          : 'Suggestion équilibrée avec ${concurrents.length} autre(s) voyageur(s) du même séjour '
                            '(${concurrents.map((c) => c['voyageur']).join(', ')}) : leurs meilleurs kilos sont réservés.',
                  style: TextStyle(color: main ? DzColors.amber : DzColors.mut, fontSize: 11.5)),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: (depasse ? DzColors.red : DzColors.lime).withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (depasse ? DzColors.red : DzColors.lime).withValues(alpha: .35)),
                ),
                child: Row(children: [
                  Expanded(child: Text(
                    'Place ${kgDispo.toStringAsFixed(1)} kg · il manque ${_f0(manqueDA)} DA pour l’objectif',
                    style: const TextStyle(fontSize: 12, color: DzColors.txt))),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${kgChoisi.toStringAsFixed(1)} kg · +${_f0(daChoisi)} DA',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800,
                            color: depasse ? DzColors.red : DzColors.lime)),
                    if (!main)
                      Text('déclaré ${usdDeclare.toStringAsFixed(2)} \$',
                          style: const TextStyle(fontSize: 10.5, color: DzColors.mut)),
                  ]),
                ]),
              ),
              if (tropVariete)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, size: 15, color: DzColors.amber),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Plus de 2 pièces d’un même produit — risque de saisie en douane. Varie plutôt les produits.',
                        style: TextStyle(color: DzColors.amber, fontSize: 11))),
                  ]),
                ),
              const SizedBox(height: 10),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  const Expanded(flex: 5, child: Text('PRODUIT', style: TextStyle(color: DzColors.mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8))),
                  const Expanded(flex: 2, child: Text('DA/KG', textAlign: TextAlign.right, style: TextStyle(color: DzColors.mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8))),
                  const Expanded(flex: 2, child: Text('DISPO', textAlign: TextAlign.right, style: TextStyle(color: DzColors.mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8))),
                  const SizedBox(width: 82, child: Text('QTÉ', textAlign: TextAlign.center, style: TextStyle(color: DzColors.mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8))),
                  if (!main)
                    const SizedBox(width: 90, child: Text('DÉCLARÉ \$/PC', textAlign: TextAlign.center, style: TextStyle(color: DzColors.mut, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .8))),
                ]),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: lignes.isEmpty
                    ? const Padding(padding: EdgeInsets.all(30), child: Center(child: Text(
                        'Inventaire vide — ouvre un bon dans l’Inventaire.', style: TextStyle(color: DzColors.mut))))
                    : ListView(shrinkWrap: true, children: [
                        for (final l in lignes) _row(l, ctrls[l['id']]!, prixCtrls[l['id']]!, libre[l['id']]!,
                            reserve[l['id']] ?? 0, reservePar[l['id']], sugg[l['id']] ?? 0, prixKiloMin,
                            usdCny, main, enValise(l), () => setSt(() {})),
                      ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => setSt(() { for (final l in lignes) {
                    final s = sugg[l['id']] ?? 0; ctrls[l['id']]!.text = s > 0 ? _f0(s) : ''; } }),
                  child: const Text('Suggestion'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (saving || depasse || kgChoisi <= 0 || prixManquant) ? null : save,
                  child: saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(depasse
                          ? 'Trop de kilos'
                          : prixManquant
                              ? 'Prix déclaré manquant'
                              : main ? 'Mettre dans le bagage à main' : 'Mettre dans la valise'),
                ),
              ]),
            ]),
          ),
        ),
      );
    }),
  );
  return ok;
}

Widget _row(Map l, TextEditingController c, TextEditingController px, double libre, double reserve, String? par,
    double sugg, double pkMin, double usdCny, bool main, bool enValise, VoidCallback onChange) {
  final gainKg = _n(l['gain_kg']);
  final bon = gainKg >= pkMin;
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(color: DzColors.card2, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: enValise
            ? DzColors.amber.withValues(alpha: .4)
            : sugg > 0 ? DzColors.lime.withValues(alpha: .35) : DzColors.line)),
    child: Row(children: [
      Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: Text('${l['produit']}', overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          if (sugg > 0) ...[
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: DzColors.lime.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
                child: Text('suggéré ${_f0(sugg)}', style: const TextStyle(color: DzColors.lime, fontSize: 9, fontWeight: FontWeight.w700))),
          ],
        ]),

        Text('${l['chambre_nom']} · ${_n(l['poids_unit']).toStringAsFixed(2)} kg/pc · '
            '${l['mode'] == 'kg' ? '${_f0(_n(l['prix']))} DA/kg' : '${_f0(_n(l['prix']))} DA/pc'}'
            ' · manque ${_f0(_n(l['manque_rmb']))} ¥'
            '${usdCny > 0 ? ' (≈ ${(_n(l['manque_rmb']) / usdCny).toStringAsFixed(2)} \$)' : ''}'
            '${reserve > 0 ? ' · ${_f0(reserve)} pc réservées pour $par' : ''}'
            '${enValise ? ' · ⚠ déjà dans la valise déclarée — risque de saisie' : ''}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: enValise || reserve > 0 ? DzColors.amber : DzColors.mut, fontSize: 10.5)),
      ])),
      Expanded(flex: 2, child: Text(_f0(gainKg), textAlign: TextAlign.right,
          style: TextStyle(color: bon ? DzColors.lime : DzColors.txt, fontSize: 12.5, fontWeight: FontWeight.w700))),
      Expanded(flex: 2, child: Text('${_f0(libre)} pc\n${(libre * _n(l['poids_unit'])).toStringAsFixed(1)} kg',
          textAlign: TextAlign.right, style: const TextStyle(color: DzColors.mut, fontSize: 10.5, height: 1.3))),
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
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: DzColors.lime),
              decoration: const InputDecoration(isDense: true, hintText: '\$',
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
            ),
          ),
        ),
    ]),
  );
}

double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
String _f0(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
