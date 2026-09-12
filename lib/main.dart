import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Моя Карта',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? mapController;
  bool _locationGranted = false;
  bool _mapReady = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  // Инициализация: запрос разрешения и получение координат
  Future<void> _initLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Служба геолокации выключена');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      debugPrint('Разрешение отклонено навсегда');
      return;
    }

    setState(() => _locationGranted = true);

    // Получаем текущую позицию
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    _currentPosition = position;

    // Если карта уже готова — сразу центрируем
    if (_mapReady) {
      _centerOnMe();
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    mapController = controller;
  }

  void _onStyleLoaded() {
    _mapReady = true;
    // Карта загрузилась, если у нас уже есть координаты — центрируем
    if (_currentPosition != null) {
      _centerOnMe();
    }
  }

  // Центрирование на текущем местоположении
  void _centerOnMe() {
    if (_currentPosition == null || mapController == null) return;

    mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        16.0, // Приближение при центрировании
      ),
      duration: const Duration(milliseconds: 800),
    );
  }

  // Приблизить
  void _zoomIn() {
    mapController?.animateCamera(CameraUpdate.zoomIn());
  }

  // Отдалить
  void _zoomOut() {
    mapController?.animateCamera(CameraUpdate.zoomOut());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            initialCameraPosition: const CameraPosition(
              // Временная позиция до получения GPS
              target: LatLng(55.7558, 37.6173),
              zoom: 12.0,
            ),
            styleString: 'https://tiles.openfreemap.org/styles/liberty',
            myLocationEnabled: _locationGranted,
            myLocationTrackingMode: _locationGranted
                ? MyLocationTrackingMode.tracking
                : MyLocationTrackingMode.none,
          ),

          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                _MapButton(icon: Icons.add, onPressed: _zoomIn),
                const SizedBox(height: 8),
                _MapButton(icon: Icons.remove, onPressed: _zoomOut),
                const SizedBox(height: 8),
                _MapButton(icon: Icons.my_location, onPressed: _centerOnMe),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _MapButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: Colors.black87),
        ),
      ),
    );
  }
}