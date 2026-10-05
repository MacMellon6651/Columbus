import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorite_place.dart';

class FavoritesService extends ChangeNotifier {
  static const _key = 'favorite_places';

  List<FavoritePlace> _favorites = [];

  List<FavoritePlace> get favorites => List.unmodifiable(_favorites);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];

    _favorites = raw
        .map((s) => FavoritePlace.fromJson(jsonDecode(s)))
        .toList();

    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _favorites
        .map((f) => jsonEncode(f.toJson()))
        .toList();
    await prefs.setStringList(_key, raw);
  }

  bool isFavorite(double lat, double lng) {
    return _favorites.any(
          (f) => (f.lat - lat).abs() < 0.0001 && (f.lng - lng).abs() < 0.0001,
    );
  }

  FavoritePlace? findByCoordinates(double lat, double lng) {
    for (final f in _favorites) {
      if ((f.lat - lat).abs() < 0.0001 && (f.lng - lng).abs() < 0.0001) {
        return f;
      }
    }
    return null;
  }

  Future<void> add({
    required String name,
    required String address,
    required double lat,
    required double lng,
  }) async {
    // Проверяем, нет ли уже такого
    if (isFavorite(lat, lng)) return;

    _favorites.add(FavoritePlace(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      address: address,
      lat: lat,
      lng: lng,
    ));

    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _favorites.removeWhere((f) => f.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> rename(String id, String newName) async {
    final index = _favorites.indexWhere((f) => f.id == id);
    if (index == -1) return;

    _favorites[index] = FavoritePlace(
      id: _favorites[index].id,
      name: newName,
      address: _favorites[index].address,
      lat: _favorites[index].lat,
      lng: _favorites[index].lng,
    );

    notifyListeners();
    await _save();
  }
}