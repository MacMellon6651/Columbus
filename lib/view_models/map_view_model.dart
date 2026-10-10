import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../models/place.dart';
import '../services/geocoding_service.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import '../services/voice_service.dart';
import '../services/settings_service.dart';

class MapViewModel extends ChangeNotifier {
  final LocationService _locationService = LocationService();
  final GeocodingService _geocodingService = GeocodingService();
  final RouteService _routeService = RouteService();
  final VoiceService _voiceService = VoiceService();

  SettingsService? _settings;

  // ============ СОСТОЯНИЕ ============

  Position? currentPosition;
  List<Place> searchResults = [];
  Place? selectedDestination;
  RouteResult? currentRoute;
  RouteStep? currentStep;
  bool isSearching = false;
  bool isBuildingRoute = false;
  bool isNavigationMode = false;
  double? speedKmh;
  bool justRebuiltRoute = false;
  bool justExitedNavigation = false;

  String? _lastSpokenInstruction;
  StreamSubscription<Position>? _positionStream;
  bool _isRouteRequestInProgress = false;

  bool get voiceEnabled => _voiceService.enabled;

  void setSettings(SettingsService settings) {
    _settings = settings;
    _voiceService.enabled = settings.voiceEnabled;
    notifyListeners();
  }

  Future<void> setVoiceEnabled(bool value) async {
    _voiceService.enabled = value;
    await _settings?.setVoiceEnabled(value);
    notifyListeners();
  }

  // ============ ИНИЦИАЛИЗАЦИЯ ============

  Future<void> initialize() async {
    await _voiceService.initialize();
    currentPosition = await _locationService.getCurrentPosition();
    notifyListeners();
    _startPositionStream();
  }

  void _startPositionStream() {
    _positionStream = _locationService.getPositionStream().listen((position) {
      currentPosition = position;
      speedKmh = position.speed * 3.6;

      if (isNavigationMode && selectedDestination != null) {
        // Автостоп при достижении цели (10 метров)
        final distance = _distanceBetween(
          position.latitude,
          position.longitude,
          selectedDestination!.location.latitude,
          selectedDestination!.location.longitude,
        );

        if (distance <= 10) {
          stopNavigation();
          return;
        }

        // Обновляем текущий манёвр
        updateCurrentStep();

        // Проверяем отклонение от маршрута
        final deviation = _distanceToRoute();
        if (deviation > 50.0) {
          print('=== ОТКЛОНЕНИЕ ОТ МАРШРУТА: ${deviation.round()} м — перестраиваем');
        }
        _rebuildRouteInNavigation();
      }

      notifyListeners();
    });
  }

  // ============ ПОИСК ============

  Future<void> search(String query) async {
    if (query.trim().length < 3) return;

    await _settings?.addToHistory(query);

    isSearching = true;
    notifyListeners();

    final userLocation = currentPosition != null
        ? ll.LatLng(currentPosition!.latitude, currentPosition!.longitude)
        : null;

    searchResults = await _geocodingService.search(
      query,
      userLocation: userLocation,
    );

    isSearching = false;
    notifyListeners();
  }

  void selectPlace(Place place) {
    selectedDestination = place;
    searchResults = [];
    notifyListeners();
  }

  // ============ МАРШРУТ ============

  Future<void> buildRoute() async {
    if (currentPosition == null || selectedDestination == null) return;

    isBuildingRoute = true;
    notifyListeners();

    final from = ll.LatLng(
      currentPosition!.latitude,
      currentPosition!.longitude,
    );
    final to = ll.LatLng(
      selectedDestination!.location.latitude,
      selectedDestination!.location.longitude,
    );

    currentRoute = await _routeService.getRoute(from, to);
    isBuildingRoute = false;
    notifyListeners();
  }

  Future<void> _rebuildRouteInNavigation() async {
    if (_isRouteRequestInProgress) return;
    if (currentPosition == null || selectedDestination == null) return;

    _isRouteRequestInProgress = true;

    try {
      final from = ll.LatLng(
        currentPosition!.latitude,
        currentPosition!.longitude,
      );
      final to = ll.LatLng(
        selectedDestination!.location.latitude,
        selectedDestination!.location.longitude,
      );

      final newRoute = await _routeService.getRoute(from, to);
      if (newRoute != null) {
        currentRoute = newRoute;
        justRebuiltRoute = true;
        notifyListeners();
      }
    } finally {
      _isRouteRequestInProgress = false;
    }
  }

  // ============ МАНЁВРЫ ============

  void updateCurrentStep() {
    if (currentRoute == null || currentRoute!.steps.isEmpty) {
      currentStep = null;
      return;
    }
    if (currentPosition == null) return;

    RouteStep? nearest;
    double nearestDistance = double.infinity;
    int nearestIndex = 0;

    for (int i = 0; i < currentRoute!.steps.length; i++) {
      final step = currentRoute!.steps[i];
      final dist = _distanceBetween(
        currentPosition!.latitude,
        currentPosition!.longitude,
        step.location.latitude,
        step.location.longitude,
      );
      if (dist < nearestDistance) {
        nearestDistance = dist;
        nearest = step;
        nearestIndex = i;
      }
    }

    if (nearest != null && nearestDistance < 30) {
      if (nearestIndex < currentRoute!.steps.length - 1) {
        nearest = currentRoute!.steps[nearestIndex + 1];
      }
    }

    if (nearest != currentStep) {
      currentStep = nearest;

      if (nearest != null && nearest.instruction != _lastSpokenInstruction) {
        _lastSpokenInstruction = nearest.instruction;
        _voiceService.speak(nearest.instruction);
      }
    }
  }

  // ============ НАВИГАЦИЯ ============

  void startNavigation() {
    isNavigationMode = true;
    _lastSpokenInstruction = null;
    updateCurrentStep();
    notifyListeners();
  }

  void stopNavigation() {
    isNavigationMode = false;
    speedKmh = null;
    currentStep = null;
    _lastSpokenInstruction = null;
    _voiceService.stop();
    justExitedNavigation = true;
    notifyListeners();
  }

  void clearRoute() {
    final wasNavigating = isNavigationMode;

    currentRoute = null;
    selectedDestination = null;
    isNavigationMode = false;
    speedKmh = null;
    currentStep = null;
    _lastSpokenInstruction = null;
    _voiceService.stop();

    if (wasNavigating) {
      justExitedNavigation = true;
    }
    notifyListeners();
  }

  // ============ УТИЛИТЫ ============

  // Расстояние до ближайшей точки маршрута
  double _distanceToRoute() {
    if (currentRoute == null || currentPosition == null) return 0;
    if (currentRoute!.points.isEmpty) return 0;

    final pos = currentPosition!;
    double minDistance = double.infinity;

    for (int i = 0; i < currentRoute!.points.length; i += 5) {
      final point = currentRoute!.points[i];
      final dist = _distanceBetween(
        pos.latitude,
        pos.longitude,
        point.latitude,
        point.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
      }
    }

    return minDistance;
  }

  double _distanceBetween(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * 3.141592653589793 / 180.0;
    final dLon = (lon2 - lon1) * 3.141592653589793 / 180.0;

    final a = (dLat / 2).abs() * (dLat / 2).abs() +
        (lat1 * 3.141592653589793 / 180.0).abs() *
            (lat2 * 3.141592653589793 / 180.0).abs() *
            (dLon / 2).abs() *
            (dLon / 2).abs();

    return earthRadius * 2 * a;
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _voiceService.stop();
    super.dispose();
  }
}