import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';

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
        'valise_ajout' => ('a mis dans la valise de', Icons.luggage_outlined, DzColors.lime),
        'valise_retrait' => ('a retiré de la valise de', Icons.luggage_outlined, DzColors.amber),
        'tranche' => ('a déposé une tranche sur', Icons.payments_outlined, DzColors.txt),
        _ => (action, Icons.circle_outlined, DzColors.mut),
      };

  String _entite(String e) => switch (e) {
        'mission' => 'la mission',
        'voyageur' => 'le voyageur',
        'chambre' => 'la chambre',
        'bon' => 'un bon',
        _ => e,
      };

  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();

  String _detail(String action, String entite, Map d) {
    String s(dynamic v) => v == null ? '' : '$v';
    switch (action) {
      case 'valise_ajout':
        return '${s(d['produit'])}${d['quantite'] != null ? ' · ${_f(_n(d['quantite']))} pc' : ''}'
            '${d['kg'] != null ? ' · ${_n(d['kg']).toStringAsFixed(1)} kg' : ''}'
            '${d['chambre'] != null ? ' · de ${s(d['chambre'])}' : ''}'
            '${d['hors_inventaire'] == true ? ' · hors inventaire' : ''}';
      case 'valise_retrait':
        return '${s(d['produit'])} · ${_f(_n(d['quantite']))} pc remises en stock';
      case 'tranche':
        return '${d['motif'] == 'poche' ? 'argent de poche' : 'marchandise (carte BEA)'} · '
            '${_f(_n(d['montant']))} ${s(d['devise'])} × ${s(d['taux'])}'
            '${s(d['source']).isNotEmpty ? ' · ${s(d['source'])}' : ''}';
      case 'cloture':
        return 'attendu ${_f(_n(d['attendu']))} DA · commission ${_f(_n(d['commission']))} DA';
    }
    if (entite == 'bon') {
      if (action == 'create') {
        final prods = (d['produits'] as List?)?.join(', ') ?? '';
        return 'chambre ${s(d['chambre'])} · ${s(d['lignes'])} produit(s) · '
            '${_n(d['kg']).toStringAsFixed(1)} kg · ${_f(_n(d['da']))} DA'
            '${prods.isNotEmpty ? '\n$prods' : ''}';
      }
      return 'chambre ${s(d['chambre'])}';
    }
    if (entite == 'mission' && action == 'update') {
      if (d['valise'] != null) return 'valise ${s(d['valise'])}';
      if (d['check'] != null) return 'check ${s(d['check'])} mis à jour';
      final ch = (d['champs'] as List?)?.join(', ') ?? '';
      return ch.isNotEmpty ? 'champs : $ch' : '';
    }
    if (entite == 'mission' && action == 'create') return 'voyageur ${s(d['voyageur'])}';
    return '';
  }

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
    final action = '${a['action']}';
    final entite = '${a['entite']}';
    final (verbe, icon, col) = _style(action);
    final details = a['details'] is Map ? a['details'] as Map : <String, dynamic>{};

    var ref = '${details['code'] ?? details['nom'] ?? ''}';
    if (entite == 'mission' && details['voyageur'] != null && (action == 'valise_ajout' || action == 'valise_retrait')) {
      ref = '${details['voyageur']} ($ref)';
    }
    if (entite == 'bon' && details['chambre'] != null && ref.isEmpty) ref = '';
    final detail = _detail(action, entite, details);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: DzColors.card,
          borderRadius: BorderRadius.circular(14)),
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
              TextSpan(text: '$verbe ${_entite(entite)}',
                  style: const TextStyle(fontSize: 12.5, color: DzColors.txt)),
              if (ref.isNotEmpty)
                TextSpan(text: ' $ref',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DzColors.lime)),
            ])),
            if (detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(detail, style: const TextStyle(color: DzColors.mut, fontSize: 11.5, height: 1.35)),
              ),
            Text(_quand('${a['created_at']}'),
                style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
          ]),
        ),
      ]),
    );
  }
}
