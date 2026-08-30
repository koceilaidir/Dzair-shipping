import 'dart:typed_data';

Future<(Uint8List, String, String)?> pickImage() async {
  throw UnsupportedError('Téléversement disponible sur la version web pour l’instant.');
}

Future<(Uint8List, String, String)?> pickFichier() async {
  throw UnsupportedError('Téléversement disponible sur la version web pour l’instant.');
}

Future<(Uint8List, String)> compresserImage(Uint8List bytes, String mime,
    {int maxCote = 1600, double qualite = 0.82}) async => (bytes, mime);
