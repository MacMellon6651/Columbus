import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vehicle.dart';

class TransportService {
  static const String _baseUrl =
      'http://www.traffic22.ru/php/getVehiclesMarkers.php';

  // Список ID маршрутов в формате "rid-направление"
  // Например "20-0,21-0" — маршруты 20 и 21, направление 0
  final String rids;

  TransportService({required this.rids});

  Future<List<Vehicle>> fetchVehicles() async {
    final uri = Uri.parse(
      '$_baseUrl?rids=$rids'
          '&lat0=0&lng0=0&lat1=90&lng1=180'
          '&curk=0'
          '&city=barnaul'
          '&info=12345'
          '&_=${DateTime.now().millisecondsSinceEpoch}',
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final anims = data['anims'] as List? ?? [];

      return anims.map((json) => Vehicle.fromJson(json)).toList();
    } catch (e) {
      print('Ошибка загрузки транспорта: $e');
      return [];
    }
  }
}