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
  Map? _seuil;             // seuil de collecte du séjour (missions ouvertes)
  List _ouvertes = [];
  String? _error;
  bool _voirEpuises = false;
  String _tri = 'gain_kg'; // gain_kg | recent | kg | quantite
  int? _filtreChambre;     // null = toutes les chambres
  String _statutFiltre = 'tous'; // tous | hotel | valise
  double _tauxUsd = 0, _usdCny = 0;
  bool _creation = false;  // page « nouveau bon » ouverte dans la zone de contenu (PC)

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('/inventaire/stock') as Map;
      if (mounted) setState(() {
        _lignes = d['lignes'] as List;
        _seuil = d['seuil'] as Map?;
        _ouvertes = (d['ouvertes'] as List?) ?? [];
        _tauxUsd = _n(d['taux_officiel']);
        _usdCny = _n(d['usd_cny']);
        _error = null;
      });
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
    var visibles = [...(_voirEpuises ? _lignes! : actifs)];
    // Filtres : chambre + statut (à l'hôtel / en valise).
    if (_filtreChambre != null) {
      visibles = visibles.where((l) => l['chambre_id'] == _filtreChambre).toList();
    }
    visibles = switch (_statutFiltre) {
      'hotel' => visibles.where((l) => _n(l['restant']) > 0).toList(),
      'valise' => visibles.where((l) => _n(l['en_cours']) > 0).toList(),
      _ => visibles,
    };
    visibles.sort((a, b) => switch (_tri) {
          'kg' => (_n(b['kg_restant']) + _n(b['kg_en_cours'])).compareTo(_n(a['kg_restant']) + _n(a['kg_en_cours'])),
          'quantite' => (_n(b['restant']) + _n(b['en_cours'])).compareTo(_n(a['restant']) + _n(a['en_cours'])),
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
          // ---- Seuil de collecte du séjour : ce que les valises ouvertes doivent
          //      encore couvrir ÷ leurs kilos libres. Baisse quand on collecte bien. ----
          _seuilCard(),
          const SizedBox(height: 12),
          // ---- Fin de séjour : ce qui reste à l'hôtel doit être rendu ou réparti
          //      AVANT le premier retour d'un admin. ----
          ..._alerteRetour(kgHotel),
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
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${visibles.length} produit(s)', style: const TextStyle(color: DzColors.mut, fontSize: 12)),
            // Chambre (défaut : toutes)
            PopupMenuButton<int?>(
              color: DzColors.card2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (v) => setState(() => _filtreChambre = v),
              itemBuilder: (_) => [
                const PopupMenuItem<int?>(value: null, child: Text('Toutes les chambres', style: TextStyle(fontSize: 13))),
                for (final c in _chambresDuStock())
                  PopupMenuItem<int?>(value: c.$1, child: Text(c.$2, style: const TextStyle(fontSize: 13))),
              ],
              child: _pill(_filtreChambre == null
                      ? 'Toutes les chambres'
                      : _chambresDuStock().firstWhere((c) => c.$1 == _filtreChambre,
                          orElse: () => (0, 'Chambre')).$2,
                  Icons.storefront_outlined, null),
            ),
            // Statut : dispo à l'hôtel / en valise
            PopupMenuButton<String>(
              initialValue: _statutFiltre, color: DzColors.card2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (v) => setState(() => _statutFiltre = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'tous', child: Text('Dispo + en valise', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'hotel', child: Text('Dispo à l’hôtel', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'valise', child: Text('En valise', style: TextStyle(fontSize: 13))),
              ],
              child: _pill({'tous': 'Dispo + en valise', 'hotel': 'Dispo à l’hôtel', 'valise': 'En valise'}[_statutFiltre]!,
                  Icons.filter_list, null),
            ),
            // Tri
            PopupMenuButton<String>(
              initialValue: _tri, color: DzColors.card2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (v) => setState(() => _tri = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'gain_kg', child: Text('Rapporte le plus (DA/kg)', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'recent', child: Text('Date d’ajout', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'kg', child: Text('Poids', style: TextStyle(fontSize: 13))),
                PopupMenuItem(value: 'quantite', child: Text('Quantité', style: TextStyle(fontSize: 13))),
              ],
              child: _pill({'gain_kg': 'Rapporte le plus', 'recent': 'Date d’ajout', 'kg': 'Poids', 'quantite': 'Quantité'}[_tri]!,
                  Icons.swap_vert, null),
            ),
            _pill(_voirEpuises ? 'Avec livrés' : 'En jeu seulement',
                Icons.visibility_outlined, () => setState(() => _voirEpuises = !_voirEpuises)),
          ]),
          const SizedBox(height: 10),
          if (visibles.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 50),
                child: Center(child: Text('Rien en stock.\nOuvre un bon dès que tu récupères de la marchandise.',
                    textAlign: TextAlign.center, style: TextStyle(color: DzColors.mut, height: 1.6)))),
          LayoutBuilder(builder: (context, c) {
            final cols = (c.maxWidth / 330).floor().clamp(1, 4);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10,
                mainAxisExtent: 172,
              ),
              itemCount: visibles.length,
              itemBuilder: (_, i) => _carte(visibles[i] as Map),
            );
          }),
        ]),
      ),
    );
  }

  double get _seuilKg => _n(_seuil?['seuil_kg']);

  Widget _seuilCard() {
    final s = _seuil;
    if (s == null || _ouvertes.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: DzColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: DzColors.line)),
        child: const Row(children: [
          Icon(Icons.speed_outlined, size: 16, color: DzColors.mut), SizedBox(width: 10),
          Expanded(child: Text('Aucune valise ouverte — le seuil de collecte s’affichera dès qu’une mission est en cours.',
              style: TextStyle(color: DzColors.mut, fontSize: 12))),
        ]),
      );
    }
    final couvert = _n(s['a_couvrir']) <= 0;
    final c = couvert ? DzColors.lime : DzColors.amber;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: .06), DzColors.card),
        borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withValues(alpha: .35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 28, height: 28, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.speed_outlined, size: 15, color: c)),
          const SizedBox(width: 10),
          const Text('SEUIL DE COLLECTE DU SÉJOUR', style: TextStyle(color: DzColors.mut, fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: .8)),
          const Spacer(),
          Text('${_ouvertes.length} valise(s) ouverte(s)', style: const TextStyle(color: DzColors.mut, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        couvert
            ? const Text('Objectifs couverts pour toutes les valises ouvertes — le reste est du bonus.',
                style: TextStyle(color: DzColors.lime, fontSize: 12.5, fontWeight: FontWeight.w600))
            : Text.rich(TextSpan(children: [
                TextSpan(text: '${_f(_seuilKg)} DA/kg', style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w800)),
                TextSpan(text: '   ${_n(s['kg_libre']).toStringAsFixed(1)} kg libres · ${_f(_n(s['a_couvrir']))} DA à couvrir',
                    style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
              ])),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final m in _ouvertes)
            Text('${m['voyageur']} ${_n(m['a_couvrir']) <= 0 ? '✓' : '${_f(_n(m['seuil_kg']))} DA/kg'} · ${_n(m['kg_libre']).toStringAsFixed(1)} kg',
                style: TextStyle(color: _n(m['a_couvrir']) <= 0 ? DzColors.lime : DzColors.mut, fontSize: 10.5)),
        ]),
        const SizedBox(height: 4),
        const Text('Au-dessus du seuil : lime. En dessous : gris (utile en complément une fois les objectifs couverts).',
            style: TextStyle(color: DzColors.mut, fontSize: 10)),
      ]),
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

  /// Chambres présentes dans le stock (pour le filtre).
  List<(int, String)> _chambresDuStock() {
    final map = <int, String>{};
    for (final l in _lignes!) {
      final id = l['chambre_id'];
      if (id is int) map[id] = '${l['chambre_nom']}';
    }
    final list = map.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  /// Bandeau fin de séjour : stock encore à l'hôtel + retour d'un admin qui approche.
  List<Widget> _alerteRetour(double kgHotel) {
    if (kgHotel <= 0 || _ouvertes.isEmpty) return const [];
    DateTime? premier;
    for (final m in _ouvertes) {
      final d = DateTime.tryParse('${m['retour'] ?? ''}'.split('T').first);
      if (d != null && (premier == null || d.isBefore(premier))) premier = d;
    }
    if (premier == null) return const [];
    final jours = premier.difference(DateTime.now()).inDays;
    final urgent = jours <= 2;
    final c = urgent ? DzColors.red : DzColors.amber;
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: c.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: .4)),
        ),
        child: Row(children: [
          Icon(Icons.assignment_return_outlined, size: 17, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(
              '${kgHotel.toStringAsFixed(1)} kg encore à l’hôtel — à répartir dans les valises '
              'ou à RENDRE aux chambres avant le premier retour, le ${dateFr(isoDate(premier))}'
              '${jours >= 0 ? ' (J−$jours)' : ''}. Chaque restitution s’enregistre toute seule.',
              style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4))),
        ]),
      ),
      const SizedBox(height: 12),
    ];
  }

  /// Rendre des pièces à leur chambre — enregistré automatiquement (historique conservé).
  Future<void> _rendreChambre(Map l) async {
    final restant = _n(l['restant']);
    final qte = TextEditingController(text: restant.toStringAsFixed(0));
    bool saving = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          final v = double.tryParse(qte.text.replaceAll(',', '.')) ?? 0;
          if (v <= 0 || saving) return;
          setSt(() => saving = true);
          try {
            await Api.post('/inventaire/retours', {'ligne_id': l['id'], 'quantite': v});
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${_f(v)} pc de « ${l['produit']} » rendues à ${l['chambre_nom']} ✓'),
                  backgroundColor: const Color(0xFF1E2A12)));
            }
            _load();
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text('Rendre à ${l['chambre_nom']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${l['produit']} — ${_f(restant)} pc à l’hôtel. La restitution est '
                    'enregistrée sur le bon (historique récupéré / rendu / net).',
                    style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                const SizedBox(height: 14),
                TextField(controller: qte, keyboardType: TextInputType.number, autofocus: true,
                    decoration: const InputDecoration(labelText: 'Pièces à rendre')),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Rendre à la chambre'),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              ]),
            ),
          ),
        );
      }),
    );
  }

  /// Même produit venu de plusieurs chambres → prix/manque/qualité différents :
  /// on le signale pour ne jamais confondre les lots.
  int _nbSources(Map l) {
    final nom = '${l['produit']}'.trim().toLowerCase();
    return _lignes!.where((x) => '${x['produit']}'.trim().toLowerCase() == nom && _n(x['expose']) > 0)
        .map((x) => x['chambre_id']).toSet().length;
  }

  /// Carte produit (grille). Photo du produit : prévue en fin de projet (V2).
  Widget _carte(Map l) {
    final restant = _n(l['restant']);
    final enCours = _n(l['en_cours']);
    final rendu = _n(l['rendu']);
    final epuise = _n(l['expose']) <= 0;
    final sources = _nbSources(l);
    final gainKg = _n(l['gain_kg']);
    final bon = _seuilKg <= 0 || gainKg >= _seuilKg;

    return Opacity(
      opacity: epuise ? .5 : 1,
      child: Material(
        color: DzColors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _voirTrace(l['id'] as int),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DzColors.line),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text('${l['produit']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.25)),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  color: DzColors.card2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  icon: const Icon(Icons.more_vert, size: 17, color: DzColors.mut),
                  onSelected: (v) {
                    if (v == 'trace') _voirTrace(l['id'] as int);
                    if (v == 'rendre') _rendreChambre(l);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'trace', child: Text('Traçabilité', style: TextStyle(fontSize: 13))),
                    if (restant > 0)
                      const PopupMenuItem(value: 'rendre',
                          child: Text('Rendre à la chambre', style: TextStyle(fontSize: 13))),
                  ],
                ),
              ]),
              const SizedBox(height: 2),
              Wrap(spacing: 6, runSpacing: 4, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: DzColors.card2, borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: DzColors.line)),
                  child: Text('${l['chambre_nom']}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                ),
                if (sources > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: DzColors.amber.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)),
                    child: Text('$sources chambres', style: const TextStyle(color: DzColors.amber, fontSize: 9.5, fontWeight: FontWeight.w700)),
                  ),
                Text(dateFr(l['bon_date']), style: const TextStyle(color: DzColors.mut, fontSize: 10)),
              ]),
              const SizedBox(height: 8),
              // Manque ¥ → \$ au cours croisé OFFICIEL du jour (USD/CNY, ex. 1 \$ = 7,18 ¥).
              Text('${_n(l['poids_unit']).toStringAsFixed(2)} kg/pc · '
                  '${l['mode'] == 'kg' ? '${_f(_n(l['prix']))} DA/kg' : '${_f(_n(l['prix']))} DA/pc'}\n'
                  'manque ${_f(_n(l['manque_rmb']))} ¥/pc'
                  '${_usdCny > 0 ? ' (≈ ${(_n(l['manque_rmb']) / _usdCny).toStringAsFixed(2)} \$)' : ''}',
                  style: const TextStyle(color: DzColors.mut, fontSize: 10.5, height: 1.45)),
              const Spacer(),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(epuise
                            ? (rendu > 0 && _n(l['livre']) <= 0 ? 'tout rendu' : 'livré')
                            : restant > 0
                                ? '${_f(restant)} pc · ${_n(l['kg_restant']).toStringAsFixed(1)} kg dispo'
                                : 'tout en valise',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: epuise ? DzColors.mut : DzColors.txt)),
                    if (!epuise && enCours > 0)
                      Text('${_f(enCours)} pc en valise', style: const TextStyle(color: DzColors.amber, fontSize: 10, fontWeight: FontWeight.w600)),
                    if (rendu > 0 && !epuise)
                      Text('${_f(rendu)} pc rendues', style: const TextStyle(color: DzColors.mut, fontSize: 10)),
                  ]),
                ),
                Text('${_f(gainKg)} DA/kg',
                    style: TextStyle(color: bon ? DzColors.lime : DzColors.mut,
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
              ]),
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
                const Text('ORIGINE', style: TextStyle(color: DzColors.mut2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
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
                const Text('OÙ SONT LES PIÈCES', style: TextStyle(color: DzColors.mut2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                ligne('À l’hôtel (pas encore en valise)', '${_f(restant)} pc'),
                if (_n(l['rendu']) > 0)
                  ligne('Rendues à la chambre', '${_f(_n(l['rendu']))} pc', c: DzColors.amber),
                for (final r in (l['retours'] as List? ?? []))
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: ligne('↩ ${dateFr(r['date'])}${(r['admin'] ?? '') != '' ? ' · ${r['admin']}' : ''}',
                        '${_f(_n(r['quantite']))} pc'),
                  ),
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
