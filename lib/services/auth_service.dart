import 'package:flutter/material.dart';
import 'api_client.dart';
import 'package:jsonwebtoken_decode/jsonwebtoken_decode.dart';

class AuthService extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  String? _currentUserEmail;
  String? _currentUserRole;
  bool _isLoading = false;

  String? get currentUserEmail => _currentUserEmail;
  String? get currentUserRole => _currentUserRole;
  bool get isAuthenticated => _currentUserEmail != null;
  bool get isLoading => _isLoading;
  bool get isModerator =>
      _currentUserRole == 'moderator' || _currentUserRole == 'admin';

  ApiClient get api => _api;

  /// Декодирует JWT-токен и достаёт роль
  String? _extractRoleFromToken(String token) {
    try {
      final jwt = JwtBuilder.fromToken(token);
      final payload = jwt.payload;
      return payload?.claim('role') as String?;
    } catch (e) {
      print('=== ОШИБКА ДЕКОДИРОВАНИЯ JWT: $e');
      return null;
    }
  }

  /// Декодирует JWT-токен и достаёт email
  String? _extractEmailFromToken(String token) {
    try {
      final jwt = JwtBuilder.fromToken(token);
      final payload = jwt.payload;
      return payload?.claim('sub') as String?;
    } catch (e) {
      print('=== ОШИБКА ДЕКОДИРОВАНИЯ JWT (email): $e');
      return null;
    }
  }

  /// Загрузка сохранённой сессии при старте приложения
  Future<void> load() async {
    await _api.loadToken();

    final token = _api.token;
    if (token != null && token.isNotEmpty) {
      _currentUserEmail = _extractEmailFromToken(token);
      _currentUserRole = _extractRoleFromToken(token);

      print('=== LOAD OK, EMAIL: $_currentUserEmail, ROLE: $_currentUserRole');
    }

    notifyListeners();
  }

  /// Регистрация
  Future<String?> register(String email, String password) async {
    print('=== REGISTER API: $email');
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _api.post('/api/auth/register', {
        'email': email,
        'password': password,
      });

      final token = response['access_token'] as String;

      print('=== REGISTER OK, TOKEN: ${token.substring(0, 20)}...');

      await _api.saveToken(token);

      // Декодируем токен
      _currentUserEmail = _extractEmailFromToken(token) ?? email;
      _currentUserRole = _extractRoleFromToken(token);

      print('=== REGISTER OK, ROLE: $_currentUserRole');

      return null;
    } on ApiException catch (e) {
      print('=== REGISTER API ERROR: ${e.message}');
      return e.message;
    } catch (e) {
      print('=== REGISTER NETWORK ERROR: $e');
      return 'Ошибка сети: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Логин
  Future<String?> login(String email, String password) async {
    print('=== LOGIN API: $email');
    _isLoading = true;
    notifyListeners();

    try {
      // FastAPI OAuth2PasswordRequestForm ждёт form-data:
      // username=<email>, password=<password>
      final response = await _api.postForm('/api/auth/login', {
        'username': email,
        'password': password,
      });

      final token = response['access_token'] as String;

      print('=== LOGIN OK, TOKEN: ${token.substring(0, 20)}...');

      await _api.saveToken(token);

      // Декодируем токен
      _currentUserEmail = _extractEmailFromToken(token) ?? email;
      _currentUserRole = _extractRoleFromToken(token);

      print('=== LOGIN OK, ROLE: $_currentUserRole');

      return null;
    } on ApiException catch (e) {
      print('=== LOGIN API ERROR: ${e.message}');
      return e.message;
    } catch (e) {
      print('=== LOGIN NETWORK ERROR: $e');
      return 'Ошибка сети: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Выход
  Future<void> logout() async {
    await _api.clearToken();
    _currentUserEmail = null;
    _currentUserRole = null;
    notifyListeners();
  }
}