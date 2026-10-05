import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/place.dart';

class GeocodingService {
  Future<List<Place>> search(String query, {LatLng? userLocation}) async {
    print('=== ПОИСК PHOTON: $query');

    final params = <String, String>{
      'q': query,
      'limit': '20', // берём с запасом, чтобы было что фильтровать
    };

    if (userLocation != null) {
      params['lat'] = userLocation.latitude.toString();
      params['lon'] = userLocation.longitude.toString();
    }

    final uri = Uri.https('photon.komoot.io', '/api', params);
    print('=== URI: $uri');

    try {
      final response = await http.get(uri, headers: {
        'User-Agent': 'CityTransportApp/1.0',
      });

      print('=== ОТВЕТ: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('=== ТЕЛО ОШИБКИ: ${response.body}');
        return [];
      }

      final data = jsonDecode(response.body);
      final features = data['features'] as List? ?? [];

      print('=== НАЙДЕНО (до фильтра): ${features.length}');

      // Парсим все результаты
      var places = features.map((feature) {
        final props = feature['properties'];
        final coords = feature['geometry']['coordinates'];

        final nameParts = [
          props['name'],
          props['street'],
          props['housenumber'],
          props['city'],
        ].where((p) => p != null && p.toString().isNotEmpty).join(', ');

        return Place(
          displayName: nameParts.isNotEmpty ? nameParts : 'Без названия',
          location: LatLng(
            coords[1] as double,
            coords[0] as double,
          ),
        );
      }).toList();

      // ========== ФИЛЬТР И СОРТИРОВКА ==========

      if (userLocation != null) {
        const distance = Distance();

        // 1. Вычисляем расстояние до каждого места
        final placesWithDistance = places.map((place) {
          final dist = distance.as(
            LengthUnit.Meter,
            userLocation,
            place.location,
          );
          return _PlaceWithDistance(place: place, distanceMeters: dist);
        }).toList();

        // 2. Фильтруем — убираем слишком далёкие (например, > 100 км)
        const maxDistanceMeters = 100000.0; // 100 км
        final filtered = placesWithDistance
            .where((p) => p.distanceMeters <= maxDistanceMeters)
            .toList();

        // Если после фильтра ничего не осталось — возвращаем всё
        final toSort = filtered.isNotEmpty ? filtered : placesWithDistance;

        // 3. Сортируем по расстоянию (ближние сверху)
        toSort.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

        // 4. Ограничиваем до 10 результатов
        places = toSort.take(10).map((p) => p.place).toList();

        print('=== НАЙДЕНО (после фильтра): ${places.length}');
        for (final p in toSort.take(5)) {
          print('    ${(p.distanceMeters / 1000).toStringAsFixed(1)} км — ${p.place.displayName}');
        }
      }

      return places;
    } catch (e) {
      print('=== ОШИБКА: $e');
      return [];
    }
  }
}

// Вспомогательный класс для сортировки
class _PlaceWithDistance {
  final Place place;
  final double distanceMeters;

  _PlaceWithDistance({required this.place, required this.distanceMeters});
}