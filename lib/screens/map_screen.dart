import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../view_models/map_view_model.dart';
import '../services/route_service.dart';
import '../services/settings_service.dart';
import '../services/favorites_service.dart';
import '../services/place_info_service.dart';
import '../services/weather_service.dart';
import '../services/places_service.dart';
import '../models/place.dart';
import '../models/favorite_place.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'add_place_screen.dart';
import '../widgets/place_details_panel.dart';
import 'dart:math';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapViewModel _viewModel = MapViewModel();
  final TextEditingController _searchController = TextEditingController();
  final PlaceInfoService _placeInfoService = PlaceInfoService();
  MapLibreMapController? _mapController;
  String? _activeWeatherLayerCode;

  Line? _routeLine;
  Symbol? _destinationSymbol;

  // Маркеры добавленных мест
  final List<Symbol> _placeMarkers = [];

  // Кэш загруженных мест (для поиска ближайшего при тапе)
  List<Map<String, dynamic>> _cachedPlaces = [];

  // ID выбранного места (для боковой панели)
  int? _selectedPlaceId;

  // Флаг: был ли выбран пункт назначения (для очистки строки поиска)
  bool _wasDestinationSelected = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _viewModel.setSettings(settings);
    _viewModel.addListener(_onViewModelChanged);
    _viewModel.initialize();

    settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    context.read<SettingsService>().removeListener(_onSettingsChanged);
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    final settings = context.read<SettingsService>();
    if (_viewModel.voiceEnabled != settings.voiceEnabled) {
      _viewModel.setVoiceEnabled(settings.voiceEnabled);
    }
    _updateMapFromViewModel();
  }

  void _onViewModelChanged() {
    // Реакция на сброс выбранной точки — очищаем строку поиска.
    final hasDestination = _viewModel.selectedDestination != null;
    if (_wasDestinationSelected && !hasDestination) {
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
      }
    }
    _wasDestinationSelected = hasDestination;

    if (mounted) setState(() {});
    _updateMapFromViewModel();

    if (_viewModel.justRebuiltRoute) {
      _viewModel.justRebuiltRoute = false;
      if (_viewModel.isNavigationMode && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Маршрут перестроен'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ============ ОБНОВЛЕНИЕ КАРТЫ ============

  Future<void> _updateMapFromViewModel() async {
    final controller = _mapController;
    if (controller == null) return;

    // 1. Маршрут
    if (_viewModel.currentRoute != null) {
      final points = _viewModel.currentRoute!.points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();

      if (_routeLine != null) {
        await controller.removeLine(_routeLine!);
      }

      _routeLine = await controller.addLine(LineOptions(
        geometry: points,
        lineColor: '#007AFF',
        lineWidth: _viewModel.isNavigationMode ? 10.0 : 5.0,
        lineOpacity: 0.9,
      ));
    } else {
      if (_routeLine != null) {
        await controller.removeLine(_routeLine!);
        _routeLine = null;
      }
    }

    // 2. Маркер назначения
    if (_viewModel.selectedDestination != null) {
      if (_destinationSymbol != null) {
        await controller.removeSymbol(_destinationSymbol!);
      }

      _destinationSymbol = await controller.addSymbol(SymbolOptions(
        geometry: LatLng(
          _viewModel.selectedDestination!.location.latitude,
          _viewModel.selectedDestination!.location.longitude,
        ),
        iconImage: 'destination-marker',
        iconSize: 0.4,
        iconAnchor: 'bottom',
      ));
    } else {
      if (_destinationSymbol != null) {
        await controller.removeSymbol(_destinationSymbol!);
        _destinationSymbol = null;
      }
    }

    // 3. Камера в навигации
    if (_viewModel.isNavigationMode && _viewModel.currentPosition != null) {
      controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(
            _viewModel.currentPosition!.latitude,
            _viewModel.currentPosition!.longitude,
          ),
          zoom: 17.0,
          tilt: 60.0,
        ),
      ));
    }

    // 4. Возврат камеры после выхода из навигации
    if (_viewModel.justExitedNavigation && _viewModel.currentPosition != null) {
      _viewModel.justExitedNavigation = false;

      controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(
            _viewModel.currentPosition!.latitude,
            _viewModel.currentPosition!.longitude,
          ),
          zoom: 16.0,
          bearing: 0.0,
          tilt: 0.0,
        ),
      ));
    }

    // 5. Погодный слой
    final settings = context.read<SettingsService>();
    final weatherService = WeatherService();

    if (settings.weatherEnabled && weatherService.hasApiKey) {
      final layerCode = settings.weatherLayer;

      if (_activeWeatherLayerCode != layerCode) {
        if (_activeWeatherLayerCode != null) {
          try {
            await controller.removeLayer('weather_layer');
            await controller.removeSource('weather_source');
          } catch (_) {}
        }

        try {
          await controller.addSource(
            'weather_source',
            RasterSourceProperties(
              tiles: [
                weatherService.getTileUrl(WeatherLayer.values.firstWhere(
                  (l) => l.code == layerCode,
                  orElse: () => WeatherLayer.precipitation,
                ))
              ],
              tileSize: 256,
            ),
          );

          await controller.addLayer(
            'weather_layer',
            'weather_source',
            RasterLayerProperties(rasterOpacity: 0.6),
          );

          _activeWeatherLayerCode = layerCode;
          debugPrint('=== ПОГОДНЫЙ СЛОЙ ДОБАВЛЕН ПОВЕРХ: $layerCode');

          final camera = await controller.queryCameraPosition();
          if (camera != null) {
            await controller.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: LatLng(
                    camera.target.latitude + 0.000001,
                    camera.target.longitude,
                  ),
                  zoom: camera.zoom,
                  bearing: camera.bearing,
                  tilt: camera.tilt,
                ),
              ),
              duration: const Duration(milliseconds: 30),
            );
            await controller.animateCamera(
              CameraUpdate.newCameraPosition(camera),
              duration: const Duration(milliseconds: 30),
            );
          }
        } catch (e) {
          debugPrint('=== ОШИБКА ДОБАВЛЕНИЯ ПОГОДЫ: $e');
        }
      }
    } else {
      if (_activeWeatherLayerCode != null) {
        try {
          await controller.removeLayer('weather_layer');
          await controller.removeSource('weather_source');
        } catch (_) {}
        _activeWeatherLayerCode = null;
      }
    }

    // 6. Загрузка погоды
    if (settings.weatherEnabled &&
        weatherService.hasApiKey &&
        _viewModel.currentPosition != null) {
      weatherService.getCurrentWeather(
        lat: _viewModel.currentPosition!.latitude,
        lon: _viewModel.currentPosition!.longitude,
      ).then((weather) {
        if (weather != null && mounted) {
          debugPrint(
              '=== ПОГОДА: ${weather.temperature}°C, ${weather.description}');
        }
      });
    }
  }

  // ============ КАРТА ============

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    controller.onSymbolTapped.add(_onSymbolTapped);
  }

  Future<void> _onStyleLoaded() async {
    // Иконка маркера назначения
    try {
      final bytes = await rootBundle.load('assets/marker.png');
      await _mapController?.addImage(
        'destination-marker',
        bytes.buffer.asUint8List(),
      );
      debugPrint('=== ИКОНКА МАРКЕРА ЗАГРУЖЕНА');
    } catch (e) {
      debugPrint('=== ОШИБКА ЗАГРУЗКИ ИКОНКИ: $e');
    }

    // Иконки категорий
    final iconNames = [
      'cafe',
      'shop',
      'restaurant',
      'pharmacy',
      'park',
      'hospital',
      'university',
    ];

    for (final name in iconNames) {
      try {
        final bytes = await rootBundle.load('assets/icons/$name.png');
        await _mapController?.addImage(
          'icon_$name',
          bytes.buffer.asUint8List(),
        );
        debugPrint('=== ИКОНКА $name ЗАГРУЖЕНА');
      } catch (e) {
        debugPrint('=== ИКОНКА $name НЕ ЗАГРУЖЕНА: $e');
      }
    }

    // Места из БД
    await _loadPlacesFromDb();

    // Центрируем камеру
    final pos = _viewModel.currentPosition;
    if (pos != null && pos.latitude.abs() > 0.1) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(pos.latitude, pos.longitude),
        16.0,
      ));
    } else {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
        const LatLng(53.3532, 83.7737),
        12.0,
      ));
    }
  }

  // ============ ЗАГРУЗКА МЕСТ ИЗ БД ============

  Future<void> _loadPlacesFromDb() async {
    final controller = _mapController;
    if (controller == null) return;

    try {
      final auth = context.read<AuthService>();
      final placesService = PlacesService(auth.api);

      final places = await placesService.getAllPlaces();
      debugPrint('=== ЗАГРУЖЕНО МЕСТ ИЗ БД: ${places.length}');

      _cachedPlaces = places;

      for (final place in places) {
        final lat = (place['lat'] as num).toDouble();
        final lng = (place['lng'] as num).toDouble();
        final name = place['name'] as String? ?? 'Без названия';
        final category = place['category'] as String?;

        await _addPlaceMarker(LatLng(lat, lng), name, category);
      }
    } catch (e) {
      debugPrint('=== ОШИБКА ЗАГРУЗКИ МЕСТ: $e');
    }
  }

  // ============ ТАП ПО КАРТЕ ============

  Future<void> _onMapClick(dynamic point, LatLng coordinates) async {
    debugPrint(
        '=== ТАП ПО КАРТЕ: ${coordinates.latitude}, ${coordinates.longitude}');

    // 1. Если рядом (≤30 м) есть место из БД — открываем боковую панель.
    if (_cachedPlaces.isNotEmpty) {
      Map<String, dynamic>? nearest;
      double nearestDistance = double.infinity;

      for (final place in _cachedPlaces) {
        final lat = (place['lat'] as num).toDouble();
        final lng = (place['lng'] as num).toDouble();
        final distance = _distanceBetween(
          coordinates.latitude,
          coordinates.longitude,
          lat,
          lng,
        );
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = place;
        }
      }

      if (nearest != null && nearestDistance <= 30.0) {
        final rawId = nearest['id'];
        final id = rawId is int ? rawId : int.tryParse(rawId.toString());
        if (id != null) {
          debugPrint('=== ОТКРЫВАЮ ПАНЕЛЬ: ${nearest['name']} (id=$id)');
          setState(() => _selectedPlaceId = id);
          return;
        }
      }
    }

    // 2. Иначе — берём адрес через PlaceInfoService
    //    и ставим точку как пункт назначения (как при поиске).
    final info = await _placeInfoService.getInfoAt(
      ll.LatLng(coordinates.latitude, coordinates.longitude),
    );

    if (!mounted) return;

    final address = info.address.isNotEmpty
        ? info.address
        : '${coordinates.latitude.toStringAsFixed(5)}, '
            '${coordinates.longitude.toStringAsFixed(5)}';

    final place = Place(
      displayName: address,
      location: ll.LatLng(coordinates.latitude, coordinates.longitude),
    );

    // selectPlace очистит searchResults и установит selectedDestination.
    // _updateMapFromViewModel сам нарисует _destinationSymbol
    // и покажет панель маршрута снизу.
    _viewModel.selectPlace(place);

    // Показываем адрес/координаты выбранной точки в строке поиска.
    _searchController.text = address;

    // Небольшой сдвиг камеры на точку.
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(coordinates.latitude, coordinates.longitude),
        16.0,
      ),
    );

    setState(() {});
  }

  // ============ ТАП ПО МАРКЕРУ (Symbol) ============

  void _onSymbolTapped(Symbol symbol) {
    final coords = symbol.options.geometry;
    debugPrint('=== SYMBOL TAPPED: $coords');
    if (coords == null) return;

    if (_cachedPlaces.isEmpty) return;

    Map<String, dynamic>? nearest;
    double nearestDistance = double.infinity;

    for (final place in _cachedPlaces) {
      final lat = (place['lat'] as num).toDouble();
      final lng = (place['lng'] as num).toDouble();
      final d = _distanceBetween(
        coords.latitude,
        coords.longitude,
        lat,
        lng,
      );
      if (d < nearestDistance) {
        nearestDistance = d;
        nearest = place;
      }
    }

    if (nearest == null || nearestDistance > 5.0) {
      debugPrint(
          '=== СИМВОЛ БЕЗ МЕСТА В БД (dist=${nearestDistance.round()}м)');
      return;
    }

    final rawId = nearest['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId.toString());
    if (id == null) {
      debugPrint('=== ID НЕ ПОЛУЧЕН: rawId=$rawId');
      return;
    }

    debugPrint('=== SYMBOL TAP → ПАНЕЛЬ: ${nearest['name']} (id=$id)');
    setState(() => _selectedPlaceId = id);
  }

  double _distanceBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    const deg2rad = 3.141592653589793 / 180.0;
    final dLat = (lat2 - lat1) * deg2rad;
    final dLon = (lon2 - lon1) * deg2rad;

    final a = (dLat / 2).abs() * (dLat / 2).abs() +
        (lat1 * deg2rad).abs() *
            (lat2 * deg2rad).abs() *
            (dLon / 2).abs() *
            (dLon / 2).abs();

    return earthRadius * 2 * a;
  }

  void _zoomIn() => _mapController?.animateCamera(CameraUpdate.zoomIn());
  void _zoomOut() => _mapController?.animateCamera(CameraUpdate.zoomOut());

  void _centerOnMe() {
    final pos = _viewModel.currentPosition;
    if (pos == null) return;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
      LatLng(pos.latitude, pos.longitude),
      16.0,
    ));
  }

  // ============ ДОБАВЛЕНИЕ МЕСТА НА КАРТУ ============

  Future<void> _addPlaceMarker(
      LatLng coordinates, String name, String? category) async {
    final controller = _mapController;
    if (controller == null) return;

    String iconName = 'destination-marker';
    if (category != null) {
      final lower = category.toLowerCase();
      if (lower.contains('кафе') || lower.contains('cafe')) {
        iconName = 'icon_cafe';
      } else if (lower.contains('магазин') || lower.contains('shop')) {
        iconName = 'icon_shop';
      } else if (lower.contains('ресторан') || lower.contains('restaurant')) {
        iconName = 'icon_restaurant';
      } else if (lower.contains('аптека') || lower.contains('pharmacy')) {
        iconName = 'icon_pharmacy';
      } else if (lower.contains('парк') || lower.contains('park')) {
        iconName = 'icon_park';
      } else if (lower.contains('больница') || lower.contains('hospital')) {
        iconName = 'icon_hospital';
      } else if (lower.contains('университет') ||
          lower.contains('university')) {
        iconName = 'icon_university';
      }
    }

    try {
      final marker = await controller.addSymbol(
        SymbolOptions(
          geometry: coordinates,
          iconImage: iconName,
          iconSize: 0.4,
          iconAnchor: 'bottom',
          textField: name,
          textSize: 12,
          textColor: '#000000',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2,
          textOffset: const Offset(0, 1.5),
          textAnchor: 'top',
        ),
      );

      setState(() {
        _placeMarkers.add(marker);
      });

      debugPrint('=== МАРКЕР ДОБАВЛЕН: $name');
    } catch (e) {
      debugPrint('=== ОШИБКА ДОБАВЛЕНИЯ МАРКЕРА: $e');
    }
  }

  // ============ ПОИСК ============

  Future<void> _performSearch() async {
    FocusScope.of(context).unfocus();

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _viewModel.searchResults = [];
      setState(() {});
      return;
    }

    final lowerQuery = query.toLowerCase();

    // 1. Совпадения в избранном (побуквенно, без учёта регистра).
    //    Формат: "имя, адрес" — адрес подтянут автоматически.
    final favoritePlaces = context
        .read<FavoritesService>()
        .favorites
        .where((fav) =>
            fav.name.toLowerCase().contains(lowerQuery) ||
            fav.address.toLowerCase().contains(lowerQuery))
        .map((fav) {
      final parts = <String>[
        if (fav.name.trim().isNotEmpty) fav.name.trim(),
        if (fav.address.trim().isNotEmpty) fav.address.trim(),
      ];
      final display = parts.isEmpty ? 'Без названия' : parts.join(', ');

      return Place(
        displayName: display,
        location: ll.LatLng(fav.lat, fav.lng),
      );
    }).toList();

    // 2. Внешний поиск через API. GeocodingService уже отфильтровал
    //    по 100 км и отсортировал по возрастанию расстояния — «ближайшие выше».
    await _viewModel.search(query);

    // 3. Избранное — всегда сверху, без дублей по координатам.
    final externalResults = _viewModel.searchResults;
    final merged = [
      ...favoritePlaces,
      ...externalResults.where((p) => !favoritePlaces.any(
            (f) =>
                (f.location.latitude - p.location.latitude).abs() < 0.0001 &&
                (f.location.longitude - p.location.longitude).abs() < 0.0001,
          )),
    ];

    _viewModel.searchResults = merged;
    if (mounted) setState(() {});
  }

  void _onPlaceSelected(Place place) {
    _viewModel.selectPlace(place);

    // Если это место из избранного — в строку поиска подставляем только имя.
    final fav = context.read<FavoritesService>().findByCoordinates(
          place.location.latitude,
          place.location.longitude,
        );
    _searchController.text = fav?.name ?? place.displayName;

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
      LatLng(place.location.latitude, place.location.longitude),
      16.0,
    ));
  }

  // ============ НАСТРОЙКИ ============

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) => PointerInterceptor(
        child: _SettingsPanel(
          onPlaceAdded: (placeData) async {
            await _addPlaceMarker(
              LatLng(placeData['lat'], placeData['lng']),
              placeData['name'],
              placeData['category'],
            );

            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(placeData['lat'], placeData['lng']),
                16.0,
              ),
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('Место "${placeData['name']}" добавлено!')),
              );
            }
          },
        ),
      ),
    );
  }

  // ============ ИЗБРАННОЕ ============

  void _openFavorites() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => PointerInterceptor(
        child: _FavoritesPanel(
          onSelect: (fav) => _buildRouteToFavorite(fav),
        ),
      ),
    );
  }

  Future<void> _addCurrentToFavorites() async {
    final dest = _viewModel.selectedDestination;
    if (dest == null) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Название места'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Дом, Работа, ...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    await context.read<FavoritesService>().add(
          name: name,
          address: dest.displayName,
          lat: dest.location.latitude,
          lng: dest.location.longitude,
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«$name» добавлено в избранное')),
      );
      setState(() {});
    }
  }

  void _buildRouteToFavorite(FavoritePlace fav) {
    final place = Place(
      displayName: fav.address,
      location: ll.LatLng(fav.lat, fav.lng),
    );

    _viewModel.selectPlace(place);
    _searchController.text = fav.name;

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
      LatLng(fav.lat, fav.lng),
      16.0,
    ));

    _viewModel.buildRoute();
  }

  // ============ UI ============

  @override
  Widget build(BuildContext context) {
    final vm = _viewModel;

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapClick: _onMapClick,
            initialCameraPosition: CameraPosition(
              target: LatLng(
                vm.currentPosition?.latitude ?? 53.3532,
                vm.currentPosition?.longitude ?? 83.7737,
              ),
              zoom: 12.0,
            ),
            styleString: 'https://tiles.openfreemap.org/styles/liberty',
            myLocationEnabled: vm.currentPosition != null,
            myLocationTrackingMode: vm.currentPosition != null
                ? MyLocationTrackingMode.tracking
                : MyLocationTrackingMode.none,

            // Компас — в левый нижний угол
            compassEnabled: true,
            compassViewPosition: CompassViewPosition.bottomLeft,
            compassViewMargins: const Point(16, 16),
          ),

          // Поисковая строка
          if (!vm.isNavigationMode)
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: PointerInterceptor(
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.5, // ← половина ширины экрана
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSearchBar(),
                        if (vm.searchResults.isNotEmpty) _buildSearchResults(),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Кнопка настроек
          Positioned(
            top: 50,
            left: 16,
            child: PointerInterceptor(
              child: _MapButton(
                icon: Icons.settings,
                onPressed: _openSettings,
              ),
            ),
          ),

          // Кнопка избранного
          if (!vm.isNavigationMode)
            Positioned(
              top: 120,
              left: 16,
              child: PointerInterceptor(
                child: _MapButton(
                  icon: Icons.star,
                  onPressed: _openFavorites,
                  backgroundColor: Colors.amber,
                  iconColor: Colors.white,
                ),
              ),
            ),

          // Спидометр
          if (vm.isNavigationMode && vm.speedKmh != null)
            Positioned(
              top: 50,
              right: 16,
              child: PointerInterceptor(
                child: _buildSpeedDisplay(vm.speedKmh!),
              ),
            ),

          // Баннер манёвра
          if (vm.isNavigationMode && vm.currentStep != null)
            Positioned(
              top: 50,
              left: 16,
              right: 110,
              child: PointerInterceptor(
                child: _buildManeuverBanner(vm.currentStep!),
              ),
            ),

          // Кнопки зума
          Positioned(
            right: 16,
            bottom: vm.selectedDestination != null ? 220 : 100,
            child: PointerInterceptor(
              child: Column(
                children: [
                  _MapButton(icon: Icons.add, onPressed: _zoomIn),
                  const SizedBox(height: 12),
                  _MapButton(icon: Icons.remove, onPressed: _zoomOut),
                  const SizedBox(height: 12),
                  _MapButton(
                    icon: Icons.my_location,
                    onPressed: _centerOnMe,
                    backgroundColor: Colors.blue,
                    iconColor: Colors.white,
                  ),
                ],
              ),
            ),
          ),

          // Панель маршрута
          if (vm.selectedDestination != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: PointerInterceptor(
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.6, // ← ширина: 60% экрана
                    child: _buildRoutePanel(),
                  ),
                ),
              ),
            ),

          // Боковая панель места
          if (_selectedPlaceId != null)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: PointerInterceptor(
                child: PlaceDetailsPanel(
                  key: ValueKey(_selectedPlaceId),
                  placeId: _selectedPlaceId!,
                  api: context.read<AuthService>().api,
                  onClose: () {
                    setState(() => _selectedPlaceId = null);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _performSearch(),
        decoration: InputDecoration(
          hintText: 'Поиск места...',
          hintStyle: const TextStyle(color: Colors.grey),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 12, right: 8),
            child: Icon(Icons.search, color: Colors.grey),
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    _viewModel.searchResults = [];
                    setState(() {});
                  },
                ),
              if (!_viewModel.isSearching)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: Colors.blue,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _performSearch,
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _viewModel.searchResults.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final place = _viewModel.searchResults[index];
            return ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              title: Text(
                place.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              onTap: () => _onPlaceSelected(place),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSpeedDisplay(double speed) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: Colors.black87,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speed, color: Colors.white, size: 22),
                const SizedBox(width: 6),
                Text(
                  '${speed.round()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ],
            ),
            const Text(
              'км/ч',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManeuverBanner(RouteStep step) {
    final icon = _getManeuverIcon(step.modifier, step.type);

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: Colors.blue.shade700,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                step.instruction,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getManeuverIcon(String modifier, String type) {
    if (type == 'arrive') return Icons.flag;
    if (type == 'depart') return Icons.navigation;

    switch (modifier) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      case 'straight':
        return Icons.straight;
      default:
        return Icons.navigation;
    }
  }

  Widget _buildRoutePanel() {
    final vm = _viewModel;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).colorScheme.surface,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (vm.currentRoute != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildInfoChip(
                    Icons.straighten,
                    vm.currentRoute!.distanceText,
                  ),
                  _buildInfoChip(
                    Icons.access_time,
                    vm.currentRoute!.durationText,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (!vm.isNavigationMode &&
                vm.selectedDestination != null &&
                !context
                    .read<FavoritesService>()
                    .isFavorite(
                      vm.selectedDestination!.location.latitude,
                      vm.selectedDestination!.location.longitude,
                    ))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.star_border, size: 18),
                    label: const Text('Добавить в избранное'),
                    onPressed: _addCurrentToFavorites,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),

            if (!vm.isNavigationMode) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: vm.clearRoute,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Отмена'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: vm.isBuildingRoute ? null : vm.buildRoute,
                      icon: vm.isBuildingRoute
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.directions, size: 18),
                      label: Text(
                        vm.currentRoute == null ? 'Построить' : 'Обновить',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (vm.currentRoute != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.navigation),
                    label: const Text('В режим авто'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: vm.startNavigation,
                  ),
                ),
              ],
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('Выйти из режима авто'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: vm.stopNavigation,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}

class _MapButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? iconColor;

  const _MapButton({
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.iconColor,
  });

  @override
  State<_MapButton> createState() => _MapButtonState();
}

class _MapButtonState extends State<_MapButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Material(
        elevation: 6,
        shape: const CircleBorder(),
        color: widget.backgroundColor ?? Theme.of(context).colorScheme.surface,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        child: InkWell(
          onTap: () {
            _controller.forward().then((_) => _controller.reverse());
            widget.onPressed();
          },
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              widget.icon,
              color: widget.iconColor ??
                  Theme.of(context).colorScheme.onSurface,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

// ============ ПАНЕЛЬ НАСТРОЕК ============

class _SettingsPanel extends StatelessWidget {
  final void Function(Map<String, dynamic> placeData) onPlaceAdded;

  const _SettingsPanel({required this.onPlaceAdded});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final auth = context.watch<AuthService>();

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Настройки',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 20),

            SwitchListTile(
              title: const Text('Тёмная тема'),
              subtitle: const Text('Переключить светлую / тёмную тему'),
              secondary: Icon(
                settings.themeMode == ThemeMode.dark
                    ? Icons.dark_mode
                    : Icons.light_mode,
              ),
              value: settings.themeMode == ThemeMode.dark,
              onChanged: (value) {
                settings.setThemeMode(
                  value ? ThemeMode.dark : ThemeMode.light,
                );
              },
            ),

            SwitchListTile(
              title: const Text('Голосовые подсказки'),
              subtitle: const Text('Озвучивать манёвры на маршруте'),
              secondary: Icon(
                settings.voiceEnabled ? Icons.volume_up : Icons.volume_off,
              ),
              value: settings.voiceEnabled,
              onChanged: (value) {
                settings.setVoiceEnabled(value);
              },
            ),

            const Divider(height: 32),

            SwitchListTile(
              title: const Text('Погодные слои'),
              subtitle: const Text('Показывать погоду на карте'),
              secondary: Icon(
                settings.weatherEnabled ? Icons.cloud : Icons.cloud_off,
              ),
              value: settings.weatherEnabled,
              onChanged: (value) {
                settings.setWeatherEnabled(value);
              },
            ),

            if (settings.weatherEnabled) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: WeatherLayer.values.map((layer) {
                    final isSelected = settings.weatherLayer == layer.code;
                    return ChoiceChip(
                      label: Text(layer.label),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          settings.setWeatherLayer(layer.code);
                        }
                      },
                      selectedColor: Colors.blue.withValues(alpha: 0.2),
                    );
                  }).toList(),
                ),
              ),
            ],

            if (settings.searchHistory.isNotEmpty) ...[
              const Divider(height: 32),
              Row(
                children: [
                  const Icon(Icons.history, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'История поиска',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => settings.clearHistory(),
                    child: const Text('Очистить'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: settings.searchHistory.take(10).map((query) {
                  return Chip(
                    label: Text(query),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      settings.removeFromHistory(query);
                    },
                  );
                }).toList(),
              ),
            ],

            // Кнопка добавления места (только для модераторов)
            if (auth.isModerator) ...[
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.add_location, color: Colors.green),
                title: const Text('Добавить место'),
                subtitle: const Text('Только для модераторов'),
                onTap: () async {
                  Navigator.pop(context);

                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddPlaceScreen(),
                    ),
                  );

                  if (result != null && result['success'] == true) {
                    onPlaceAdded(result);
                  }
                },
              ),
            ],

            const Divider(height: 32),

            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Выйти из аккаунта',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: Text(
                auth.currentUserEmail ?? '',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Выйти?'),
                    content: const Text(
                        'Вы уверены, что хотите выйти из аккаунта?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Выйти'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && context.mounted) {
                  await context.read<AuthService>().logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                      (route) => false,
                    );
                  }
                }
              },
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ============ ПАНЕЛЬ ИЗБРАННОГО ============

class _FavoritesPanel extends StatelessWidget {
  final void Function(FavoritePlace) onSelect;

  const _FavoritesPanel({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesService>();
    final list = favorites.favorites;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star, size: 28, color: Colors.amber),
                const SizedBox(width: 12),
                Text(
                  'Избранные места',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.star_border,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Пока ничего нет',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Выбери место на карте и нажми «В избранное»',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...list.map((fav) {
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.star,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    fav.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    fav.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Удалить?'),
                          content: Text('Удалить «${fav.name}» из избранного?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Отмена'),
                            ),
                            TextButton(
                              onPressed: () {
                                favorites.remove(fav.id);
                                Navigator.pop(context);
                              },
                              child: const Text('Удалить'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onSelect(fav);
                  },
                );
              }).toList(),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}