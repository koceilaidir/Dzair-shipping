import 'dart:html' as html;

void sauverSession(String token, String role, String nom) {
  html.window.localStorage['dz_token'] = token;
  html.window.localStorage['dz_role'] = role;
  html.window.localStorage['dz_nom'] = nom;
}

(String, String, String)? lireSession() {
  final t = html.window.localStorage['dz_token'];
  if (t == null || t.isEmpty) return null;
  return (t, html.window.localStorage['dz_role'] ?? '',
      html.window.localStorage['dz_nom'] ?? '');
}

void effacerSession() {
  html.window.localStorage.remove('dz_token');
  html.window.localStorage.remove('dz_role');
  html.window.localStorage.remove('dz_nom');
}
