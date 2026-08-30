import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_store.dart' as store;

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  static const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3000/api',
  );

  static String? _token;
  static String? role;
  static String? nom;
  static bool get connecte => _token != null;

  static Future<void> login(String email, String password,
      {bool souvenir = false}) async {
    final data = await _send('POST', '/auth/login',
        body: {'email': email, 'password': password, 'souvenir': souvenir},
        auth: false);
    _token = data['token'] as String?;
    role = data['role'] as String?;
    nom = data['nom'] as String?;
    if (_token == null) throw ApiException('Réponse inattendue du serveur.');
    if (souvenir) {
      store.sauverSession(_token!, role ?? '', nom ?? '');
    } else {
      store.effacerSession();
    }
  }

  static Future<bool> restaurerSession() async {
    final s = store.lireSession();
    if (s == null) return false;
    _token = s.$1;
    role = s.$2;
    nom = s.$3;
    try {
      final moi = await get('/auth/moi') as Map;
      role = '${moi['role'] ?? role}';
      nom = '${moi['nom'] ?? nom}';
      return true;
    } catch (_) {
      logout();
      return false;
    }
  }

  static void logout() {
    _token = null;
    role = null;
    nom = null;
    store.effacerSession();
  }

  static Future<dynamic> get(String path) => _send('GET', path);
  static Future<dynamic> post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body: body);
  static Future<dynamic> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body: body);
  static Future<dynamic> delete(String path) => _send('DELETE', path);

  static Future<List<int>> getBytes(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    http.Response r;
    try {
      r = await http.get(uri, headers: {if (_token != null) 'Authorization': 'Bearer $_token'});
    } catch (_) {
      throw ApiException('API injoignable — vérifie que « docker compose up -d » tourne.');
    }
    if (r.statusCode >= 400) throw ApiException('Erreur ${r.statusCode} au téléchargement.');
    return r.bodyBytes;
  }

  static Future<dynamic> _send(String method, String path,
      {Map<String, dynamic>? body, bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      if (auth && _token != null) 'Authorization': 'Bearer $_token',
    };

    http.Response r;
    try {
      switch (method) {
        case 'GET':
          r = await http.get(uri, headers: headers);
        case 'PUT':
          r = await http.put(uri, headers: headers, body: jsonEncode(body ?? {}));
        case 'DELETE':
          r = await http.delete(uri, headers: headers);
        default:
          r = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      }
    } catch (_) {
      throw ApiException('API injoignable — vérifie que « docker compose up -d » tourne.');
    }

    final dynamic data =
        r.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      final msg = (data is Map && data['error'] is String)
          ? data['error'] as String
          : 'Erreur ${r.statusCode}.';
      throw ApiException(msg);
    }
    return data;
  }
}
