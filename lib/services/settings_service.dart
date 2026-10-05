import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const _keyTheme = 'theme_mode';
  static const _keyVoice = 'voice_enabled';
  static const _keyHistory = 'search_history';

  ThemeMode _themeMode = ThemeMode.light;
  bool _voiceEnabled = true;
  List<String> _searchHistory = [];

  ThemeMode get themeMode => _themeMode;
  bool get voiceEnabled => _voiceEnabled;
  List<String> get searchHistory => List.unmodifiable(_searchHistory);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeStr = prefs.getString(_keyTheme) ?? 'light';
    _themeMode = themeStr == 'dark' ? ThemeMode.dark : ThemeMode.light;

    _voiceEnabled = prefs.getBool(_keyVoice) ?? true;
    _searchHistory = prefs.getStringList(_keyHistory) ?? [];

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, mode == ThemeMode.dark ? 'dark' : 'light');
  }

  Future<void> setVoiceEnabled(bool value) async {
    _voiceEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVoice, value);
  }

  Future<void> addToHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return;

    _searchHistory.remove(trimmed);
    _searchHistory.insert(0, trimmed);
    if (_searchHistory.length > 10) {
      _searchHistory = _searchHistory.sublist(0, 10);
    }
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyHistory, _searchHistory);
  }

  Future<void> removeFromHistory(String query) async {
    _searchHistory.remove(query);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyHistory, _searchHistory);
  }

  Future<void> clearHistory() async {
    _searchHistory = [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }
}