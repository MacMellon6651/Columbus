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
      return 'http://localhost:8003';
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8003';
    }
    return 'http://localhost:8003';
  }

  static const String _tokenKey = 'auth_token';

  String? _token;
  String? get token => _token;

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

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.patch(
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

  Future<void> delete(String path) async {
    final response = await http.delete(
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
  }

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