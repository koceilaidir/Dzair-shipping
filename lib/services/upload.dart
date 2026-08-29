/// Choisit une image côté client (sélecteur de fichier du navigateur sur le web).
/// Sur mobile/desktop natif : à brancher plus tard (image_picker).
export 'upload_stub.dart' if (dart.library.html) 'upload_web.dart';
