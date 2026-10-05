import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../view_models/map_view_model.dart';
import '../services/route_service.dart';
import '../services/settings_service.dart';
import '../services/favorites_service.dart';
import '../services/place_info_service.dart';
import '../models/place.dart';
import '../models/favorite_place.dart';

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

  Line? _routeLine;
  Symbol? _destinationSymbol;

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
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
    _updateMapFromViewModel();

    // Показываем SnackBar при перестроении маршрута
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
        iconSize: 0.3,
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
  }

  // ============ КАРТА ============

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    try {
      final bytes = await rootBundle.load('assets/marker.png');
      await _mapController?.addImage(
        'destination-marker',
        bytes.buffer.asUint8List(),
      );
      print('=== ИКОНКА МАРКЕРА ЗАГРУЖЕНА');
    } catch (e) {
      print('=== ОШИБКА ЗАГРУЗКИ ИКОНКИ: $e');
    }

    final pos = _viewModel.currentPosition;
    if (pos != null) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(pos.latitude, pos.longitude),
        16.0,
      ));
    }
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

  // ============ ТАП ПО КАРТЕ ============

  Future<void> _onMapTap(dynamic point, LatLng coordinates) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    final info = await _placeInfoService.getInfoAt(
      ll.LatLng(coordinates.latitude, coordinates.longitude),
    );

    if (mounted) Navigator.pop(context);

    if (mounted) {
      _showPlaceInfoBottomSheet(info, coordinates);
    }
  }

  void _showPlaceInfoBottomSheet(PlaceInfo info, LatLng coords) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.blue, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        info.address,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Text(
                  '${coords.latitude.toStringAsFixed(5)}, ${coords.longitude.toStringAsFixed(5)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                if (info.pois.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Заведений рядом не найдено',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Text(
                    'Заведения рядом (${info.pois.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: Material(
                      color: Colors.transparent,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: info.pois.length,
                        itemBuilder: (context, index) {
                          final poi = info.pois[index];
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.place,
                                color: Colors.blue,
                                size: 20,
                              ),
                            ),
                            title: Text(poi.name),
                            subtitle: Text(
                              poi.type,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _buildRouteToPoi(poi);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _buildRouteToPoi(PoiItem poi) {
    final place = Place(
      displayName: poi.name,
      location: ll.LatLng(poi.lat, poi.lng),
    );

    _viewModel.selectPlace(place);
    _searchController.text = poi.name;

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
      LatLng(poi.lat, poi.lng),
      18.0,
    ));

    _viewModel.buildRoute();
  }

  // ============ ПОИСК ============

  void _performSearch() {
    FocusScope.of(context).unfocus();
    _viewModel.search(_searchController.text);
  }

  void _onPlaceSelected(Place place) {
    _viewModel.selectPlace(place);
    _searchController.text = place.displayName;

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
      builder: (context) => const _SettingsPanel(),
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
      builder: (context) => _FavoritesPanel(
        onSelect: (fav) => _buildRouteToFavorite(fav),
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
            onMapClick: _onMapTap,
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
          ),

          if (!vm.isNavigationMode)
            Positioned(
              top: 50,
              left: 70,
              right: 16,
              child: Column(
                children: [
                  _buildSearchBar(),
                  if (vm.searchResults.isNotEmpty) _buildSearchResults(),
                ],
              ),
            ),

          Positioned(
            top: 50,
            left: 16,
            child: _MapButton(
              icon: Icons.settings,
              onPressed: _openSettings,
            ),
          ),

          if (!vm.isNavigationMode)
            Positioned(
              top: 120,
              left: 16,
              child: _MapButton(
                icon: Icons.star,
                onPressed: _openFavorites,
                backgroundColor: Colors.amber,
                iconColor: Colors.white,
              ),
            ),

          if (vm.isNavigationMode && vm.speedKmh != null)
            Positioned(
              top: 50,
              right: 16,
              child: _buildSpeedDisplay(vm.speedKmh!),
            ),

          if (vm.isNavigationMode && vm.currentStep != null)
            Positioned(
              top: 50,
              left: 16,
              right: 110,
              child: _buildManeuverBanner(vm.currentStep!),
            ),

          Positioned(
            right: 16,
            bottom: vm.selectedDestination != null ? 220 : 100,
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

          if (vm.selectedDestination != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildRoutePanel(),
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

class _MapButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shape: const CircleBorder(),
      color: backgroundColor ?? Theme.of(context).colorScheme.surface,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            icon,
            color: iconColor ?? Theme.of(context).colorScheme.onSurface,
            size: 26,
          ),
        ),
      ),
    );
  }
}

// ============ ПАНЕЛЬ НАСТРОЕК ============

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

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