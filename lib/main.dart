import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestEntry, BoxHitTestResult;
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'clima_service.dart';
import 'ma_analysis/segmentacion_clasificacion_screen.dart';

IconData weatherIcon(int? code) {
  if (code == null) return Icons.wb_sunny_rounded;
  if (code >= 95) return Icons.flash_on_rounded;
  if (code >= 71) return Icons.ac_unit_rounded;
  if (code >= 51) return Icons.water_drop_rounded;
  if (code >= 45) return Icons.foggy;
  if (code >= 1) return Icons.cloud_rounded;
  return Icons.wb_sunny_rounded;
}

class _GuiaCamposData {
  final IconData icon;
  final String titulo;
  final String texto;
  final String ejemplo;
  final String? consejo;
  const _GuiaCamposData(this.icon, this.titulo, this.texto, this.ejemplo, [this.consejo]);
}

void main() {
  runApp(const MicoTaxApp());
}

class MicoTaxApp extends StatelessWidget {
  const MicoTaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MicoTax',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B57D0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1D1D1F),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0B57D0),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          side: BorderSide(color: Colors.white.withOpacity(0.35)),
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          backgroundColor: const Color(0xFFDCE8FF),
          selectedColor: const Color(0xFFDCE8FF),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
   const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _splashLogoPath = 'logo/LOGO HORIZONTAL.png';
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _logoRotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
    ));

    _logoRotation = Tween<double>(
      begin: -0.1,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _controller.forward();
  }

  void _irAlMenuPrincipal() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  Future<void> _onSiguienteTap() async {
    final yaTienePermiso = await Permission.location.isGranted;
    if (yaTienePermiso) {
      _irAlMenuPrincipal();
      return;
    }

    final theme = Theme.of(context);
    final quierenPermiso = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubicación para el clima'),
        content: const Text(
          'Para que el apartado de clima muestre el tiempo en tu ubicación, '
          'MicoTax necesita acceso a la ubicación.\n\n¿Permitir acceso?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Permitir'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (quierenPermiso == true) {
      final status = await Permission.location.request();
      if (!mounted) return;
      if (status.isGranted) {
        final serv = await Geolocator.isLocationServiceEnabled();
        if (!serv && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Activa la ubicación en tu dispositivo para ver el clima en tu zona.',
              ),
              backgroundColor: theme.colorScheme.errorContainer,
            ),
          );
        }
      }
    }
    _irAlMenuPrincipal();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surface,
              theme.colorScheme.primaryContainer.withOpacity(0.3),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          _splashLogoPath,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Sistema de predicción de especies de hongos micorrízicos',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: theme.colorScheme.onSurface.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _onSiguienteTap,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                      child: const Text('Siguiente'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  Map<String, dynamic>? _climaData;
  bool _climaLoading = true;
  bool _climaCargandoParaUbicacion = false;
  bool _climaSinUbicacion = false;
  String? _climaError;
  Timer? _climaRefreshTimer;

  final List<GlobalKey> _featureCardKeys = List.generate(5, (_) => GlobalKey());
  bool _guiaTarjetasActiva = false;
  int _guiaTarjetasIndice = 0;
  Rect? _guiaCardBounds;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
    _cargarClima();
    _climaRefreshTimer = Timer.periodic(const Duration(minutes: 2), (_) => _cargarClima());
  }

  Future<void> _cargarClima() async {
    final usaUbicacion = await Permission.location.isGranted;
    if (mounted) {
      setState(() {
        _climaLoading = true;
        _climaError = null;
        _climaSinUbicacion = false;
        _climaCargandoParaUbicacion = usaUbicacion;
      });
    }
    double? lat;
    double? lon;
    String? nombreLugar;
    if (usaUbicacion) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        );
        lat = pos.latitude;
        lon = pos.longitude;
        try {
          final placemarks = await placemarkFromCoordinates(lat!, lon!);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            final partes = <String>[
              if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
              if (p.subAdministrativeArea != null && p.subAdministrativeArea!.isNotEmpty) p.subAdministrativeArea!,
              if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) p.administrativeArea!,
              if (p.country != null && p.country!.isNotEmpty) p.country!,
            ];
            if (partes.isNotEmpty) {
              nombreLugar = partes.join(', ');
            }
          }
        } catch (_) {
        }
      } catch (_) {
      }
    }
    if (lat == null || lon == null) {
      if (mounted) setState(() {
        _climaData = null;
        _climaLoading = false;
        _climaSinUbicacion = true;
      });
      return;
    }
    try {
      final data = await ClimaService.getClimaActual(
        lat: lat,
        lon: lon,
        locationName: nombreLugar,
      );
      if (mounted) setState(() {
        _climaData = data;
        _climaLoading = false;
        _climaSinUbicacion = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _climaError = e.toString().replaceAll('Exception: ', '');
        _climaLoading = false;
      });
    }
  }

  void _onClimaTap(BuildContext context, ThemeData theme) {
    if (_climaError != null) {
      _cargarClima();
      return;
    }
    if (_climaLoading || _climaData == null) {
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClimaDetalleSheet(
        theme: theme,
        climaActual: _climaData!,
      ),
    );
  }

  void _onMenuPrincipalSeleccionado(BuildContext context, ThemeData theme, String value) {
    switch (value) {
      case 'objetivo':
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Objetivo de la aplicación'),
            content: const SingleChildScrollView(
              child: Text(
                'MicoTax tiene como objetivo apoyar la identificación de especies de hongos micorrízicos '
                'a partir de características observables de sus esporas (tamaño, forma, color, paredes, '
                'textura, reacción con Melzer, etc.).\n\n'
                'La aplicación permite registrar los rasgos del espécimen y obtener una predicción de la especie '
                'más probable, junto con información sobre hábitat, vegetación asociada y localidades, '
                'para uso en campo, docencia o investigación.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        break;
      case 'gracias':
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Gracias'),
            content: const SingleChildScrollView(
              child: Text(
                'Gracias por usar MicoTax.\n\n'
                'Tu feedback y uso de la aplicación ayudan a mejorar la identificación de hongos micorrízicos '
                'y a divulgar el conocimiento sobre la micorriza.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
        break;
      case 'acerca':
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Acerca de'),
            content: const SingleChildScrollView(
              child: Text(
                'MicoTax\n'
                'Sistema de predicción de especies de hongos micorrízicos.\n\n'
                'Versión 1.0.0',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
        break;
    }
  }

  static const List<Map<String, dynamic>> _tarjetasMenuGuia = [
    {
      'title': 'Segmentación y clasificación',
      'icon': Icons.photo_camera_back_rounded,
      'description': 'Módulo central para análisis por imagen. Permite captura directa o carga desde galería, '
          'segmentación por umbral y clasificación preliminar de la muestra con reporte de confianza.',
    },
    {
      'title': 'Predecir especie',
      'icon': Icons.science_rounded,
      'description': 'Introduce las características de la espora que observas (tamaño, forma, color, '
          'número de paredes, reacción con Melzer, conexión hifal y textura). MicoTax te dará una '
          'predicción de la especie más probable y opciones alternativas, con información sobre hábitat '
          'y localidades. Ideal para identificar ejemplares en campo o en el laboratorio.',
    },
    {
      'title': 'Guía de campos',
      'icon': Icons.menu_book_rounded,
      'description': 'Consulta una guía detallada de cada campo del formulario de predicción: qué significa, '
          'cómo medir o observar (tamaño, forma, color, paredes, Melzer, conexión, textura) y ejemplos prácticos. '
          'Te ayuda a rellenar correctamente los datos para obtener una predicción más precisa.',
    },
    {
      'title': 'Sobre micorrizas',
      'icon': Icons.eco_rounded,
      'description': 'Conoce qué son los hongos micorrízicos, su importancia en los ecosistemas y en la agricultura, '
          'y cómo se relacionan con las plantas. Incluye información sobre esporas, identificación y recursos '
          'para profundizar en el tema.',
    },
    {
      'title': 'Familias',
      'icon': Icons.biotech_rounded,
      'description': 'Explora las familias de hongos micorrízicos (por ejemplo Glomeraceae, Acaulosporaceae). '
          'Cada familia agrupa géneros y especies con características comunes. Útil para situar tu espécimen '
          'en el contexto taxonómico y ver relaciones entre grupos.',
    },
  ];

  void _showGuiaTarjetasMenu(BuildContext context, ThemeData theme) {
    setState(() {
      _guiaTarjetasActiva = true;
      _guiaTarjetasIndice = 0;
      _guiaCardBounds = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _actualizarGuiaCardBounds());
  }

  void _actualizarGuiaCardBounds() {
    if (!mounted || !_guiaTarjetasActiva || _guiaTarjetasIndice >= _featureCardKeys.length) return;
    final key = _featureCardKeys[_guiaTarjetasIndice];
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && mounted) {
      final bounds = box.localToGlobal(Offset.zero) & box.size;
      setState(() => _guiaCardBounds = bounds);
    }
  }

  void _avanzarGuiaTarjetas() {
    if (_guiaTarjetasIndice < _tarjetasMenuGuia.length - 1) {
      setState(() {
        _guiaTarjetasIndice++;
        _guiaCardBounds = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _actualizarGuiaCardBounds());
    } else {
      setState(() {
        _guiaTarjetasActiva = false;
        _guiaCardBounds = null;
      });
    }
  }

  void _abrirSegmentacionPrincipal(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SegmentacionClasificacionScreen(),
      ),
    );
  }

  Widget _buildSegmentacionPrincipalCard(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF312E81)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _abrirSegmentacionPrincipal(context),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.psychology_alt_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Módulo principal de tesis',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'v1',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Segmentación y clasificación de micorrizas arbusculares',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Captura o carga una imagen, ejecuta segmentación preliminar y obtiene una clasificación orientativa con indicadores cuantitativos.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildHeroBadge('Foto / Galería'),
                    _buildHeroBadge('Segmentación por umbral'),
                    _buildHeroBadge('Reporte técnico'),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1E3A8A),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _abrirSegmentacionPrincipal(context),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Iniciar análisis de imagen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDiagnosticoHeroCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDDF5F2), Color(0xFFCBECE8)],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.document_scanner_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Ver diagnóstico',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _abrirSegmentacionPrincipal(context),
            child: const Text('Tomar una foto'),
          ),
        ],
      ),
    );
  }

  Widget _buildCondicionesResumenStrip(ThemeData theme) {
    final temp = (_climaData?['temp'] as double?)?.round();
    final estadoClima = (_climaData?['weather_name'] as String?) ?? 'Condición estable';
    final humedad = _climaData?['humidity'] as int?;
    final estadoPulv = humedad == null
        ? 'Moderado'
        : (humedad >= 75 ? 'No recomendado' : (humedad >= 55 ? 'Moderado' : 'Favorable'));

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 360;
        final tarjetaClima = Container(
          height: 116,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFC7D8FF), width: 1.4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${DateTime.now().day} ${_mesCorto(DateTime.now().month)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      temp == null ? '— °C' : '$temp °C',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 31,
                        fontWeight: FontWeight.w700,
                        height: 0.95,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    weatherIcon(_climaData?['weather_code'] as int?),
                    size: 24,
                    color: const Color(0xFFF1C40F),
                  ),
                ],
              ),
            ],
          ),
        );
        final tarjetaCondicion = Container(
          height: 116,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8DFC3), width: 1.4),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Condiciones de análisis',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.12,
                        color: theme.colorScheme.onSurface.withOpacity(0.76),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          estadoPulv,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            height: 0.95,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      estadoClima,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withOpacity(0.58),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'hasta 5 p. m.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.72),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFDDF5F2),
            borderRadius: BorderRadius.circular(18),
          ),
          child: compacto
              ? Column(
                  children: [
                    tarjetaClima,
                    const SizedBox(height: 8),
                    tarjetaCondicion,
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 32, child: tarjetaClima),
                    const SizedBox(width: 8),
                    Expanded(flex: 58, child: tarjetaCondicion),
                  ],
                ),
        );
      },
    );
  }

  String _mesCorto(int mes) {
    const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    if (mes < 1 || mes > 12) return '—';
    return meses[mes - 1];
  }

  Widget _buildClimaCard(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onClimaTap(context, theme),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withOpacity(0.22),
                  theme.colorScheme.primary.withOpacity(0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.thermostat_rounded,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _climaData?['location'] ??
                                (_climaLoading ? 'Tu ubicación' : (_climaSinUbicacion ? 'Clima' : 'Clima en tiempo real')),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'En tiempo real',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_climaLoading)
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    else if (_climaError != null)
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: _cargarClima,
                        color: theme.colorScheme.primary,
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: _cargarClima,
                        color: theme.colorScheme.primary.withOpacity(0.8),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_climaLoading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Cargando datos para tu ubicación...',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  )
                else if (_climaSinUbicacion)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_off_rounded,
                            size: 40,
                            color: theme.colorScheme.primary.withOpacity(0.7),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Activa la ubicación para ver el clima en tu zona',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface.withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => openAppSettings(),
                            icon: const Icon(Icons.settings_rounded, size: 18),
                            label: const Text('Abrir configuración'),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_climaError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 22, color: theme.colorScheme.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _climaError!,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_climaData != null)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final d = _climaData!;
                      final temp = d['temp'] as double?;
                      final feels = d['feels_like'] as double?;
                      final humidity = d['humidity'] as int?;
                      final precip = (d['precipitation'] as num?)?.toDouble() ?? 0;
                      final weatherName = d['weather_name'] as String? ?? '—';
                      final code = d['weather_code'] as int?;
                      final sueloNivel = d['suelo_nivel'] as String? ?? '—';
                      final sueloDesc = d['suelo_desc'] as String? ?? '';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  weatherIcon(code),
                                  size: 36,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    temp != null ? '${temp.round()}°C' : '—',
                                    style: TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  Text(
                                    weatherName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  if (feels != null)
                                    Text(
                                      'Sensación ${feels.round()}°C',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: _buildClimaChip(
                                  theme,
                                  Icons.water_drop_rounded,
                                  'Humedad del aire',
                                  humidity != null ? '$humidity%' : '—',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildClimaChip(
                                  theme,
                                  Icons.grass_rounded,
                                  'Humedad del suelo',
                                  sueloNivel,
                                  sub: sueloDesc,
                                ),
                              ),
                            ],
                          ),
                          if (precip > 0) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.water_drop_rounded,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Precipitación (esta hora): ${precip.toStringAsFixed(1)} mm',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClimaChip(ThemeData theme, IconData icon, String label, String value, {String? sub}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (sub != null && sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _climaRefreshTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _mostrarDialogoSalir(BuildContext context) async {
    final salir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir'),
        content: const Text('¿Quieres salir de la aplicación?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    return salir == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final quiereSalir = await _mostrarDialogoSalir(context);
        if (quiereSalir && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0B57D0),
        foregroundColor: Colors.white,
        onPressed: () => _abrirSegmentacionPrincipal(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.eco_outlined), selectedIcon: Icon(Icons.eco), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Comunidad'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
              child: CustomScrollView(
                  slivers: [
                SliverAppBar(
                  expandedHeight: 56,
                  floating: false,
                  pinned: true,
                  backgroundColor: Colors.white,
                  elevation: 0,
                  actions: [
                    TextButton(
                      onPressed: () => _showGuiaTarjetasMenu(context, theme),
                      child: Text(
                        'Muéstrame',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        color: theme.colorScheme.onSurface,
                      ),
                      color: theme.colorScheme.surface,
                      onSelected: (value) => _onMenuPrincipalSeleccionado(context, theme, value),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'objetivo',
                          child: ListTile(
                            leading: Icon(Icons.flag_rounded, size: 22),
                            title: Text('Objetivo de la aplicación'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'gracias',
                          child: ListTile(
                            leading: Icon(Icons.favorite_rounded, size: 22),
                            title: Text('Gracias'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'acerca',
                          child: ListTile(
                            leading: Icon(Icons.info_outline_rounded, size: 22),
                            title: Text('Acerca de'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.eco,
                          color: const Color(0xFF2E7D32),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'MicoTax',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    titlePadding: const EdgeInsets.only(left: 16, bottom: 12),
                    centerTitle: false,
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildDiagnosticoHeroCard(theme),
                      const SizedBox(height: 12),
                      _buildCondicionesResumenStrip(theme),
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Herramientas',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Módulos de soporte para el análisis de MA',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                      _buildFeaturesGrid(context, theme),
                      const SizedBox(height: 24),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ...(_guiaTarjetasActiva
            ? [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _avanzarGuiaTarjetas,
                    behavior: HitTestBehavior.opaque,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _OverlayGuiaPainter(
                              cardRect: _guiaCardBounds,
                              dimColor: Colors.black.withOpacity(0.52),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          top: 80,
                          child: _buildGuiaTarjetasDescripcionBox(theme),
                        ),
                      ],
                    ),
                  ),
                ),
              ]
            : []),
        ],
      ),
    ));
  }

  Widget _buildGuiaTarjetasDescripcionBox(ThemeData theme) {
    if (_guiaTarjetasIndice >= _tarjetasMenuGuia.length) return const SizedBox.shrink();
    final t = _tarjetasMenuGuia[_guiaTarjetasIndice];
    final title = t['title'] as String;
    final description = t['description'] as String;
    final esUltima = _guiaTarjetasIndice == _tarjetasMenuGuia.length - 1;
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surface.withOpacity(0.94),
      elevation: 8,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.88),
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              esUltima ? 'Toque en cualquier lugar para cerrar' : 'Toque en cualquier lugar para continuar',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color,
              color.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesGrid(BuildContext context, ThemeData theme) {
    final features = [
      {
        'icon': Icons.photo_camera_back_rounded,
        'title': 'Segmentar imagen',
        'description': 'Módulo principal',
        'color': Colors.indigo,
      },
      {
        'icon': Icons.science_rounded,
        'title': 'Predecir especie',
        'description': 'Identificar hongo micorrízico',
        'color': const Color(0xFF2E7D32),
        'imagePath': 'imagenes/icono 1.png',
      },
      {
        'icon': Icons.menu_book_rounded,
        'title': 'Guía de campos',
        'description': 'Forma, color, textura y más',
        'color': Colors.orange,
      },
      {
        'icon': Icons.eco_rounded,
        'title': 'Sobre micorrizas',
        'description': 'Qué son y su importancia',
        'color': Colors.purple,
      },
      {
        'icon': Icons.biotech_rounded,
        'title': 'Familias',
        'description': 'Familias de micorrizas',
        'color': Colors.teal,
      },
    ];

    final onTaps = [
      () => _abrirSegmentacionPrincipal(context),
      () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PredictionFormScreen(),
            ),
          ),
      () => _showGuiaCampos(context, theme),
      () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SobreMicorrizasScreen(theme: theme),
            ),
          ),
      () => _showFamilias(context, theme),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: features.length,
      itemBuilder: (context, index) {
        final feature = features[index];
        return RepaintBoundary(
          key: _featureCardKeys[index],
          child: _buildFeatureGridCard(
            context: context,
            theme: theme,
            icon: feature['icon'] as IconData,
            title: feature['title'] as String,
            description: feature['description'] as String,
            color: feature['color'] as Color,
            onTap: onTaps[index],
            imagePath: feature['imagePath'] as String?,
          ),
        );
      },
    );
  }

  void _showGuiaCampos(BuildContext context, ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final guiaItems = [
      _GuiaCamposData(
        Icons.straighten_rounded,
        'Tamaño de la espora',
        'El tamaño es uno de los caracteres más útiles para identificar especies de Glomeromycota. Debes medir el diámetro (o eje largo y corto si no es esférica) en micrómetros (µm). En el formulario se pide un rango: valor mínimo y máximo; opcionalmente puedes indicar un promedio. Es recomendable medir al menos 20–30 esporas por muestra para obtener un rango representativo. El tamaño varía entre especies: desde menos de 50 µm hasta más de 500 µm en algunas Gigasporaceae.',
        'Ej: 60-140 µm',
        'Mide varias esporas y anota el mínimo y el máximo; el promedio ayuda a refinar la predicción.',
      ),
      _GuiaCamposData(
        Icons.shape_line_rounded,
        'Forma',
        'La forma de la espora es un carácter morfológico clave. Las opciones más habituales son: globosa (esférica), subglobosa (casi esférica), ovoide, elipsoide, piriforme (en forma de pera), clavada, cilíndrica o irregular. Observa la espora bajo el microscopio en diferentes orientaciones para no confundir una espora ovoide vista de frente con una subglobosa. Algunos géneros tienen formas típicas (por ejemplo, muchas Acaulospora son elipsoides).',
        'Ej: globosa, subglobosa',
        'Si la espora no es perfectamente redonda, indica la forma que más se aproxime (ovoide, elipsoide, etc.).',
      ),
      _GuiaCamposData(
        Icons.palette_rounded,
        'Color',
        'El color de la espora se observa en fresco o en preparaciones montadas. Los términos estándar usados en la literatura incluyen: amarillo, ámbar, blanco, crema, dorado, gris, hialino (transparente), marrón (claro a oscuro), miel, naranja, negro, ocre, rojo y verdoso. El color puede cambiar con la madurez o con reactivos (por ejemplo Melzer). Anota el color predominante de la pared o del contenido si es visible.',
        'Ej: amarillo, marrón',
        'Usa luz transmitida y anota el color de la pared esporal; evita describir solo el contenido interno.',
      ),
      _GuiaCamposData(
        Icons.layers_rounded,
        'Número de paredes',
        'Las esporas de Glomeromycota pueden tener una o varias capas en la pared (paredes). Se cuentan como 1 a 6 paredes según el número de capas distinguibles. La estructura de la pared (grosor, color, reacción a Melzer) suele ser característica de género o especie. Es importante cortar o romper esporas para ver las capas internas si no son visibles desde fuera.',
        'Ej: 2 paredes',
        'Observa cortes o esporas rotas para contar correctamente las capas; una sola vista externa puede inducir a error.',
      ),
      _GuiaCamposData(
        Icons.science_rounded,
        'Reacción con Melzer',
        'El reactivo de Melzer (yodo + yoduro de potasio) se usa para detectar reacciones de las paredes esporales. Las opciones típicas son: negativo (no cambia de color), positivo (azulación o coloración oscura), ninguna (no aplica o no observado), paredes internas (solo algunas capas reaccionan) y sin reporte. La reacción positiva es diagnóstica en muchos Glomus y Acaulospora; en otros géneros es negativo.',
        'Ej: negativo',
        'Aplica Melzer según protocolo estándar; anota si la reacción es en toda la pared o solo en capas internas.',
      ),
      _GuiaCamposData(
        Icons.account_tree_rounded,
        'Conexión hifal',
        'Describe cómo la espora se une a la hifa: tipo de estructura (hifa suspensora, pedicelo, etc.), forma de la unión, presencia de septo o poro en la base, y cualquier detalle extra (constricción, engrosamiento). Este carácter es muy útil para separar géneros: por ejemplo, Acaulospora forma esporas en el cuello de una vesícula; Glomus suele tener una hifa suspensora directa.',
        'Ej: hifa suspensora',
        'Incluye si hay septo, poro abierto o cerrado, y si la base es lisa o ornamentada.',
      ),
      _GuiaCamposData(
        Icons.texture_rounded,
        'Textura',
        'La textura engloba la superficie (lisa, verrugosa, espinosa), la estructura de la pared (compacta, laminada), la consistencia (frágil, dura) y la ornamentación (verrugas, espinas, crestas). Estos caracteres se observan con objetivos de mayor aumento (40x, 100x). La ornamentación es clave en muchos géneros (por ejemplo Scutellospora, Diversispora).',
        'Ej: lisa, verrugosa',
        'Describe tanto la superficie externa como la estructura interna si es visible en corte.',
      ),
    ];

    final chipColors = [
      const Color(0xFF81C784),
      const Color(0xFF64B5F6),
      const Color(0xFFBA68C8),
      const Color(0xFFFFB74D),
      const Color(0xFF4DB6AC),
      const Color(0xFFF06292),
      const Color(0xFF90A4AE),
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuiaDeCamposScreen(
          theme: theme,
          primary: primary,
          guiaItems: guiaItems,
          chipColors: chipColors,
          buildCard: (ctx, data, color) => _buildGuiaCamposCard(ctx, theme, data, color, primary),
        ),
      ),
    );
  }

  static List<String> _guiaCamposImagePaths(String titulo) {
    const extensiones = ['.png', '.jpg', '.jpeg', '.webp'];
    final bases = <String>[];
    switch (titulo) {
      case 'Tamaño de la espora':
        bases.addAll(['tamaño_espora', 'tamaño de la espora', 'Tamaño de la espora', 'tamano_espora']);
        break;
      case 'Forma':
        bases.addAll(['Forma', 'forma', 'forma_espora', 'forma espora', 'Forma de la espora', 'forma de la espora']);
        break;
      case 'Color':
        bases.addAll(['color', 'color_espora', 'Color']);
        break;
      case 'Número de paredes':
        bases.addAll(['paredes_espora', 'número de paredes', 'numero_de_paredes', 'Número de paredes']);
        break;
      case 'Reacción con Melzer':
        bases.addAll(['reaccion_melzer_espora', 'reacción con melzer', 'Reacción con Melzer']);
        break;
      case 'Conexión hifal':
        bases.addAll(['conexion_hifal_espora', 'conexión hifal', 'Conexión hifal']);
        break;
      case 'Textura':
        bases.addAll(['textura_espora_micorriza', 'textura', 'Textura']);
        break;
      default:
        final limpio = titulo.toLowerCase().replaceAll(' ', '_');
        bases.addAll([titulo, limpio, titulo.replaceAll(' ', '_')]);
    }
    final paths = <String>[];
    for (final base in bases) {
      for (final ext in extensiones) {
        paths.add('imagenes/$base$ext');
      }
    }
    return paths;
  }

  Widget _buildGuiaCamposImage(BuildContext context, String titulo) {
    final paths = _guiaCamposImagePaths(titulo);
    return _tryLoadGuiaImage(context, paths, 0);
  }

  Widget _tryLoadGuiaImage(BuildContext context, List<String> paths, int index) {
    if (index >= paths.length) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        paths[index],
        width: double.infinity,
        fit: BoxFit.contain,
        height: 200,
        errorBuilder: (_, __, ___) => _tryLoadGuiaImage(context, paths, index + 1),
      ),
    );
  }

  void _showDialogGuiaCampo(BuildContext context, ThemeData theme, _GuiaCamposData data, Color chipColor) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withOpacity(0.2),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      chipColor,
                      chipColor.withOpacity(0.85),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(data.icon, size: 24, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            data.titulo,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: chipColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          data.ejemplo,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: chipColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildGuiaCamposImage(ctx, data.titulo),
                      const SizedBox(height: 16),
                      Text(
                        'Descripción',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: chipColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data.texto,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: theme.colorScheme.onSurface.withOpacity(0.9),
                        ),
                      ),
                      if (data.consejo != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: chipColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: chipColor.withOpacity(0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lightbulb_outline_rounded, size: 20, color: chipColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Consejo',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: chipColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      data.consejo!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: theme.colorScheme.onSurface.withOpacity(0.85),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('Cerrar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: chipColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuiaCamposCard(BuildContext context, ThemeData theme, _GuiaCamposData data, Color chipColor, Color primaryColor) {
    final descripcionCorta = data.texto.length > 70 ? '${data.texto.substring(0, 70)}...' : data.texto;
    
    return Card(
      elevation: 3,
      shadowColor: theme.colorScheme.shadow.withOpacity(0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDialogGuiaCampo(context, theme, data, chipColor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 90,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    chipColor.withOpacity(0.3),
                    chipColor.withOpacity(0.15),
                  ],
                ),
              ),
              child: Center(
                child: Icon(
                  data.icon,
                  size: 42,
                  color: chipColor.withOpacity(0.8),
                ),
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: chipColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        data.ejemplo,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: chipColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data.titulo,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: Text(
                        descripcionCorta,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Leer más',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: chipColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: chipColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFamiliasDetalle(BuildContext context, ThemeData theme, String nombreFamilia, String descripcion, List<String> especies) {
    final primary = theme.colorScheme.primary;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withOpacity(0.18),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primary,
                      primary.withOpacity(0.88),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.eco_rounded, size: 24, color: theme.colorScheme.onPrimary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombreFamilia,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            descripcion,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onPrimary.withOpacity(0.95),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Row(
                  children: [
                    Icon(Icons.list_rounded, size: 18, color: primary),
                    const SizedBox(width: 8),
                    Text(
                      'Especies conocidas · toca para más información',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: especies.length,
                  itemBuilder: (context, index) {
                    final especie = especies[index];
                    return Card(
                      elevation: 2,
                      shadowColor: theme.colorScheme.shadow.withOpacity(0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _showDialogEspecie(context, theme, especie, nombreFamilia),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  primary.withOpacity(0.1),
                                  primary.withOpacity(0.05),
                                ],
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.eco_rounded,
                                    size: 32,
                                    color: primary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  especie,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                    fontStyle: especie.endsWith('spp.') ? FontStyle.italic : FontStyle.normal,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Icon(
                                  Icons.touch_app_rounded,
                                  size: 16,
                                  color: primary.withOpacity(0.6),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Map<String, String> _infoEspecieCompleta(String especie, String familia) {
    const info = <String, Map<String, String>>{
      'Glomus intraradices': {
        'descripcion': 'Una de las especies más utilizadas en inoculantes comerciales. Forma esporas globosas a subglobosas. Muy común en suelos agrícolas y de invernadero.',
        'tamano': '60-140 µm',
        'forma': 'Globosa a subglobosa',
        'color': 'Amarillo a marrón claro',
        'paredes': '2-3 paredes',
        'habitat': 'Suelos agrícolas, invernaderos, pastizales',
        'uso': 'Inoculante comercial, mejora crecimiento de cultivos',
      },
      'Glomus mosseae': {
        'descripcion': 'Especie cosmopolita y muy estudiada. Esporas grandes, amarillentas. Importante en simbiosis con múltiples cultivos agrícolas.',
        'tamano': '120-200 µm',
        'forma': 'Globosa',
        'color': 'Amarillo a ámbar',
        'paredes': '2 paredes',
        'habitat': 'Suelos agrícolas, praderas, bosques',
        'uso': 'Inoculante, investigación, agricultura sostenible',
      },
      'Glomus aggregatum': {
        'descripcion': 'Esporas de forma irregular. Asociada a raíces de múltiples plantas hospederas. Común en suelos naturales.',
        'tamano': '80-150 µm',
        'forma': 'Irregular, subglobosa',
        'color': 'Marrón claro a marrón',
        'paredes': '2 paredes',
        'habitat': 'Suelos naturales, bosques, pastizales',
        'uso': 'Restauración de suelos, ecosistemas naturales',
      },
      'Septoglomus constrictum': {
        'descripcion': 'Esporas con septo distintivo en la base de la hifa. Común en ecosistemas templados y suelos agrícolas.',
        'tamano': '90-160 µm',
        'forma': 'Globosa a subglobosa',
        'color': 'Marrón claro',
        'paredes': '2 paredes',
        'habitat': 'Ecosistemas templados, suelos agrícolas',
        'uso': 'Estudios ecológicos, inoculación',
      },
      'Funneliformis caledonius': {
        'descripcion': 'Antes clasificada como Glomus caledonium. Esporas globosas. Amplia distribución geográfica. Importante en asociaciones micorrízicas.',
        'tamano': '100-180 µm',
        'forma': 'Globosa',
        'color': 'Amarillo a marrón',
        'paredes': '2 paredes',
        'habitat': 'Amplia distribución, suelos diversos',
        'uso': 'Investigación, inoculación',
      },
      'Acaulospora laevis': {
        'descripcion': 'Esporas lisas, formadas lateralmente en el cuello de una vesícula. Muy utilizada en estudios de inoculación y producción comercial.',
        'tamano': '120-200 µm',
        'forma': 'Elipsoide a subglobosa',
        'color': 'Blanco a crema',
        'paredes': '2-3 paredes',
        'habitat': 'Suelos agrícolas, pastizales',
        'uso': 'Inoculante comercial, investigación',
      },
      'Acaulospora scrobiculata': {
        'descripcion': 'Esporas con ornamentación distintiva tipo "scrobículas" en la superficie. Carácter diagnóstico importante para identificación.',
        'tamano': '140-220 µm',
        'forma': 'Elipsoide',
        'color': 'Blanco a crema',
        'paredes': '2 paredes',
        'habitat': 'Suelos naturales, bosques',
        'uso': 'Identificación taxonómica, estudios ecológicos',
      },
      'Acaulospora myriocarpa': {
        'descripcion': 'Esporas formadas en cadenas (múltiples por esporóforo). Característica distintiva de la familia. Menos común que otras Acaulospora.',
        'tamano': '100-180 µm',
        'forma': 'Elipsoide',
        'color': 'Blanco a crema',
        'paredes': '2 paredes',
        'habitat': 'Suelos naturales, bosques',
        'uso': 'Estudios taxonómicos, investigación',
      },
      'Acaulospora morrowiae': {
        'descripcion': 'Esporas de paredes delgadas. Presente principalmente en suelos tropicales y subtropicales. Asociada a diversas plantas.',
        'tamano': '130-200 µm',
        'forma': 'Elipsoide',
        'color': 'Blanco a crema',
        'paredes': '2 paredes delgadas',
        'habitat': 'Suelos tropicales y subtropicales',
        'uso': 'Restauración en climas cálidos',
      },
      'Entrophospora infrequens': {
        'descripcion': 'Esporas formadas dentro de la hifa (endógenas). Menos común que Acaulospora. Característica distintiva en la formación de esporas.',
        'tamano': '100-160 µm',
        'forma': 'Elipsoide',
        'color': 'Blanco a crema',
        'paredes': '2 paredes',
        'habitat': 'Suelos naturales',
        'uso': 'Estudios taxonómicos',
      },
      'Gigaspora margarita': {
        'descripcion': 'Esporas muy grandes, globosas. No forma vesículas en la raíz, solo arbúsculos. Coloración amarillenta. Importante en estudios de simbiosis.',
        'tamano': '200-400 µm',
        'forma': 'Globosa',
        'color': 'Amarillo a ámbar',
        'paredes': '1 pared gruesa',
        'habitat': 'Pastizales, suelos naturales',
        'uso': 'Investigación, estudios de simbiosis',
      },
      'Gigaspora rosea': {
        'descripcion': 'Esporas grandes, coloración rosada distintiva. Asociada principalmente a pastizales. No forma vesículas, solo arbúsculos en raíces.',
        'tamano': '180-350 µm',
        'forma': 'Globosa',
        'color': 'Rosa a rojizo',
        'paredes': '1 pared gruesa',
        'habitat': 'Pastizales, praderas',
        'uso': 'Estudios ecológicos',
      },
      'Scutellospora calospora': {
        'descripcion': 'Esporas con "escutelos" o estructuras distintivas en la pared. Característica morfológica única que facilita la identificación.',
        'tamano': '200-350 µm',
        'forma': 'Globosa',
        'color': 'Marrón a marrón oscuro',
        'paredes': '1 pared con escutelos',
        'habitat': 'Suelos naturales, bosques',
        'uso': 'Identificación taxonómica',
      },
      'Scutellospora pellucida': {
        'descripcion': 'Esporas de pared relativamente transparente bajo microscopio. Permite observar estructuras internas. Menos común que otras Scutellospora.',
        'tamano': '180-320 µm',
        'forma': 'Globosa',
        'color': 'Transparente a marrón claro',
        'paredes': '1 pared delgada',
        'habitat': 'Suelos naturales',
        'uso': 'Estudios morfológicos',
      },
      'Racocetra castanea': {
        'descripcion': 'Esporas castañas. Género reasignado desde Scutellospora. Características intermedias entre Scutellospora y Gigaspora.',
        'tamano': '200-380 µm',
        'forma': 'Globosa',
        'color': 'Castaño a marrón',
        'paredes': '1 pared',
        'habitat': 'Suelos naturales',
        'uso': 'Estudios taxonómicos',
      },
      'Diversispora spurca': {
        'descripcion': 'Esporas con paredes ornamentadas distintivas. Diversidad en suelos naturales y agrícolas. Características morfológicas variables.',
        'tamano': '100-180 µm',
        'forma': 'Globosa a subglobosa',
        'color': 'Marrón claro a marrón',
        'paredes': '2-3 paredes ornamentadas',
        'habitat': 'Suelos diversos, naturales y agrícolas',
        'uso': 'Investigación, estudios de diversidad',
      },
      'Diversispora eburnea': {
        'descripcion': 'Esporas de aspecto marfil o blanquecino. Menos frecuente que D. spurca. Paredes con ornamentación sutil.',
        'tamano': '90-160 µm',
        'forma': 'Globosa',
        'color': 'Marfil a blanco',
        'paredes': '2 paredes',
        'habitat': 'Suelos naturales',
        'uso': 'Estudios taxonómicos',
      },
      'Corymbiglomus tortuosum': {
        'descripcion': 'Esporas en forma de corymbo (racimo). Género relacionado con Diversispora. Morfología distintiva en la disposición de esporas.',
        'tamano': '80-150 µm',
        'forma': 'Corymbo (racimo)',
        'color': 'Marrón claro',
        'paredes': '2 paredes',
        'habitat': 'Suelos naturales',
        'uso': 'Estudios taxonómicos',
      },
      'Paraglomus occultum': {
        'descripcion': 'Esporas pequeñas, paredes delgadas. Una de las más pequeñas en Glomeromycota. Difícil de observar sin técnicas especiales.',
        'tamano': '40-80 µm',
        'forma': 'Globosa',
        'color': 'Hialino a blanco',
        'paredes': '1 pared delgada',
        'habitat': 'Suelos diversos',
        'uso': 'Estudios de diversidad microbiana',
      },
      'Paraglomus laccatum': {
        'descripcion': 'Similar a P. occultum; esporas pequeñas y poco ornamentadas. Paredes delgadas. Común en suelos naturales pero difícil de detectar.',
        'tamano': '45-85 µm',
        'forma': 'Globosa',
        'color': 'Hialino a blanco',
        'paredes': '1 pared delgada',
        'habitat': 'Suelos naturales',
        'uso': 'Estudios ecológicos',
      },
      'Archaeospora trappei': {
        'descripcion': 'Género basal en Glomeromycota; esporas con características primitivas. Interés filogenético y evolutivo importante.',
        'tamano': '80-140 µm',
        'forma': 'Globosa',
        'color': 'Marrón claro',
        'paredes': '2 paredes',
        'habitat': 'Suelos naturales',
        'uso': 'Estudios filogenéticos',
      },
      'Geosiphon pyriformis': {
        'descripcion': 'Único en Glomeromycota por formar asociación con cianobacterias (Nostoc). Estructura en forma de pera. Interés científico excepcional.',
        'tamano': 'Variable',
        'forma': 'Piriforme',
        'color': 'Verde (por cianobacterias)',
        'paredes': 'Variable',
        'habitat': 'Suelos húmedos, asociado a Nostoc',
        'uso': 'Investigación única, estudios simbióticos',
      },
      'Ambispora leptoticha': {
        'descripcion': 'Esporas con características intermedias entre grupos. Pared delgada. Género de transición morfológica.',
        'tamano': '70-130 µm',
        'forma': 'Globosa a subglobosa',
        'color': 'Blanco a crema',
        'paredes': '1-2 paredes delgadas',
        'habitat': 'Suelos naturales',
        'uso': 'Estudios taxonómicos',
      },
      'Ambispora gerdemannii': {
        'descripcion': 'Especie tipo del género Ambispora. Esporas pequeñas. Características intermedias. Importante en la clasificación del grupo.',
        'tamano': '60-120 µm',
        'forma': 'Globosa',
        'color': 'Blanco a crema',
        'paredes': '1-2 paredes',
        'habitat': 'Suelos naturales',
        'uso': 'Referencia taxonómica',
      },
      'Pacispora scintillans': {
        'descripcion': 'Esporas con paredes brillantes o "scintillans" bajo luz. Poco común. Característica distintiva en la superficie.',
        'tamano': '100-180 µm',
        'forma': 'Globosa',
        'color': 'Marrón claro',
        'paredes': '2 paredes brillantes',
        'habitat': 'Suelos naturales',
        'uso': 'Estudios taxonómicos',
      },
      'Pacispora franciscana': {
        'descripcion': 'Especie del género Pacispora. Distribución limitada. Paredes distintivas del género. Menos estudiada.',
        'tamano': '90-170 µm',
        'forma': 'Globosa',
        'color': 'Marrón claro',
        'paredes': '2 paredes',
        'habitat': 'Distribución limitada',
        'uso': 'Estudios de diversidad',
      },
      'Russula spp.': {
        'descripcion': 'Género de hongos ectomicorrízicos muy diverso. Setas con láminas características. Amplia diversidad de especies. Importantes en bosques.',
        'tamano': 'Variable según especie',
        'forma': 'Setas con sombrero',
        'color': 'Múltiples colores',
        'paredes': 'N/A (setas)',
        'habitat': 'Bosques, asociado a árboles',
        'uso': 'Ecología forestal, algunos comestibles',
      },
      'Lactarius spp.': {
        'descripcion': 'Ectomicorrízico; produce látex al cortar. Género diverso. Asociado principalmente a árboles. Algunas especies comestibles.',
        'tamano': 'Variable según especie',
        'forma': 'Setas con látex',
        'color': 'Variable',
        'paredes': 'N/A (setas)',
        'habitat': 'Bosques, asociado a árboles',
        'uso': 'Ecología forestal, micología',
      },
      'Boletus edulis': {
        'descripcion': 'Ectomicorrízico muy valorado culinariamente. Setas grandes y carnosas. Asociado principalmente a pinos y robles. Comercialmente importante.',
        'tamano': 'Sombrero 5-25 cm',
        'forma': 'Seta con poros',
        'color': 'Marrón',
        'paredes': 'N/A (setas)',
        'habitat': 'Bosques de coníferas y robles',
        'uso': 'Culinario, ecología forestal',
      },
      'Amanita muscaria': {
        'descripcion': 'Ectomicorrízico icónico; seta roja con puntos blancos. Tóxico. Asociado a abedules y coníferas. Ampliamente reconocida.',
        'tamano': 'Sombrero 8-20 cm',
        'forma': 'Seta con láminas',
        'color': 'Rojo con puntos blancos',
        'paredes': 'N/A (setas)',
        'habitat': 'Bosques de abedules y coníferas',
        'uso': 'Estudios ecológicos, micología',
      },
    };
    
    return info[especie] ?? {
      'descripcion': 'Hongo micorrízico de la familia $familia. Forma asociación simbiótica con las raíces de las plantas, mejorando la absorción de nutrientes y agua.',
      'tamano': 'Variable',
      'forma': 'Variable',
      'color': 'Variable',
      'paredes': 'Variable',
      'habitat': 'Suelos diversos',
      'uso': 'Simbiosis micorrízica',
    };
  }

  static String _infoEspecie(String especie, String familia) {
    final infoCompleta = _infoEspecieCompleta(especie, familia);
    return infoCompleta['descripcion'] ?? 'Hongo micorrízico de la familia $familia.';
  }

  Widget _buildInfoRow(ThemeData theme, Color primary, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _infoEspecieLegacyUnused(String especie, String familia) {
    const info = <String, String>{
      'Glomus intraradices': 'Una de las especies más utilizadas en inoculantes. Forma esporas globosas a subglobosas; muy común en suelos agrícolas.',
      'Glomus mosseae': 'Especie cosmopolita. Esporas grandes, amarillentas; importante en simbiosis con cultivos.',
      'Glomus aggregatum': 'Esporas de tamaño medio, forma irregular; asociada a raíces de múltiples plantas.',
      'Septoglomus constrictum': 'Esporas con septo en la base de la hifa; común en ecosistemas templados.',
      'Funneliformis caledonius': 'Antes Glomus caledonium. Esporas globosas; amplia distribución.',
      'Acaulospora laevis': 'Esporas lisas, formadas lateralmente; muy utilizada en estudios de inoculación.',
      'Acaulospora scrobiculata': 'Esporas con ornamentación tipo “scrobículas”; ayuda en identificación.',
      'Acaulospora myriocarpa': 'Esporas en cadenas (múltiples por esporóforo); característica de la familia.',
      'Acaulospora morrowiae': 'Esporas de paredes delgadas; presente en suelos tropicales y subtropicales.',
      'Entrophospora infrequens': 'Esporas formadas dentro de la hifa; menos común que Acaulospora.',
      'Gigaspora margarita': 'Esporas muy grandes, globosas; no forma vesículas en la raíz.',
      'Gigaspora rosea': 'Esporas grandes, coloración rosada; asociada a pastizales.',
      'Scutellospora calospora': 'Esporas con “escutelos” o estructuras en la pared; distintiva.',
      'Scutellospora pellucida': 'Esporas de pared relativamente transparente bajo microscopio.',
      'Racocetra castanea': 'Esporas castañas; género reasignado desde Scutellospora.',
      'Diversispora spurca': 'Esporas con paredes ornamentadas; diversidad en suelos.',
      'Diversispora eburnea': 'Esporas de aspecto marfil; menos frecuente.',
      'Corymbiglomus tortuosum': 'Esporas en forma de corymbo; género relacionado con Diversispora.',
      'Paraglomus occultum': 'Esporas pequeñas, paredes delgadas; una de las más pequeñas en Glomeromycota.',
      'Paraglomus laccatum': 'Similar a P. occultum; esporas pequeñas y poco ornamentadas.',
      'Archaeospora trappei': 'Género basal; esporas con características primitivas.',
      'Geosiphon pyriformis': 'Asociación con cianobacterias (Nostoc); único en Glomeromycota.',
      'Ambispora leptoticha': 'Esporas con características intermedias; pared delgada.',
      'Ambispora gerdemannii': 'Especie tipo del género; esporas pequeñas.',
      'Pacispora scintillans': 'Esporas con paredes brillantes o “scintillans”; poco común.',
      'Pacispora franciscana': 'Especie del género Pacispora; distribución limitada.',
      'Russula spp.': 'Género de hongos ectomicorrízicos; setas con láminas; amplia diversidad.',
      'Lactarius spp.': 'Ectomicorrízico; látex al cortar; asociado a árboles.',
      'Boletus edulis': 'Ectomicorrízico; seta comestible muy valorada; asociado a pinos y robles.',
      'Amanita muscaria': 'Ectomicorrízico; seta roja con puntos blancos; asociado a abedules y coníferas.',
    };
    return info[especie] ?? 'Hongo micorrízico de la familia $familia.';
  }

  void _showDialogEspecie(BuildContext context, ThemeData theme, String especie, String familia) {
    final primary = theme.colorScheme.primary;
    final infoCompleta = _infoEspecieCompleta(especie, familia);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withOpacity(0.2),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primary,
                      primary.withOpacity(0.85),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.eco_rounded, size: 24, color: theme.colorScheme.onPrimary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            especie,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            familia,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onPrimary.withOpacity(0.95),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: theme.colorScheme.onPrimary),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Información científica',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        infoCompleta['descripcion'] ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: theme.colorScheme.onSurface.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildInfoRow(theme, primary, Icons.forest_rounded, 'Hábitat', infoCompleta['habitat'] ?? 'Variable'),
                      const SizedBox(height: 12),
                      _buildInfoRow(theme, primary, Icons.science_rounded, 'Uso / relevancia', infoCompleta['uso'] ?? 'Variable'),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('Cerrar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFamiliaImage(String nombreFamilia, Color fallbackColor) {
    final nombreMap = <String, List<String>>{
      'Pacisporaceae': ['pacisporaceae'],
      'Otros tipos (ectomicorrizas)': ['ectomizorrizas', 'ectomicorrizas'],
    };

    final nombreLimpio = nombreFamilia
        .replaceAll(' ', '_')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('/', '_')
        .toLowerCase();
    
    final variaciones = <String>[];
    final extensiones = ['.png', '.jpg', '.jpeg', '.webp'];

    if (nombreMap.containsKey(nombreFamilia)) {
      for (final nombreArchivo in nombreMap[nombreFamilia]!) {
        for (final ext in extensiones) {
          variaciones.addAll([
            'imagenes/$nombreArchivo$ext',
            'imagenes/${nombreArchivo[0].toUpperCase()}${nombreArchivo.substring(1)}$ext',
          ]);
        }
      }
    }

    if (nombreFamilia == 'Pacisporaceae') {
      for (final ext in extensiones) {
        variaciones.addAll([
          'imagenes/pacisporaceae$ext',
          'imagenes/Pacisporaceae$ext',
        ]);
      }
    }

    if (nombreFamilia == 'Otros tipos (ectomicorrizas)') {
      for (final ext in extensiones) {
        variaciones.addAll([
          'imagenes/ectomizorrizas$ext',
          'imagenes/Ectomizorrizas$ext',
          'imagenes/ectomicorrizas$ext',
          'imagenes/Ectomicorrizas$ext',
        ]);
      }
    }

    for (final ext in extensiones) {
      variaciones.addAll([
        'imagenes/$nombreFamilia$ext',
        'imagenes/${nombreFamilia.toLowerCase()}$ext',
        'imagenes/$nombreLimpio$ext',
      ]);
    }
    
    return _tryLoadImage(variaciones, 0, fallbackColor);
  }

  Widget _tryLoadImage(List<String> paths, int index, Color fallbackColor) {
    if (index >= paths.length) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              fallbackColor,
              fallbackColor.withOpacity(0.85),
            ],
          ),
        ),
      );
    }
    
    return Image.asset(
      paths[index],
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return _tryLoadImage(paths, index + 1, fallbackColor);
      },
    );
  }

  void _showFamilias(BuildContext context, ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final familias = [
      {
        'nombre': 'Glomeraceae',
        'desc': 'Una de las familias más diversas. Esporas formadas en glomérulos.',
        'especies': ['Glomus intraradices', 'Glomus mosseae', 'Glomus aggregatum', 'Septoglomus constrictum', 'Funneliformis caledonius'],
      },
      {
        'nombre': 'Acaulosporaceae',
        'desc': 'Esporas formadas en el cuello de una vesícula (blástica).',
        'especies': ['Acaulospora laevis', 'Acaulospora scrobiculata', 'Acaulospora myriocarpa', 'Acaulospora morrowiae', 'Entrophospora infrequens'],
      },
      {
        'nombre': 'Gigasporaceae',
        'desc': 'Esporas grandes en la punta de la hifa. No forman vesículas en raíces.',
        'especies': ['Gigaspora margarita', 'Gigaspora rosea', 'Scutellospora calospora', 'Scutellospora pellucida', 'Racocetra castanea'],
      },
      {
        'nombre': 'Diversisporaceae',
        'desc': 'Esporas con paredes ornamentadas o múltiples.',
        'especies': ['Diversispora spurca', 'Diversispora eburnea', 'Corymbiglomus tortuosum'],
      },
      {
        'nombre': 'Paraglomeraceae',
        'desc': 'Esporas pequeñas y paredes delgadas.',
        'especies': ['Paraglomus occultum', 'Paraglomus laccatum'],
      },
      {
        'nombre': 'Archaeosporaceae',
        'desc': 'Algunos forman asociaciones con cianobacterias.',
        'especies': ['Archaeospora trappei', 'Geosiphon pyriformis'],
      },
      {
        'nombre': 'Ambisporaceae',
        'desc': 'Esporas con características intermedias entre grupos.',
        'especies': ['Ambispora leptoticha', 'Ambispora gerdemannii'],
      },
      {
        'nombre': 'Pacisporaceae',
        'desc': 'Esporas con paredes distintivas, menos comunes.',
        'especies': ['Pacispora scintillans', 'Pacispora franciscana'],
      },
      {
        'nombre': 'Otros tipos (ectomicorrizas)',
        'desc': 'Asociaciones con otras familias de hongos.',
        'especies': ['Russula spp.', 'Lactarius spp.', 'Boletus edulis', 'Amanita muscaria'],
      },
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamiliasScreen(
          theme: theme,
          primary: primary,
          familias: familias,
          buildFamiliaImage: (nombre, color) => _buildFamiliaImage(nombre, color),
          onVerEspecies: (ctx, nombre, desc, especies) => _showFamiliasDetalle(ctx, theme, nombre, desc, especies),
        ),
      ),
    );
  }

  Widget _buildFeatureGridCard({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
    String? imagePath,
  }) {
    const iconSize = 30.0;
    final isNovedad = title == 'Guía de campos' || title == 'Sobre micorrizas';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: color.withOpacity(0.2),
        highlightColor: color.withOpacity(0.08),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFE5E7EB),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isNovedad)
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEADCFB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Novedad',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  shape: BoxShape.circle,
                ),
                child: imagePath != null
                    ? SizedBox(
                        width: iconSize + 6,
                        height: iconSize + 6,
                        child: Image.asset(
                          imagePath,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(icon, size: iconSize, color: color),
                        ),
                      )
                    : Icon(icon, size: iconSize, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: const Color(0xFF6B7280),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _OverlayGuiaPainter extends CustomPainter {
  final Rect? cardRect;
  final Color dimColor;

  _OverlayGuiaPainter({this.cardRect, required this.dimColor});

  @override
  void paint(Canvas canvas, Size size) {
    final fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    if (cardRect != null && cardRect!.width > 0 && cardRect!.height > 0) {
      final holePath = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            cardRect!,
            const Radius.circular(18),
          ),
        );
      canvas.drawPath(
        Path.combine(PathOperation.difference, fullPath, holePath),
        Paint()..color = dimColor,
      );
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = dimColor);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayGuiaPainter oldDelegate) {
    return oldDelegate.cardRect != cardRect || oldDelegate.dimColor != dimColor;
  }
}

class _OverlayWithHoleHitTest extends LeafRenderObjectWidget {
  final Rect? holeRect;
  final Color dimColor;

  const _OverlayWithHoleHitTest({super.key, this.holeRect, required this.dimColor});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderOverlayWithHole(holeRect: holeRect, dimColor: dimColor);
  }

  @override
  void updateRenderObject(BuildContext context, covariant _RenderOverlayWithHole renderObject) {
    renderObject
      ..holeRect = holeRect
      ..dimColor = dimColor;
  }
}

class _RenderOverlayWithHole extends RenderBox {
  Rect? holeRect;
  Color dimColor;

  _RenderOverlayWithHole({this.holeRect, required this.dimColor});

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (holeRect != null && holeRect!.contains(position)) return false;
    if (size.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  void performLayout() {
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _OverlayGuiaPainter(cardRect: holeRect, dimColor: dimColor).paint(context.canvas, size);
  }
}

class _DialogOverlayGuia extends StatefulWidget {
  final GlobalKey overlayKey;
  final ValueNotifier<Rect?> buttonRectGlobalNotifier;
  final ValueNotifier<bool> mostrarHintNotifier;
  final Color dimColor;

  const _DialogOverlayGuia({
    required this.overlayKey,
    required this.buttonRectGlobalNotifier,
    required this.mostrarHintNotifier,
    required this.dimColor,
  });

  @override
  State<_DialogOverlayGuia> createState() => _DialogOverlayGuiaState();
}

class _DialogOverlayGuiaState extends State<_DialogOverlayGuia> {
  Rect? _localHoleRect;
  VoidCallback? _removeListener;

  @override
  void initState() {
    super.initState();
    void update() {
      if (!widget.mostrarHintNotifier.value) {
        setState(() => _localHoleRect = null);
        return;
      }
      final globalRect = widget.buttonRectGlobalNotifier.value;
      if (globalRect == null) {
        setState(() => _localHoleRect = null);
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final overlayBox = widget.overlayKey.currentContext?.findRenderObject() as RenderBox?;
        if (overlayBox != null && mounted) {
          final localTopLeft = overlayBox.globalToLocal(globalRect.topLeft);
          final localBottomRight = overlayBox.globalToLocal(globalRect.bottomRight);
          setState(() => _localHoleRect = Rect.fromPoints(localTopLeft, localBottomRight));
        }
      });
    }
    update();
    widget.buttonRectGlobalNotifier.addListener(update);
    widget.mostrarHintNotifier.addListener(update);
    _removeListener = () {
      widget.buttonRectGlobalNotifier.removeListener(update);
      widget.mostrarHintNotifier.removeListener(update);
    };
  }

  @override
  void dispose() {
    _removeListener?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.mostrarHintNotifier.value) return const SizedBox.shrink();
    return _OverlayWithHoleHitTest(
      key: widget.overlayKey,
      holeRect: _localHoleRect,
      dimColor: widget.dimColor,
    );
  }
}

class GuiaDeCamposScreen extends StatelessWidget {
  final ThemeData theme;
  final Color primary;
  final List<_GuiaCamposData> guiaItems;
  final List<Color> chipColors;
  final Widget Function(BuildContext context, _GuiaCamposData data, Color chipColor) buildCard;

  const GuiaDeCamposScreen({
    super.key,
    required this.theme,
    required this.primary,
    required this.guiaItems,
    required this.chipColors,
    required this.buildCard,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F0),
      appBar: AppBar(
        title: const Text('Guía de campos'),
        backgroundColor: primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            alignment: Alignment.centerLeft,
            child: Text(
              'Campos para la predicción de especies',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onPrimary.withOpacity(0.95),
              ),
            ),
          ),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.68,
        ),
        itemCount: guiaItems.length,
        itemBuilder: (context, index) {
          return buildCard(
            context,
            guiaItems[index],
            chipColors[index % chipColors.length],
          );
        },
      ),
    );
  }
}

class FamiliasScreen extends StatelessWidget {
  final ThemeData theme;
  final Color primary;
  final List<Map<String, dynamic>> familias;
  final Widget Function(String nombre, Color color) buildFamiliaImage;
  final void Function(BuildContext context, String nombre, String desc, List<String> especies) onVerEspecies;

  const FamiliasScreen({
    super.key,
    required this.theme,
    required this.primary,
    required this.familias,
    required this.buildFamiliaImage,
    required this.onVerEspecies,
  });

  @override
  Widget build(BuildContext context) {
    final cardColors = [
      primary,
      primary.withOpacity(0.85),
      primary.withOpacity(0.75),
      primary.withOpacity(0.9),
      primary.withOpacity(0.8),
      primary.withOpacity(0.88),
      primary.withOpacity(0.82),
      primary.withOpacity(0.86),
      primary.withOpacity(0.78),
    ];

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Familias de micorrizas'),
        backgroundColor: primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            alignment: Alignment.centerLeft,
            child: Text(
              'Glomeromycota · especies representativas',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onPrimary.withOpacity(0.95),
              ),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        itemCount: familias.length,
        itemBuilder: (context, index) {
          final f = familias[index];
          final nombre = f['nombre'] as String;
          final desc = f['desc'] as String;
          final especies = f['especies'] as List<String>;
          final cardColor = cardColors[index % cardColors.length];

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            child: Card(
              elevation: 4,
              shadowColor: theme.colorScheme.shadow.withOpacity(0.15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [cardColor, cardColor.withOpacity(0.85)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(child: buildFamiliaImage(nombre, cardColor)),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.3),
                                  Colors.black.withOpacity(0.5),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Familia ${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Text(
                                nombre,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 14, color: primary.withOpacity(0.7)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                desc,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                  height: 1.3,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.eco_rounded, size: 14, color: primary.withOpacity(0.7)),
                            const SizedBox(width: 6),
                            Text(
                              '${especies.length} especies',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => onVerEspecies(context, nombre, desc, especies),
                            icon: const Icon(Icons.visibility_rounded, size: 16),
                            label: const Text('Ver especies', style: TextStyle(fontSize: 13)),
                            style: FilledButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class SobreMicorrizasScreen extends StatelessWidget {
  final ThemeData theme;

  const SobreMicorrizasScreen({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Sobre micorrizas'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildHero(context),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSection(
                  context,
                  Icons.eco_rounded,
                  '¿Qué son las micorrizas?',
                  'Las micorrizas son asociaciones simbióticas entre hongos y las raíces de la mayoría de las plantas. '
                  'El hongo obtiene carbohidratos de la planta y, a cambio, ayuda a la planta a absorber agua y nutrientes del suelo. '
                  'Más del 80% de las plantas terrestres forman micorrizas; sin ellas, muchos ecosistemas no serían posibles.',
                ),
                _buildImageCard(
                  context,
                  Icons.science,
                  'Esporas bajo el microscopio',
                  'Las esporas de hongos micorrízicos arbusculares (AMF) se observan en el suelo o en raíces; su tamaño, forma, color y textura permiten identificar la especie.',
                  imageAsset: 'imagenes/esporas bajo el microscopio.jpg',
                ),
                _buildSection(
                  context,
                  Icons.grass_rounded,
                  'Las esporas',
                  'Las esporas son las unidades reproductivas del hongo. En los hongos micorrízicos arbusculares, las esporas pueden ser de distintos tamaños (desde decenas hasta cientos de micrómetros), formas (globosa, elipsoide, etc.), colores (blanco, amarillo, marrón, etc.) y número de paredes (1 a 4). La reacción con el reactivo de Melzer y la textura superficial son caracteres clave para la identificación.',
                ),
                _buildSection(
                  context,
                  Icons.category_rounded,
                  'Tipos de micorrizas',
                  'Micorrizas arbusculares (AM): el hongo penetra las células de la raíz y forma estructuras ramificadas (arbúsculos). Son las más comunes. '
                  'Ectomicorrizas: el hongo forma un manto alrededor de la raíz sin penetrar las células. Otras variantes incluyen ericoides y orquidoides.',
                ),
                _buildImageCard(
                  context,
                  Icons.forest,
                  'Micorrizas en la naturaleza',
                  'En bosques y pastizales, las redes de micorrizas conectan plantas y transfieren nutrientes entre ellas, actuando como una "red social" subterránea.',
                  imageAsset: 'imagenes/micorriza en la naturaleza.jpg',
                ),
                _buildSection(
                  context,
                  Icons.volunteer_activism_rounded,
                  'Importancia ecológica',
                  '• Mejoran la nutrición y el crecimiento de las plantas.\n'
                  '• Aumentan la resistencia al estrés hídrico y a enfermedades.\n'
                  '• Favorecen la estructura del suelo y la retención de agua.\n'
                  '• Son fundamentales en la restauración de suelos degradados y en la agricultura sostenible.',
                ),
                _buildSection(
                  context,
                  Icons.lightbulb_rounded,
                  'Dato curioso',
                  'Una sola cucharadita de suelo puede contener kilómetros de hifas fúngicas y cientos de esporas de distintas especies de hongos micorrízicos.',
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'imagenes/BANNER.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Image.asset(
                'imagenes/BANNER.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Image.asset(
                    'imagenes/banner.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.primary.withOpacity(0.85),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.5),
                ],
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text(
                'Hongos micorrízicos y esporas',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Todo lo que debes saber',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(BuildContext context, IconData icon, String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: TextStyle(
              fontSize: 15,
              height: 1.55,
              color: theme.colorScheme.onSurface.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard(BuildContext context, IconData icon, String title, String body, {String? imageAsset}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 160,
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              child: imageAsset != null && imageAsset.isNotEmpty
                  ? Image.asset(
                      imageAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildImagePlaceholder(icon),
                    )
                  : _buildImagePlaceholder(icon),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(IconData icon) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withOpacity(0.7),
            theme.colorScheme.primary.withOpacity(0.4),
          ],
        ),
      ),
      child: Center(
        child: Icon(icon, size: 64, color: Colors.white.withOpacity(0.95)),
      ),
    );
  }
}

class ClimaDetalleSheet extends StatefulWidget {
  final ThemeData theme;
  final Map<String, dynamic> climaActual;

  const ClimaDetalleSheet({
    super.key,
    required this.theme,
    required this.climaActual,
  });

  @override
  State<ClimaDetalleSheet> createState() => _ClimaDetalleSheetState();
}

class _ClimaDetalleSheetState extends State<ClimaDetalleSheet> {
  List<Map<String, dynamic>>? _forecast;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadForecast();
  }

  Future<void> _loadForecast() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = widget.climaActual;
      final lat = d['lat'] as double?;
      final lon = d['lon'] as double?;
      final data = await ClimaService.getPronostico4Dias(lat: lat, lon: lon);
      if (mounted) {
        setState(() {
          _forecast = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _showMasInfoClima(BuildContext context) {
    final theme = widget.theme;
    final d = widget.climaActual;
    final primary = theme.colorScheme.primary;
    final temp = d['temp'] as double?;
    final feels = d['feels_like'] as double?;
    final humidity = d['humidity'] as int?;
    final precip = (d['precipitation'] as num?)?.toDouble();
    final windKmh = (d['wind_speed_kmh'] as num?)?.toDouble();
    final windDir = d['wind_direction'] as int?;
    final pressure = (d['pressure_hpa'] as num?)?.toDouble();
    final sueloNivel = d['suelo_nivel'] as String?;
    final sueloDesc = d['suelo_desc'] as String?;
    final weatherName = d['weather_name'] as String? ?? '—';
    final code = d['weather_code'] as int?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.65),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [primary, primary.withOpacity(0.85)],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(weatherIcon(code), size: 28, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detalle del clima actual',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          weatherName,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.95),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildClimaInfoCard(
                      theme,
                      primary,
                      Icons.thermostat_rounded,
                      'Temperatura actual',
                      temp != null ? '${temp.round()}°C' : '—',
                    ),
                    const SizedBox(height: 12),
                    _buildClimaInfoCard(
                      theme,
                      primary,
                      Icons.whatshot_rounded,
                      'Sensación térmica',
                      feels != null ? '${feels.round()}°C' : '—',
                    ),
                    const SizedBox(height: 12),
                    _buildClimaInfoCard(
                      theme,
                      primary,
                      Icons.water_drop_rounded,
                      'Humedad del aire',
                      humidity != null ? '$humidity%' : '—',
                    ),
                    const SizedBox(height: 12),
                    _buildClimaInfoCard(
                      theme,
                      primary,
                      Icons.grain_rounded,
                      'Precipitación',
                      precip != null ? '${precip.toStringAsFixed(1)} mm' : '0 mm',
                    ),
                    if (windKmh != null) ...[
                      const SizedBox(height: 12),
                      _buildClimaInfoCard(
                        theme,
                        primary,
                        Icons.air_rounded,
                        'Viento',
                        '${windKmh.toStringAsFixed(0)} km/h${windDir != null ? ' · ${_windDirLabel(windDir)}' : ''}',
                      ),
                    ],
                    if (pressure != null) ...[
                      const SizedBox(height: 12),
                      _buildClimaInfoCard(
                        theme,
                        primary,
                        Icons.speed_rounded,
                        'Presión atmosférica',
                        '${pressure.round()} hPa',
                      ),
                    ],
                    if (sueloNivel != null && sueloDesc != null) ...[
                      const SizedBox(height: 12),
                      _buildClimaInfoCard(
                        theme,
                        primary,
                        Icons.grass_rounded,
                        'Humedad del suelo (estimada)',
                        '$sueloNivel · $sueloDesc',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _windDirLabel(int deg) {
    if (deg >= 338 || deg < 23) return 'N';
    if (deg >= 23 && deg < 68) return 'NE';
    if (deg >= 68 && deg < 113) return 'E';
    if (deg >= 113 && deg < 158) return 'SE';
    if (deg >= 158 && deg < 203) return 'S';
    if (deg >= 203 && deg < 248) return 'SO';
    if (deg >= 248 && deg < 293) return 'O';
    return 'NO';
  }

  Widget _buildClimaInfoCard(ThemeData theme, Color primary, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withOpacity(0.12), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final d = widget.climaActual;
    final temp = d['temp'] as double?;
    final feels = d['feels_like'] as double?;
    final humidity = d['humidity'] as int?;
    final precip = (d['precipitation'] as num?)?.toDouble();
    final windKmh = (d['wind_speed_kmh'] as num?)?.toDouble();
    final windDir = d['wind_direction'] as int?;
    final pressure = (d['pressure_hpa'] as num?)?.toDouble();
    final sueloNivel = d['suelo_nivel'] as String?;
    final sueloDesc = d['suelo_desc'] as String?;
    final weatherName = d['weather_name'] as String? ?? '—';
    final location = d['location'] as String? ?? 'Clima en tiempo real';
    final code = d['weather_code'] as int?;
    final primary = theme.colorScheme.primary;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outline.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.wb_cloudy_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Pronóstico actual y próximos días',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          weatherIcon(code),
                          size: 40,
                          color: primary,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              temp != null ? '${temp.round()}°C' : '—',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                                color: primary,
                              ),
                            ),
                            Text(
                              weatherName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            if (feels != null)
                              Text(
                                'Sensación ${feels.round()}°C · Humedad ${humidity ?? 0}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Próximos 4 días',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    )
                  else if (_forecast != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: _forecast!.map((f) {
                        final date = f['date'] as DateTime;
                        final maxT = f['temp_max'] as double?;
                        final minT = f['temp_min'] as double?;
                        final codeDay = f['weather_code'] as int?;
                        final dayLabel = _diaCorto(date.weekday);
                        return Expanded(
                          child: Column(
                            children: [
                              Text(
                                dayLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Icon(
                                weatherIcon(codeDay),
                                size: 24,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                maxT != null ? '${maxT.round()}°C' : '—',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                minT != null ? '${minT.round()}°C' : '—',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 28),
                  Text(
                    'Detalle del clima actual',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildClimaInfoCard(theme, primary, Icons.thermostat_rounded, 'Temperatura actual', temp != null ? '${temp.round()}°C' : '—'),
                  const SizedBox(height: 10),
                  _buildClimaInfoCard(theme, primary, Icons.whatshot_rounded, 'Sensación térmica', feels != null ? '${feels.round()}°C' : '—'),
                  const SizedBox(height: 10),
                  _buildClimaInfoCard(theme, primary, Icons.water_drop_rounded, 'Humedad del aire', humidity != null ? '$humidity%' : '—'),
                  const SizedBox(height: 10),
                  _buildClimaInfoCard(theme, primary, Icons.grain_rounded, 'Precipitación', precip != null ? '${precip.toStringAsFixed(1)} mm' : '0 mm'),
                  if (windKmh != null) ...[
                    const SizedBox(height: 10),
                    _buildClimaInfoCard(theme, primary, Icons.air_rounded, 'Viento', '${windKmh.toStringAsFixed(0)} km/h${windDir != null ? ' · ${_windDirLabel(windDir)}' : ''}'),
                  ],
                  if (pressure != null) ...[
                    const SizedBox(height: 10),
                    _buildClimaInfoCard(theme, primary, Icons.speed_rounded, 'Presión atmosférica', '${pressure.round()} hPa'),
                  ],
                  if (sueloNivel != null && sueloDesc != null) ...[
                    const SizedBox(height: 10),
                    _buildClimaInfoCard(theme, primary, Icons.grass_rounded, 'Humedad del suelo (estimada)', '$sueloNivel · $sueloDesc'),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _diaCorto(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Lun';
      case DateTime.tuesday:
        return 'Mar';
      case DateTime.wednesday:
        return 'Mié';
      case DateTime.thursday:
        return 'Jue';
      case DateTime.friday:
        return 'Vie';
      case DateTime.saturday:
        return 'Sáb';
      case DateTime.sunday:
        return 'Dom';
      default:
        return '';
    }
  }
}

class PredictionFormScreen extends StatefulWidget {
  const PredictionFormScreen({super.key});

  @override
  State<PredictionFormScreen> createState() => _PredictionFormScreenState();
}

class _PredictionFormScreenState extends State<PredictionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tamanoController = TextEditingController();
  bool _isLoading = false;

  String _paredes = '1';
  String _reaccionMelzer = 'negativo';
  final List<String> _formasSeleccionadas = [];
  final List<String> _coloresSeleccionados = [];
  final List<String> _conexionesSeleccionadas = [];
  final List<String> _texturasSeleccionadas = [];

  final _busquedaForma = TextEditingController();
  final _busquedaColor = TextEditingController();
  final _busquedaConexion = TextEditingController();
  final _busquedaTextura = TextEditingController();

  static const _formas = [
    'globosa', 'subglobosa', 'ovoide', 'elipsoide', 'piriforme', 'clavada',
    'cilindrica', 'oblonga', 'reniforme', 'fusiforme', 'triangular', 'irregular',
  ];
  static const _colores = [
    'amarillo', 'ambar', 'blanco', 'crema', 'dorado', 'gris', 'hialino',
    'marron', 'miel', 'naranja', 'negro', 'ocre', 'rojo', 'verdoso',
  ];
  static const _paredesOpciones = ['1', '2', '3', '4', '5', '6'];
  static const _reaccionesMelzer = ['negativo', 'positivo', 'ninguna', 'paredes internas', 'sin reporte'];
  static const _conexionesHifales = [
    'hifa_suspensora', 'hifa_subtendente', 'hifa_simple', 'pedicelo',
    'celula_bulbosa', 'saco_esporifero', 'plexo_central', 'manto_hifal', 'cicatriz',
    'recta', 'curvada', 'recurvada', 'cilindrica', 'acampanada', 'embudo', 'bulbosa', 'hinchada',
    'contraida', 'tubular', 'ramificada', 'multiples', 'sin_septo', 'con_septo',
    'septo_laminado', 'septo_transversal', 'septo_curvado', 'septo_continuo',
    'septo_grueso', 'tapon', 'poro_abierto', 'poro_cerrado', 'poro_ocluido',
    'poro_septado', 'poro_germinacion', 'sesil', 'cicatriz_prominente',
    'cicatriz_denticulada', 'canal', 'detritos', 'colapso', 'desprendimiento',
  ];
  static const _texturas = [
    'lisa', 'rugosa', 'aspera', 'granular', 'reticulada', 'foveolada',
    'scrobiculada', 'perforada', 'alveolada', 'laberintiforme', 'verrugosa', 'ornamentada',
    'laminada', 'membranosa', 'estratificada', 'sublaminada', 'subcapas',
    'rigida', 'flexible', 'semiflexible', 'fragil', 'quebradiza', 'suave',
    'delgada', 'gruesa', 'mucilaginosa', 'evanescente', 'verrugas', 'espinas',
    'proyecciones', 'protuberancias', 'papilas', 'pustulas', 'reticulo',
    'crestas', 'depresiones', 'hoyos', 'estrias',
  ];

  @override
  void dispose() {
    _tamanoController.dispose();
    _busquedaForma.dispose();
    _busquedaColor.dispose();
    _busquedaConexion.dispose();
    _busquedaTextura.dispose();
    super.dispose();
  }

  bool get _formCompleto {
    return _tamanoController.text.trim().isNotEmpty &&
        _formasSeleccionadas.isNotEmpty &&
        _coloresSeleccionados.isNotEmpty &&
        _conexionesSeleccionadas.isNotEmpty &&
        _texturasSeleccionadas.isNotEmpty;
  }

  Future<void> _submitPrediction() async {
    if (!_formCompleto) return;
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      String? especie;
      Map<String, dynamic>? info;
      String? errorDetalle;

      const urls = [
        'https://api-micorriza.onrender.com',
        'http://10.0.2.2:8000',
        'http://127.0.0.1:8000',
        'http://localhost:8000',
      ];
      String? urlFuncional;
      bool apiOk = false;

      for (final baseUrl in urls) {
        try {
          final checkRes = await http.get(
            Uri.parse('$baseUrl/estado'),
          ).timeout(const Duration(seconds: 10));
          if (checkRes.statusCode == 200) {
            urlFuncional = baseUrl;
            break;
          }
        } catch (e) {
          continue;
        }
      }

      if (urlFuncional != null) {
        try {
          final res = await http.post(
            Uri.parse('$urlFuncional/predecir'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'tamano': _tamanoController.text.trim(),
              'forma': _formasSeleccionadas,
              'color': _coloresSeleccionados,
              'paredes': _paredes,
              'melzer': _reaccionMelzer,
              'conexion': _conexionesSeleccionadas,
              'textura': _texturasSeleccionadas,
            }),
          ).timeout(const Duration(seconds: 15));

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            especie = data['especie'] as String?;
            info = data['info'] as Map<String, dynamic>?;
            final confianza = data['confianza'] as double?;
            final alternativas = data['especies_alternativas'] as List<dynamic>?;
            String? imagenUrl;
            final imagePath = data['imagen'] as String?;
            if (imagePath != null && imagePath.toString().trim().isNotEmpty) {
              final path = imagePath.toString().trim();
              imagenUrl = path.startsWith('http') ? path : '$urlFuncional${path.startsWith('/') ? '' : '/'}$path';
            }
            apiOk = true;
            if (mounted) {
              setState(() => _isLoading = false);
              _showResultDialog(especie ?? 'Especie no determinada', info, confianza, alternativas, imagenUrl);
            }
            return;
          } else {
            errorDetalle = 'Error ${res.statusCode}: ${res.body.substring(0, 100)}';
          }
        } catch (e) {
          errorDetalle = 'Error de conexión: ${e.toString()}';
        }
      } else {
        errorDetalle = 'No se pudo conectar a ninguna URL. Verifica que la API esté ejecutándose.';
      }

      if (!apiOk) {
        especie ??= 'Especie no determinada';
        info = {'vegetacion': '—', 'habitat': '—', 'pais': '—', 'localidad': '—', 'informacion': '—', 'particularidad': '—'};
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'API no disponible',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    errorDetalle ?? 'Ejecuta iniciar_api.bat desde la carpeta del proyecto.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
        _showResultDialog(especie ?? 'Especie no determinada', info, null, null, null);
      }
    }
  }

  void _showResultDialog(String especie, [Map<String, dynamic>? info, double? confianza, List<dynamic>? alternativas, String? imagenUrl]) {
    info ??= {};
    String v(String k) {
      final x = info![k];
      if (x == null) return '—';
      final s = x.toString().trim();
      return s.isEmpty ? '—' : s;
    }
    String vInformacion() {
      final inf = v('informacion');
      if (inf != '—') return inf;
      return v('particularidad');
    }
    
    final theme = Theme.of(context);
    final confianzaColor = confianza != null
        ? (confianza >= 80 ? Colors.green : confianza >= 60 ? Colors.orange : Colors.red)
        : theme.colorScheme.primary;

    final buttonRectGlobalNotifier = ValueNotifier<Rect?>(null);
    final mostrarHintNotifier = ValueNotifier<bool>(true);
    final keyDialogContainer = GlobalKey();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          key: keyDialogContainer,
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.eco, color: theme.colorScheme.onPrimary, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Predicción',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _BodyDialogoPrediccion(
                      especie: especie,
                      imagenUrl: imagenUrl,
                      confianza: confianza,
                      confianzaColor: confianzaColor,
                      theme: theme,
                      v: v,
                      vInformacion: vInformacion,
                      info: info!,
                      alternativas: alternativas,
                      onAbrirBusqueda: () => _abrirBusquedaEspecie(ctx, especie),
                      buildInfoRow: _buildInfoRow,
                      buildEspecieAlternativa: _buildEspecieAlternativa,
                      buttonRectGlobalNotifier: buttonRectGlobalNotifier,
                      mostrarHintNotifier: mostrarHintNotifier,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Aceptar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
              _HintFlotanteDialogo(
                keyDialog: keyDialogContainer,
                theme: theme,
                mostrarHintNotifier: mostrarHintNotifier,
                buttonRectGlobalNotifier: buttonRectGlobalNotifier,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _urlChannel = MethodChannel('micotax/url_launcher');

  Future<void> _abrirBusquedaEspecie(BuildContext context, String especie) async {
    final query = Uri.encodeComponent(
      'Información detallada del hongo micorrízico $especie: '
      'descripción morfológica de las esporas (tamaño, forma, color, número de paredes, textura), '
      'reacción con Melzer, hábitat y distribución geográfica, plantas asociadas, '
      'importancia ecológica y claves para identificación. Responde en español.'
    );
    final url = 'https://www.perplexity.ai/search/new?q=$query';
    try {
      final abrio = await _urlChannel.invokeMethod<bool>('openUrl', <String, dynamic>{'url': url});
      if (context.mounted) {
        if (abrio == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Se abrió en el navegador'), duration: Duration(seconds: 2)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo abrir el navegador')),
          );
        }
      }
    } on PlatformException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.message ?? e.code}')),
        );
      }
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                Text(value, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEspecieAlternativa(BuildContext context, String especie, double confianza) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.eco, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              especie,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${confianza.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiselectConBusqueda({
    required String titulo,
    required IconData icono,
    required List<String> opciones,
    required List<String> seleccionados,
    required TextEditingController controllerBusqueda,
    required ValueChanged<String> onTap,
    required ThemeData theme,
  }) {
    final filtradas = controllerBusqueda.text.isEmpty
        ? opciones
        : opciones.where((o) => o.toLowerCase().contains(controllerBusqueda.text.toLowerCase())).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: seleccionados.isNotEmpty
              ? theme.colorScheme.primary.withOpacity(0.3)
              : theme.colorScheme.outline.withOpacity(0.2),
          width: seleccionados.isNotEmpty ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: theme.copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: theme.colorScheme.surface,
          collapsedBackgroundColor: theme.colorScheme.surface,
          iconColor: theme.colorScheme.primary,
          collapsedIconColor: theme.colorScheme.onSurface.withOpacity(0.6),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icono, size: 20, color: theme.colorScheme.primary),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (seleccionados.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${seleccionados.length}',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: seleccionados.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: seleccionados.take(3).map((sel) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          sel,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList()
                      ..addAll(seleccionados.length > 3
                          ? [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '+${seleccionados.length - 3}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ]
                          : []),
                  ),
                )
              : null,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: TextField(
                controller: controllerBusqueda,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar opciones...',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  suffixIcon: controllerBusqueda.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 18,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                          onPressed: () {
                            controllerBusqueda.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

            filtradas.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: theme.colorScheme.onSurface.withOpacity(0.3),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No se encontraron opciones',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: filtradas.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        thickness: 1,
                        color: theme.colorScheme.outline.withOpacity(0.1),
                      ),
                      itemBuilder: (context, index) {
                        final opc = filtradas[index];
                        final sel = seleccionados.contains(opc);
                        return InkWell(
                          onTap: () => onTap(opc),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: sel
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.outline.withOpacity(0.4),
                                      width: 2,
                                    ),
                                    color: sel
                                        ? theme.colorScheme.primary
                                        : Colors.transparent,
                                  ),
                                  child: sel
                                      ? Icon(
                                          Icons.check,
                                          size: 14,
                                          color: theme.colorScheme.onPrimary,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    opc,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                                      color: sel
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Predecir especie'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer.withOpacity(0.3),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Datos de Entrada',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Solo el tamaño se ingresa manualmente. El resto se selecciona con chips.',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildTextField(
                theme: theme,
                label: 'Tamaño de la espora',
                controller: _tamanoController,
                hint: '60-140 µm',
                icon: Icons.straighten,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el tamaño (ej: 60-140 µm)' : null,
              ),
              const SizedBox(height: 20),

              _buildMultiselectConBusqueda(
                titulo: 'Forma',
                icono: Icons.shape_line_outlined,
                opciones: _formas,
                seleccionados: _formasSeleccionadas,
                controllerBusqueda: _busquedaForma,
                onTap: (o) => setState(() {
                  if (_formasSeleccionadas.contains(o)) {
                    _formasSeleccionadas.remove(o);
                  } else {
                    _formasSeleccionadas.add(o);
                  }
                }),
                theme: theme,
              ),

              _buildMultiselectConBusqueda(
                titulo: 'Color',
                icono: Icons.palette_outlined,
                opciones: _colores,
                seleccionados: _coloresSeleccionados,
                controllerBusqueda: _busquedaColor,
                onTap: (o) => setState(() {
                  if (_coloresSeleccionados.contains(o)) {
                    _coloresSeleccionados.remove(o);
                  } else {
                    _coloresSeleccionados.add(o);
                  }
                }),
                theme: theme,
              ),

              _buildDropdownField(
                theme: theme,
                label: 'Número de paredes',
                value: _paredes,
                items: _paredesOpciones,
                icon: Icons.layers_outlined,
                onChanged: (v) => setState(() => _paredes = v ?? '1'),
              ),
              const SizedBox(height: 20),

              _buildSectionLabel(theme, Icons.science_outlined, 'Reacción con Melzer'),
              Wrap(
                spacing: 12,
                children: _reaccionesMelzer.map((r) {
                  return ChoiceChip(
                    label: Text(r),
                    selected: _reaccionMelzer == r,
                    onSelected: (_) => setState(() => _reaccionMelzer = r),
                    selectedColor: theme.colorScheme.primaryContainer,
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              _buildMultiselectConBusqueda(
                titulo: 'Conexión hifal',
                icono: Icons.account_tree_outlined,
                opciones: _conexionesHifales,
                seleccionados: _conexionesSeleccionadas,
                controllerBusqueda: _busquedaConexion,
                onTap: (o) => setState(() {
                  if (_conexionesSeleccionadas.contains(o)) {
                    _conexionesSeleccionadas.remove(o);
                  } else {
                    _conexionesSeleccionadas.add(o);
                  }
                }),
                theme: theme,
              ),

              _buildMultiselectConBusqueda(
                titulo: 'Textura',
                icono: Icons.texture,
                opciones: _texturas,
                seleccionados: _texturasSeleccionadas,
                controllerBusqueda: _busquedaTextura,
                onTap: (o) => setState(() {
                  if (_texturasSeleccionadas.contains(o)) {
                    _texturasSeleccionadas.remove(o);
                  } else {
                    _texturasSeleccionadas.add(o);
                  }
                }),
                theme: theme,
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: (_isLoading || !_formCompleto) ? null : _submitPrediction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
                  disabledForegroundColor: theme.colorScheme.onSurface.withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search),
                          const SizedBox(width: 8),
                          const Text(
                            'Predecir especie',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(ThemeData theme, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required ThemeData theme,
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            const SizedBox(width: 4),
            Text('*', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            filled: true,
            fillColor: theme.colorScheme.surface,
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required ThemeData theme,
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
          onChanged: onChanged,
          icon: Icon(Icons.arrow_drop_down, color: theme.colorScheme.primary),
          dropdownColor: theme.colorScheme.surface,
        ),
      ],
    );
  }
}

class _HintFlotanteDialogo extends StatefulWidget {
  final GlobalKey keyDialog;
  final ThemeData theme;
  final ValueNotifier<bool> mostrarHintNotifier;
  final ValueNotifier<Rect?> buttonRectGlobalNotifier;

  const _HintFlotanteDialogo({
    required this.keyDialog,
    required this.theme,
    required this.mostrarHintNotifier,
    required this.buttonRectGlobalNotifier,
  });

  @override
  State<_HintFlotanteDialogo> createState() => _HintFlotanteDialogoState();
}

class _HintFlotanteDialogoState extends State<_HintFlotanteDialogo> {
  double? _hintTopLocal;
  VoidCallback? _removeListener;

  @override
  void initState() {
    super.initState();
    void update() {
      if (!widget.mostrarHintNotifier.value) {
        setState(() => _hintTopLocal = null);
        return;
      }
      final globalRect = widget.buttonRectGlobalNotifier.value;
      if (globalRect == null) {
        setState(() => _hintTopLocal = null);
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box = widget.keyDialog.currentContext?.findRenderObject() as RenderBox?;
        if (box != null && mounted) {
          final hintTopGlobal = globalRect.bottom + 22;
          final localTop = box.globalToLocal(Offset(0, hintTopGlobal)).dy;
          setState(() => _hintTopLocal = localTop);
        }
      });
    }
    update();
    widget.buttonRectGlobalNotifier.addListener(update);
    widget.mostrarHintNotifier.addListener(update);
    _removeListener = () {
      widget.buttonRectGlobalNotifier.removeListener(update);
      widget.mostrarHintNotifier.removeListener(update);
    };
  }

  @override
  void dispose() {
    _removeListener?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.mostrarHintNotifier.value || _hintTopLocal == null) return const SizedBox.shrink();
    return Positioned(
      left: 20,
      right: 20,
      top: _hintTopLocal!,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: widget.theme.colorScheme.surface.withOpacity(0.92),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.touch_app_rounded, color: widget.theme.colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Presione aquí para saber más información sobre la especie',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: widget.theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => widget.mostrarHintNotifier.value = false,
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BodyDialogoPrediccion extends StatefulWidget {
  final String especie;
  final String? imagenUrl;
  final double? confianza;
  final Color confianzaColor;
  final ThemeData theme;
  final String Function(String) v;
  final String Function() vInformacion;
  final Map<String, dynamic> info;
  final List<dynamic>? alternativas;
  final VoidCallback onAbrirBusqueda;
  final Widget Function(IconData, String, String) buildInfoRow;
  final Widget Function(BuildContext, String, double) buildEspecieAlternativa;
  final ValueNotifier<Rect?>? buttonRectGlobalNotifier;
  final ValueNotifier<bool>? mostrarHintNotifier;

  const _BodyDialogoPrediccion({
    required this.especie,
    this.imagenUrl,
    required this.confianza,
    required this.confianzaColor,
    required this.theme,
    required this.v,
    required this.vInformacion,
    required this.info,
    required this.alternativas,
    required this.onAbrirBusqueda,
    required this.buildInfoRow,
    required this.buildEspecieAlternativa,
    this.buttonRectGlobalNotifier,
    this.mostrarHintNotifier,
  });

  @override
  State<_BodyDialogoPrediccion> createState() => _BodyDialogoPrediccionState();
}

class _BodyDialogoPrediccionState extends State<_BodyDialogoPrediccion> {
  final GlobalKey _keyStack = GlobalKey();
  final GlobalKey _keyBoton = GlobalKey();
  bool _mostrarHint = true;
  Rect? _buttonRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _medirBoton());
    widget.mostrarHintNotifier?.addListener(_onMostrarHintChanged);
  }

  @override
  void dispose() {
    widget.mostrarHintNotifier?.removeListener(_onMostrarHintChanged);
    super.dispose();
  }

  void _onMostrarHintChanged() {
    if (mounted && !(widget.mostrarHintNotifier?.value ?? true)) {
      setState(() => _mostrarHint = false);
    }
  }

  void _medirBoton() {
    final stackBox = _keyStack.currentContext?.findRenderObject() as RenderBox?;
    final buttonBox = _keyBoton.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox != null && buttonBox != null && mounted) {
      final stackPos = stackBox.localToGlobal(Offset.zero);
      final buttonPos = buttonBox.localToGlobal(Offset.zero);
      widget.buttonRectGlobalNotifier?.value = Rect.fromLTWH(
        buttonPos.dx,
        buttonPos.dy,
        buttonBox.size.width,
        buttonBox.size.height,
      );
      setState(() => _buttonRect = Rect.fromLTWH(
        buttonPos.dx - stackPos.dx,
        buttonPos.dy - stackPos.dy,
        buttonBox.size.width,
        buttonBox.size.height,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final confianza = widget.confianza;
    final confianzaColor = widget.confianzaColor;
    final alternativas = widget.alternativas;

    return Stack(
      key: _keyStack,
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  widget.especie,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (widget.imagenUrl != null && widget.imagenUrl!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      widget.imagenUrl!,
                      height: 140,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return SizedBox(
                          height: 140,
                          child: Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes!)
                                  : null,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 100,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.broken_image_outlined, size: 48, color: theme.colorScheme.outline),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (confianza != null) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: confianzaColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: confianzaColor, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: confianzaColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${confianza.toStringAsFixed(1)}% de confianza',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: confianzaColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: _mostrarHint ? const EdgeInsets.all(3) : EdgeInsets.zero,
                  decoration: _mostrarHint
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        )
                      : null,
                  child: ElevatedButton.icon(
                    key: _keyBoton,
                    onPressed: widget.onAbrirBusqueda,
                    icon: const Icon(Icons.search_rounded, size: 22),
                    label: const Text('Más información'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              widget.buildInfoRow(Icons.grass_outlined, 'Vegetación', widget.v('vegetacion')),
              widget.buildInfoRow(Icons.public, 'Hábitat', widget.v('habitat')),
              widget.buildInfoRow(Icons.place, 'País', widget.v('pais')),
              widget.buildInfoRow(Icons.location_on, 'Localidad', widget.v('localidad')),
              widget.buildInfoRow(Icons.info_outline, 'Información', widget.vInformacion()),
              widget.buildInfoRow(Icons.star_outline, 'Particularidad', widget.v('particularidad')),
              if (alternativas != null && alternativas.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Especies Alternativas',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...alternativas!.map((alt) {
                        final esp = alt['especie'] as String? ?? '';
                        final conf = alt['confianza'] as double? ?? 0.0;
                        return widget.buildEspecieAlternativa(context, esp, conf);
                      }).toList(),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _VentanaWebView extends StatefulWidget {
  final String url;
  final String titulo;

  const _VentanaWebView({required this.url, required this.titulo});

  @override
  State<_VentanaWebView> createState() => _VentanaWebViewState();
}

class _VentanaWebViewState extends State<_VentanaWebView> {
  late final WebViewController _controller;
  bool _cargando = true;
  Timer? _timerOcultarCargando;

  static const _userAgentDesktop = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _cargando = true);
          },
          onPageFinished: (_) {
            _timerOcultarCargando?.cancel();
            if (mounted) setState(() => _cargando = false);
          },
        ),
      );
    _timerOcultarCargando = Timer(const Duration(seconds: 10), () {
      if (mounted && _cargando) setState(() => _cargando = false);
    });
    _inicializarYCargar();
  }

  @override
  void dispose() {
    _timerOcultarCargando?.cancel();
    super.dispose();
  }

  Future<void> _inicializarYCargar() async {
    if (Platform.isAndroid && _controller.platform is AndroidWebViewController) {
      await (_controller.platform! as AndroidWebViewController).setUserAgent(_userAgentDesktop);
    }
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: theme.colorScheme.primary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        widget.titulo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                    child: WebViewWidget(controller: _controller),
                  ),
                  if (_cargando)
                    Container(
                      color: theme.colorScheme.surface,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: theme.colorScheme.primary),
                            const SizedBox(height: 16),
                            Text(
                              'Cargando...',
                              style: TextStyle(color: theme.colorScheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}