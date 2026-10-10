import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';


class ApiClient {
    static String get baseUrl {
    if (kIsWeb) {
      // Web (Chrome, Edge, Safari)
      return 'http://localhost:8000';
    }
    
    // Android
    if (Platform.isAndroid) {
      // Для эмулятора — 10.0.2.2
      // Для реального устройства — IP компа (например, 192.168.1.100)
      return 'http://10.0.2.2:8000';
    }
    
    // iOS / macOS / Linux / Windows
    return 'http://localhost:8000';
  }

  static const String _tokenKey = 'auth_token';

  String? _token;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  bool get isAuthenticated => _token != null;

  Map<String, String> get _jsonHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Map<String, String> get _formHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  /// POST с JSON-телом (для регистрации, мест, отзывов)
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );

    if (response.statusCode >= 400) {
      final error = jsonDecode(response.body);
      throw ApiException(
        response.statusCode,
        error['detail'] ?? 'Ошибка сервера',
      );
    }

    return jsonDecode(response.body);
  }

  /// POST с form-data (для логина через OAuth2PasswordRequestForm)
  Future<Map<String, dynamic>> postForm(
    String path,
    Map<String, String> body,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _formHeaders,
      body: body,
    );

    if (response.statusCode >= 400) {
      final error = jsonDecode(response.body);
      throw ApiException(
        response.statusCode,
        error['detail'] ?? 'Ошибка сервера',
      );
    }

    return jsonDecode(response.body);
  }

  /// GET-запрос
  Future<dynamic> get(String path) async {
    final response = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: _jsonHeaders,
    );

    if (response.statusCode >= 400) {
      final error = jsonDecode(response.body);
      throw ApiException(
        response.statusCode,
        error['detail'] ?? 'Ошибка сервера',
      );
    }

    return jsonDecode(response.body);
  }

    Future<String> uploadImage(
    String path,
    List<int> bytes,
    String filename,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/uploads'),
    );

    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }

    final mimeType = lookupMimeType(filename) ?? 'image/jpeg';
    final parts = mimeType.split('/');

    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: MediaType(parts[0], parts[1]),
    ));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, 'Ошибка загрузки фото');
    }

    final data = jsonDecode(response.body);
    return data['url'] as String;
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}