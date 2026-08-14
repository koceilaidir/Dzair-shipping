import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';

/// Finance — la comptabilité agrégée (fin de mission).
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  Map? _data;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('/rapports/finance');
      if (mounted) setState(() => _data = d as Map);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)));
    if (_data == null) return const Center(child: CircularProgressIndicator(color: DzColors.lime));
    final t = _data!['totaux'] as Map;
    final parMois = (_data!['par_mois'] as List);
    final missions = (_data!['missions'] as List);

    return RefreshIndicator(
      color: DzColors.lime,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 32), children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Finance', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const Text('Comptabilité agrégée des missions clôturées.',
                style: TextStyle(color: DzColors.mut, fontSize: 12)),
            const SizedBox(height: 16),
            // KPIs
            Wrap(spacing: 10, runSpacing: 10, children: [
              _kpi('Net agence', '${_f(_n(t['net_agence']))} DA',
                  _n(t['net_agence']) >= 0 ? DzColors.lime : DzColors.red),
              _kpi('DA sortis', '${_f(_n(t['sortis']))} DA', DzColors.txt),
              _kpi('Revenus', '${_f(_n(t['revenus']))} DA', DzColors.txt),
              _kpi('Créances dehors', '${_f(_n(t['creances']))} DA',
                  _n(t['creances']) > 0 ? DzColors.amber : DzColors.lime),
              _kpi('Part voyageurs', '${_f(_n(t['part_voyageurs']))} DA', DzColors.txt),
              _kpi('Missions clôturées', '${t['missions_cloturees']}', DzColors.txt),
            ]),
            const SizedBox(height: 16),
            // Net par mois
            _bloc('Net agence par mois', Column(children: [
              if (parMois.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Pas encore de mission clôturée.',
                        style: TextStyle(color: DzColors.mut, fontSize: 12.5))),
              for (final m in parMois)
                _ligne(_moisFr('${m['mois']}'), '${_n(m['net']) >= 0 ? '+' : ''}${_f(_n(m['net']))} DA',
                    couleur: _n(m['net']) >= 0 ? DzColors.lime : DzColors.red),
            ])),
            const SizedBox(height: 12),
            // Détail par mission
            _bloc('Détail par mission', Column(children: [
              for (final m in missions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${m['code']} · ${m['voyageur']}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                      Text('${_f(_n(m['attendu']) - _n(m['frais']) - _n(m['marchandise']))} DA',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                              color: DzColors.lime)),
                    ]),
                    Text('frais ${_f(_n(m['frais']))} · march. ${_f(_n(m['marchandise']))} · '
                        'comm. ${_f(_n(m['commission']))}'
                        '${_n(m['solde']) > 0 ? ' · créance ${_f(_n(m['solde']))}' : ''}',
                        style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
                  ]),
                ),
            ])),
          ]),
        ),
      ]),
    );
  }

  String _moisFr(String k) {
    if (k.length < 7) return k;
    const m = ['janvier','février','mars','avril','mai','juin','juillet','août',
      'septembre','octobre','novembre','décembre'];
    final i = int.tryParse(k.substring(5, 7)) ?? 1;
    return '${m[i - 1]} ${k.substring(0, 4)}';
  }

  Widget _kpi(String l, String v, Color c) => Container(
        width: 180,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(color: DzColors.card,
            borderRadius: BorderRadius.circular(16), border: Border.all(color: DzColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.toUpperCase(), style: const TextStyle(color: DzColors.mut, fontSize: 8.5,
              fontWeight: FontWeight.w700, letterSpacing: .6)),
          const SizedBox(height: 8),
          FittedBox(child: Text(v, style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w800))),
        ]),
      );

  Widget _bloc(String titre, Widget child) => Container(
        decoration: BoxDecoration(color: DzColors.card,
            borderRadius: BorderRadius.circular(16), border: Border.all(color: DzColors.line)),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _ligne(String l, String v, {Color couleur = DzColors.txt}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(l, style: const TextStyle(color: DzColors.mut, fontSize: 12.5))),
          Text(v, style: TextStyle(color: couleur, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      );
}
