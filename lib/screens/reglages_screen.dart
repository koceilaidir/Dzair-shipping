import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';

/// Réglages — la source des valeurs par défaut de toute l'app.
class ReglagesScreen extends StatefulWidget {
  const ReglagesScreen({super.key});

  @override
  State<ReglagesScreen> createState() => _ReglagesScreenState();
}

class _ReglagesScreenState extends State<ReglagesScreen> {
  final _c = <String, TextEditingController>{};
  String? _error;
  bool _loaded = false;
  bool _saving = false;
  // Société de facturation (celle par défaut) — en-tête des factures des valises.
  Map? _societe;
  final _sc = <String, TextEditingController>{};
  bool _savingSoc = false;
  static const _socChamps = [
    ('nom_cn', '公司名称 — Nom de la société (chinois)'),
    ('nom_en', 'Nom de la société (anglais)'),
    ('code_credit', '统一社会信用代码 — Code de crédit social'),
    ('adresse_cn', '地址 — Adresse (chinois)'),
    ('adresse_en', 'Adresse (anglais)'),
    ('tel', '电话 — Téléphone'),
    ('email', '邮箱 — E-mail'),
  ];

  // Page réorganisée : les taux d'abord (le nerf de la compta), puis mission,
  // démarches, commission, alertes — et la société de facturation en bas.
  static const _groupes = [
    ('Taux de change', [
      ('taux_officiel', 'Taux OFFICIEL (DA / USD) — douane & factures'),
      ('taux_parallele_usd', 'Taux parallèle (DA / USD) — taxes de carte'),
      ('taux_parallele_eur', 'Taux parallèle (DA / EUR)'),
      ('taux_rmb', 'Taux RMB (DA / ¥) — pièces manquantes'),
    ]),
    ('Mission par défaut', [
      ('budget_jour_defaut', 'Argent de poche par jour (DA)'),
      ('objectif_devises_usd', 'Objectif devises par voyage (USD)'),
    ]),
    ('Démarches & visa (DA)', [
      ('prix_premiere', 'Première demande'),
      ('prix_renouvellement', 'Renouvellement'),
      ('prix_visa_double', 'Visa double entrée'),
      ('frais_depot_visa', 'Frais de dépôt du visa'),
    ]),
    ('Commission & carte', [
      ('comm_pct_defaut', 'Commission voyageur par défaut (%)'),
      ('frais_carte_pct', 'Taxes de carte au retrait (% des retraits)'),
    ]),
    ('Seuils d’alerte', [
      ('seuil_passeport_mois', 'Passeport : alerte X mois avant'),
      ('seuil_autorisation_jours', 'Autorisation : alerte X jours avant'),
    ]),
  ];

  bool _fetchTaux = false;

  /// Cours OFFICIEL USD/DZD en direct — remplit le champ, l'admin garde la main.
  Future<void> _coursOfficiel() async {
    setState(() => _fetchTaux = true);
    try {
      final d = await Api.get('/reglages/taux-usd') as Map;
      final v = num.tryParse('${d['valeur']}');
      if (v != null && mounted) {
        _c['taux_officiel']?.text = '$v';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Cours officiel : 1 USD = $v DZD — pense à Enregistrer.'),
            backgroundColor: const Color(0xFF1E2A12)));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _fetchTaux = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([Api.get('/reglages'), Api.get('/inventaire/societes')]);
      final data = res[0] as Map;
      final socs = res[1] as List;
      if (!mounted) return;
      setState(() {
        for (final e in data.entries) {
          _c[e.key] = TextEditingController(text: '${e.value}');
        }
        _societe = socs.isEmpty ? null : socs.first as Map;
        for (final (k, _) in _socChamps) {
          _sc[k] = TextEditingController(text: '${_societe?[k] ?? ''}');
        }
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _saveSociete() async {
    setState(() => _savingSoc = true);
    final body = {for (final e in _sc.entries) e.key: e.value.text.trim(), 'devise': 'USD', 'par_defaut': true};
    try {
      _societe = (_societe == null
          ? await Api.post('/inventaire/societes', body)
          : await Api.put('/inventaire/societes/${_societe!['id']}', body)) as Map;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Société de facturation enregistrée ✓'), backgroundColor: Color(0xFF1E2A12)));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _savingSoc = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.put('/reglages',
          {for (final e in _c.entries) e.key: num.tryParse(e.value.text) ?? 0});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Réglages enregistrés ✓'), backgroundColor: Color(0xFF1E2A12)));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)));
    }
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator(color: DzColors.lime));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Réglages',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const Text('Ces valeurs alimentent les missions automatiquement.',
                style: TextStyle(color: DzColors.mut, fontSize: 12)),
            const SizedBox(height: 16),
            for (final (titre, champs) in _groupes) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(titre.toUpperCase(),
                        style: const TextStyle(color: DzColors.lime, fontSize: 10,
                            fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                    const SizedBox(height: 14),
                    for (final (cle, label) in champs) ...[
                      cle == 'taux_officiel'
                          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                              Expanded(child: TextField(
                                controller: _c[cle],
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(labelText: label),
                              )),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: _fetchTaux ? null : _coursOfficiel,
                                icon: _fetchTaux
                                    ? const SizedBox(height: 14, width: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.sync, size: 15),
                                label: const Text('Cours du jour', style: TextStyle(fontSize: 12)),
                              ),
                            ])
                          : TextField(
                              controller: _c[cle],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: label),
                            ),
                      const SizedBox(height: 14),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer les réglages'),
            ),
            const SizedBox(height: 28),
            // ---- Société de facturation ----
            const Text('Société de facturation',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Text('En-tête des factures des valises (tout en chinois, sauf les produits en anglais). '
                'Le nom du représentant légal n’apparaît jamais.',
                style: TextStyle(color: DzColors.mut, fontSize: 12)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('SOCIÉTÉ PAR DÉFAUT', style: TextStyle(color: DzColors.lime, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  const SizedBox(height: 14),
                  for (final (cle, label) in _socChamps) ...[
                    TextField(controller: _sc[cle], decoration: InputDecoration(labelText: label)),
                    const SizedBox(height: 14),
                  ],
                  FilledButton(
                    onPressed: _savingSoc ? null : _saveSociete,
                    child: _savingSoc
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enregistrer la société'),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
