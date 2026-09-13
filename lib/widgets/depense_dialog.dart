import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import 'date_field.dart';

const kDepenseTypes = [
  ('hotel', 'Hôtel', Icons.hotel_outlined),
  ('nourriture', 'Nourriture', Icons.restaurant_outlined),
  ('transport', 'Transport', Icons.directions_bus_outlined),
  ('autre', 'Autre', Icons.add_circle_outline),
];

const kDepenseMoyens = [
  ('alipay', 'RMB', 'Alipay ¥'),
  ('cash', 'RMB', 'Cash ¥'),
  ('cash', 'USD', 'Cash \$'),
  ('cash', 'EUR', 'Cash €'),
  ('cash', 'DA', 'Dinars'),
];

String libelleType(String t) =>
    kDepenseTypes.firstWhere((e) => e.$1 == t, orElse: () => kDepenseTypes.last).$2;

IconData iconeType(String t) =>
    kDepenseTypes.firstWhere((e) => e.$1 == t, orElse: () => kDepenseTypes.last).$3;

Future<bool> montrerDepenseDialog(BuildContext context,
    {required Map sejour, List admins = const [], Map? reglages}) async {
  var ajoutee = false;
  final rg = reglages ?? await _chargerReglages();
  if (!context.mounted) return false;
  await showDialog(
    context: context,
    builder: (_) => _DepenseDialog(
      sejour: sejour,
      admins: admins,
      reglages: rg,
      onAjout: () => ajoutee = true,
    ),
  );
  return ajoutee;
}

Future<Map?> _chargerReglages() async {
  try {
    return await Api.get('/reglages') as Map;
  } catch (_) {
    return null;
  }
}

class _DepenseDialog extends StatefulWidget {
  final Map sejour;
  final List admins;
  final Map? reglages;
  final VoidCallback onAjout;
  const _DepenseDialog({required this.sejour, required this.admins,
      required this.reglages, required this.onAjout});

  @override
  State<_DepenseDialog> createState() => _DepenseDialogState();
}

class _DepenseDialogState extends State<_DepenseDialog> {
  String _type = 'hotel';
  int _moyen = 0;
  final _montant = TextEditingController();
  final _taux = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  int? _payePar;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.admins.isNotEmpty) _payePar = widget.admins.first['id'] as int?;
    _majTaux();
  }

  double _tauxReglage(String devise) => switch (devise) {
        'RMB' => _n(widget.reglages?['taux_rmb']),
        'USD' => _n(widget.reglages?['taux_parallele_usd']),
        'EUR' => _n(widget.reglages?['taux_parallele_eur']),
        _ => 1,
      };

  void _majTaux() {
    if (_enDA) { _taux.text = ''; return; }
    final t = _tauxReglage(_devise);
    _taux.text = t > 0 ? (t % 1 == 0 ? t.toStringAsFixed(0) : t.toStringAsFixed(2)) : '';
  }

  @override
  void dispose() {
    _montant.dispose(); _taux.dispose(); _note.dispose();
    super.dispose();
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.round().toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  String get _devise => kDepenseMoyens[_moyen].$2;
  bool get _enDA => _devise == 'DA';
  double get _montantDA =>
      _n(_montant.text) * (_enDA ? 1 : _n(_taux.text));

  int get _nbMembres {
    final n = (num.tryParse('${widget.sejour['nb_membres'] ?? 1}') ?? 1).toInt();
    return n < 1 ? 1 : n;
  }

  String get _symbole => switch (_devise) {
        'RMB' => '¥',
        'USD' => '\$',
        'EUR' => '€',
        _ => 'DA',
      };

  Future<void> _save() async {
    if (_saving) return;
    final montant = _n(_montant.text);
    if (montant <= 0) {
      _snack('Entre un montant.');
      return;
    }
    if (!_enDA && _n(_taux.text) <= 0) {
      _snack('Entre le taux du jour pour convertir en dinars.');
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.post('/sejours/${widget.sejour['id']}/depenses', {
        'type': _type,
        'montant': montant,
        'devise': _devise,
        if (!_enDA) 'taux': _n(_taux.text),
        'moyen': kDepenseMoyens[_moyen].$1,
        if (_payePar != null) 'paye_par': _payePar,
        'note': _note.text.trim(),
        'date': isoDate(_date),
      });
      widget.onAjout();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) { setState(() => _saving = false); _snack(e.message); }
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Widget _pilule(String texte, bool actif, VoidCallback onTap, {IconData? icone}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: actif ? DzColors.lime : DzColors.card2,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icone != null) ...[
              Icon(icone, size: 14,
                  color: actif ? DzColors.inkOnLime : DzColors.txt2),
              const SizedBox(width: 6),
            ],
            Text(texte,
                style: TextStyle(
                    color: actif ? DzColors.inkOnLime : DzColors.txt2,
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _lab(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: DzColors.mut, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 1)),
      );

  @override
  Widget build(BuildContext context) {
    final part = _montantDA / _nbMembres;
    final membres = ((widget.sejour['membres'] as List?) ?? [])
        .map((m) => '${(m as Map)['nom']}').join(', ');
    return Dialog(
      backgroundColor: DzColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Nouvelle dépense',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                    '${widget.sejour['vol'] ?? 'Séjour'} · '
                    '$_nbMembres personne${_nbMembres > 1 ? 's' : ''}',
                    style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
                const SizedBox(height: 18),

                _lab('Type de dépense'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in kDepenseTypes)
                    _pilule(t.$2, _type == t.$1,
                        () => setState(() => _type = t.$1), icone: t.$3),
                ]),
                const SizedBox(height: 16),

                _lab('Payé avec'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < kDepenseMoyens.length; i++)
                    _pilule(kDepenseMoyens[i].$3, _moyen == i,
                        () => setState(() { _moyen = i; _majTaux(); })),
                ]),
                const SizedBox(height: 16),

                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _montant,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: 'Montant ($_symbole)'),
                    ),
                  ),
                  if (!_enDA) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _taux,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                            labelText: 'Taux du jour (DA / 1 $_symbole)',
                            helperText: 'depuis les réglages · modifiable ici',
                            helperStyle: const TextStyle(
                                color: DzColors.mut2, fontSize: 10)),
                      ),
                    ),
                  ],
                ]),
                if (!_enDA) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Text('= ${_f(_montantDA)} DA',
                        style: const TextStyle(color: DzColors.lime,
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('figé sur cette dépense — un changement de taux '
                          'plus tard ne la touchera pas',
                          style: TextStyle(color: DzColors.mut2, fontSize: 10.5)),
                    ),
                  ]),
                ],
                const SizedBox(height: 16),

                if (widget.admins.isNotEmpty) ...[
                  _lab('Payé par'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final a in widget.admins)
                      _pilule('${a['nom']}', _payePar == a['id'],
                          () => setState(() => _payePar = a['id'] as int?)),
                  ]),
                  const SizedBox(height: 16),
                ],

                Row(children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _note,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Note'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DzDateField(
                      label: 'Date', value: _date,
                      onChanged: (d) => setState(() => _date = d),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
                  decoration: BoxDecoration(
                      color: DzColors.card2, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.groups_outlined, size: 19, color: DzColors.lime),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Partagée entre les $_nbMembres membres du séjour',
                              style: const TextStyle(color: DzColors.txt2, fontSize: 12)),
                          if (membres.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(membres,
                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: DzColors.mut, fontSize: 10.5)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${_f(part)} DA',
                          style: const TextStyle(color: DzColors.lime,
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      const Text('chacun',
                          style: TextStyle(color: DzColors.mut, fontSize: 9.5)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 10),
                const Text(
                    'Ajoutée aux frais de chaque mission du séjour — '
                    'le prix du kilo à viser se recalcule.',
                    style: TextStyle(color: DzColors.mut2, fontSize: 10.5, height: 1.45)),
                const SizedBox(height: 16),

                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Ajouter la dépense'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> montrerHistoriqueDepenses(BuildContext context,
    {required Map sejour, required Future<void> Function() onChange}) async {
  await showDialog(
    context: context,
    builder: (_) => _HistoriqueDialog(sejour: sejour, onChange: onChange),
  );
}

class _HistoriqueDialog extends StatefulWidget {
  final Map sejour;
  final Future<void> Function() onChange;
  const _HistoriqueDialog({required this.sejour, required this.onChange});

  @override
  State<_HistoriqueDialog> createState() => _HistoriqueDialogState();
}

class _HistoriqueDialogState extends State<_HistoriqueDialog> {
  late Map _sejour = widget.sejour;
  bool _charge = false;

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.round().toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  Future<void> _recharger() async {
    setState(() => _charge = true);
    try {
      final s = await Api.get('/sejours/${_sejour['id']}') as Map;
      if (mounted) setState(() { _sejour = s; _charge = false; });
      await widget.onChange();
    } catch (_) {
      if (mounted) setState(() => _charge = false);
    }
  }

  Future<void> _supprimer(int id) async {
    try {
      await Api.delete('/sejours/${_sejour['id']}/depenses/$id');
      await _recharger();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  String _dateFr(dynamic d) {
    final s = '$d';
    return s.length >= 10
        ? '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}'
        : '—';
  }

  @override
  Widget build(BuildContext context) {
    final depenses = (_sejour['depenses'] as List?) ?? [];
    final total = _n(_sejour['total_da']);
    final nb = (num.tryParse('${_sejour['nb_membres'] ?? 1}') ?? 1).toInt();
    return Dialog(
      backgroundColor: DzColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Expanded(
                  child: Text('Dépenses du séjour',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                if (_charge)
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 3),
              Text('${_f(total)} DA au total · ${_f(total / (nb < 1 ? 1 : nb))} DA '
                  'par personne ($nb membre${nb > 1 ? 's' : ''})',
                  style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
              const SizedBox(height: 16),
              Flexible(
                child: depenses.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Text('Aucune dépense enregistrée pour ce séjour.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: DzColors.mut, fontSize: 12.5)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: depenses.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: DzColors.line, height: 14),
                        itemBuilder: (_, i) {
                          final d = depenses[i] as Map;
                          final devise = '${d['devise']}';
                          return Row(children: [
                            Container(
                              width: 34, height: 34, alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                  color: DzColors.card2, shape: BoxShape.circle),
                              child: Icon(iconeType('${d['type']}'),
                                  size: 16, color: DzColors.txt2),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${libelleType('${d['type']}')}'
                                      '${'${d['note'] ?? ''}'.isNotEmpty ? ' — ${d['note']}' : ''}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  Text(
                                      '${_dateFr(d['date'])} · '
                                      '${d['moyen'] == 'alipay' ? 'Alipay' : 'cash'} '
                                      '${devise == 'DA' ? '' : devise}'
                                      '${d['paye_par_nom'] != null ? ' · ${d['paye_par_nom']}' : ''}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: DzColors.mut, fontSize: 10.5)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('${_f(_n(d['montant_da']))} DA',
                                  style: const TextStyle(
                                      fontSize: 12.5, fontWeight: FontWeight.w700)),
                              if (devise != 'DA')
                                Text('${_f(_n(d['montant']))} $devise',
                                    style: const TextStyle(
                                        color: DzColors.mut2, fontSize: 10)),
                            ]),
                            if (_sejour['cloture'] != true)
                              IconButton(
                                onPressed: () => _supprimer(d['id'] as int),
                                icon: const Icon(Icons.close_rounded,
                                    size: 15, color: DzColors.mut),
                                tooltip: 'Supprimer',
                              ),
                          ]);
                        },
                      ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
