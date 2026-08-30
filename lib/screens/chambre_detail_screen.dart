import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';
import 'chambres_screen.dart' show showChambreForm;
import '../services/download.dart';

class ChambreDetailScreen extends StatefulWidget {
  final int id;
  final bool embedded;
  final VoidCallback? onBack;
  const ChambreDetailScreen({super.key, required this.id, this.embedded = false, this.onBack});
  @override
  State<ChambreDetailScreen> createState() => _ChambreDetailScreenState();
}

class _ChambreDetailScreenState extends State<ChambreDetailScreen> {
  Map? _c;
  String? _error;
  int? _annee;
  int? _mois;

  static const _moisCourts = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('/inventaire/chambres/${widget.id}') as Map;
      if (!mounted) return;
      setState(() {
        _c = d; _error = null;

        if (_annee == null) {
          final bons = d['bons'] as List;
          if (bons.isNotEmpty) _annee = DateTime.tryParse('${bons.first['date']}'.substring(0, 10))?.year;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  DateTime? _d(dynamic s) => s == null ? null : DateTime.tryParse('$s'.substring(0, 10));

  List get _bons => (_c!['bons'] as List);
  List get _bonsFiltres => _bons.where((b) {
        final d = _d(b['date']);
        if (d == null) return false;
        if (_annee != null && d.year != _annee) return false;
        if (_mois != null && d.month != _mois) return false;
        return true;
      }).toList();
  List<int> get _annees {
    final s = <int>{};
    for (final b in _bons) { final d = _d(b['date']); if (d != null) s.add(d.year); }
    final l = s.toList()..sort((a, b) => b.compareTo(a));
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final body = _error != null
        ? Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)))
        : _c == null
            ? const Center(child: CircularProgressIndicator(color: DzColors.lime))
            : _body();
    final titre = _c == null ? 'Chambre' : '${_c!['nom']}';
    final actions = [
      if (_c != null)
        IconButton(
          tooltip: 'Modifier',
          onPressed: () async {
            await showChambreForm(context, chambre: _c, onDone: _load);
          },
          icon: const Icon(Icons.edit_outlined, size: 19, color: DzColors.mut),
        ),
    ];
    if (widget.embedded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
          child: Row(children: [
            IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back, color: DzColors.mut, size: 20)),
            const SizedBox(width: 4),
            Expanded(child: Text(titre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            ...actions,
          ]),
        ),
        Expanded(child: body),
      ]);
    }
    return Scaffold(
      appBar: AppBar(backgroundColor: DzColors.bg, title: Text(titre), actions: [...actions, const SizedBox(width: 6)]),
      body: body,
    );
  }

  Widget _body() {
    final c = _c!;
    final contacts = (c['contacts'] as List);
    final chine = contacts.where((k) => '${k['role']}'.toLowerCase() == 'chine').toList();
    final algerie = contacts.where((k) => '${k['role']}'.toLowerCase() != 'chine').toList();
    final wide = MediaQuery.of(context).size.width >= 850;
    final bf = _bonsFiltres;
    final kg = bf.fold(0.0, (s, b) => s + _n(b['kg']));
    final pcs = bf.fold(0.0, (s, b) => s + _n(b['pieces']));
    final da = bf.fold(0.0, (s, b) => s + _n(b['gain_da']));

    final infos = _card('Dépôt en Algérie', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${c['depot_wilaya'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      if ((c['depot_adresse'] ?? '').toString().isNotEmpty)
        Text('${c['depot_adresse']}', style: const TextStyle(color: DzColors.mut, fontSize: 12.5)),
      if ((c['note'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('${c['note']}', style: const TextStyle(color: DzColors.mut, fontSize: 12, fontStyle: FontStyle.italic)),
      ],
    ]));
    final contactsCard = _card('Contacts', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _groupeContacts('En Chine', chine),
      const SizedBox(height: 8),
      _groupeContacts('En Algérie', algerie),
    ]));

    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 32), children: [
      Text('${c['ville'] ?? 'Canton'} · ${_bons.length} bon(s) au total',
          style: const TextStyle(color: DzColors.mut, fontSize: 12)),
      const SizedBox(height: 12),
      if (wide)
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: infos), const SizedBox(width: 12), Expanded(child: contactsCard),
        ]))
      else ...[infos, const SizedBox(height: 12), contactsCard],
      const SizedBox(height: 12),

      _card('Performances', action: _filtres(), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _kpi('Bons', '${bf.length}', Icons.receipt_long_outlined)),
          const SizedBox(width: 10),
          Expanded(child: _kpi('Pièces', _f(pcs), Icons.widgets_outlined)),
          const SizedBox(width: 10),
          Expanded(child: _kpi('Kilos', kg.toStringAsFixed(1), Icons.scale_outlined)),
          const SizedBox(width: 10),
          Expanded(child: _kpi('Gain', '${_f(da)} DA', Icons.trending_up, accent: DzColors.lime,
              sous: kg > 0 ? '${_f(da / kg)} DA/kg' : null)),
        ]),
        const SizedBox(height: 14),
        _barresMois(),
      ])),
      const SizedBox(height: 12),

      _card('Historique des bons${_annee != null ? ' · $_annee' : ''}${_mois != null ? ' · ${_moisCourts[_mois! - 1]}' : ''}',
          child: Column(children: [
        if (bf.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Aucun bon sur cette période.', style: TextStyle(color: DzColors.mut, fontSize: 12))),
        for (final b in bf)
          InkWell(
            onTap: () => _voirBon(b['id'] as int),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Container(width: 34, height: 34, alignment: Alignment.center,
                    decoration: BoxDecoration(color: DzColors.lime.withValues(alpha: .1), borderRadius: BorderRadius.circular(9)),
                    child: const Icon(Icons.receipt_long_outlined, size: 16, color: DzColors.lime)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Bon du ${dateFr(b['date'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('${_f(_n(b['pieces']))} pcs · ${_n(b['kg']).toStringAsFixed(1)} kg'
                    '${_n(b['rendu']) > 0 ? ' · ${_f(_n(b['rendu']))} rendues' : ''}'
                      '${(b['note'] ?? '').toString().isNotEmpty ? ' · ${b['note']}' : ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: DzColors.mut, fontSize: 11)),
                ])),
                Text('${_f(_n(b['gain_da']))} DA', style: const TextStyle(color: DzColors.lime, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: DzColors.mut),
              ]),
            ),
          ),
      ])),
    ]);
  }

  Widget _filtres() {
    final annees = _annees;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _menu<int?>(
        label: _annee == null ? 'Toutes années' : '$_annee',
        items: [(null, 'Toutes années'), for (final a in annees) (a, '$a')],
        onSelected: (v) => setState(() { _annee = v; }),
      ),
      const SizedBox(width: 6),
      _menu<int?>(
        label: _mois == null ? 'Tous mois' : _moisCourts[_mois! - 1],
        items: [(null, 'Tous mois'), for (var m = 1; m <= 12; m++) (m, _moisCourts[m - 1])],
        onSelected: (v) => setState(() { _mois = v; }),
      ),
    ]);
  }

  Widget _menu<T>({required String label, required List<(T, String)> items, required ValueChanged<T> onSelected}) =>
      PopupMenuButton<T>(
        color: DzColors.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: onSelected,
        itemBuilder: (_) => [for (final it in items) PopupMenuItem<T>(value: it.$1,
            child: Text(it.$2, style: const TextStyle(fontSize: 13)))],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: DzColors.card2,
              borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            const Icon(Icons.expand_more, size: 15, color: DzColors.mut),
          ]),
        ),
      );

  Widget _barresMois() {
    final Map<String, double> par = {};
    final List<String> cles;
    if (_annee != null) {
      cles = [for (var m = 1; m <= 12; m++) _moisCourts[m - 1]];
      for (final k in cles) { par[k] = 0; }
      for (final b in _bons) {
        final d = _d(b['date']);
        if (d == null || d.year != _annee) continue;
        par[_moisCourts[d.month - 1]] = par[_moisCourts[d.month - 1]]! + _n(b['gain_da']);
      }
    } else {
      final an = _annees.reversed.toList();
      cles = [for (final a in an) '$a'];
      for (final k in cles) { par[k] = 0; }
      for (final b in _bons) {
        final d = _d(b['date']);
        if (d == null) continue;
        par['${d.year}'] = (par['${d.year}'] ?? 0) + _n(b['gain_da']);
      }
    }
    final max = par.values.fold(0.0, (m, v) => v > m ? v : m);
    if (max <= 0) {
      return const Text('Pas encore de données pour tracer les mois.',
          style: TextStyle(color: DzColors.mut, fontSize: 11.5));
    }
    return SizedBox(
      height: 90,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final k in cles)
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (par[k]! > 0)
                Text(_f(par[k]! / 1000), style: const TextStyle(color: DzColors.mut, fontSize: 8.5)),
              const SizedBox(height: 2),
              Container(
                height: (par[k]! / max * 56).clamp(par[k]! > 0 ? 3 : 1, 56).toDouble(),
                decoration: BoxDecoration(
                  color: (_mois != null && _annee != null && k == _moisCourts[_mois! - 1])
                      ? DzColors.lime : (par[k]! > 0 ? DzColors.lime.withValues(alpha: .55) : DzColors.card2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Text(k, style: const TextStyle(color: DzColors.mut, fontSize: 9)),
            ]),
          )),
      ]),
    );
  }

  Widget _groupeContacts(String titre, List l) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre, style: const TextStyle(color: DzColors.mut, fontSize: 11, fontWeight: FontWeight.w700)),
        if (l.isEmpty) const Text('—', style: TextStyle(color: DzColors.mut, fontSize: 12)),
        for (final k in l)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              const Icon(Icons.person_outline, size: 15, color: DzColors.mut),
              const SizedBox(width: 8),
              Expanded(child: Text('${k['nom']}', style: const TextStyle(fontSize: 12.5))),
              Text('${k['tel'] ?? ''}', style: const TextStyle(color: DzColors.lime, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]);

  Widget _kpi(String label, String valeur, IconData ic, {Color accent = DzColors.mut, String? sous}) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: DzColors.card2, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ic, size: 13, color: accent),
            const SizedBox(width: 5),
            Text(label.toUpperCase(), style: const TextStyle(color: DzColors.mut, fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: .8)),
          ]),
          const SizedBox(height: 6),
          FittedBox(child: Text(valeur, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
              color: accent == DzColors.mut ? DzColors.txt : accent))),
          if (sous != null) Text(sous, style: const TextStyle(color: DzColors.mut, fontSize: 9.5)),
        ]),
      );

  Widget _card(String titre, {Widget? action, required Widget child}) => Container(
        decoration: BoxDecoration(color: DzColors.card, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 40, child: Row(children: [
            Expanded(child: Text(titre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
            if (action != null) action,
          ])),
          const SizedBox(height: 4),
          child,
        ]),
      );

  Future<void> _voirBon(int id) async {
    Map b;
    try { b = await Api.get('/inventaire/bons/$id') as Map; }
    on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    final lignes = b['lignes'] as List;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: DzColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text('Bon du ${dateFr(b['date'])} · ${b['chambre_nom']}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              if ((b['note'] ?? '').toString().isNotEmpty)
                Text('${b['note']}', style: const TextStyle(color: DzColors.mut, fontSize: 12)),
              const SizedBox(height: 12),
              for (final l in lignes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${l['produit']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('${_f(_n(l['quantite']))} pcs'
                          '${_n(l['rendu']) > 0 ? ' (−${_f(_n(l['rendu']))} rendues)' : ''}'
                          ' · ${_n(l['poids_total']).toStringAsFixed(1)} kg · '
                          '${l['mode'] == 'kg' ? '${_f(_n(l['prix']))} DA/kg' : '${_f(_n(l['prix']))} DA/pc'} · '
                          'manque ${_f(_n(l['manque_rmb']))} ¥/pc · '
                          '${_f(_n(l['affecte']))} en valise',
                          style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
                    ])),
                    Text('${_f(l['mode'] == 'kg' ? _n(l['prix']) * _n(l['poids_total']) : _n(l['prix']) * _n(l['quantite']))} DA',
                        style: const TextStyle(color: DzColors.lime, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
              const SizedBox(height: 10),
              Row(children: [
                TextButton.icon(
                  onPressed: () async {
                    try {
                      final bytes = await Api.getBytes('/inventaire/bons/$id/pdf');
                      await saveFile('bon-${b['chambre_nom']}-$id.pdf', bytes);
                    } catch (e) {
                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16, color: DzColors.lime),
                  label: const Text('PDF', style: TextStyle(color: DzColors.lime, fontSize: 12.5)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await Api.delete('/inventaire/bons/$id');
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    } on ApiException catch (e) {
                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16, color: DzColors.red),
                  label: const Text('Supprimer le bon', style: TextStyle(color: DzColors.red, fontSize: 12.5)),
                ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
