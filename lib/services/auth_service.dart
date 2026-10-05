import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  static const _keyUsers = 'auth_users';
  static const _keyCurrentUser = 'auth_current_user';

  String? _currentUserEmail;
  bool _isLoading = false;

  String? get currentUserEmail => _currentUserEmail;
  bool get isAuthenticated => _currentUserEmail != null;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserEmail = prefs.getString(_keyCurrentUser);
    notifyListeners();
  }

  Future<String?> register(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final normalizedEmail = email.trim().toLowerCase();

      // Проверяем, есть ли уже такой пользователь
      final users = await _loadUsers();
      if (users.containsKey(normalizedEmail)) {
        return 'Пользователь с таким email уже существует';
      }

      // Генерируем соль и хеш
      final salt = _generateSalt();
      final hash = _hashPassword(password, salt);

      // Сохраняем
      users[normalizedEmail] = {
        'salt': salt,
        'hash': hash,
        'createdAt': DateTime.now().toIso8601String(),
      };
      await _saveUsers(users);

      // Автоматически логиним
      await _setCurrentUser(normalizedEmail);

      return null; // успех
    } catch (e) {
      return 'Ошибка регистрации: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final normalizedEmail = email.trim().toLowerCase();
      final users = await _loadUsers();

      if (!users.containsKey(normalizedEmail)) {
        return 'Пользователь не найден';
      }

      final user = users[normalizedEmail]!;
      final salt = user['salt'] as String;
      final storedHash = user['hash'] as String;

      final inputHash = _hashPassword(password, salt);

      if (inputHash != storedHash) {
        return 'Неверный пароль';
      }

      await _setCurrentUser(normalizedEmail);
      return null; // успех
    } catch (e) {
      return 'Ошибка входа: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _currentUserEmail = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentUser);
    notifyListeners();
  }

  // ============ ВНУТРЕННИЕ МЕТОДЫ ============

  Future<Map<String, Map<String, dynamic>>> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyUsers);
    if (json == null) return {};

    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return decoded.map((key, value) =>
        MapEntry(key, Map<String, dynamic>.from(value as Map)));
  }

  Future<void> _saveUsers(Map<String, Map<String, dynamic>> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsers, jsonEncode(users));
  }

  Future<void> _setCurrentUser(String email) async {
    _currentUserEmail = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrentUser, email);
    notifyListeners();
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}