import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';

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

  final _tel = TextEditingController();
  bool _savingTel = false;

  bool _ifuMarge30 = true;

  Future<void> _coursOfficiel() async {
    setState(() => _fetchTaux = true);
    try {
      final d = await Api.get('/reglages/taux-usd') as Map;
      final v = num.tryParse('${d['valeur']}');
      if (v != null && mounted) {
        _c['taux_officiel']?.text = '$v';
        _snack('Cours officiel : 1 USD = $v DZD — pense à Enregistrer.');
      }
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _fetchTaux = false);
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait(
          [Api.get('/reglages'), Api.get('/inventaire/societes'), Api.get('/auth/moi')]);
      final data = res[0] as Map;
      final socs = res[1] as List;
      _tel.text = '${(res[2] as Map)['tel'] ?? ''}';
      if (!mounted) return;
      setState(() {
        for (final e in data.entries) {
          if (e.key == 'ifu_marge_30') continue;
          _c[e.key] = TextEditingController(text: '${e.value}');
        }
        _ifuMarge30 = (num.tryParse('${data['ifu_marge_30']}') ?? 1) != 0;
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.put('/reglages', {
        for (final e in _c.entries) e.key: num.tryParse(e.value.text) ?? 0,
        'ifu_marge_30': _ifuMarge30 ? 1 : 0,
      });
      _snack('Réglages enregistrés ✓');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveTel() async {
    setState(() => _savingTel = true);
    try {
      await Api.put('/auth/moi', {'tel': _tel.text.trim()});
      _snack('Numéro enregistré ✓');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _savingTel = false);
    }
  }

  Future<void> _saveSociete() async {
    setState(() => _savingSoc = true);
    final body = {
      for (final e in _sc.entries) e.key: e.value.text.trim(),
      'devise': 'USD', 'par_defaut': true,
    };
    try {
      _societe = (_societe == null
          ? await Api.post('/inventaire/societes', body)
          : await Api.put('/inventaire/societes/${_societe!['id']}', body)) as Map;
      _snack('Société de facturation enregistrée ✓');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _savingSoc = false);
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
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 980;
      final gauche = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _groupeTaux(),
        const SizedBox(height: 18),
        _groupeChamps(_groupes[1]),
        const SizedBox(height: 18),
        _groupeChamps(_groupes[2]),
      ]);
      final droite = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _groupeChamps(_groupes[3]),
        const SizedBox(height: 18),
        _groupeChamps(_groupes[4]),
        const SizedBox(height: 18),
        _groupeProfil(),
        const SizedBox(height: 18),
        _groupeSociete(),
      ]);
      return ListView(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
        children: [
          Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Réglages',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                Text('Ces valeurs alimentent les missions automatiquement.',
                    style: TextStyle(color: DzColors.mut, fontSize: 12.5)),
              ]),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 16, width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer'),
            ),
          ]),
          const SizedBox(height: 18),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: gauche),
              const SizedBox(width: 18),
              Expanded(child: droite),
            ])
          else ...[gauche, const SizedBox(height: 18), droite],
        ],
      );
    });
  }

  Widget _lab(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: DzColors.mut, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: .8)),
      );

  Widget _groupe(String titre, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _lab(titre),
          Container(
            decoration: BoxDecoration(
                color: DzColors.card, borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      );

  Widget _champ(String cle, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c[cle],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  Widget _groupeChamps((String, List<(String, String)>) g) => _groupe(g.$1, [
        for (final (cle, label) in g.$2) _champ(cle, label),
      ]);

  Widget _groupeTaux() => _groupe('Taux de change', [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _c['taux_officiel'],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Taux OFFICIEL (DA / USD) — douane & factures', isDense: true),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _fetchTaux ? null : _coursOfficiel,
              icon: _fetchTaux
                  ? const SizedBox(height: 13, width: 13,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 15),
              label: const Text('Cours du jour', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
        _champ('taux_parallele_usd', 'Taux parallèle (DA / USD) — taxes de carte'),
        _champ('taux_parallele_eur', 'Taux parallèle (DA / EUR)'),
        _champ('taux_rmb', 'Taux RMB (DA / ¥) — pièces manquantes'),

        Container(
          decoration: BoxDecoration(
              color: DzColors.card2, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          child: Row(children: [
            const Expanded(
              child: Text('Marge douane +30 % avant l’IFU (0,5 %)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Switch(
              value: _ifuMarge30,
              onChanged: (v) => setState(() => _ifuMarge30 = v),
              activeColor: DzColors.inkOnLime,
              activeTrackColor: DzColors.lime,
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 7, left: 2),
          child: Text('Pré-coche la taxe réelle à l’arrivée et à la clôture — '
              'la prévision compte toujours la marge.',
              style: TextStyle(color: DzColors.mut2, fontSize: 11)),
        ),
      ]);

  Widget _groupeProfil() => _groupe('Mon profil', [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _tel,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Mon numéro — affiché sur les bons', isDense: true),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _savingTel ? null : _saveTel,
            child: _savingTel
                ? const SizedBox(height: 14, width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('OK'),
          ),
        ]),
      ]);

  Widget _groupeSociete() => _groupe('Société de facturation', [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('En-tête des factures des valises — tout en chinois, produits en '
              'anglais. Le nom du représentant légal n’apparaît jamais.',
              style: TextStyle(color: DzColors.mut, fontSize: 11.5)),
        ),
        for (final (cle, label) in _socChamps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _sc[cle],
              decoration: InputDecoration(labelText: label, isDense: true),
            ),
          ),
        OutlinedButton(
          onPressed: _savingSoc ? null : _saveSociete,
          child: _savingSoc
              ? const SizedBox(height: 14, width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer la société'),
        ),
      ]);
}
