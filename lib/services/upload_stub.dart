import 'dart:typed_data';

/// Plateformes non web : à implémenter (V2 mobile).
Future<(Uint8List, String, String)?> pickImage() async {
  throw UnsupportedError('Téléversement disponible sur la version web pour l’instant.');
}
