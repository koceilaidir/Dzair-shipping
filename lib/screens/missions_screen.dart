import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';
import 'mission_detail_screen.dart';

class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  List<dynamic>? _list;
  String? _error;
  int? _selectedId;
  String _sort = 'recent';

  static const _sorts = {
    'recent': 'Dernières ajoutées',
    'retour': 'Retour proche',
    'depart': 'Date de départ',
  };

  List<dynamic> get _sorted {
    final l = [..._list!];
    switch (_sort) {
      case 'retour':
        l.sort((a, b) {
          final ca = a['statut'] == 'cloturee' ? 1 : 0;
          final cb = b['statut'] == 'cloturee' ? 1 : 0;
          if (ca != cb) return ca - cb;
          return '${a['retour'] ?? '9999'}'.compareTo('${b['retour'] ?? '9999'}');
        });
      case 'depart':
        l.sort((a, b) => '${b['depart'] ?? ''}'.compareTo('${a['depart'] ?? ''}'));
      default:
        l.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    }
    return l;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await Api.get('/missions');
      if (mounted) setState(() => _list = data as List);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  num _nn(Map m, String k) => num.tryParse('${m[k] ?? 0}') ?? 0;

  num _frais(Map m) {
    final poche = _nn(m, 'poche_da') > 0
        ? _nn(m, 'poche_da') : _nn(m, 'jours') * _nn(m, 'budget_jour');
    final pocheNette = poche - _nn(m, 'reste_da');
    return _nn(m, 'billet') + _nn(m, 'dem_cout') + _nn(m, 'frais_visa') +
        (pocheNette > 0 ? pocheNette : 0) +
        _nn(m, 'douane') + _nn(m, 'taxes_carte') + _nn(m, 'autres') + _nn(m, 'manques_da') +
        _nn(m, 'saisie_da') + (m['valise_sup'] == true ? _nn(m, 'valise_sup_prix') : 0);
  }
  num _benefDe(Map m) {
    final base = m['statut'] == 'cloturee' ? _nn(m, 'attendu') : _nn(m, 'revenu');
    return base - _frais(m);
  }

  (String, Color) _statut(Map m) {
    if (m['statut'] == 'cloturee') return ('✓ Clôturée', DzColors.mut);
    final pret = _nn(m, 'kg_total') > 0 && _benefDe(m) >= _nn(m, 'objectif');
    return pret ? ('● Prêt', DzColors.lime) : ('● En cours', DzColors.amber);
  }

  void _open(int id) {
    final wide = MediaQuery.of(context).size.width >= 950;
    if (wide) {
      setState(() => _selectedId = id);
    } else {
      Navigator.push(context,
              MaterialPageRoute(builder: (_) => MissionDetailScreen(id: id)))
          .then((_) => _load());
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_selectedId != null && MediaQuery.of(context).size.width >= 950) {
      return MissionDetailScreen(
        id: _selectedId!,
        embedded: true,
        onBack: () {
          setState(() => _selectedId = null);
          _load();
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: DzColors.lime,
        foregroundColor: DzColors.inkOnLime,
        icon: const Icon(Icons.add),
        label: const Text('Mission', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: DzColors.lime,
        onRefresh: _load,
        child: _error != null
            ? _ErrorView(msg: _error!, onRetry: _load)
            : _list == null
                ? const Center(child: CircularProgressIndicator(color: DzColors.lime))
                : _list!.isEmpty
                    ? ListView(padding: const EdgeInsets.all(24), children: const [
                        SizedBox(height: 80),
                        Center(child: Text(
                            'Aucune mission.\nCrée la première avec le bouton +.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: DzColors.mut, height: 1.6))),
                      ])
                    : Builder(builder: (context) {
                        final sorted = _sorted;
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                          itemCount: sorted.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            if (i == 0) return _sortBar();
                            return _tile(sorted[i - 1] as Map);
                          },
                        );
                      }),
      ),
    );
  }

  Widget _sortBar() => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          Text('${_list!.length} mission(s)',
              style: const TextStyle(color: DzColors.mut, fontSize: 12)),
          const Spacer(),
          PopupMenuButton<String>(
            initialValue: _sort,
            color: DzColors.card2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              for (final e in _sorts.entries)
                PopupMenuItem(
                  value: e.key,
                  child: Row(children: [
                    Icon(e.key == _sort ? Icons.check : null,
                        size: 15, color: DzColors.lime),
                    const SizedBox(width: 8),
                    Text(e.value, style: const TextStyle(fontSize: 13)),
                  ]),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                  color: DzColors.card,
                  borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.swap_vert, size: 14, color: DzColors.mut),
                const SizedBox(width: 6),
                Text(_sorts[_sort]!,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      );

  Widget _tile(Map m) {
    final (label, col) = _statut(m);
    final closed = m['statut'] == 'cloturee';
    final b = _benefDe(m);
    return Card(
      child: ListTile(
        onTap: () => _open(m['id'] as int),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 38, height: 38, alignment: Alignment.center,
          decoration: const BoxDecoration(
              color: DzColors.card2, shape: BoxShape.circle),
          child: Text('${m['voyageur_nom'] ?? '?'}'.characters.first.toUpperCase(),
              style: const TextStyle(color: DzColors.txt2, fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
        ),
        title: Text('${m['code']} · ${m['voyageur_nom']}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
            '${m['vol'] ?? ''} · ${dateFr(m['depart'])} · '
            '${num.parse('${m['kg_total'] ?? 0}').toStringAsFixed(1)} kg',
            style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (closed)
              Text('${b >= 0 ? '+' : ''}${b.toStringAsFixed(0)} DA',
                  style: TextStyle(color: b >= 0 ? DzColors.lime : DzColors.red,
                      fontWeight: FontWeight.w700, fontSize: 12.5)),

            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: DzColors.card2,
                  borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6,
                    decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(label.replaceAll('● ', '').replaceAll('✓ ', ''),
                    style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreate() async {
    List<dynamic> voyageurs;
    try {
      voyageurs = await Api.get('/voyageurs') as List;
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (voyageurs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ajoute d’abord un voyageur.')));
      }
      return;
    }
    if (!mounted) return;

    final vol = TextEditingController(text: 'AH — CAN→ALG');
    final billet = TextEditingController(text: '110000');
    final objectif = TextEditingController(text: '20000');
    DateTime depart = DateTime.now();
    DateTime? retour;
    String demType = 'multiple';
    final selected = <int>{};
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          if (selected.isEmpty || saving) return;
          setSt(() => saving = true);
          try {
            await Api.post('/missions', {
              'voyageur_ids': selected.toList(),
              'vol': vol.text.trim(),
              'depart': isoDate(depart),
              'retour': retour == null ? null : isoDate(retour!),
              'billet': num.tryParse(billet.text) ?? 0,
              'dem_type': demType,
              'objectif': num.tryParse(objectif.text) ?? 20000,
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(e.message), backgroundColor: const Color(0xFF3A1512)));
            }
          }
        }

        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min, children: [
                  const Text('Nouvelle mission',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 18),
                  TextField(controller: vol,
                      decoration: const InputDecoration(labelText: 'N° de vol / billet')),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: DzDateField(
                        label: 'Départ', value: depart,
                        onChanged: (d) => setSt(() => depart = d))),
                    const SizedBox(width: 12),
                    Expanded(child: DzDateField(
                        label: 'Retour', value: retour,
                        onChanged: (d) => setSt(() => retour = d))),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: TextField(controller: billet,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Billet A/R (DA)'))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: objectif,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Objectif bénéf'))),
                  ]),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: demType,
                    dropdownColor: DzColors.card2,
                    decoration: const InputDecoration(labelText: 'Démarches'),
                    items: const [
                      DropdownMenuItem(value: 'premiere', child: Text('Première demande')),
                      DropdownMenuItem(value: 'renouvellement', child: Text('Renouvellement')),
                      DropdownMenuItem(value: 'visa_double', child: Text('Visa double entrée')),
                      DropdownMenuItem(value: 'multiple', child: Text('Visa multiple — rien')),
                    ],
                    onChanged: (x) => setSt(() => demType = x ?? 'multiple'),
                  ),
                  const SizedBox(height: 20),
                  const Text('ASSIGNER LES VOYAGEURS',
                      style: TextStyle(color: DzColors.mut, fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  const Text('Une fiche mission sera créée pour chacun (sa valise, ses frais).',
                      style: TextStyle(color: DzColors.mut, fontSize: 11)),
                  const SizedBox(height: 8),

                  ...voyageurs.map((v) {
                    final id = v['id'] as int;
                    final on = selected.contains(id);
                    final statut = '${v['statut_dispo'] ?? 'disponible'}';
                    final bloque = statut != 'disponible';
                    final motif = statut == 'limite'
                        ? 'limite atteinte — 2 missions ce mois'
                        : 'indisponible';
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: DzColors.lime,
                      checkColor: DzColors.inkOnLime,
                      value: on && !bloque,
                      enabled: !bloque,
                      onChanged: bloque ? null : (x) =>
                          setSt(() => x! ? selected.add(id) : selected.remove(id)),
                      title: Text('${v['nom']}',
                          style: TextStyle(fontSize: 13.5,
                              color: bloque ? DzColors.mut.withValues(alpha: .6) : DzColors.txt)),
                      subtitle: Text(
                          bloque
                              ? motif
                              : '${v['bagages']} valise(s) → ${(v['bagages'] as int) * 23} kg',
                          style: TextStyle(
                              color: bloque
                                  ? (statut == 'limite' ? DzColors.amber : DzColors.red)
                                      .withValues(alpha: .8)
                                  : DzColors.mut,
                              fontSize: 11)),
                    );
                  }),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(selected.isEmpty
                            ? 'Sélectionne au moins un voyageur'
                            : 'Créer ${selected.length} mission(s)'),
                  ),
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const _ErrorView({required this.msg, required this.onRetry});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.cloud_off, color: DzColors.mut.withValues(alpha: .6), size: 44),
          const SizedBox(height: 12),
          Center(child: Text(msg, textAlign: TextAlign.center,
              style: const TextStyle(color: DzColors.mut))),
          const SizedBox(height: 16),
          Center(child: TextButton(onPressed: onRetry, child: const Text('Réessayer'))),
        ],
      );
}
