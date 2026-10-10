import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteService {
  static const String _baseUrl =
      'https://router.project-osrm.org/route/v1/driving';

  Future<RouteResult?> getRoute(LatLng from, LatLng to) async {
    final coords =
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    // steps=true — чтобы получить манёвры
    final uri = Uri.parse(
      '$_baseUrl/$coords?overview=full&geometries=geojson&steps=true',
    );

    print('=== МАРШРУТ: $uri');

    try {
      final response = await http.get(uri);
      print('=== ОТВЕТ: ${response.statusCode}');

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);

      if (data['code'] != 'Ok') {
        print('=== ОШИБКА OSRM: ${data['code']}');
        return null;
      }

      final route = data['routes'][0];
      final coordsList = route['geometry']['coordinates'] as List;

      final points = coordsList
          .map((c) => LatLng(c[1] as double, c[0] as double))
          .toList();

      // Парсим манёвры
      final steps = <RouteStep>[];
      final legs = route['legs'] as List;
      for (final leg in legs) {
        final legSteps = leg['steps'] as List;
        for (final step in legSteps) {
          final maneuver = step['maneuver'];
          final location = maneuver['location'] as List;
          final stepDistance = (step['distance'] as num).toDouble();

          steps.add(RouteStep(
            location: LatLng(location[1] as double, location[0] as double),
            distance: stepDistance,
            duration: (step['duration'] as num).toDouble(),
            type: maneuver['type'] as String? ?? 'turn',
            modifier: maneuver['modifier'] as String? ?? '',
            instruction: _buildInstruction(
              maneuver['type'] as String? ?? 'turn',
              maneuver['modifier'] as String? ?? '',
              stepDistance,
            ),
          ));
        }
      }

      return RouteResult(
        points: points,
        distanceMeters: (route['distance'] as num).toDouble(),
        durationSeconds: (route['duration'] as num).toDouble(),
        steps: steps,
      );
    } catch (e) {
      print('=== ОШИБКА: $e');
      return null;
    }
  }

  String _buildInstruction(String type, String modifier, double distance) {
    String action;
    switch (type) {
      case 'turn':
        action = _modifierToRussian(modifier);
        break;
      case 'depart':
        action = 'Начните движение';
        break;
      case 'arrive':
        action = 'Вы прибыли';
        break;
      case 'merge':
        action = 'Влейтесь в поток';
        break;
      case 'fork':
        action = 'Держитесь ${_modifierToRussian(modifier)}';
        break;
      case 'roundabout':
        action = 'Въезжайте на круг';
        break;
      default:
        action = _modifierToRussian(modifier);
    }

    if (type == 'arrive' || type == 'depart') {
      return action;
    }

    return 'Через ${_formatDistance(distance)} $action';
  }

  String _modifierToRussian(String modifier) {
    switch (modifier) {
      case 'left':
        return 'поверните налево';
      case 'right':
        return 'поверните направо';
      case 'slight left':
        return 'плавно налево';
      case 'slight right':
        return 'плавно направо';
      case 'sharp left':
        return 'резко налево';
      case 'sharp right':
        return 'резко направо';
      case 'straight':
        return 'продолжайте прямо';
      case 'uturn':
        return 'развернитесь';
      default:
        return 'продолжайте движение';
    }
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} км';
    }
    return '${meters.round()} м';
  }
}

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStep> steps;

  RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.steps = const [],
  });

  String get distanceText {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} км';
    }
    return '${distanceMeters.round()} м';
  }

  String get durationText {
    final minutes = (durationSeconds / 60).round();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '$hours ч $mins мин';
    }
    return '$minutes мин';
  }
}

class RouteStep {
  final LatLng location;
  final double distance;
  final double duration;
  final String type;
  final String modifier;
  final String instruction;

  RouteStep({
    required this.location,
    required this.distance,
    required this.duration,
    required this.type,
    required this.modifier,
    required this.instruction,
  });
}