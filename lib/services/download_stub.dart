Future<void> saveFile(String filename, List<int> bytes, {String mime = 'application/pdf'}) async {
  // Plateformes non web : à implémenter (V2 mobile).
  throw UnsupportedError('Téléchargement disponible sur la version web pour l’instant.');
}
