import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'map_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // Анимация карты на фоне
  Timer? _cameraTimer;
  MapLibreMapController? _bgMapController;
  int _cameraIndex = 0;

  // Точки, по которым будет двигаться камера
  static const List<Map<String, dynamic>> _cameraPositions = [
    {
      'target': LatLng(53.3532, 83.7737), // Барнаул, центр
      'zoom': 12.0,
      'bearing': 0.0,
      'tilt': 0.0,
    },
    {
      'target': LatLng(53.3474, 83.7784), // Площадь Советов
      'zoom': 15.0,
      'bearing': 45.0,
      'tilt': 40.0,
    },
    {
      'target': LatLng(53.3465, 83.7793), // Проспект Ленина
      'zoom': 14.0,
      'bearing': -30.0,
      'tilt': 30.0,
    },
    {
      'target': LatLng(53.3600, 83.7600), // Речной вокзал
      'zoom': 13.5,
      'bearing': 90.0,
      'tilt': 20.0,
    },
    {
      'target': LatLng(53.3532, 83.7737), // Возврат в центр
      'zoom': 12.0,
      'bearing': 0.0,
      'tilt': 0.0,
    },
  ];

  @override
  void initState() {
    super.initState();
    _startCameraAnimation();
  }

  @override
  void dispose() {
    _cameraTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _startCameraAnimation() {
    _cameraTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (_bgMapController == null) return;

      _cameraIndex = (_cameraIndex + 1) % _cameraPositions.length;
      final pos = _cameraPositions[_cameraIndex];

      _bgMapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: pos['target'] as LatLng,
            zoom: pos['zoom'] as double,
            bearing: pos['bearing'] as double,
            tilt: pos['tilt'] as double,
          ),
        ),
        duration: const Duration(milliseconds: 4000),
      );
    });
  }

  Future<void> _submit() async {
    print('=== SUBMIT НАЖАТ: register=$_isRegisterMode');

    setState(() => _errorMessage = null);

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    print('=== EMAIL: $email, PASSWORD LENGTH: ${password.length}');

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Заполните все поля');
      return;
    }

    if (!email.contains('@')) {
      setState(() => _errorMessage = 'Некорректный email');
      return;
    }

    if (password.length < 6) {
      setState(() => _errorMessage = 'Пароль должен быть не менее 6 символов');
      return;
    }

    if (_isRegisterMode && password != _confirmController.text) {
      setState(() => _errorMessage = 'Пароли не совпадают');
      return;
    }

    final auth = context.read<AuthService>();

    final error = _isRegisterMode
        ? await auth.register(email, password)
        : await auth.login(email, password);

    print('=== РЕЗУЛЬТАТ: error=$error, isAuth=${auth.isAuthenticated}');

    if (error != null && mounted) {
      setState(() => _errorMessage = error);
      return;
    }

    if (mounted && auth.isAuthenticated) {
      print('=== АВТОРИЗАЦИЯ УСПЕШНА, ПЕРЕХОДИМ НА КАРТУ');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MapScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    // Ограничиваем ширину формы
    final formWidth = screenWidth > 500 ? 420.0 : screenWidth - 48;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Карта на фоне
          Positioned.fill(
            child: MapLibreMap(
              onMapCreated: (controller) {
                _bgMapController = controller;
              },
              onStyleLoadedCallback: () {
                // Запускаем первую анимацию через 1 секунду
                Future.delayed(const Duration(seconds: 1), () {
                  final pos = _cameraPositions[0];
                  _bgMapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: pos['target'] as LatLng,
                        zoom: pos['zoom'] as double,
                        bearing: pos['bearing'] as double,
                        tilt: pos['tilt'] as double,
                      ),
                    ),
                    duration: const Duration(seconds: 1),
                  );
                });
              },
              initialCameraPosition: const CameraPosition(
                target: LatLng(53.3532, 83.7737),
                zoom: 12.0,
              ),
              styleString: 'https://tiles.openfreemap.org/styles/liberty',
              myLocationEnabled: false,
              myLocationTrackingMode: MyLocationTrackingMode.none,
              rotateGesturesEnabled: false,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              tiltGesturesEnabled: false,
              compassEnabled: false,
              attributionButtonPosition: AttributionButtonPosition.bottomLeft,
            ),
          ),

          // 2. Затемнение + размытие фона
          Positioned.fill(
            child: Container(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.3),
            ),
          ),

          // 3. Форма с frosted glass
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: formWidth),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ColorFilter.mode(
                      Colors.white.withValues(alpha: isDark ? 0.1 : 0.7),
                      BlendMode.srcOver,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.white.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: _buildForm(auth, isDark),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(AuthService auth, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Логотип
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade400, Colors.blue.shade700],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.map, size: 48, color: Colors.white),
        ),
        const SizedBox(height: 20),

        Text(
          _isRegisterMode ? 'Регистрация' : 'Вход',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isRegisterMode
              ? 'Создайте аккаунт для синхронизации'
              : 'Войдите, чтобы продолжить',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Email
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            labelText: 'Email',
            labelStyle: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            prefixIcon: Icon(
              Icons.email_outlined,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Пароль
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            labelText: 'Пароль',
            labelStyle: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            prefixIcon: Icon(
              Icons.lock_outline,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),

        // Подтверждение пароля
        if (_isRegisterMode) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: _obscurePassword,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Повторите пароль',
              labelStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              prefixIcon: Icon(
                Icons.lock_outline,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],

        // Ошибка
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Кнопка
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: auth.isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
            child: auth.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _isRegisterMode ? 'Зарегистрироваться' : 'Войти',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 12),

        TextButton(
          onPressed: () {
            setState(() {
              _isRegisterMode = !_isRegisterMode;
              _errorMessage = null;
            });
          },
          child: Text(
            _isRegisterMode
                ? 'Уже есть аккаунт? Войти'
                : 'Нет аккаунта? Зарегистрироваться',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.blue.shade700,
            ),
          ),
        ),
      ],
    );
  }
}