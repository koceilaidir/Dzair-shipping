import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/encaisser_dialog.dart';
import 'rapport_depots_screen.dart';

class CreancesScreen extends StatefulWidget {
  const CreancesScreen({super.key});

  @override
  State<CreancesScreen> createState() => _CreancesScreenState();
}

class _CreancesScreenState extends State<CreancesScreen> {
  Map? _data;
  Map? _reglages;
  String? _error;
  final _ouverts = <int>{};
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
    try {
      final r = await Api.get('/reglages') as Map;
      if (mounted) setState(() => _reglages = r);
    } catch (_) {}
  }

  List<Map> get _tousVersements {
    final out = <Map>[];
    for (final m in ((_data?['missions'] as List?) ?? []).cast<Map>()) {
      for (final p in ((m['versements'] as List?) ?? []).cast<Map>()) {
        out.add({...p, 'code': m['code']});
      }
    }
    out.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return out;
  }

  Future<void> _encaisser(Map m, {Map? depot}) async {
    final resteM = _n(m['reste']);
    final resteD = depot == null
        ? resteM
        : (_n(depot['du']) - _n(depot['encaisse'])).clamp(0.0, double.infinity);
    final ok = await montrerEncaisserDialog(
      context,
      missionId: m['id'] as int,
      titre: 'Encaisser — ${m['code']}${depot != null ? ' · ${depot['chambre']}' : ''}',
      suggereDA: (depot == null ? resteM : resteD).toDouble(),
      chambreId: depot?['chambre_id'] as int?,
      noteInitiale: depot == null ? 'versement' : 'versement ${depot['chambre']}',
    );
    if (ok) _load();
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
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 1000;
        final colMissions = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _carteRecouvrement(),
          const SizedBox(height: 12),
          if (liste.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: Text('Aucune créance ouverte — tout est encaissé ✓',
                  style: TextStyle(color: DzColors.mut))),
            ),
          for (final m in liste) _carteMission(m),
        ]);
        final colDroite = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ..._comptesVoyageurs(),
          _carteEncaissementsMois(),
          const SizedBox(height: 16),
          _carteDerniersVersements(),
        ]);
        return ListView(
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
            const Text('Qui doit quoi, d’un coup d’œil — l’argent rentre par tranches, rien ne se perd.',
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
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 7, child: colMissions),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: colDroite),
              ])
            else ...[colMissions, const SizedBox(height: 16), colDroite],
          ],
        );
      }),
    );
  }

  Widget _carteRecouvrement() {
    final enc = _n(_data!['total_encaisse']);
    final reste = _n(_data!['total_a_recuperer']);
    final total = enc + reste;
    if (total <= 0) return const SizedBox.shrink();
    double enLigne = 0;
    for (final p in _tousVersements) {
      if ('${p['moyen']}' == 'en_ligne') enLigne += _n(p['montant']);
    }
    final cash = (enc - enLigne).clamp(0.0, double.infinity);
    final pct = (enc / total * 100).round();
    String part(num v, num t) => t > 0 ? '${(v / t * 100).round()} %' : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Recouvrement global'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: DzColors.card, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          DzDonut(
            taille: 132, epaisseur: 14,
            segments: [
              DzSegment(enc, DzColors.lime),
              DzSegment(reste, DzColors.card2),
            ],
            centre: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$pct %',
                  style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
              const Text('récupéré', style: TextStyle(color: DzColors.mut, fontSize: 9.5)),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(children: [
              DzLegende(couleur: DzColors.lime, libelle: 'Encaissé',
                  valeur: '${_f(enc)} DA', part: part(enc, total)),
              DzLegende(couleur: DzColors.card2, libelle: 'Reste à récupérer',
                  valeur: '${_f(reste)} DA', part: part(reste, total)),
              const Divider(color: DzColors.line, height: 16),
              DzLegende(couleur: DzChartColors.bleu, libelle: 'Encaissé en ligne',
                  valeur: '${_f(enLigne)} DA', part: part(enLigne, enc)),
              DzLegende(couleur: DzColors.txt2, libelle: 'Encaissé en cash',
                  valeur: '${_f(cash)} DA', part: part(cash, enc)),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _carteEncaissementsMois() {
    final parMois = <String, double>{};
    final now = DateTime.now();
    final cles = <String>[];
    for (var i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i);
      final k = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      cles.add(k);
      parMois[k] = 0;
    }
    for (final p in _tousVersements) {
      final k = '${p['date']}'.length >= 7 ? '${p['date']}'.substring(0, 7) : '';
      if (parMois.containsKey(k)) parMois[k] = parMois[k]! + _n(p['montant']);
    }
    const moisCourt = ['', 'janv', 'févr', 'mars', 'avril', 'mai', 'juin',
      'juil', 'août', 'sept', 'oct', 'nov', 'déc'];
    final barres = [
      for (final k in cles)
        DzBarreMois(moisCourt[int.tryParse(k.substring(5, 7)) ?? 0], parMois[k]!,
            actif: k == cles.last),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Encaissements — 6 derniers mois'),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: BoxDecoration(
            color: DzColors.card, borderRadius: BorderRadius.circular(16)),
        child: DzBarres(barres: barres, hauteur: 92),
      ),
    ]);
  }

  Widget _carteDerniersVersements() {
    final vs = _tousVersements.take(5).toList();
    if (vs.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _lab('Derniers versements'),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            color: DzColors.card, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          for (var i = 0; i < vs.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: i == 0 ? null : const BoxDecoration(
                  border: Border(top: BorderSide(color: DzColors.line))),
              child: Row(children: [
                Expanded(
                  child: Text(
                      '${_dateFr(vs[i]['date'])} · ${vs[i]['code']}'
                      '${vs[i]['chambre'] != null ? ' · ${vs[i]['chambre']}' : ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                ),
                _chipMoyen('${vs[i]['moyen'] ?? 'cash'}'),
                if ('${vs[i]['devise'] ?? 'DA'}' != 'DA')
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                        '${_f(_n(vs[i]['montant_devise']))} ${vs[i]['devise']} × ${_n(vs[i]['taux']).toStringAsFixed(0)}',
                        style: const TextStyle(color: DzColors.mut, fontSize: 10)),
                  ),
                const SizedBox(width: 8),
                Text('${_f(_n(vs[i]['montant']))} DA',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _chipMoyen(String moyen) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
            color: DzColors.card2, borderRadius: BorderRadius.circular(99)),
        child: Text(moyen == 'en_ligne' ? 'en ligne' : 'cash',
            style: TextStyle(
                color: moyen == 'en_ligne' ? DzChartColors.bleu : DzColors.txt2,
                fontSize: 9.5, fontWeight: FontWeight.w700)),
      );

  Widget _lab(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: DzColors.mut, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: .8)),
      );

  List<Widget> _comptesVoyageurs() {
    final comptes = (_data!['comptes'] as List? ?? []).cast<Map>();
    if (comptes.isEmpty) return const [];
    return [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 6),
        child: Text('ARGENT SUR LES COMPTES VOYAGEURS',
            style: TextStyle(color: DzColors.mut, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1)),
      ),
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: DzColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          for (var i = 0; i < comptes.length; i++) ...[
            if (i > 0) const Divider(color: DzColors.line, height: 12),
            Row(children: [
              Container(
                width: 26, height: 26, alignment: Alignment.center,
                decoration: const BoxDecoration(color: DzColors.card2, shape: BoxShape.circle),
                child: Text('${comptes[i]['voyageur']}'.isNotEmpty
                        ? '${comptes[i]['voyageur']}'[0].toUpperCase() : '?',
                    style: const TextStyle(color: DzColors.lime, fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('${comptes[i]['voyageur']}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              Text('${_f(_n(comptes[i]['solde']))} ${comptes[i]['devise'] ?? 'USD'}',
                  style: const TextStyle(color: DzColors.lime, fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ]),
          ],
          if (_totalComptesDA(comptes) > 0) ...[
            const Divider(color: DzColors.line, height: 18),
            Row(children: [
              const Expanded(child: Text('≈ en dinars (taux parallèle)',
                  style: TextStyle(color: DzColors.mut, fontSize: 11))),
              Text('${_f(_totalComptesDA(comptes))} DA',
                  style: const TextStyle(color: DzColors.txt2, fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ]),
          ],
        ]),
      ),
    ];
  }

  double _totalComptesDA(List<Map> comptes) {
    if (_reglages == null) return 0;
    final tUsd = _n(_reglages!['taux_parallele_usd']);
    final tEur = _n(_reglages!['taux_parallele_eur']);
    double total = 0;
    for (final c in comptes) {
      final t = '${c['devise']}' == 'EUR' ? tEur : tUsd;
      if (t <= 0) return 0;
      total += _n(c['solde']) * t;
    }
    return total;
  }

  Widget _kpi(String label, String val, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DzColors.card,
            borderRadius: BorderRadius.circular(14),
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
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => ouvert ? _ouverts.remove(id) : _ouverts.add(id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
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
              if (_n(m['attendu']) > 0) ...[
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (_n(m['encaisse']) / _n(m['attendu'])).clamp(0.0, 1.0).toDouble(),
                    minHeight: 6,
                    backgroundColor: DzColors.card2,
                    valueColor: AlwaysStoppedAnimation(
                        reste > 0 ? DzColors.limeDim : DzColors.lime),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${(_n(m['encaisse']) / _n(m['attendu']) * 100).clamp(0, 100).round()} % récupéré',
                    style: const TextStyle(color: DzColors.mut2, fontSize: 9.5)),
              ],
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
                          ' · ${'${p['moyen'] ?? 'cash'}' == 'en_ligne' ? 'en ligne' : 'cash'}'
                          '${'${p['note'] ?? ''}'.isNotEmpty ? ' · ${p['note']}' : ''}',
                          style: const TextStyle(color: DzColors.mut, fontSize: 11))),
                      if ('${p['devise'] ?? 'DA'}' != 'DA')
                        Text('${_f(_n(p['montant_devise']))} ${p['devise']} × ${_n(p['taux']).toStringAsFixed(0)}  ',
                            style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
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
