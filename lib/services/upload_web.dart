import 'dart:async';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// Ouvre le sélecteur de fichier et retourne (octets, type MIME, nom du fichier).
/// Retourne null si l'utilisateur annule (dans ce cas le Future peut ne jamais
/// se terminer sur certains navigateurs — l'appelant ne doit pas bloquer dessus).
Future<(Uint8List, String, String)?> pickImage() async {
  final input = html.FileUploadInputElement()..accept = 'image/*';
  input.click();
  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return null;
  final f = files.first;
  final reader = html.FileReader();
  reader.readAsArrayBuffer(f);
  await reader.onLoad.first;
  final res = reader.result;
  final bytes = res is Uint8List
      ? res
      : res is ByteBuffer
          ? Uint8List.view(res)
          : Uint8List.fromList((res as List).cast<int>());
  return (bytes, f.type.isNotEmpty ? f.type : 'image/jpeg', f.name);
}
