class Vehicle {
  final String id;
  final String gosNum;
  final String routeNum;
  final String routeType;
  final double lat;
  final double lng;
  final int dir;
  final int speed;
  final String lastTime;

  Vehicle({
    required this.id,
    required this.gosNum,
    required this.routeNum,
    required this.routeType,
    required this.lat,
    required this.lng,
    required this.dir,
    required this.speed,
    required this.lastTime,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    // Сырые координаты от сервера
    final rawLon = (json['lon'] as num).toInt();
    final rawLat = (json['lat'] as num).toInt();

    return Vehicle(
      id: json['id'] as String,
      gosNum: json['gos_num'] as String? ?? '',
      routeNum: json['rnum'] as String? ?? '',
      routeType: json['rtype'] as String? ?? '',
      // ВОТ ФОРМУЛА ПРЕОБРАЗОВАНИЯ КООРДИНАТ
      lng: (rawLon + 2000591) / 1500000.0,
      lat: (rawLat + 9551466) / 1300000.0,
      dir: (json['dir'] as num?)?.toInt() ?? 0,
      speed: (json['speed'] as num?)?.toInt() ?? 0,
      lastTime: json['lasttime'] as String? ?? '',
    );
  }
}