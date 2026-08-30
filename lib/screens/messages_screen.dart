import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/download.dart';
import '../services/upload.dart';
import '../theme.dart';
import '../widgets/avatar_user.dart';

class MessagesScreen extends StatefulWidget {
  final VoidCallback? onLu;
  const MessagesScreen({super.key, this.onLu});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Map>? _contacts;
  String? _error;
  Map? _actif;
  List<Map>? _fil;
  final _texte = TextEditingController();
  final _scroll = ScrollController();
  final _version = ValueNotifier<int>(0);
  Timer? _timer;
  bool _envoi = false;
  (Uint8List, String, String)? _piece;

  void _maj(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _version.value++;
  }

  @override
  void initState() {
    super.initState();
    _loadContacts();

    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadContacts(silencieux: true);
      if (_actif != null) _loadFil(silencieux: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _texte.dispose();
    _scroll.dispose();
    _version.dispose();
    super.dispose();
  }

  Future<void> _loadContacts({bool silencieux = false}) async {
    try {
      final d = (await Api.get('/messages/contacts') as List).cast<Map>();
      if (mounted) setState(() { _contacts = d; _error = null; });
    } on ApiException catch (e) {
      if (mounted && !silencieux) setState(() => _error = e.message);
    }
  }

  Future<void> _loadFil({bool silencieux = false}) async {
    final c = _actif;
    if (c == null) return;
    try {
      final d = (await Api.get('/messages/avec/${c['id']}') as List).cast<Map>();
      if (!mounted || _actif?['id'] != c['id']) return;
      final grandit = d.length != (_fil?.length ?? -1);
      _maj(() => _fil = d);
      if (grandit) _versLeBas();
      widget.onLu?.call();
    } on ApiException catch (e) {
      if (mounted && !silencieux) _snack(e.message);
    }
  }

  void _versLeBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _ouvrir(Map c) async {
    setState(() { _actif = c; _fil = null; });
    await _loadFil();
    _loadContacts(silencieux: true);

    if (mounted && MediaQuery.of(context).size.width < 950) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => _pageFilMobile()));
      if (mounted) setState(() => _actif = null);
      _loadContacts(silencieux: true);
    }
  }

  Future<void> _joindre() async {
    try {
      final f = await pickFichier();
      if (f == null || !mounted) return;
      var bytes = f.$1;
      var mime = f.$2;
      if (mime.startsWith('image/')) {
        final c = await compresserImage(bytes, mime, maxCote: 1600);
        bytes = Uint8List.fromList(c.$1);
        mime = c.$2;
      }
      if (mime != 'application/pdf' && !mime.startsWith('image/')) {
        _snack('Photos et PDF uniquement.');
        return;
      }
      if (bytes.length > 7 * 1024 * 1024) {
        _snack('Fichier trop lourd (7 Mo max).');
        return;
      }
      _maj(() => _piece = (bytes, mime, f.$3));
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _envoyer() async {
    final t = _texte.text.trim();
    final p = _piece;
    if ((t.isEmpty && p == null) || _envoi || _actif == null) return;
    _maj(() => _envoi = true);
    try {
      final m = await Api.post('/messages/avec/${_actif!['id']}', {
        'texte': t,
        if (p != null) 'piece': base64Encode(p.$1),
        if (p != null) 'piece_mime': p.$2,
        if (p != null) 'piece_nom': p.$3,
      }) as Map;
      _texte.clear();
      _maj(() {
        _piece = null;
        (_fil ??= []).add(m);
      });
      _versLeBas();
      _loadContacts(silencieux: true);
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      _maj(() => _envoi = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _heure(dynamic d) {
    final t = DateTime.tryParse('$d')?.toLocal();
    if (t == null) return '';
    final now = DateTime.now();
    final memeJour = t.year == now.year && t.month == now.month && t.day == now.day;
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return memeJour ? hm : '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 950;
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: DzColors.mut)));
    }
    if (_contacts == null) {
      return const Center(child: CircularProgressIndicator(color: DzColors.lime));
    }
    if (!wide) return _listeContacts();
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 310, child: _listeContacts()),
      Container(width: 1, color: DzColors.line),
      Expanded(child: _actif == null ? _vide() : _fildiscussion()),
    ]);
  }

  Widget _vide() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.chat_bubble_outline, color: DzColors.mut2, size: 40),
          SizedBox(height: 10),
          Text('Choisis une conversation à gauche.',
              style: TextStyle(color: DzColors.mut, fontSize: 13)),
        ]),
      );

  Widget _listeContacts() {
    final cs = _contacts!;
    return RefreshIndicator(
      color: DzColors.lime,
      onRefresh: _loadContacts,
      child: cs.isEmpty
          ? ListView(padding: const EdgeInsets.all(24), children: const [
              SizedBox(height: 60),
              Center(child: Text('Personne à contacter pour le moment.\n'
                  'Les comptes admins et voyageurs apparaîtront ici.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DzColors.mut, height: 1.6))),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: cs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final c = cs[i];
                final nonLus = (num.tryParse('${c['non_lus']}') ?? 0).toInt();
                final sel = _actif?['id'] == c['id'];
                return Material(
                  color: sel ? DzColors.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _ouvrir(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(children: [
                        AvatarUser(userId: c['id'] as int?, nom: '${c['nom']}', taille: 38),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('${c['nom']}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13.5,
                                      fontWeight: nonLus > 0 ? FontWeight.w800 : FontWeight.w600))),
                              Text(_heure(c['dernier_date']),
                                  style: const TextStyle(color: DzColors.mut2, fontSize: 10)),
                            ]),
                            const SizedBox(height: 2),
                            Row(children: [
                              Expanded(
                                child: Text(
                                  c['dernier_texte'] == null
                                      ? (c['role'] == 'voyageur' ? 'Voyageur' : 'Admin')
                                      : '${c['dernier_recu'] == true ? '' : 'Toi : '}'
                                        '${'${c['dernier_texte']}'.isEmpty ? '📎 Pièce jointe' : c['dernier_texte']}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: nonLus > 0 ? DzColors.txt : DzColors.mut,
                                      fontSize: 11.5,
                                      fontWeight: nonLus > 0 ? FontWeight.w600 : FontWeight.w400),
                                ),
                              ),
                              if (nonLus > 0)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: DzColors.lime,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text('$nonLus',
                                      style: const TextStyle(color: DzColors.inkOnLime,
                                          fontSize: 10, fontWeight: FontWeight.w800)),
                                ),
                            ]),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _pageFilMobile() => Scaffold(
        backgroundColor: DzColors.bg,
        appBar: AppBar(
          backgroundColor: DzColors.bg,
          title: Text('${_actif?['nom'] ?? ''}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        body: AnimatedBuilder(
          animation: _version,
          builder: (_, __) => _actif == null
              ? const SizedBox.shrink()
              : _fildiscussion(),
        ),
      );

  Widget _fildiscussion() {
    final c = _actif!;
    final wide = MediaQuery.of(context).size.width >= 950;
    return Column(children: [
      if (wide)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            AvatarUser(userId: c['id'] as int?, nom: '${c['nom']}', taille: 32),
            const SizedBox(width: 10),
            Text('${c['nom']}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: DzColors.card2,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(c['role'] == 'voyageur' ? 'Voyageur' : 'Admin',
                  style: const TextStyle(color: DzColors.txt2, fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      if (wide) Container(height: 1, color: DzColors.line),
      Expanded(
        child: _fil == null
            ? const Center(child: CircularProgressIndicator(color: DzColors.lime))
            : _fil!.isEmpty
                ? const Center(child: Text('Écris le premier message.',
                    style: TextStyle(color: DzColors.mut, fontSize: 12.5)))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    itemCount: _fil!.length,
                    itemBuilder: (_, i) => _bulle(_fil![i]),
                  ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_piece != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                      color: DzColors.card2, borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_piece!.$2 == 'application/pdf'
                            ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                        size: 15, color: DzColors.lime),
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(_piece!.$3,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5)),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _maj(() => _piece = null),
                      child: const Icon(Icons.close_rounded,
                          size: 15, color: DzColors.mut),
                    ),
                  ]),
                ),
              ]),
            ),
          Row(children: [
            IconButton(
              tooltip: 'Photo ou PDF',
              onPressed: _envoi ? null : _joindre,
              icon: const Icon(Icons.attach_file_rounded,
                  size: 20, color: DzColors.mut),
            ),
            Expanded(
              child: TextField(textCapitalization: TextCapitalization.sentences,
                controller: _texte,
                minLines: 1, maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _envoyer(),
                decoration: const InputDecoration(hintText: 'Écris un message…'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 44, height: 44,
              child: FilledButton(
                onPressed: _envoi ? null : _envoyer,
                style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero, shape: const CircleBorder()),
                child: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }

  Widget _bulle(Map m) {
    final deMoi = m['de_moi'] == true;
    return Align(
      alignment: deMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: deMoi ? DzColors.lime : DzColors.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(deMoi ? 16 : 5),
            bottomRight: Radius.circular(deMoi ? 5 : 16),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          if ('${m['piece_mime'] ?? ''}'.startsWith('image/'))
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _PieceImage(messageId: m['id'] as int),
              ),
            ),
          if ('${m['piece_mime'] ?? ''}' == 'application/pdf')
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 2),
              child: InkWell(
                onTap: () => _telechargerPiece(m),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: deMoi ? DzColors.limeDim : DzColors.card2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.picture_as_pdf_outlined, size: 17,
                        color: deMoi ? DzColors.inkOnLime : DzColors.lime),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text('${m['piece_nom'] ?? 'document.pdf'}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: deMoi ? DzColors.inkOnLime : DzColors.txt,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.download_rounded, size: 15,
                        color: deMoi
                            ? DzColors.inkOnLime.withValues(alpha: .7) : DzColors.mut),
                  ]),
                ),
              ),
            ),
          if ('${m['texte'] ?? ''}'.isNotEmpty)
            Text('${m['texte']}',
                style: TextStyle(
                    color: deMoi ? DzColors.inkOnLime : DzColors.txt,
                    fontSize: 13, height: 1.35)),
          const SizedBox(height: 2),
          Text(_heure(m['date']),
              style: TextStyle(
                  color: deMoi ? DzColors.inkOnLime.withValues(alpha: .55) : DzColors.mut2,
                  fontSize: 9.5)),
        ]),
      ),
    );
  }

  Future<void> _telechargerPiece(Map m) async {
    try {
      final bytes = await Api.getBytes('/messages/piece/${m['id']}');
      await saveFile('${m['piece_nom'] ?? 'document.pdf'}', bytes);
    } catch (e) {
      _snack('$e');
    }
  }
}

class _PieceImage extends StatefulWidget {
  final int messageId;
  const _PieceImage({required this.messageId});

  static final _cache = <int, Uint8List>{};

  @override
  State<_PieceImage> createState() => _PieceImageState();
}

class _PieceImageState extends State<_PieceImage> {
  bool _erreur = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    if (_PieceImage._cache.containsKey(widget.messageId)) return;
    try {
      final b = await Api.getBytes('/messages/piece/${widget.messageId}');
      _PieceImage._cache[widget.messageId] = Uint8List.fromList(b);
    } catch (_) {
      _erreur = true;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _PieceImage._cache[widget.messageId];
    if (bytes != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 300),
        child: Image.memory(bytes, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 200, height: 120,
      alignment: Alignment.center,
      color: DzColors.card2,
      child: _erreur
          ? const Icon(Icons.broken_image_outlined, color: DzColors.mut, size: 22)
          : const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: DzColors.lime)),
    );
  }
}
