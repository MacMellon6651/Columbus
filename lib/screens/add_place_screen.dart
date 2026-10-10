import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/places_service.dart';
import '../services/place_info_service.dart';

class AddPlaceScreen extends StatefulWidget {
  const AddPlaceScreen({super.key});

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _websiteController = TextEditingController();
  final _hoursController = TextEditingController();

  String? _selectedCategory;
  bool _isLoading = false;
  bool _isFetchingAddress = false;

  LatLng? _selectedLocation;
  MapLibreMapController? _mapController;
  Symbol? _tempMarker;

  final List<XFile> _images = [];
  final ImagePicker _picker = ImagePicker();

  final PlaceInfoService _placeInfoService = PlaceInfoService();

  final List<String> _categories = [
    'Кафе', 'Ресторан', 'Магазин', 'Аптека', 'Бар',
    'Парк', 'Больница', 'Школа', 'Университет', 'Другое',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  // ============ АДРЕС ЧЕРЕЗ NOMINATIM ============

  Future<void> _fetchAddress(LatLng coords) async {
    setState(() => _isFetchingAddress = true);
    try {
      // Конвертируем maplibre_gl.LatLng → latlong2.LatLng
      final llCoords = ll.LatLng(coords.latitude, coords.longitude);
      final info = await _placeInfoService.getInfoAt(llCoords);
      if (mounted && info.address.isNotEmpty) {
        setState(() => _addressController.text = info.address);
      }
    } catch (e) {
      debugPrint('=== ОШИБКА АДРЕСА: $e');
    } finally {
      if (mounted) setState(() => _isFetchingAddress = false);
    }
  }

  // ============ ТАП ПО КАРТЕ ============

  Future<void> _onMapTap(dynamic point, LatLng coordinates) async {
    setState(() => _selectedLocation = coordinates);

    if (_tempMarker != null && _mapController != null) {
      await _mapController!.removeSymbol(_tempMarker!);
    }

    try {
      final marker = await _mapController?.addSymbol(
        SymbolOptions(
          geometry: coordinates,
          iconImage: 'destination-marker',
          iconSize: 0.15,
          iconAnchor: 'bottom',
        ),
      );
      setState(() => _tempMarker = marker);
    } catch (e) {
      debugPrint('=== ОШИБКА МАРКЕРА: $e');
    }

    await _fetchAddress(coordinates);
  }

  Future<void> _onStyleLoaded() async {
    try {
      final bytes = await rootBundle.load('assets/marker.png');
      await _mapController?.addImage(
        'destination-marker',
        bytes.buffer.asUint8List(),
      );
    } catch (e) {
      debugPrint('=== ОШИБКА ИКОНКИ: $e');
    }
  }

  // ============ КАРТИНКИ ============

  Future<void> _pickImage() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (file != null && mounted) {
        setState(() => _images.add(file));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора: $e')),
        );
      }
    }
  }

  // ============ SUBMIT ============

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тапните по карте, чтобы выбрать место')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final auth = context.read<AuthService>();
    final placesService = PlacesService(auth.api);

    try {
      // 1. Создаём/находим место
      final placeId = await placesService.findOrCreatePlace(
        name: _nameController.text.trim(),
        lat: _selectedLocation!.latitude,
        lng: _selectedLocation!.longitude,
        address: _addressController.text.trim(),
        description: _descriptionController.text.trim(),
        phone: _phoneController.text.trim(),
        website: _websiteController.text.trim(),
        openingHours: _hoursController.text.trim(),
        category: _selectedCategory,
      );

      // 2. Загружаем картинки
      if (_images.isNotEmpty) {
        final urls = <String>[];
        for (final img in _images) {
          try {
            final url = await placesService.uploadImage(img);
            if (url != null) urls.add(url);
          } catch (e) {
            debugPrint('=== ОШИБКА ЗАГРУЗКИ ФОТО: $e');
          }
        }
        if (urls.isNotEmpty) {
          await placesService.updatePlaceImages(placeId, urls);
        }
      }

      if (!mounted) return;
      Navigator.pop(context, {
        'success': true,
        'placeId': placeId,
        'name': _nameController.text.trim(),
        'lat': _selectedLocation!.latitude,
        'lng': _selectedLocation!.longitude,
        'category': _selectedCategory,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============ UI ============

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Добавить место'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Компактная карта
          Expanded(
            flex: 35,
            child: Stack(
              children: [
                MapLibreMap(
                  onMapCreated: (c) => _mapController = c,
                  onStyleLoadedCallback: _onStyleLoaded,
                  onMapClick: _onMapTap,
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(53.3532, 83.7737),
                    zoom: 14.0,
                  ),
                  styleString: 'https://tiles.openfreemap.org/styles/liberty',
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: PointerInterceptor(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.touch_app, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Тапните по карте — адрес подтянется сам',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Форма
          Expanded(
            flex: 65,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    if (_selectedLocation != null)
                      _buildStatusChip(
                        color: Colors.green,
                        icon: Icons.check_circle,
                        text:
                            '${_selectedLocation!.latitude.toStringAsFixed(5)}, '
                            '${_selectedLocation!.longitude.toStringAsFixed(5)}',
                        title: 'Место выбрано',
                      )
                    else
                      _buildStatusChip(
                        color: Colors.orange,
                        icon: Icons.warning_amber,
                        text: 'Тапните по карте, чтобы выбрать место',
                        title: null,
                      ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration(
                        label: 'Название *',
                        hint: 'Кофейня "Утро"',
                        icon: Icons.store,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Введите название'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: _inputDecoration(
                        label: 'Категория',
                        icon: Icons.category,
                      ),
                      items: _categories
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedCategory = v),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _addressController,
                      readOnly: true,
                      decoration: _inputDecoration(
                        label: 'Адрес',
                        hint: _isFetchingAddress
                            ? 'Определяем адрес...'
                            : 'Подтянется автоматически',
                        icon: _isFetchingAddress
                            ? Icons.hourglass_top
                            : Icons.location_on,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: _inputDecoration(
                        label: 'Описание',
                        hint: 'Уютная кофейня с выпечкой',
                        icon: Icons.description,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _hoursController,
                      decoration: _inputDecoration(
                        label: 'Часы работы',
                        hint: 'Пн-Пт 9:00-18:00',
                        icon: Icons.access_time,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration(
                        label: 'Телефон',
                        hint: '+7 (999) 123-45-67',
                        icon: Icons.phone,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _websiteController,
                      keyboardType: TextInputType.url,
                      decoration: _inputDecoration(
                        label: 'Сайт',
                        hint: 'https://example.com',
                        icon: Icons.language,
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildImagesSection(theme),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Добавить место',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon) : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  Widget _buildStatusChip({
    required Color color,
    required IconData icon,
    required String text,
    String? title,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                Text(
                  text,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagesSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.photo_library,
                color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Фотографии',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '${_images.length}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap: _isLoading ? null : _pickImage,
                child: Container(
                  width: 100,
                  height: 100,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 4),
                      const Text('Добавить',
                          style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
              ..._images.asMap().entries.map((entry) {
                final i = entry.key;
                final img = entry.value;
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(
                          image: kIsWeb
                              ? NetworkImage(img.path) as ImageProvider
                              : FileImage(File(img.path)),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 14,
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _images.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}