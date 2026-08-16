import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';
import 'bon_screen.dart';

/// Inventaire — le stock récupéré dans les chambres (à l'hôtel), avant répartition
/// dans les valises. « Ouvrir un bon » = chambre + liste des produits récupérés.
class InventaireScreen extends StatefulWidget {
  const InventaireScreen({super.key});
  @override
  State<InventaireScreen> createState() => _InventaireScreenState();
}

class _InventaireScreenState extends State<InventaireScreen> {
  List<dynamic>? _lignes;
  String? _error;
  bool _voirEpuises = false;
  String _tri = 'gain_kg'; // gain_kg | recent | kg
  bool _creation = false;  // page « nouveau bon » ouverte dans la zone de contenu (PC)

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('/inventaire/stock') as Map;
      if (mounted) setState(() { _lignes = d['lignes'] as List; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  @override
  Widget build(BuildContext context) {
    if (_creation && MediaQuery.of(context).size.width >= 950) {
      return BonScreen(embedded: true, onBack: () { setState(() => _creation = false); _load(); });
    }
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)));
    if (_lignes == null) return const Center(child: CircularProgressIndicator(color: DzColors.lime));

    // « Exposé » = à l'hôtel + dans des valises de missions NON clôturées :
    // tant que la mission n'est pas clôturée, le gain n'est pas encaissé et la
    // perte reste possible. Épuisé = plus rien en jeu (tout livré).
    final actifs = _lignes!.where((l) => _n(l['expose']) > 0).toList();
    final visibles = [...(_voirEpuises ? _lignes! : actifs)];
    visibles.sort((a, b) => switch (_tri) {
          'kg' => (_n(b['kg_restant']) + _n(b['kg_en_cours'])).compareTo(_n(a['kg_restant']) + _n(a['kg_en_cours'])),
          'recent' => (b['id'] as int).compareTo(a['id'] as int),
          _ => _n(b['gain_kg']).compareTo(_n(a['gain_kg'])),
        });
    final kgHotel = actifs.fold(0.0, (s, l) => s + _n(l['kg_restant']));
    final kgValise = actifs.fold(0.0, (s, l) => s + _n(l['kg_en_cours']));
    final kgTotal = kgHotel + kgValise;
    final gainHotel = actifs.fold(0.0, (s, l) => s + _n(l['gain_restant']));
    final gainValise = actifs.fold(0.0, (s, l) => s + _n(l['gain_en_cours']));
    final gainTotal = gainHotel + gainValise;
    final manqueRmb = actifs.fold(0.0, (s, l) => s + _n(l['expose']) * _n(l['manque_rmb']));
    final wide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ouvrirBon,
        backgroundColor: DzColors.lime, foregroundColor: DzColors.inkOnLime,
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Ouvrir un bon', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: DzColors.lime, onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
          // KPIs
          _kpis([
            ('En jeu', '${kgTotal.toStringAsFixed(1)} kg',
                '${kgHotel.toStringAsFixed(1)} kg à l’hôtel · ${kgValise.toStringAsFixed(1)} kg en valise · ${actifs.length} produit(s)',
                Icons.inventory_2_outlined, DzColors.txt),
            ('Gain en jeu', '${_f(gainTotal)} DA',
                '${_f(gainHotel)} à l’hôtel · ${_f(gainValise)} en valise'
                '${kgTotal > 0 ? ' · ${_f(gainTotal / kgTotal)} DA/kg' : ''}',
                Icons.trending_up, DzColors.lime),
            ('Manque exposé', '${_f(manqueRmb)} ¥', 'si tout était perdu (hôtel + valises en cours)',
                Icons.warning_amber_outlined, DzColors.amber),
          ], wide),
          const SizedBox(height: 14),
          // Barre outils
          Row(children: [
            Text('${visibles.length} ligne(s)', style: const TextStyle(color: DzColors.mut, fontSize: 12)),
            const Spacer(),
            _pill(_voirEpuises ? 'Avec livrés' : 'En jeu seulement',
                Icons.filter_list, () => setState(() => _voirEpuises = !_voirEpuises)),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              initialValue: _tri, color: DzColors.card2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (v) => setState(() => _tri = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'gain_kg', child: Text('Meilleur DA/kg', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'kg', child: Text('Plus de kilos', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'recent', child: Text('Plus récent', style: TextStyle(fontSize: 13))),
              ],
              child: _pill({'gain_kg': 'Meilleur DA/kg', 'kg': 'Plus de kilos', 'recent': 'Plus récent'}[_tri]!,
                  Icons.swap_vert, null),
            ),
          ]),
          const SizedBox(height: 10),
          if (visibles.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 50),
                child: Center(child: Text('Rien en stock.\nOuvre un bon dès que tu récupères de la marchandise.',
                    textAlign: TextAlign.center, style: TextStyle(color: DzColors.mut, height: 1.6)))),
          for (final l in visibles) _ligneTile(l as Map),
        ]),
      ),
    );
  }

  Widget _kpis(List<(String, String, String, IconData, Color)> data, bool wide) {
    Widget k((String, String, String, IconData, Color) d) => Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(color: DzColors.card, borderRadius: BorderRadius.circular(18),
              border: Border.all(color: DzColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 28, height: 28, alignment: Alignment.center,
                  decoration: BoxDecoration(color: d.$5.withValues(alpha: .12), borderRadius: BorderRadius.circular(9)),
                  child: Icon(d.$4, size: 15, color: d.$5 == DzColors.txt ? DzColors.mut : d.$5)),
              const SizedBox(width: 9),
              Expanded(child: Text(d.$1.toUpperCase(), style: const TextStyle(color: DzColors.mut, fontSize: 8.5,
                  fontWeight: FontWeight.w700, letterSpacing: .8))),
            ]),
            const SizedBox(height: 12),
            FittedBox(child: Text(d.$2, style: TextStyle(color: d.$5, fontSize: 21, fontWeight: FontWeight.w800, height: 1))),
            const SizedBox(height: 3),
            Text(d.$3, style: const TextStyle(color: DzColors.mut, fontSize: 9.5)),
          ]),
        );
    if (wide) {
      return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < data.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: k(data[i]))],
      ]));
    }
    return Column(children: [for (final d in data) Padding(padding: const EdgeInsets.only(bottom: 8), child: k(d))]);
  }

  Widget _pill(String label, IconData ic, VoidCallback? onTap) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: DzColors.card, border: Border.all(color: DzColors.line),
              borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic, size: 14, color: DzColors.mut), const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  /// Même produit venu de plusieurs chambres → prix/manque/qualité différents :
  /// on le signale pour ne jamais confondre les lots.
  int _nbSources(Map l) {
    final nom = '${l['produit']}'.trim().toLowerCase();
    return _lignes!.where((x) => '${x['produit']}'.trim().toLowerCase() == nom && _n(x['expose']) > 0)
        .map((x) => x['chambre_id']).toSet().length;
  }

  Widget _ligneTile(Map l) {
    final restant = _n(l['restant']);
    final enCours = _n(l['en_cours']);
    final epuise = _n(l['expose']) <= 0; // tout livré : plus rien en jeu
    final sources = _nbSources(l);
    return Opacity(
      opacity: epuise ? .5 : 1,
      child: Card(
        child: InkWell(
          onTap: () => _voirTrace(l['id'] as int),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text('${l['produit']}', overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                    const SizedBox(width: 6),
                    // Origine toujours visible : la chambre est l'identité du lot.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: DzColors.card2, borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: DzColors.line)),
                      child: Text('${l['chambre_nom']}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                    if (sources > 1) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: DzColors.amber.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)),
                        child: Text('$sources chambres', style: const TextStyle(color: DzColors.amber, fontSize: 9.5, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text('bon du ${dateFr(l['bon_date'])} · '
                      '${_n(l['poids_unit']).toStringAsFixed(2)} kg/pc · '
                      '${l['mode'] == 'kg' ? '${_f(_n(l['prix']))} DA/kg' : '${_f(_n(l['prix']))} DA/pc'} · '
                      'manque ${_f(_n(l['manque_rmb']))} ¥/pc',
                      style: const TextStyle(color: DzColors.mut, fontSize: 11)),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(epuise
                        ? 'livré'
                        : restant > 0
                            ? '${_f(restant)} pc · ${_n(l['kg_restant']).toStringAsFixed(1)} kg'
                            : 'tout en valise',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                        color: epuise ? DzColors.mut : DzColors.txt)),
                if (!epuise && enCours > 0)
                  Text('${_f(enCours)} pc en valise (${_n(l['kg_en_cours']).toStringAsFixed(1)} kg)',
                      style: const TextStyle(color: DzColors.amber, fontSize: 10.5, fontWeight: FontWeight.w600)),
                Text('${_f(_n(l['gain_kg']))} DA/kg',
                    style: const TextStyle(color: DzColors.lime, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: DzColors.mut),
            ]),
          ),
        ),
      ),
    );
  }

  /// Traçabilité : d'où vient le lot, où sont ses pièces, qui les a descendues.
  Future<void> _voirTrace(int id) async {
    Map l;
    try { l = await Api.get('/inventaire/lignes/$id') as Map; }
    on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    final traces = l['traces'] as List;
    final restant = _n(l['restant']);
    Widget ligne(String k, String v, {Color c = DzColors.txt}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(color: DzColors.mut, fontSize: 12))),
            Text(v, style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        );
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: DzColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: SingleChildScrollView(child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
              children: [
                Text('${l['produit']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text('Traçabilité du lot', style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                const SizedBox(height: 14),
                const Text('ORIGINE', style: TextStyle(color: DzColors.lime, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                ligne('Chambre', '${l['chambre_nom']}'),
                ligne('Dépôt en Algérie', '${l['depot_wilaya'] ?? '—'}'
                    '${(l['depot_adresse'] ?? '').toString().isNotEmpty ? ' · ${l['depot_adresse']}' : ''}'),
                ligne('Bon du', dateFr(l['bon_date'])),
                ligne('Récupéré', '${_f(_n(l['quantite']))} pc · ${_n(l['poids_total']).toStringAsFixed(1)} kg · '
                    '${_n(l['poids_unit']).toStringAsFixed(2)} kg/pc'),
                ligne('Payé par le dépôt', l['mode'] == 'kg' ? '${_f(_n(l['prix']))} DA/kg' : '${_f(_n(l['prix']))} DA/pc'),
                ligne('Gain par pièce', '${_f(_n(l['gain_piece']))} DA', c: DzColors.lime),
                ligne('Prix du manque', '${_f(_n(l['manque_rmb']))} ¥/pc', c: DzColors.amber),
                const SizedBox(height: 14),
                const Text('OÙ SONT LES PIÈCES', style: TextStyle(color: DzColors.lime, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                ligne('À l’hôtel (pas encore en valise)', '${_f(restant)} pc'),
                if (traces.isEmpty)
                  const Padding(padding: EdgeInsets.only(top: 4),
                      child: Text('Aucune pièce descendue pour l’instant.', style: TextStyle(color: DzColors.mut, fontSize: 12))),
                for (final t in traces)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: DzColors.card2, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: DzColors.line)),
                    child: Row(children: [
                      Icon(t['statut'] == 'cloturee' ? Icons.check_circle_outline : Icons.flight_takeoff_outlined,
                          size: 16, color: t['statut'] == 'cloturee' ? DzColors.lime : DzColors.amber),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${t['voyageur']} · ${t['code']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(t['statut'] == 'cloturee'
                                ? 'livré le ${dateFr(t['cloture_date'])}${(t['depot'] ?? '').toString().isNotEmpty ? ' · ${t['depot']}' : ''}'
                                : 'en cours · retour ${dateFr(t['retour'])}',
                            style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${_f(_n(t['quantite']))} pc', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        if (_n(t['manquants']) > 0)
                          Text('${_f(_n(t['manquants']))} manquante(s)', style: const TextStyle(color: DzColors.red, fontSize: 10.5, fontWeight: FontWeight.w600)),
                      ]),
                    ]),
                  ),
                const SizedBox(height: 12),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
              ]),
            )),
        ),
      ),
    );
  }

  /* ---------- Ouvrir un bon : en PAGE (liste potentiellement longue) ---------- */
  void _ouvrirBon() {
    if (MediaQuery.of(context).size.width >= 950) {
      setState(() => _creation = true);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const BonScreen()))
          .then((_) => _load());
    }
  }
}
