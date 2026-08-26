/// Enregistre un fichier côté client (téléchargement navigateur sur le web).
/// Sur mobile/desktop natif : à brancher plus tard (path_provider + open_file).
export 'download_stub.dart' if (dart.library.html) 'download_web.dart';
