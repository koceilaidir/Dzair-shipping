import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';

/// Activité — journal de tout ce qui se fait (qui, quoi, quand).
class ActiviteScreen extends StatefulWidget {
  const ActiviteScreen({super.key});
  @override
  State<ActiviteScreen> createState() => _ActiviteScreenState();
}

class _ActiviteScreenState extends State<ActiviteScreen> {
  List<dynamic>? _list;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('/rapports/activite');
      if (mounted) setState(() => _list = d as List);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  (String, IconData, Color) _style(String action) => switch (action) {
        'create' => ('a créé', Icons.add_circle_outline, DzColors.lime),
        'update' => ('a modifié', Icons.edit_outlined, DzColors.txt),
        'cloture' => ('a clôturé', Icons.check_circle_outline, DzColors.lime),
        'delete' => ('a supprimé', Icons.delete_outline, DzColors.red),
        'demande_suppression' => ('demande à supprimer', Icons.report_outlined, DzColors.amber),
        _ => (action, Icons.circle_outlined, DzColors.mut),
      };

  String _entite(String e) => switch (e) {
        'mission' => 'une mission',
        'voyageur' => 'un voyageur',
        _ => e,
      };

  String _quand(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'à l’instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)));
    if (_list == null) return const Center(child: CircularProgressIndicator(color: DzColors.lime));

    return RefreshIndicator(
      color: DzColors.lime,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 32), children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Activité', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const Text('Tout ce qui se fait dans l’app — qui, quoi, quand.',
                style: TextStyle(color: DzColors.mut, fontSize: 12)),
            const SizedBox(height: 16),
            if (_list!.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 40),
                  child: Center(child: Text('Aucune activité pour l’instant.',
                      style: TextStyle(color: DzColors.mut)))),
            for (final a in _list!) _tile(a as Map),
          ]),
        ),
      ]),
    );
  }

  Widget _tile(Map a) {
    final (verbe, icon, col) = _style('${a['action']}');
    final details = a['details'] is Map ? a['details'] as Map : {};
    final ref = details['code'] ?? details['nom'] ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: DzColors.card,
          borderRadius: BorderRadius.circular(14), border: Border.all(color: DzColors.line)),
      child: Row(children: [
        Container(width: 32, height: 32, alignment: Alignment.center,
            decoration: BoxDecoration(color: col.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: col, size: 17)),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '${a['auteur'] ?? 'Quelqu’un'} ',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              TextSpan(text: '$verbe ${_entite('${a['entite']}')}',
                  style: const TextStyle(fontSize: 12.5, color: DzColors.txt)),
              if ('$ref'.isNotEmpty)
                TextSpan(text: ' $ref',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DzColors.lime)),
            ])),
            Text(_quand('${a['created_at']}'),
                style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
          ]),
        ),
      ]),
    );
  }
}
