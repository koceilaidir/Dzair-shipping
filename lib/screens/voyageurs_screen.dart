import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';

/// Module Voyageurs — premier module branché de bout en bout sur l'API.
class VoyageursScreen extends StatefulWidget {
  const VoyageursScreen({super.key});

  @override
  State<VoyageursScreen> createState() => _VoyageursScreenState();
}

class _VoyageursScreenState extends State<VoyageursScreen> {
  List<dynamic>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await Api.get('/voyageurs');
      if (!mounted) return;
      setState(() => _list = data as List<dynamic>);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  String _commLabel(Map v) {
    final val = num.tryParse('${v['comm_val']}') ?? 0;
    switch (v['comm_mode']) {
      case 'kg':
        return '${val.toStringAsFixed(0)} DA/kg';
      case 'pct':
        return '${val.toStringAsFixed(0)} % du bénéfice';
      default:
        return '${val.toStringAsFixed(0)} DA fixe';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: DzColors.lime,
        foregroundColor: DzColors.inkOnLime,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Voyageur', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: DzColors.lime,
        onRefresh: _load,
        child: _error != null
            ? ListView(padding: const EdgeInsets.all(24), children: [
                const SizedBox(height: 60),
                Icon(Icons.cloud_off, color: DzColors.mut.withValues(alpha: .6), size: 44),
                const SizedBox(height: 12),
                Center(child: Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(color: DzColors.mut))),
                const SizedBox(height: 16),
                Center(child: TextButton(onPressed: _load, child: const Text('Réessayer'))),
              ])
            : _list == null
                ? const Center(child: CircularProgressIndicator(color: DzColors.lime))
                : _list!.isEmpty
                    ? ListView(padding: const EdgeInsets.all(24), children: const [
                        SizedBox(height: 80),
                        Center(child: Text('Aucun voyageur pour le moment.\nAjoute ton premier gars avec le bouton +.',
                            textAlign: TextAlign.center, style: TextStyle(color: DzColors.mut, height: 1.6))),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                        itemCount: _list!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final v = _list![i] as Map;
                          final dette = (num.tryParse('${v['dette_montant']}') ?? 0) -
                              (num.tryParse('${v['dette_rembourse']}') ?? 0);
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              leading: CircleAvatar(
                                backgroundColor: DzColors.card2,
                                child: Text((v['nom'] as String? ?? '?').characters.first.toUpperCase(),
                                    style: const TextStyle(color: DzColors.lime, fontWeight: FontWeight.w700)),
                              ),
                              title: Text(v['nom'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_commLabel(v)} · ${v['bagages']} valise(s)'
                                    '${v['dette_active'] == true && dette > 0 ? ' · dette ${dette.toStringAsFixed(0)} DA' : ''}',
                                    style: const TextStyle(color: DzColors.mut, fontSize: 11.5),
                                  ),
                                  ..._alertesValidite(v),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit_outlined, color: DzColors.mut, size: 19),
                                onPressed: () => _openForm(v),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  /// Badges d'alerte : passeport (8 mois avant) et autorisation ANAE (60 j avant).
  List<Widget> _alertesValidite(Map v) {
    final out = <Widget>[];
    final now = DateTime.now();
    DateTime? parse(dynamic s) =>
        s == null ? null : DateTime.tryParse('$s'.substring(0, 10));

    void badge(String txt, Color c) => out.add(Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(txt,
              style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ));

    final pass = parse(v['passeport_expire']);
    if (pass != null) {
      final seuil = DateTime(now.year, now.month + 8, now.day);
      if (pass.isBefore(now)) {
        badge('🛂 Passeport EXPIRÉ', DzColors.red);
      } else if (pass.isBefore(seuil)) {
        badge('🛂 Passeport expire le ${dateFr(isoDate(pass))} — renouveler', DzColors.amber);
      }
    }
    final aut = parse(v['autorisation_expire']);
    if (aut != null) {
      if (aut.isBefore(now)) {
        badge('📄 Autorisation ANAE EXPIRÉE', DzColors.red);
      } else if (aut.isBefore(now.add(const Duration(days: 60)))) {
        badge('📄 Autorisation expire le ${dateFr(isoDate(aut))}', DzColors.amber);
      }
    }
    return out;
  }

  Future<void> _openForm([Map? v]) async {
    final nom = TextEditingController(text: v?['nom'] ?? '');
    final tel = TextEditingController(text: v?['tel'] ?? '');
    final commVal = TextEditingController(text: '${v?['comm_val'] ?? 500}');
    final bagages = TextEditingController(text: '${v?['bagages'] ?? 2}');
    final depuis = TextEditingController(text: v?['depuis'] ?? '${DateTime.now().year}');
    final detteMontant = TextEditingController(text: '${v?['dette_montant'] ?? 260000}');
    String commMode = v?['comm_mode'] ?? 'kg';
    bool detteActive = v?['dette_active'] == true;
    bool saving = false;
    DateTime? passExp = v?['passeport_expire'] == null
        ? null : DateTime.tryParse('${v!['passeport_expire']}'.substring(0, 10));
    DateTime? autExp = v?['autorisation_expire'] == null
        ? null : DateTime.tryParse('${v!['autorisation_expire']}'.substring(0, 10));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          if (nom.text.trim().length < 2 || saving) return;
          setSt(() => saving = true);
          final body = {
            'nom': nom.text.trim(),
            'tel': tel.text.trim(),
            'comm_mode': commMode,
            'comm_val': num.tryParse(commVal.text) ?? 0,
            'bagages': int.tryParse(bagages.text) ?? 2,
            'depuis': depuis.text.trim(),
            'dette_active': detteActive,
            'dette_montant': num.tryParse(detteMontant.text) ?? 0,
            'passeport_expire': passExp == null ? null : isoDate(passExp!),
            'autorisation_expire': autExp == null ? null : isoDate(autExp!),
          };
          try {
            if (v == null) {
              await Api.post('/voyageurs', body);
            } else {
              await Api.put('/voyageurs/${v['id']}', body);
            }
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } on ApiException catch (e) {
            setSt(() => saving = false);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(e.message), backgroundColor: const Color(0xFF3A1512)));
            }
          }
        }

        return Dialog(
          backgroundColor: DzColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: SingleChildScrollView(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(v == null ? 'Nouveau voyageur' : 'Modifier ${v['nom']}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom complet')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: tel,
                      decoration: const InputDecoration(labelText: 'Téléphone'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: depuis,
                      decoration: const InputDecoration(labelText: 'Membre depuis'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: commMode,
                      dropdownColor: DzColors.card2,
                      decoration: const InputDecoration(labelText: 'Commission'),
                      items: const [
                        DropdownMenuItem(value: 'kg', child: Text('DA / kg')),
                        DropdownMenuItem(value: 'pct', child: Text('% du bénéfice')),
                        DropdownMenuItem(value: 'fixe', child: Text('Montant fixe')),
                      ],
                      onChanged: (x) => setSt(() => commMode = x ?? 'kg'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: commVal, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Valeur'))),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: bagages,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Valises par défaut',
                      helperText: 'Poids autorisé de ses missions = valises × 23 kg + 10 kg cabine',
                      helperStyle: TextStyle(color: DzColors.mut, fontSize: 10.5)),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: DzDateField(
                      label: 'Passeport valable jusqu’au',
                      value: passExp,
                      futureYears: 11,
                      onChanged: (d) => setSt(() => passExp = d))),
                  const SizedBox(width: 12),
                  Expanded(child: DzDateField(
                      label: 'Autorisation ANAE jusqu’au',
                      value: autExp,
                      futureYears: 3,
                      onChanged: (d) => setSt(() => autExp = d))),
                ]),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: DzColors.lime,
                  title: const Text('Dépôt 1 100 \$ avancé par l’agence',
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text('Active le registre de dette',
                      style: TextStyle(color: DzColors.mut, fontSize: 11)),
                  value: detteActive,
                  onChanged: (x) => setSt(() => detteActive = x),
                ),
                if (detteActive)
                  TextField(controller: detteMontant, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Dette initiale (DA)')),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(v == null ? 'Créer le voyageur' : 'Enregistrer'),
                ),
              ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
