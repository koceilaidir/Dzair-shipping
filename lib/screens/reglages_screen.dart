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

  static const _groupes = [
    ('Démarches — prix par défaut (DA)', [
      ('prix_premiere', 'Première demande'),
      ('prix_renouvellement', 'Renouvellement'),
      ('prix_visa_double', 'Visa double entrée'),
    ]),
    ('Douane & devises', [
      ('taux_officiel', 'Taux officiel (DA / USD)'),
      ('objectif_devises_usd', 'Objectif devises par voyage (USD)'),
    ]),
    ('Seuils d’alerte', [
      ('seuil_passeport_mois', 'Passeport : alerte X mois avant'),
      ('seuil_autorisation_jours', 'Autorisation : alerte X jours avant'),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Api.get('/reglages') as Map;
      if (!mounted) return;
      setState(() {
        for (final e in data.entries) {
          _c[e.key] = TextEditingController(text: '${e.value}');
        }
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
                      TextField(
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
          ]),
        ),
      ],
    );
  }
}
