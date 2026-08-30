import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/upload.dart';
import '../theme.dart';
import '../screens/login_screen.dart';

Future<bool> montrerProfilDialog(BuildContext context) async {
  var change = false;
  await showDialog(
    context: context,
    builder: (_) => _ProfilDialog(onChange: () => change = true),
  );
  return change;
}

class _ProfilDialog extends StatefulWidget {
  final VoidCallback onChange;
  const _ProfilDialog({required this.onChange});

  @override
  State<_ProfilDialog> createState() => _ProfilDialogState();
}

class _ProfilDialogState extends State<_ProfilDialog> {
  Map? _moi;
  String? _error;
  final _nom = TextEditingController();
  final _email = TextEditingController();
  final _tel = TextEditingController();
  final _adresse = TextEditingController();
  final _wilaya = TextEditingController();
  final _mdp = TextEditingController();
  Uint8List? _photo;
  String? _photoMime;
  bool _photoChangee = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nom.dispose(); _email.dispose(); _tel.dispose(); _adresse.dispose();
    _wilaya.dispose(); _mdp.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await Api.get('/auth/moi') as Map;
      if (!mounted) return;
      setState(() {
        _moi = m;
        _nom.text = '${m['nom'] ?? ''}';
        _email.text = '${m['email'] ?? ''}';
        _tel.text = '${m['tel'] ?? ''}';
        _adresse.text = '${m['adresse'] ?? ''}';
        _wilaya.text = '${m['wilaya'] ?? ''}';
      });
      if (m['a_photo'] == true) {
        final b = await Api.getBytes('/auth/moi/photo');
        if (mounted) setState(() => _photo = Uint8List.fromList(b));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {}
  }

  Future<void> _choisirPhoto() async {
    final img = await pickImage();
    if (img == null || !mounted) return;
    final (bytes, mime) =
        await compresserImage(img.$1, img.$2, maxCote: 512, qualite: 0.85);
    if (!mounted) return;
    if (bytes.length > 3000000) {
      _snack('Photo trop lourde même compressée — choisis-en une autre.');
      return;
    }
    setState(() {
      _photo = Uint8List.fromList(bytes);
      _photoMime = mime;
      _photoChangee = true;
    });
  }

  Future<void> _enregistrer() async {
    if (_nom.text.trim().length < 2 || _saving) return;
    if (_mdp.text.isNotEmpty && _mdp.text.length < 8) {
      _snack('Le nouveau mot de passe doit faire 8 caractères minimum.');
      return;
    }
    setState(() => _saving = true);
    try {
      final estVoyageur = _moi?['est_voyageur'] == true;
      await Api.put('/auth/moi', {
        'nom': _nom.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        'tel': _tel.text.trim(),
        if (estVoyageur) 'adresse': _adresse.text.trim(),
        if (estVoyageur) 'wilaya': _wilaya.text.trim(),
        if (_mdp.text.isNotEmpty) 'password': _mdp.text,
      });
      if (_photoChangee && _photo != null) {
        await Api.post('/auth/moi/photo', {
          'data': base64Encode(_photo!),
          'mime': _photoMime ?? 'image/jpeg',
        });
      }
      Api.nom = _nom.text.trim();
      widget.onChange();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) { setState(() => _saving = false); _snack(e.message); }
    }
  }

  void _deconnecter() {
    Api.logout();
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DzColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_error!, style: const TextStyle(color: DzColors.mut)))
              : _moi == null
                  ? const SizedBox(height: 120,
                      child: Center(child: CircularProgressIndicator(color: DzColors.lime)))
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Mon compte',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 18),
                          Center(
                            child: GestureDetector(
                              onTap: _choisirPhoto,
                              child: Stack(clipBehavior: Clip.none, children: [
                                Container(
                                  width: 84, height: 84,
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: const BoxDecoration(
                                      color: DzColors.card2, shape: BoxShape.circle),
                                  child: _photo != null
                                      ? Image.memory(_photo!,
                                          width: 84, height: 84, fit: BoxFit.cover)
                                      : Text(
                                          _nom.text.isNotEmpty
                                              ? _nom.text[0].toUpperCase() : '?',
                                          style: const TextStyle(color: DzColors.lime,
                                              fontSize: 30, fontWeight: FontWeight.w800)),
                                ),
                                Positioned(
                                  right: -2, bottom: -2,
                                  child: Container(
                                    width: 28, height: 28,
                                    alignment: Alignment.center,
                                    decoration: const BoxDecoration(
                                        color: DzColors.lime, shape: BoxShape.circle),
                                    child: const Icon(Icons.photo_camera_outlined,
                                        size: 15, color: DzColors.inkOnLime),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextField(textCapitalization: TextCapitalization.words, controller: _nom,
                              decoration: const InputDecoration(labelText: 'Nom complet')),
                          const SizedBox(height: 10),
                          TextField(controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                  labelText: 'Adresse email (connexion)')),
                          const SizedBox(height: 10),
                          TextField(controller: _tel,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(labelText: 'Téléphone')),
                          if (_moi!['est_voyageur'] == true) ...[
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(flex: 3, child: TextField(textCapitalization: TextCapitalization.sentences, controller: _adresse,
                                  decoration: const InputDecoration(labelText: 'Adresse'))),
                              const SizedBox(width: 10),
                              Expanded(flex: 2, child: TextField(textCapitalization: TextCapitalization.words, controller: _wilaya,
                                  decoration: const InputDecoration(labelText: 'Wilaya'))),
                            ]),
                          ],
                          const SizedBox(height: 16),
                          const Text('SÉCURITÉ',
                              style: TextStyle(color: DzColors.mut, fontSize: 11,
                                  fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _mdp,
                            obscureText: true,
                            decoration: const InputDecoration(
                                labelText: 'Nouveau mot de passe',
                                helperText: 'Laisse vide pour ne pas le changer · 8 caractères minimum',
                                helperStyle: TextStyle(color: DzColors.mut, fontSize: 10.5)),
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: _saving ? null : _enregistrer,
                            child: _saving
                                ? const SizedBox(height: 18, width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Enregistrer'),
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: _saving ? null : _deconnecter,
                            icon: const Icon(Icons.logout_rounded,
                                size: 16, color: DzColors.red),
                            label: const Text('Se déconnecter',
                                style: TextStyle(color: DzColors.red, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
