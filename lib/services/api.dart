import 'dart:convert';
import 'package:http/http.dart' as http;

/// Erreur lisible renvoyée à l'interface.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Client HTTP de l'API Dzair Shipping.
/// En dev : l'API tourne via `docker compose up -d` sur localhost:3000.
class Api {
  static const baseUrl = 'http://localhost:3000/api';

  static String? _token;
  static String? role; // 'admin' | 'voyageur' | 'client'
  static String? nom;
  static bool get connecte => _token != null;

  static Future<void> login(String email, String password) async {
    final data = await _send('POST', '/auth/login',
        body: {'email': email, 'password': password}, auth: false);
    _token = data['token'] as String?;
    role = data['role'] as String?;
    nom = data['nom'] as String?;
    if (_token == null) throw ApiException('Réponse inattendue du serveur.');
  }

  static void logout() {
    _token = null;
    role = null;
    nom = null;
  }

  static Future<dynamic> get(String path) => _send('GET', path);
  static Future<dynamic> post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body: body);
  static Future<dynamic> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body: body);
  static Future<dynamic> delete(String path) => _send('DELETE', path);

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
