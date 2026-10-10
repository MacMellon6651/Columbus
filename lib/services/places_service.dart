import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'api_client.dart';

class PlacesService {
  final ApiClient api;

  PlacesService(this.api);

  /// Находит существующее место по координатам или создаёт новое.
  /// Возвращает ID места в БД.
  Future<int> findOrCreatePlace({
    int? osmId,
    String? osmType,
    required String name,
    required double lat,
    required double lng,
    String? address,
    String? description,
    String? openingHours,
    String? phone,
    String? website,
    String? category,
  }) async {
    final data = await api.post('/api/places/find-or-create', {
      'osm_id': osmId,
      'osm_type': osmType,
      'name': name,
      'lat': lat,
      'lng': lng,
      'address': address,
      'description': description,
      'opening_hours': openingHours,
      'phone': phone,
      'website': website,
      'category': category,
    });

    return data['id'] as int;
  }

  Future<Map<String, dynamic>> getPlaceDetails(int placeId) async {
    final data = await api.get('/api/places/$placeId/details');
    return data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getAllPlaces() async {
    final data = await api.get('/api/places');
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Загружает картинку на сервер и возвращает URL.
  Future<String?> uploadImage(XFile image) async {
    try {
      final token = api.token;
      final uri = Uri.parse('${ApiClient.baseUrl}/api/uploads');

      final request = http.MultipartRequest('POST', uri);
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: image.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          image.path,
        ));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('=== ОШИБКА UPLOAD: $e');
      return null;
    }
  }

  /// Прикрепляет список URL-ов картинок к месту.
  Future<void> updatePlaceImages(int placeId, List<String> urls) async {
    await api.patch('/api/places/$placeId/images', {'photo_urls': urls});
  }
}