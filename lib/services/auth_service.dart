import 'package:flutter/material.dart';
import 'api_client.dart';

class AuthService extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  String? _currentUserEmail;
  bool _isLoading = false;

  String? get currentUserEmail => _currentUserEmail;
  bool get isAuthenticated => _currentUserEmail != null;
  bool get isLoading => _isLoading;

  ApiClient get api => _api;

  Future<void> load() async {
    await _api.loadToken();
    if (_api.isAuthenticated) {
      _currentUserEmail = 'user'; // заглушка, потом заменим на /api/auth/me
    }
    notifyListeners();
  }

  Future<String?> register(String email, String password) async {
    print('=== REGISTER API: $email');
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _api.post('/api/auth/register', {
        'email': email,
        'password': password,
      });

      print('=== REGISTER OK, TOKEN: ${response['access_token']?.substring(0, 20)}...');

      await _api.saveToken(response['access_token']);
      _currentUserEmail = email;
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

      print('=== LOGIN OK, TOKEN: ${response['access_token']?.substring(0, 20)}...');

      await _api.saveToken(response['access_token']);
      _currentUserEmail = email;
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

  Future<void> logout() async {
    await _api.clearToken();
    _currentUserEmail = null;
    notifyListeners();
  }
}