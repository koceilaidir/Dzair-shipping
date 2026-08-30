import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import 'voyageur_mission_screen.dart';

class VoyageurMissionsScreen extends StatefulWidget {
  const VoyageurMissionsScreen({super.key});

  @override
  State<VoyageurMissionsScreen> createState() => _VoyageurMissionsScreenState();
}

class _VoyageurMissionsScreenState extends State<VoyageurMissionsScreen> {
  List? _missions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/missions') as List;
      if (mounted) setState(() { _missions = d; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();
  String _f(num n) => n.round().toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  String _dateFr(dynamic d) {
    final s = '$d';
    return s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}' : '—';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)));
    }
    if (_missions == null) {
      return const Center(child: CircularProgressIndicator(color: DzColors.lime));
    }
    final ms = _missions!.cast<Map>();
    return RefreshIndicator(
      color: DzColors.lime,
      onRefresh: _load,
      child: ms.isEmpty
          ? ListView(padding: const EdgeInsets.all(24), children: const [
              SizedBox(height: 80),
              Center(child: Text('Pas encore de mission —\nl’admin t’assignera bientôt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DzColors.mut, height: 1.6))),
            ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              children: [
                const Text('Mes missions',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                Text('${ms.where((m) => m['statut'] != 'cloturee').length} en cours · '
                    '${ms.where((m) => m['statut'] == 'cloturee').length} terminée(s)',
                    style: const TextStyle(color: DzColors.mut, fontSize: 12)),
                const SizedBox(height: 14),
                for (final m in ms) _tuile(m),
              ],
            ),
    );
  }

  Widget _tuile(Map m) {
    final cloturee = '${m['statut']}' == 'cloturee';
    final gain = _n(m['commission']) + _n(m['primes']);
    final (lab, c) = cloturee
        ? ('Terminée', DzColors.mut)
        : _n(m['kg_total']) == 0
            ? ('Préparation', DzColors.amber)
            : ('En cours', DzColors.amber);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: DzColors.card, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => VoyageurMissionScreen(id: m['id'] as int)))
            .then((_) => _load()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Container(
              width: 34, height: 34, alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: DzColors.card2, shape: BoxShape.circle),
              child: Icon(cloturee ? Icons.check_rounded : Icons.flight_takeoff_outlined,
                  size: 16, color: cloturee ? DzColors.mut : DzColors.lime),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m['code']}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text(
                    cloturee
                        ? 'clôturée le ${_dateFr(m['cloture_date'])} · '
                          '${_n(m['kg_total']).toStringAsFixed(1)} kg · ton gain : ${_f(gain)} DA'
                        : '${'${m['vol'] ?? ''}'.isNotEmpty ? '${m['vol']} · ' : ''}'
                          '${_dateFr(m['depart'])}'
                          '${'${m['heure_depart'] ?? ''}'.isNotEmpty ? ' ${m['heure_depart']}' : ''}'
                          ' → ${_dateFr(m['retour'])} · '
                          '${_n(m['kg_total']).toStringAsFixed(1)} kg en valise',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: DzColors.mut, fontSize: 11)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: DzColors.card2, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(lab, style: TextStyle(color: c, fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: DzColors.mut, size: 18),
          ]),
        ),
      ),
    );
  }
}
