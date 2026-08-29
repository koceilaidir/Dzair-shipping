import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/download.dart';
import '../theme.dart';

/// Rapport dépôts d'une mission : après l'arrivée, Koceila génère les bons,
/// compte et vérifie, dépose la marchandise aux dépôts (chambres) puis encaisse.
/// Par dépôt : produits livrés (net des manquants/saisis), kg, DA dus,
/// bon de remise PDF, statut (à vérifier → vérifié → déposé → payé) et versements.
class RapportDepotsScreen extends StatefulWidget {
  final int missionId;
  final String code;
  const RapportDepotsScreen({super.key, required this.missionId, required this.code});

  @override
  State<RapportDepotsScreen> createState() => _RapportDepotsScreenState();
}

class _RapportDepotsScreenState extends State<RapportDepotsScreen> {
  List? _depots;
  String? _error;

  static const _statuts = [
    ('a_verifier', 'À vérifier'),
    ('verifie', 'Vérifié'),
    ('depose', 'Déposé'),
    ('paye', 'Payé'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) =>
      n.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  Future<void> _load() async {
    try {
      final d = await Api.get('/inventaire/depots/${widget.missionId}') as List;
      if (mounted) setState(() => _depots = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _setStatut(Map d, String statut) async {
    try {
      await Api.post('/inventaire/depots/${widget.missionId}/statut',
          {'chambre_id': d['chambre_id'], 'statut': statut});
      _load();
    } on ApiException catch (e) { _snack(e.message); }
  }

  Future<void> _pdf(Map d) async {
    try {
      final bytes = await Api.getBytes(
          '/inventaire/depots/${widget.missionId}/pdf/${d['chambre_id']}');
      await saveFile('remise-${d['chambre']}-${widget.code}.pdf', bytes);
    } catch (e) { _snack('$e'); }
  }

  Future<void> _encaisser(Map d) async {
    final montant = TextEditingController(
        text: (_n(d['total_da']) - _n(d['encaisse'])).clamp(0, double.infinity).toStringAsFixed(0));
    final note = TextEditingController(text: 'versement ${d['chambre']}');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DzColors.card,
        title: Text('Encaisser — ${d['chambre']}', style: const TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Dû ${_f(_n(d['total_da']))} DA · déjà versé ${_f(_n(d['encaisse']))} DA',
              style: const TextStyle(color: DzColors.mut, fontSize: 12)),
          const SizedBox(height: 14),
          TextField(controller: montant, keyboardType: TextInputType.number, autofocus: true,
              decoration: const InputDecoration(labelText: 'Montant reçu (DA)')),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Api.post('/missions/${widget.missionId}/paiements', {
                  'montant': num.tryParse(montant.text.replaceAll(' ', '')) ?? 0,
                  'note': note.text.trim(),
                  'chambre_id': d['chambre_id'],
                });
                await _load();
                // Tout versé → statut « payé » proposé automatiquement.
                if (mounted) {
                  final maj = (_depots ?? []).cast<Map>().firstWhere(
                      (x) => x['chambre_id'] == d['chambre_id'], orElse: () => d);
                  if (_n(maj['encaisse']) >= _n(maj['total_da']) - 0.5 && maj['statut'] != 'paye') {
                    _setStatut(maj, 'paye');
                  }
                }
              } on ApiException catch (e) { _snack(e.message); }
            },
            child: const Text('Encaisser'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Color _statutColor(String s) => switch (s) {
        'paye' => DzColors.lime,
        'depose' => DzColors.amber,
        'verifie' => DzColors.txt,
        _ => DzColors.mut,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DzColors.bg,
      appBar: AppBar(
        backgroundColor: DzColors.bg,
        title: Text('Rapport dépôts · ${widget.code}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)))
          : _depots == null
              ? const Center(child: CircularProgressIndicator(color: DzColors.lime))
              : _depots!.isEmpty
                  ? const Center(child: Text('Aucun produit d’inventaire dans cette mission.',
                      style: TextStyle(color: DzColors.mut)))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                      children: [
                        const Text(
                            'Vérifie chaque dépôt, imprime son bon de remise, dépose la marchandise '
                            'puis encaisse — chaque étape est tracée.',
                            style: TextStyle(color: DzColors.mut, fontSize: 12)),
                        const SizedBox(height: 14),
                        for (final d in _depots!.cast<Map>()) _carteDepot(d),
                      ],
                    ),
    );
  }

  Widget _carteDepot(Map d) {
    final du = _n(d['total_da']), enc = _n(d['encaisse']);
    final reste = (du - enc).clamp(0, double.infinity);
    final statut = '${d['statut']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DzColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DzColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['chambre']}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text('${d['depot_wilaya'] ?? '—'}'
                  '${'${d['depot_adresse'] ?? ''}'.isNotEmpty ? ' · ${d['depot_adresse']}' : ''}',
                  style: const TextStyle(color: DzColors.mut, fontSize: 11)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: _statutColor(statut).withValues(alpha: .5)),
            ),
            child: Text(_statuts.firstWhere((s) => s.$1 == statut, orElse: () => _statuts.first).$2,
                style: TextStyle(color: _statutColor(statut), fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        for (final l in (d['lignes'] as List).cast<Map>())
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text.rich(TextSpan(children: [
                TextSpan(text: '${l['produit']}', style: const TextStyle(fontSize: 12.5)),
                if ('${l['emplacement']}' == 'main')
                  const TextSpan(text: '  · bagage à main',
                      style: TextStyle(color: DzColors.mut, fontSize: 10.5)),
                if (_n(l['manquants']) > 0 || _n(l['saisis']) > 0)
                  TextSpan(
                      text: '  · ${_n(l['manquants']) > 0 ? '${_f(_n(l['manquants']))} manquante(s)' : ''}'
                          '${_n(l['manquants']) > 0 && _n(l['saisis']) > 0 ? ' + ' : ''}'
                          '${_n(l['saisis']) > 0 ? '${_f(_n(l['saisis']))} saisie(s)' : ''} — remboursées',
                      style: const TextStyle(color: DzColors.red, fontSize: 10.5)),
              ]))),
              Text('${_f(_n(l['quantite']))} pc · ${_n(l['kg']).toStringAsFixed(1)} kg  ',
                  style: const TextStyle(color: DzColors.mut, fontSize: 11)),
              Text('${_f(_n(l['da']))} DA',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        const Divider(color: DzColors.line, height: 18),
        Row(children: [
          Expanded(child: Text('Dû ${_f(du)} DA · versé ${_f(enc)} DA',
              style: const TextStyle(color: DzColors.mut, fontSize: 12))),
          Text(reste > 0 ? 'reste ${_f(reste)} DA' : 'soldé ✓',
              style: TextStyle(
                  color: reste > 0 ? DzColors.amber : DzColors.lime,
                  fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          // Avancement du statut, étape par étape.
          for (var i = 0; i < _statuts.length; i++)
            if (_statuts[i].$1 != statut)
              OutlinedButton(
                onPressed: () => _setStatut(d, _statuts[i].$1),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: Text(_statuts[i].$2, style: const TextStyle(fontSize: 11.5)),
              ),
          OutlinedButton.icon(
            onPressed: () => _pdf(d),
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
            label: const Text('Bon de remise', style: TextStyle(fontSize: 11.5)),
          ),
          FilledButton.icon(
            onPressed: reste > 0 ? () => _encaisser(d) : null,
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12)),
            icon: const Icon(Icons.payments_outlined, size: 14),
            label: const Text('Encaisser', style: TextStyle(fontSize: 11.5)),
          ),
        ]),
      ]),
    );
  }
}
