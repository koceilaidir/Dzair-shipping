import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';

class AvatarUser extends StatefulWidget {
  final int? userId;
  final String nom;
  final double taille;
  const AvatarUser({super.key, required this.userId, required this.nom,
      this.taille = 38});

  static final _cache = <int, Uint8List?>{};
  static final _enCours = <int>{};

  @override
  State<AvatarUser> createState() => _AvatarUserState();
}

class _AvatarUserState extends State<AvatarUser> {
  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(AvatarUser old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _charger();
  }

  Future<void> _charger() async {
    final id = widget.userId;
    if (id == null || AvatarUser._cache.containsKey(id) ||
        AvatarUser._enCours.contains(id)) {
      return;
    }
    AvatarUser._enCours.add(id);
    try {
      final b = await Api.getBytes('/auth/photo/$id');
      AvatarUser._cache[id] = Uint8List.fromList(b);
    } catch (_) {
      AvatarUser._cache[id] = null;
    } finally {
      AvatarUser._enCours.remove(id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.userId == null ? null : AvatarUser._cache[widget.userId];
    return Container(
      width: widget.taille, height: widget.taille,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: DzColors.card2, shape: BoxShape.circle),
      child: photo != null
          ? Image.memory(photo,
              width: widget.taille, height: widget.taille, fit: BoxFit.cover)
          : Text(widget.nom.isNotEmpty ? widget.nom[0].toUpperCase() : '?',
              style: TextStyle(color: DzColors.lime,
                  fontSize: widget.taille * .34, fontWeight: FontWeight.w800)),
    );
  }
}
