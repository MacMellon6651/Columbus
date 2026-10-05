import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum WeatherLayer {
  precipitation('precipitation_new', 'Осадки'),
  temperature('temp_new', 'Температура'),
  clouds('clouds_new', 'Облачность'),
  wind('wind_new', 'Ветер');

  final String code;
  final String label;

  const WeatherLayer(this.code, this.label);
}

class WeatherService {
  // API КЛЮЧ
  static const String _apiKey = '2026257ee329105eeda63c36bfb2b1bd';

  static const String _cacheKeyPrefix = 'weather_cache_';
  static const Duration _cacheTtl = Duration(minutes: 30);

  bool get hasApiKey => _apiKey != 'ТВОЙ_API_КЛЮЧ_ЗДЕСЬ' && _apiKey.isNotEmpty;

  /// Формирует URL для погодного тайла.
  String getTileUrl(WeatherLayer layer) {
    return 'https://tile.openweathermap.org/map/${layer.code}/{z}/{x}/{y}.png?appid=$_apiKey';
  }

  /// Получает текущую погоду для координат (с кэшированием).
  Future<WeatherData?> getCurrentWeather({
    required double lat,
    required double lon,
  }) async {
    if (!hasApiKey) return null;

    final cacheKey = '$_cacheKeyPrefix${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';

    // 1. Пробуем прочитать из кэша
    final cached = await _readFromCache(cacheKey);
    if (cached != null) {
      print('=== ПОГОДА ИЗ КЭША: ${cached.temperature}°C');
      return cached;
    }

    // 2. Кэша нет или он устарел — запрашиваем новые данные
    print('=== ЗАПРОС ПОГОДЫ К API');
    final fresh = await _fetchFromApi(lat, lon);
    if (fresh != null) {
      await _saveToCache(cacheKey, fresh);
    }
    return fresh;
  }

  Future<WeatherData?> _readFromCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(key);
      if (json == null) return null;

      final data = WeatherData.fromJson(jsonDecode(json));
      if (data.isExpired) {
        print('=== КЭШ ПОГОДЫ УСТАРЕЛ');
        await prefs.remove(key);
        return null;
      }

      return data;
    } catch (e) {
      print('=== ОШИБКА ЧТЕНИЯ КЭША: $e');
      return null;
    }
  }

  Future<void> _saveToCache(String key, WeatherData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(data.toJson()));
      print('=== ПОГОДА СОХРАНЕНА В КЭШ: ${data.temperature}°C');
    } catch (e) {
      print('=== ОШИБКА СОХРАНЕНИЯ КЭША: $e');
    }
  }

  Future<WeatherData?> _fetchFromApi(double lat, double lon) async {
    final uri = Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather?'
      'lat=$lat&lon=$lon&appid=$_apiKey&units=metric&lang=ru',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        print('=== ОШИБКА API ПОГОДЫ: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      return WeatherData.fromApiResponse(data);
    } catch (e) {
      print('=== ОШИБКА ЗАПРОСА ПОГОДЫ: $e');
      return null;
    }
  }
}

class WeatherData {
  final double temperature;
  final String description;
  final String icon;
  final int humidity;
  final double windSpeed;
  final DateTime timestamp;

  WeatherData({
    required this.temperature,
    required this.description,
    required this.icon,
    required this.humidity,
    required this.windSpeed,
    required this.timestamp,
  });

  bool get isExpired {
    final now = DateTime.now();
    final age = now.difference(timestamp);
    return age.inMinutes > 30;
  }

  factory WeatherData.fromApiResponse(Map<String, dynamic> data) {
    final main = data['main'] as Map<String, dynamic>;
    final weather = (data['weather'] as List).first as Map<String, dynamic>;
    final wind = data['wind'] as Map<String, dynamic>?;

    return WeatherData(
      temperature: (main['temp'] as num).toDouble(),
      description: weather['description'] as String? ?? '',
      icon: weather['icon'] as String? ?? '01d',
      humidity: (main['humidity'] as num).toInt(),
      windSpeed: (wind?['speed'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.now(),
    );
  }

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temperature: (json['temperature'] as num).toDouble(),
      description: json['description'] as String,
      icon: json['icon'] as String,
      humidity: (json['humidity'] as num).toInt(),
      windSpeed: (json['windSpeed'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'description': description,
        'icon': icon,
        'humidity': humidity,
        'windSpeed': windSpeed,
        'timestamp': timestamp.toIso8601String(),
      };
}