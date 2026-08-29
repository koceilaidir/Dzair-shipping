import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';

/// Répartition interactive des produits d'une valise en factures :
/// sélectionner des produits → « Mettre dans la même facture » → « Ajouter une
/// facture » tant qu'il reste des produits ; puis taux RMB → générer.
/// Retourne true si des factures ont été générées.
Future<bool> showFacturesDialog(BuildContext context, {
  required int missionId,
  required List affectations,      // produits de la valise pas encore facturés
  String? depart, String? retour,  // pour proposer des dates dans le séjour
}) async {
  if (affectations.isEmpty) return false;
  final groupes = <_Groupe>[];
  final selection = <int>{};
  final taux = TextEditingController();
  bool saving = false;
  bool ok = false;

  // Taux USD → RMB pré-rempli avec le cours OFFICIEL du jour (cache serveur 12 h) —
  // modifiable à la main. Repli hors ligne : taux_officiel ÷ taux_rmb des réglages.
  try {
    final d = await Api.get('/reglages/taux-usd') as Map;
    final cny = (num.tryParse('${d['cny']}') ?? 0).toDouble();
    if (cny > 0) taux.text = cny.toStringAsFixed(2);
  } catch (_) {
    try {
      final r = await Api.get('/reglages') as Map;
      final off = (num.tryParse('${r['taux_officiel']}') ?? 0).toDouble();
      final rmb = (num.tryParse('${r['taux_rmb']}') ?? 0).toDouble();
      if (off > 0 && rmb > 0) taux.text = (off / rmb).toStringAsFixed(2);
    } catch (_) {}
  }
  if (!context.mounted) return false;

  double n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String f2(num v) => v.toStringAsFixed(2);
  final dep = depart == null ? null : DateTime.tryParse(depart);
  final ret = retour == null ? null : DateTime.tryParse(retour);

  // Date proposée = AUJOURD'HUI : la facture suit le paiement carte du jour.
  // (Bornée au séjour si on est hors des dates de la mission.)
  DateTime dateProposee(int i, int total) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (dep != null && today.isBefore(dep)) return dep;
    if (ret != null && today.isAfter(ret)) return ret;
    return today;
  }

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      final dansGroupe = {for (final g in groupes) for (final id in g.ids) id};
      final restants = affectations.where((a) => !dansGroupe.contains(a['id'])).toList();
      final tousRepartis = restants.isEmpty;
      final tauxOk = (double.tryParse(taux.text.replaceAll(',', '.')) ?? 0) > 0;
      double totalSel(Iterable ids) => affectations
          .where((a) => ids.contains(a['id']))
          .fold(0.0, (s, a) => s + n(a['quantite']) * n(a['prix_declare']));

      void mettreEnsemble() {
        if (selection.isEmpty) return;
        groupes.add(_Groupe(ids: {...selection}, date: dateProposee(groupes.length, groupes.length + 1)));
        selection.clear();
        // Redistribue les dates proposées (une différente par facture, dans le séjour)
        for (var i = 0; i < groupes.length; i++) {
          if (!groupes[i].dateManuelle) groupes[i].date = dateProposee(i, groupes.length);
        }
        setSt(() {});
      }

      Future<void> generer() async {
        if (saving || groupes.isEmpty || !tauxOk) return;
        setSt(() => saving = true);
        try {
          await Api.post('/factures/generer', {
            'mission_id': missionId,
            'taux_rmb': double.tryParse(taux.text.replaceAll(',', '.')) ?? 0,
            'groupes': [for (final g in groupes) {'affectation_ids': g.ids.toList(), 'date': isoDate(g.date)}],
          });
          ok = true;
          if (ctx.mounted) Navigator.pop(ctx);
        } on ApiException catch (e) {
          setSt(() => saving = false);
          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }

      Widget produitTile(Map a, {bool checkable = true}) {
        final id = a['id'] as int;
        final sel = selection.contains(id);
        return InkWell(
          onTap: checkable ? () => setSt(() => sel ? selection.remove(id) : selection.add(id)) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? DzColors.lime.withValues(alpha: .10) : DzColors.card2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sel ? DzColors.lime.withValues(alpha: .5) : DzColors.line),
            ),
            child: Row(children: [
              if (checkable)
                Icon(sel ? Icons.check_box : Icons.check_box_outline_blank, size: 18,
                    color: sel ? DzColors.lime : DzColors.mut),
              if (checkable) const SizedBox(width: 8),
              Expanded(child: Text('${a['produit']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              Text('${n(a['quantite']).toStringAsFixed(0)} × ${f2(n(a['prix_declare']))} \$',
                  style: const TextStyle(color: DzColors.mut, fontSize: 11)),
              const SizedBox(width: 10),
              Text('${f2(n(a['quantite']) * n(a['prix_declare']))} \$',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
      }

      return Dialog(
        backgroundColor: DzColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 700),
          child: Padding(padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              const Text('Factures de la valise', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Sélectionne les produits payés aujourd’hui puis « Mettre dans la même facture ». '
                  'Tu peux facturer le reste plus tard, au prochain paiement. Date = aujourd’hui (modifiable).',
                  style: TextStyle(color: DzColors.mut, fontSize: 11.5)),
              const SizedBox(height: 14),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  // ---- Factures déjà composées ----
                  for (var i = 0; i < groupes.length; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: DzColors.card2, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: DzColors.lime.withValues(alpha: .35)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: DzColors.lime, borderRadius: BorderRadius.circular(99)),
                              child: Text('Facture ${i + 1}', style: const TextStyle(color: DzColors.inkOnLime, fontSize: 10.5, fontWeight: FontWeight.w800))),
                          const SizedBox(width: 10),
                          Expanded(child: Text('${groupes[i].ids.length} produit(s) · ${f2(totalSel(groupes[i].ids))} \$',
                              style: const TextStyle(fontSize: 12, color: DzColors.mut))),
                          SizedBox(width: 150, child: DzDateField(
                            label: 'Date', value: groupes[i].date,
                            onChanged: (d) => setSt(() { groupes[i].date = d; groupes[i].dateManuelle = true; }),
                          )),
                          IconButton(
                            tooltip: 'Défaire', padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                            onPressed: () => setSt(() => groupes.removeAt(i)),
                            icon: const Icon(Icons.close, size: 16, color: DzColors.red),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        for (final a in affectations.where((a) => groupes[i].ids.contains(a['id'])))
                          produitTile(a, checkable: false),
                      ]),
                    ),
                  // ---- Produits restants à répartir ----
                  if (!tousRepartis) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, top: 4),
                      child: Row(children: [
                        Text(groupes.isEmpty ? 'PRODUITS DE LA VALISE' : 'RESTE À FACTURER',
                            style: const TextStyle(color: DzColors.mut2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setSt(() => selection.addAll(restants.map((a) => a['id'] as int))),
                          child: const Text('Tout sélectionner', style: TextStyle(fontSize: 11.5)),
                        ),
                      ]),
                    ),
                    for (final a in restants) produitTile(a),
                    const SizedBox(height: 4),
                    FilledButton.tonal(
                      onPressed: selection.isEmpty ? null : mettreEnsemble,
                      child: Text(selection.isEmpty
                          ? 'Sélectionne des produits'
                          : groupes.isEmpty
                              ? 'Mettre dans la même facture (${selection.length})'
                              : 'Ajouter une facture avec ces ${selection.length} produit(s)'),
                    ),
                  ] else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: DzColors.lime.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)),
                      child: Text('✓ Tous les produits sont répartis en ${groupes.length} facture(s).',
                          style: const TextStyle(color: DzColors.lime, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  if (!tousRepartis && groupes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${restants.length} produit(s) resteront à facturer plus tard.',
                          style: const TextStyle(color: DzColors.mut, fontSize: 11)),
                    ),
                ]),
              ),
              const Divider(color: DzColors.line, height: 22),
              Row(children: [
                SizedBox(width: 170, child: TextField(
                  controller: taux, keyboardType: TextInputType.number, onChanged: (_) => setSt(() {}),
                  decoration: const InputDecoration(labelText: 'Taux : 1 USD = … RMB', isDense: true),
                )),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  tauxOk
                      ? 'Total valise ${f2(totalSel(affectations.map((a) => a['id'])))} \$ = '
                        '${f2(totalSel(affectations.map((a) => a['id'])) * (double.tryParse(taux.text.replaceAll(',', '.')) ?? 0))} RMB'
                      : 'Le total en RMB s’affiche sur chaque facture.',
                  style: const TextStyle(color: DzColors.mut, fontSize: 11.5))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Plus tard')),
                const Spacer(),
                FilledButton(
                  onPressed: (saving || groupes.isEmpty || !tauxOk) ? null : generer,
                  child: saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(!tousRepartis ? 'Répartis tous les produits'
                          : !tauxOk ? 'Indique le taux RMB'
                          : 'Générer ${groupes.length} facture(s)'),
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

class _Groupe {
  Set<int> ids;
  DateTime date;
  bool dateManuelle = false;
  _Groupe({required this.ids, required this.date});
}
