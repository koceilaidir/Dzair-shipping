import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import 'rapport_depots_screen.dart';

/// Créances — qui doit quoi : par mission clôturée, attendu / encaissé / reste,
/// avec le détail par dépôt (dû, versé, statut de remise) et l'historique des
/// versements. L'argent rentre au fil du temps ; ici on ne perd aucune miette.
class CreancesScreen extends StatefulWidget {
  const CreancesScreen({super.key});

  @override
  State<CreancesScreen> createState() => _CreancesScreenState();
}

class _CreancesScreenState extends State<CreancesScreen> {
  Map? _data;
  String? _error;
  final _ouverts = <int>{}; // missions dépliées
  bool _voirSoldees = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) =>
      n.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  String _dateFr(dynamic d) {
    final s = '$d';
    if (s.length < 10) return '—';
    return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/rapports/creances') as Map;
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _encaisser(Map m, {Map? depot}) async {
    final resteM = _n(m['reste']);
    final resteD = depot == null
        ? resteM
        : (_n(depot['du']) - _n(depot['encaisse'])).clamp(0.0, double.infinity);
    final montant = TextEditingController(
        text: (depot == null ? resteM : resteD).clamp(0, double.infinity).toStringAsFixed(0));
    final note = TextEditingController(
        text: depot == null ? 'versement' : 'versement ${depot['chambre']}');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DzColors.card,
        title: Text('Encaisser — ${m['code']}${depot != null ? ' · ${depot['chambre']}' : ''}',
            style: const TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
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
                await Api.post('/missions/${m['id']}/paiements', {
                  'montant': num.tryParse(montant.text.replaceAll(' ', '')) ?? 0,
                  'note': note.text.trim(),
                  if (depot != null) 'chambre_id': depot['chambre_id'],
                });
                _load();
              } on ApiException catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
            child: const Text('Encaisser'),
          ),
        ],
      ),
    );
  }

  static const _statutLabels = {
    'a_verifier': 'à vérifier', 'verifie': 'vérifié', 'depose': 'déposé', 'paye': 'payé',
  };

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)));
    }
    if (_data == null) {
      return const Center(child: CircularProgressIndicator(color: DzColors.lime));
    }
    final missions = (_data!['missions'] as List).cast<Map>();
    final ouvertes = missions.where((m) => _n(m['reste']) > 0.5).toList();
    final soldees = missions.where((m) => _n(m['reste']) <= 0.5).toList();
    final liste = _voirSoldees ? missions : ouvertes;
    return RefreshIndicator(
      color: DzColors.lime,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          Row(children: [
            const Expanded(child: Text('Créances',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
            TextButton(
              onPressed: () => setState(() => _voirSoldees = !_voirSoldees),
              child: Text(_voirSoldees ? 'Masquer les soldées' : 'Voir les soldées (${soldees.length})',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const Text('L’argent des missions rentre au fil des versements — rien ne se perd.',
              style: TextStyle(color: DzColors.mut, fontSize: 12)),
          const SizedBox(height: 14),
          Row(children: [
            _kpi('À récupérer', '${_f(_n(_data!['total_a_recuperer']))} DA',
                _n(_data!['total_a_recuperer']) > 0 ? DzColors.amber : DzColors.lime),
            const SizedBox(width: 10),
            _kpi('Encaissé (total)', '${_f(_n(_data!['total_encaisse']))} DA', DzColors.lime),
            const SizedBox(width: 10),
            _kpi('Missions avec solde', '${ouvertes.length}',
                ouvertes.isEmpty ? DzColors.lime : DzColors.txt),
          ]),
          const SizedBox(height: 16),
          if (liste.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: Text('Aucune créance ouverte — tout est encaissé ✓',
                  style: TextStyle(color: DzColors.mut))),
            ),
          for (final m in liste) _carteMission(m),
        ],
      ),
    );
  }

  Widget _kpi(String label, String val, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DzColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DzColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: DzColors.mut, fontSize: 11)),
            const SizedBox(height: 4),
            Text(val, style: TextStyle(color: c, fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  Widget _carteMission(Map m) {
    final id = m['id'] as int;
    final ouvert = _ouverts.contains(id);
    final reste = _n(m['reste']);
    final depots = (m['depots'] as List? ?? []).cast<Map>();
    final versements = (m['versements'] as List? ?? []).cast<Map>();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: DzColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DzColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => ouvert ? _ouverts.remove(id) : _ouverts.add(id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${m['code']} · ${m['voyageur']}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text('clôturée le ${_dateFr(m['cloture_date'])}'
                      '${'${m['depot'] ?? ''}'.isNotEmpty ? ' · dépôt ${m['depot']}' : ''}',
                      style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(reste > 0 ? 'reste ${_f(reste)} DA' : 'soldée ✓',
                    style: TextStyle(
                        color: reste > 0 ? DzColors.amber : DzColors.lime,
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Text('${_f(_n(m['encaisse']))} / ${_f(_n(m['attendu']))} DA',
                    style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
              ]),
              Icon(ouvert ? Icons.expand_less : Icons.expand_more, color: DzColors.mut, size: 18),
            ]),
          ),
        ),
        if (ouvert)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Divider(color: DzColors.line, height: 8),
              if (depots.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  child: Text('PAR DÉPÔT', style: TextStyle(color: DzColors.mut, fontSize: 9.5,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
                for (final d in depots)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(child: Text('${d['chambre']}  ·  ${_statutLabels['${d['statut']}'] ?? ''}',
                          style: const TextStyle(fontSize: 12))),
                      Text('${_f(_n(d['encaisse']))} / ${_f(_n(d['du']))} DA  ',
                          style: TextStyle(
                              color: _n(d['encaisse']) >= _n(d['du']) - 0.5
                                  ? DzColors.lime : DzColors.mut,
                              fontSize: 11.5)),
                      IconButton(
                        padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                        tooltip: 'Encaisser ce dépôt',
                        onPressed: () => _encaisser(m, depot: d),
                        icon: const Icon(Icons.payments_outlined, size: 15, color: DzColors.lime),
                      ),
                    ]),
                  ),
              ],
              if (versements.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 4),
                  child: Text('VERSEMENTS', style: TextStyle(color: DzColors.mut, fontSize: 9.5,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
                for (final p in versements)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text(
                          '${_dateFr(p['date'])}'
                          '${p['chambre'] != null ? ' · ${p['chambre']}' : ''}'
                          '${'${p['note'] ?? ''}'.isNotEmpty ? ' · ${p['note']}' : ''}',
                          style: const TextStyle(color: DzColors.mut, fontSize: 11))),
                      Text('${_f(_n(p['montant']))} DA',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                FilledButton.icon(
                  onPressed: reste > 0 ? () => _encaisser(m) : null,
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.payments_outlined, size: 14),
                  label: const Text('Encaisser', style: TextStyle(fontSize: 11.5)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => RapportDepotsScreen(
                            missionId: id, code: '${m['code']}')));
                    _load();
                  },
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.warehouse_outlined, size: 14),
                  label: const Text('Rapport dépôts', style: TextStyle(fontSize: 11.5)),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }
}
