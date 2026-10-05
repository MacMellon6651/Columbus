import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlaceInfo {
  final String address;
  final List<PoiItem> pois;

  PlaceInfo({required this.address, required this.pois});
}

class PoiItem {
  final String name;
  final String type;
  final double lat;
  final double lng;

  PoiItem({
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
  });
}

class PlaceInfoService {
  static const String _nominatimUrl =
      'https://nominatim.openstreetmap.org/reverse';

  static const String _overpassUrl =
      'https://overpass.osm.ch/api/interpreter';

  Future<PlaceInfo> getInfoAt(LatLng location) async {
    final address = await _getAddress(location);
    final pois = await _getPois(location);
    return PlaceInfo(address: address, pois: pois);
  }

  Future<String> _getAddress(LatLng location) async {
    final uri = Uri.parse(
      '$_nominatimUrl?lat=${location.latitude}&lon=${location.longitude}'
          '&format=jsonv2&addressdetails=1&accept-language=ru',
    );

    try {
      final response = await http.get(uri, headers: {
        'User-Agent': 'CityTransportApp/1.0',
      });

      if (response.statusCode != 200) return 'Адрес не найден';

      final data = jsonDecode(response.body);
      final address = data['address'] as Map<String, dynamic>?;

      if (address == null) {
        return data['display_name'] as String? ?? 'Адрес не найден';
      }

      final parts = <String>[];
      if (address['road'] != null) parts.add(address['road']);
      if (address['house_number'] != null) parts.add(address['house_number']);
      if (address['city'] != null) parts.add(address['city']);

      return parts.isNotEmpty
          ? parts.join(', ')
          : data['display_name'] ?? 'Адрес не найден';
    } catch (e) {
      print('=== ОШИБКА АДРЕСА: $e');
      return 'Адрес не найден';
    }
  }

  Future<List<PoiItem>> _getPois(LatLng location) async {
    const radius = 150; // было 100, увеличили до 150 м
    final query = '''
[out:json][timeout:25];
(
  node["amenity"](around:$radius,${location.latitude},${location.longitude});
  node["shop"](around:$radius,${location.latitude},${location.longitude});
  node["office"](around:$radius,${location.latitude},${location.longitude});
  node["leisure"](around:$radius,${location.latitude},${location.longitude});
  node["tourism"](around:$radius,${location.latitude},${location.longitude});
  node["healthcare"](around:$radius,${location.latitude},${location.longitude});
  node["craft"](around:$radius,${location.latitude},${location.longitude});
  way["amenity"](around:$radius,${location.latitude},${location.longitude});
  way["shop"](around:$radius,${location.latitude},${location.longitude});
  way["office"](around:$radius,${location.latitude},${location.longitude});
  way["leisure"](around:$radius,${location.latitude},${location.longitude});
  way["tourism"](around:$radius,${location.latitude},${location.longitude});
  way["healthcare"](around:$radius,${location.latitude},${location.longitude});
  way["craft"](around:$radius,${location.latitude},${location.longitude});
  relation["amenity"](around:$radius,${location.latitude},${location.longitude});
  relation["shop"](around:$radius,${location.latitude},${location.longitude});
);
out center;
''';

    const mirrors = [
      'https://overpass.osm.ch/api/interpreter',
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://overpass-api.openstreetmap.fr/api/interpreter',
      'https://overpass.osm.ch/api/interpreter',
    ];

    print('=== OVERPASS ЗАПРОС для ${location.latitude},${location.longitude}, радиус $radius');

    for (final mirror in mirrors) {
      try {
        final response = await http.post(
          Uri.parse(mirror),
          body: {'data': query},
          headers: {'User-Agent': 'CityTransportApp/1.0'},
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body);
        final elements = data['elements'] as List? ?? [];

        print('=== ЭЛЕМЕНТОВ: ${elements.length}');

        final pois = <PoiItem>[];

        for (final el in elements) {
          final tags = el['tags'] as Map<String, dynamic>?;
          if (tags == null) continue;

          final name = tags['name'] as String?;
          if (name == null || name.isEmpty) continue;

          // Определяем тип
          String type = 'место';
          if (tags['amenity'] != null) type = _amenityToRussian(tags['amenity'] as String);
          if (tags['shop'] != null) type = 'магазин';
          if (tags['office'] != null) type = 'офис';
          if (tags['leisure'] != null) type = _leisureToRussian(tags['leisure'] as String);
          if (tags['tourism'] != null) type = _tourismToRussian(tags['tourism'] as String);
          if (tags['healthcare'] != null) type = 'медицина';
          if (tags['craft'] != null) type = 'мастерская';

          double lat, lng;
          if (el['type'] == 'node') {
            lat = (el['lat'] as num).toDouble();
            lng = (el['lon'] as num).toDouble();
          } else {
            final center = el['center'];
            if (center == null) continue;
            lat = (center['lat'] as num).toDouble();
            lng = (center['lon'] as num).toDouble();
          }

          pois.add(PoiItem(
            name: name,
            type: type,
            lat: lat,
            lng: lng,
          ));
        }

        print('=== POI НАЙДЕНО: ${pois.length}');

        final unique = <String, PoiItem>{};
        for (final poi in pois) {
          unique[poi.name] = poi;
        }

        return unique.values.toList();
      } catch (e) {
        print('=== ЗЕРКАЛО $mirror НЕ РАБОТАЕТ: $e');
      }
    }

    return [];
  }

  String _amenityToRussian(String value) {
    const map = {
      'restaurant': 'ресторан',
      'cafe': 'кафе',
      'fast_food': 'фастфуд',
      'bar': 'бар',
      'pub': 'паб',
      'pharmacy': 'аптека',
      'hospital': 'больница',
      'clinic': 'клиника',
      'dentist': 'стоматология',
      'bank': 'банк',
      'atm': 'банкомат',
      'fuel': 'заправка',
      'parking': 'парковка',
      'school': 'школа',
      'kindergarten': 'детский сад',
      'university': 'университет',
      'library': 'библиотека',
      'post_office': 'почта',
      'police': 'полиция',
      'fire_station': 'пожарная',
      'townhall': 'мэрия',
      'place_of_worship': 'храм',
      'theatre': 'театр',
      'cinema': 'кинотеатр',
      'museum': 'музей',
      'marketplace': 'рынок',
      'veterinary': 'ветклиника',
      'toilets': 'туалет',
      'bus_station': 'автостанция',
      'taxi': 'такси',
    };
    return map[value] ?? value;
  }

  String _leisureToRussian(String value) {
    const map = {
      'park': 'парк',
      'playground': 'площадка',
      'sports_centre': 'спортцентр',
      'stadium': 'стадион',
      'fitness_centre': 'фитнес',
      'swimming_pool': 'бассейн',
      'garden': 'сад',
    };
    return map[value] ?? value;
  }

  String _tourismToRussian(String value) {
    const map = {
      'hotel': 'отель',
      'hostel': 'хостел',
      'guest_house': 'гостевой дом',
      'museum': 'музей',
      'attraction': 'достопримечательность',
      'viewpoint': 'смотровая',
      'information': 'информация',
      'picnic_site': 'пикник',
      'camp_site': 'кемпинг',
    };
    return map[value] ?? value;
  }
}