import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/date_field.dart';
import 'chambre_detail_screen.dart';

class ChambresScreen extends StatefulWidget {
  const ChambresScreen({super.key});
  @override
  State<ChambresScreen> createState() => _ChambresScreenState();
}

class _ChambresScreenState extends State<ChambresScreen> {
  List<dynamic>? _list;
  String? _error;
  String _filtre = '';
  int? _selectedId;

  void _open(int id) {
    if (MediaQuery.of(context).size.width >= 950) {
      setState(() => _selectedId = id);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChambreDetailScreen(id: id)))
          .then((_) => _load());
    }
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('/inventaire/chambres');
      if (mounted) setState(() { _list = d as List; _error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _f(num n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  @override
  Widget build(BuildContext context) {
    if (_selectedId != null && MediaQuery.of(context).size.width >= 950) {
      return ChambreDetailScreen(
        id: _selectedId!, embedded: true,
        onBack: () { setState(() => _selectedId = null); _load(); },
      );
    }
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)));
    if (_list == null) return const Center(child: CircularProgressIndicator(color: DzColors.lime));
    final f = _filtre.trim().toLowerCase();
    final visibles = _list!.where((c) {
      if (f.isEmpty) return true;
      final m = c as Map;
      return '${m['nom']} ${m['depot_wilaya'] ?? ''} ${m['depot_adresse'] ?? ''}'.toLowerCase().contains(f);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showChambreForm(context, onDone: _load),
        backgroundColor: DzColors.lime, foregroundColor: DzColors.inkOnLime,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Chambre', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: DzColors.lime, onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
          Row(children: [
            Expanded(child: TextField(
              onChanged: (v) => setState(() => _filtre = v),
              decoration: const InputDecoration(
                  isDense: true, prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Rechercher une chambre, une wilaya…'),
            )),
            const SizedBox(width: 10),
            Text('${_list!.length} chambre(s)', style: const TextStyle(color: DzColors.mut, fontSize: 12)),
          ]),
          const SizedBox(height: 12),
          if (visibles.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 60),
                child: Center(child: Text('Aucune chambre.\nCrée la première avec le bouton +, '
                    'ou directement depuis un bon dans l’Inventaire.',
                    textAlign: TextAlign.center, style: TextStyle(color: DzColors.mut, height: 1.6)))),
          for (final c in visibles) _tile(c as Map),
        ]),
      ),
    );
  }

  Widget _tile(Map c) {
    final contacts = (c['contacts'] as List?) ?? [];
    final nb = num.tryParse('${c['nb_bons'] ?? 0}') ?? 0;
    return Card(
      child: ListTile(
        onTap: () => _open(c['id'] as int),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: DzColors.lime.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.storefront_outlined, color: DzColors.lime, size: 19),
        ),
        title: Text('${c['nom']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c['ville'] ?? 'Canton'} → dépôt ${c['depot_wilaya'] ?? '—'}'
              '${(c['depot_adresse'] ?? '').toString().isNotEmpty ? ' · ${c['depot_adresse']}' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: DzColors.mut, fontSize: 11.5)),
          if (contacts.isNotEmpty)
            Text(contacts.map((k) => '${k['nom']}${(k['tel'] ?? '').toString().isNotEmpty ? ' ${k['tel']}' : ''}'
                    ' (${'${k['role']}'.toLowerCase() == 'chine' ? 'Chine' : 'Algérie'})').join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: DzColors.mut, fontSize: 11)),
        ]),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${_f(nb)} bon${nb > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (c['dernier_bon'] != null)
                Text('dernier ${dateFr(c['dernier_bon'])}',
                    style: const TextStyle(color: DzColors.mut, fontSize: 10)),
            ]),
      ),
    );
  }

}

Future<Map?> showChambreForm(BuildContext context, {Map? chambre, VoidCallback? onDone,
    String? nomInitial}) async {
  final nom = TextEditingController(text: chambre?['nom'] ?? nomInitial ?? '');
  final ville = TextEditingController(text: chambre?['ville'] ?? 'Canton');
  final wilaya = TextEditingController(text: chambre?['depot_wilaya'] ?? '');
  final adresse = TextEditingController(text: chambre?['depot_adresse'] ?? '');
  final note = TextEditingController(text: chambre?['note'] ?? '');

  final contacts = <(TextEditingController, TextEditingController, TextEditingController)>[
    for (final k in (chambre?['contacts'] as List? ?? []))
      (TextEditingController(text: '${k['nom']}'), TextEditingController(text: '${k['tel'] ?? ''}'),
       TextEditingController(text: '${k['role']}'.toLowerCase() == 'chine' ? 'chine' : 'algerie')),
  ];
  if (contacts.isEmpty) {
    contacts.add((TextEditingController(), TextEditingController(), TextEditingController(text: 'chine')));
  }
  bool saving = false;
  Map? resultat;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      Future<void> save() async {
        if (nom.text.trim().isEmpty || saving) return;
        setSt(() => saving = true);
        final body = {
          'nom': nom.text.trim(), 'ville': ville.text.trim(),
          'depot_wilaya': wilaya.text.trim(), 'depot_adresse': adresse.text.trim(),
          'note': note.text.trim(),
          'contacts': [
            for (final k in contacts)
              if (k.$1.text.trim().isNotEmpty)
                {'nom': k.$1.text.trim(), 'tel': k.$2.text.trim(), 'role': k.$3.text.trim()},
          ],
        };
        try {
          resultat = (chambre == null
              ? await Api.post('/inventaire/chambres', body)
              : await Api.put('/inventaire/chambres/${chambre['id']}', body)) as Map;
          if (ctx.mounted) Navigator.pop(ctx);
          onDone?.call();
        } on ApiException catch (e) {
          setSt(() => saving = false);
          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
      return Dialog(
        backgroundColor: DzColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: SingleChildScrollView(child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
              children: [
                Text(chambre == null ? 'Nouvelle chambre' : 'Modifier ${chambre['nom']}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(flex: 3, child: TextField(textCapitalization: TextCapitalization.words, controller: nom,
                      decoration: const InputDecoration(labelText: 'Nom / n° de la chambre'))),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: TextField(textCapitalization: TextCapitalization.words, controller: ville,
                      decoration: const InputDecoration(labelText: 'Ville'))),
                ]),
                const SizedBox(height: 18),
                const Text('DÉPÔT EN ALGÉRIE', style: TextStyle(color: DzColors.mut, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(flex: 2, child: TextField(textCapitalization: TextCapitalization.words, controller: wilaya,
                      decoration: const InputDecoration(labelText: 'Wilaya'))),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: TextField(textCapitalization: TextCapitalization.sentences, controller: adresse,
                      decoration: const InputDecoration(labelText: 'Adresse du dépôt'))),
                ]),
                const SizedBox(height: 18),
                Row(children: [
                  const Expanded(child: Text('CONTACTS (CHINE / ALGÉRIE)', style: TextStyle(color: DzColors.mut,
                      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2))),
                  TextButton.icon(
                    onPressed: () => setSt(() => contacts.add(
                        (TextEditingController(), TextEditingController(), TextEditingController(text: 'algerie')))),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Ajouter', style: TextStyle(fontSize: 12)),
                  ),
                ]),
                for (var i = 0; i < contacts.length; i++) ...[
                  Row(children: [
                    Expanded(flex: 3, child: TextField(textCapitalization: TextCapitalization.words, controller: contacts[i].$1,
                        decoration: const InputDecoration(labelText: 'Nom', isDense: true))),
                    const SizedBox(width: 8),
                    Expanded(flex: 3, child: TextField(controller: contacts[i].$2,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Téléphone', isDense: true))),
                    const SizedBox(width: 8),

                    SegmentedButton<String>(
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.selected) ? DzColors.lime : DzColors.card2),
                        foregroundColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.selected) ? DzColors.inkOnLime : DzColors.mut),
                        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'chine', label: Text('Chine')),
                        ButtonSegment(value: 'algerie', label: Text('Algérie')),
                      ],
                      selected: {contacts[i].$3.text.isEmpty ? 'algerie' : contacts[i].$3.text},
                      onSelectionChanged: (s) => setSt(() => contacts[i].$3.text = s.first),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                      onPressed: contacts.length == 1 ? null : () => setSt(() => contacts.removeAt(i)),
                      icon: const Icon(Icons.close, size: 15, color: DzColors.red),
                    ),
                  ]),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                TextField(textCapitalization: TextCapitalization.sentences, controller: note, maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Note (horaires, spécialité, remarques…)')),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(chambre == null ? 'Créer la chambre' : 'Enregistrer'),
                ),
                if (chambre != null) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        await Api.delete('/inventaire/chambres/${chambre['id']}');
                        if (ctx.mounted) Navigator.pop(ctx);
                        onDone?.call();
                      } on ApiException catch (e) {
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    },
                    icon: const Icon(Icons.delete_outline, color: DzColors.red, size: 16),
                    label: const Text('Supprimer', style: TextStyle(color: DzColors.red, fontSize: 12.5)),
                  ),
                ],
              ]),
            )),
        ),
      );
    }),
  );
  return resultat;
}
