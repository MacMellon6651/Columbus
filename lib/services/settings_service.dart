import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const _keyTheme = 'theme_mode';
  static const _keyVoice = 'voice_enabled';
  static const _keyHistory = 'search_history';
  static const _keyWeatherEnabled = 'weather_enabled';
  static const _keyWeatherLayer = 'weather_layer';

  ThemeMode _themeMode = ThemeMode.light;
  bool _voiceEnabled = true;
  List<String> _searchHistory = [];
  bool _weatherEnabled = false;
  String _weatherLayer = 'precipitation_new';

  ThemeMode get themeMode => _themeMode;
  bool get voiceEnabled => _voiceEnabled;
  List<String> get searchHistory => List.unmodifiable(_searchHistory);
  bool get weatherEnabled => _weatherEnabled;
  String get weatherLayer => _weatherLayer;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeStr = prefs.getString(_keyTheme) ?? 'light';
    _themeMode = themeStr == 'dark' ? ThemeMode.dark : ThemeMode.light;

    _voiceEnabled = prefs.getBool(_keyVoice) ?? true;
    _searchHistory = prefs.getStringList(_keyHistory) ?? [];
    _weatherEnabled = prefs.getBool(_keyWeatherEnabled) ?? false;
    _weatherLayer = prefs.getString(_keyWeatherLayer) ?? 'precipitation_new';

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

  Future<void> setWeatherEnabled(bool value) async {
    _weatherEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWeatherEnabled, value);
  }

  Future<void> setWeatherLayer(String layerCode) async {
    _weatherLayer = layerCode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWeatherLayer, layerCode);
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