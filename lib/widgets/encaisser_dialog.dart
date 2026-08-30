import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';

Future<bool> montrerEncaisserDialog(
  BuildContext context, {
  required int missionId,
  required String titre,
  required double suggereDA,
  int? chambreId,
  String noteInitiale = 'versement',
}) async {
  final montant = TextEditingController(text: suggereDA.clamp(0, double.infinity).toStringAsFixed(0));
  final taux = TextEditingController();
  final note = TextEditingController(text: noteInitiale);
  var devise = 'DA';
  var moyen = 'cash';
  var ok = false;

  double n(String s) => num.tryParse(s.replaceAll(' ', '').replaceAll(',', '.'))?.toDouble() ?? 0;
  String f(num v) =>
      v.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final enDA = devise == 'DA' ? n(montant.text) : n(montant.text) * n(taux.text);
      Widget chip(String val, String label, String groupe) {
        final sel = (groupe == 'devise' ? devise : moyen) == val;
        return GestureDetector(
          onTap: () => setD(() {
            if (groupe == 'devise') { devise = val; } else { moyen = val; }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? DzColors.lime : DzColors.card2,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(label,
                style: TextStyle(
                    color: sel ? DzColors.inkOnLime : DzColors.txt2,
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        );
      }

      return AlertDialog(
        backgroundColor: DzColors.card,
        title: Text(titre, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('DEVISE', style: TextStyle(color: DzColors.mut, fontSize: 9.5,
                fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 6),
            Row(children: [
              chip('DA', 'Dinar', 'devise'), const SizedBox(width: 8),
              chip('USD', 'Dollar', 'devise'), const SizedBox(width: 8),
              chip('EUR', 'Euro', 'devise'),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: montant, autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setD(() {}),
              decoration: InputDecoration(
                  labelText: 'Montant reçu (${devise == 'DA' ? 'DA' : devise})'),
            ),
            if (devise != 'DA') ...[
              const SizedBox(height: 10),
              TextField(
                controller: taux,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setD(() {}),
                decoration: InputDecoration(labelText: 'Taux du jour (DA / 1 $devise)'),
              ),
              const SizedBox(height: 6),
              Text(enDA > 0 ? '= ${f(enDA)} DA' : 'Le montant sera converti et compté en DA.',
                  style: TextStyle(
                      color: enDA > 0 ? DzColors.lime : DzColors.mut,
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            const Text('MOYEN', style: TextStyle(color: DzColors.mut, fontSize: 9.5,
                fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 6),
            Row(children: [
              chip('cash', 'Cash', 'moyen'), const SizedBox(width: 8),
              chip('en_ligne', 'En ligne', 'moyen'),
            ]),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final m = n(montant.text);
              if (m <= 0) return;
              if (devise != 'DA' && n(taux.text) <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Indique le taux du jour pour convertir en DA.')));
                return;
              }
              try {
                await Api.post('/missions/$missionId/paiements', {
                  'montant': m,
                  'devise': devise,
                  if (devise != 'DA') 'taux': n(taux.text),
                  'moyen': moyen,
                  'note': note.text.trim(),
                  if (chambreId != null) 'chambre_id': chambreId,
                });
                ok = true;
                if (ctx.mounted) Navigator.pop(ctx);
              } on ApiException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('Encaisser'),
          ),
        ],
      );
    }),
  );
  return ok;
}
