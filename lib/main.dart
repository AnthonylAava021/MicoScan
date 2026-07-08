import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestEntry, BoxHitTestResult;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'clima_service.dart';
import 'ma_analysis/estadisticas_screen.dart';
import 'ma_analysis/preprocessing_pipeline_screen.dart';
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

void main() {
  runApp(const MicoScanApp());
}

class MicoScanApp extends StatelessWidget {
  const MicoScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MicoScan',
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
  static const _splashLogoPath = 'logo/logoo.png';
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
          'MicoScan necesita acceso a la ubicación.\n\n¿Permitir acceso?',
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
                          'Sistema de segmentación y clasificación de micorrizas arbusculares',
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

  final List<GlobalKey> _featureCardKeys = List.generate(2, (_) => GlobalKey());
  bool _guiaTarjetasActiva = false;
  int _guiaTarjetasIndice = 0;
  Rect? _guiaCardBounds;
  int _selectedIndex = 0;

  // Carrusel
  late PageController _carruselController;
  int _carruselPagina = 0;
  Timer? _carruselTimer;

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

    // Carrusel automático
    _carruselController = PageController();
    _carruselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final siguiente = (_carruselPagina + 1) % 2;
      _carruselController.animateToPage(
        siguiente,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
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
                'MicoScan tiene como objetivo apoyar el análisis de imágenes de hongos micorrízicos arbusculares (MA) '
                'para la identificación y cuantificación de sus estructuras clave (Hifas, Vesículas y Arbúsculos) '
                'a partir de muestras microscópicas.\n\n'
                'La aplicación permite capturar o cargar imágenes, realizar segmentación y obtener una clasificación '
                'preliminar y reporte técnico, para uso en campo, docencia o investigación.',
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
                'Gracias por usar MicoScan.\n\n'
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
                'MicoScan\n'
                'Sistema de análisis por imagen (segmentación y clasificación) de estructuras de hongos micorrízicos arbusculares.\n\n'
                'Versión 1.0.1',
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

  void _mostrarDetallesGiiar(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: theme.colorScheme.surface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.hub_rounded,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'GIIAR',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Grupo de Investigación en Inteligencia Artificial y Reconocimiento Facial',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Universidad Politécnica Salesiana\nSede Guayaquil, Ecuador',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Divider(height: 24, thickness: 1.2),
              Text(
                'Perfil y Misión',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'El GIIAR se dedica a organizar, analizar, modelar e implementar proyectos de investigación en el ámbito de la Inteligencia Artificial, con el objetivo de abordar problemas concretos del entorno social y cultural, aspirando a ser un referente científico nacional e internacional.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  color: theme.colorScheme.onSurface.withOpacity(0.85),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Coordinador',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.person_rounded, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Quiroz Martinez Miguel Angel',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Líneas de Investigación Clave',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              _buildLineaResearchItem(theme, 'Inteligencia artificial y aprendizaje automático'),
              _buildLineaResearchItem(theme, 'Reconocimiento facial y visión por computadora'),
              _buildLineaResearchItem(theme, 'Analítica predictiva y sistemas inteligentes'),
              _buildLineaResearchItem(theme, 'Tecnologías inclusivas y educativas con IA'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
            ),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildLineaResearchItem(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Icon(
              Icons.circle,
              size: 6,
              color: theme.colorScheme.primary.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiiarCreditCard(BuildContext context, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _mostrarDetallesGiiar(context, theme),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F0FE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hub_rounded,
                    color: Color(0xFF0B57D0),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RESPALDO CIENTÍFICO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0B57D0),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Desarrollado por GIIAR - UPS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Grupo de Inteligencia Artificial y Reconocimiento Facial. Presiona para ver más.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const List<Map<String, dynamic>> _tarjetasMenuGuia = [
    {
      'title': 'Segmentación y clasificación',
      'icon': Icons.photo_camera_back_rounded,
      'description': 'Módulo central para análisis por imagen. Permite captura directa o carga desde galería, '
          'segmentación por umbral y clasificación preliminar de la muestra con reporte de confianza.',
    },
    {
      'title': 'Sobre micorrizas',
      'icon': Icons.eco_rounded,
      'description': 'Información educativa sobre micorrizas arbusculares, centrándose en hifas, vesículas y arbúsculos.',
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

  Future<void> _abrirSegmentacionPrincipal(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const SegmentacionClasificacionScreen(),
      ),
    );
    if (result == 'pipeline' && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PreprocesarPipelineScreen()),
      );
    }
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

  Widget _buildCarruselTarjetas(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 240,
          child: PageView(
            controller: _carruselController,
            onPageChanged: (i) => setState(() => _carruselPagina = i),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _buildDiagnosticoHeroCard(theme),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _buildCondicionesResumenStrip(theme),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(2, (i) {
            final activo = i == _carruselPagina;
            return GestureDetector(
              onTap: () => _carruselController.animateToPage(
                i,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: activo ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: activo
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildDiagnosticoHeroCard(ThemeData theme) {

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDDF5F2), Color(0xFFCBECE8)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.document_scanner_rounded,
              size: 36,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Ver diagnóstico',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _abrirSegmentacionPrincipal(context),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Tomar una foto', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCondicionesResumenStrip(ThemeData theme) {
    final temp = _climaData == null
        ? null
        : (_climaData!['temp'] as double?)?.round();
    final estadoClima = (_climaData?['weather_name'] as String?) ?? 'Condición estable';
    final humedad    = _climaData?['humidity'] as int?;
    final feels      = (_climaData?['feels_like'] as double?)?.round();
    final code       = _climaData?['weather_code'] as int?;
    final wind       = (_climaData?['wind_speed_kmh'] as num?)?.toDouble();
    final precip     = (_climaData?['precipitation'] as num?)?.toDouble() ?? 0;
    final sueloNivel = _climaData?['suelo_nivel'] as String? ?? '—';

    // Estado de pulverización basado en humedad
    final Color estadoColor;
    final String estadoPulv;
    final IconData estadoIcon;
    if (humedad == null) {
      estadoPulv  = 'Sin datos';
      estadoColor = Colors.grey;
      estadoIcon  = Icons.help_outline_rounded;
    } else if (humedad >= 75) {
      estadoPulv  = 'No recomendado';
      estadoColor = const Color(0xFFE53935);
      estadoIcon  = Icons.cancel_rounded;
    } else if (humedad >= 55) {
      estadoPulv  = 'Moderado';
      estadoColor = const Color(0xFFF57C00);
      estadoIcon  = Icons.warning_amber_rounded;
    } else {
      estadoPulv  = 'Favorable';
      estadoColor = const Color(0xFF2E7D32);
      estadoIcon  = Icons.check_circle_rounded;
    }

    final gradColors = _climaGradient(code);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradColors,
        ),
        boxShadow: [
          BoxShadow(
            color: gradColors[0].withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fila 1: fecha + badge estado ──────────────────────────────
            Row(
              children: [
                Text(
                  '${DateTime.now().day} ${_mesCorto(DateTime.now().month)}  •  ${TimeOfDay.now().format(context)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                // Badge condición de análisis
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: estadoColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: estadoColor.withValues(alpha: 0.6), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(estadoIcon, size: 13, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        estadoPulv,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Fila 2: temperatura grande + icono glow ────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icono clima con glow
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.15),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _climaLoading ? Icons.hourglass_top_rounded : weatherIcon(code),
                    size: 30,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Temperatura
                      if (_climaLoading)
                        const Text(
                          '— °C',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: Colors.white54,
                            height: 1.0,
                            letterSpacing: -1.5,
                          ),
                        )
                      else
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: temp != null ? '$temp' : '—',
                                style: const TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1.0,
                                  letterSpacing: -2,
                                ),
                              ),
                              const TextSpan(
                                text: ' °C',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white70,
                                  height: 2.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        estadoClima,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (feels != null)
                        Text(
                          'Sensación $feels °C',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Línea divisora sutil ──────────────────────────────────────
            if (!_climaLoading && _climaData != null) ...[
              const SizedBox(height: 16),
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 14),

              // ── Fila 3: métricas compactas ──────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (humedad != null)
                      _buildWeatherPill(Icons.water_drop_rounded, '$humedad%', 'Humedad'),
                    if (sueloNivel != '—')
                      _buildWeatherPill(Icons.grass_rounded, sueloNivel, 'Suelo'),
                    if (precip > 0)
                      _buildWeatherPill(Icons.umbrella_rounded, '${precip.toStringAsFixed(1)} mm', 'Lluvia'),
                    if (wind != null)
                      _buildWeatherPill(Icons.air_rounded, '${wind.round()} km/h', 'Viento'),
                    // Etiqueta "Condiciones análisis"
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(estadoIcon, size: 14, color: Colors.white),
                          const SizedBox(height: 2),
                          Text(
                            'Análisis',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            estadoPulv,
                            style: const TextStyle(fontSize: 9, color: Colors.white60),
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
    );
  }

  Widget _buildWeatherPill(IconData icon, String value, String label) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(label,
              style: const TextStyle(fontSize: 9, color: Colors.white60)),
        ],
      ),
    );
  }



  String _mesCorto(int mes) {
    const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    if (mes < 1 || mes > 12) return '—';
    return meses[mes - 1];
  }

  // ── Gradiente dinámico según código de clima ──────────────────────────────
  List<Color> _climaGradient(int? code) {
    if (code == null) return [const Color(0xFF1565C0), const Color(0xFF42A5F5)];
    if (code == 0)           return [const Color(0xFFFF8F00), const Color(0xFFFFCA28)]; // soleado
    if (code <= 2)           return [const Color(0xFF1565C0), const Color(0xFF64B5F6)]; // parcial
    if (code <= 48)          return [const Color(0xFF546E7A), const Color(0xFF90A4AE)]; // niebla
    if (code <= 67)          return [const Color(0xFF0277BD), const Color(0xFF4FC3F7)]; // lluvia
    if (code <= 86)          return [const Color(0xFF37474F), const Color(0xFF90A4AE)]; // nieve
    return [const Color(0xFF4A148C), const Color(0xFF7B1FA2)];                          // tormenta
  }

  Widget _buildClimaCard(ThemeData theme) {
    final code      = _climaData?['weather_code'] as int?;
    final gradColors = _climaGradient(code);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradColors,
        ),
        boxShadow: [
          BoxShadow(
            color: gradColors[0].withValues(alpha: 0.45),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onClimaTap(context, theme),
          borderRadius: BorderRadius.circular(24),
          splashColor: Colors.white12,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Fila superior: ubicación + refresh ──────────────────────
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 14, color: Colors.white70),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _climaData?['location'] ??
                            (_climaLoading
                                ? 'Obteniendo ubicación...'
                                : _climaSinUbicacion
                                    ? 'Sin ubicación'
                                    : 'Clima en tiempo real'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Badge "En vivo"
                    if (!_climaLoading && _climaData != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white38, width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle,
                                size: 6, color: Color(0xFF69F0AE)),
                            SizedBox(width: 4),
                            Text('En vivo',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _cargarClima,
                      child: _climaLoading
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white70))
                          : const Icon(Icons.refresh_rounded,
                              size: 20, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Estado de la tarjeta ─────────────────────────────────────
                if (_climaLoading)
                  _buildClimaShimmer()
                else if (_climaSinUbicacion)
                  _buildClimaSinUbicacion()
                else if (_climaError != null)
                  _buildClimaError()
                else if (_climaData != null)
                  _buildClimaDatos(theme, _climaData!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClimaShimmer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: Colors.white12,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    width: 80, height: 42,
                    decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 6),
                Container(
                    width: 110, height: 14,
                    decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6))),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: List.generate(3, (i) => Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
              height: 52,
              decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12)),
            ),
          )),
        ),
      ],
    );
  }

  Widget _buildClimaSinUbicacion() {
    return Column(
      children: [
        const Icon(Icons.location_off_rounded,
            size: 36, color: Colors.white60),
        const SizedBox(height: 8),
        const Text(
          'Activa la ubicación para ver\nel clima en tu zona',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.white70),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => openAppSettings(),
          icon: const Icon(Icons.settings_rounded,
              size: 16, color: Colors.white),
          label: const Text('Abrir ajustes',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white54),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildClimaError() {
    return Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _climaError!,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 2,
          ),
        ),
        TextButton(
          onPressed: _cargarClima,
          child: const Text('Reintentar',
              style: TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildClimaDatos(ThemeData theme, Map<String, dynamic> d) {
    final temp        = d['temp'] as double?;
    final feels       = d['feels_like'] as double?;
    final humidity    = d['humidity'] as int?;
    final precip      = (d['precipitation'] as num?)?.toDouble() ?? 0;
    final weatherName = d['weather_name'] as String? ?? '—';
    final code        = d['weather_code'] as int?;
    final sueloNivel  = d['suelo_nivel'] as String? ?? '—';
    final wind        = (d['wind_speed_kmh'] as num?)?.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Temperatura grande + icono ──────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icono con circulo glow
            Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.2),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                weatherIcon(code),
                size: 34,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Temperatura
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: temp != null ? '${temp.round()}' : '—',
                        style: const TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.0,
                          letterSpacing: -2,
                        ),
                      ),
                      const TextSpan(
                        text: '°C',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w400,
                          color: Colors.white70,
                          height: 1.8,
                        ),
                      ),
                    ],
                  ),
                ),
                // Descripción del tiempo
                Text(
                  weatherName,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                if (feels != null)
                  Text(
                    'Sensación ${feels.round()}°C',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white60,
                    ),
                  ),
              ],
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 16),

        // ── Chips de métricas ────────────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (humidity != null)
                _buildClimaMetric(
                    Icons.water_drop_rounded, '$humidity%', 'Humedad'),
              if (sueloNivel != '—')
                _buildClimaMetric(
                    Icons.grass_rounded, sueloNivel, 'Suelo'),
              if (precip > 0)
                _buildClimaMetric(
                    Icons.umbrella_rounded,
                    '${precip.toStringAsFixed(1)} mm',
                    'Lluvia'),
              if (wind != null)
                _buildClimaMetric(
                    Icons.air_rounded,
                    '${wind.round()} km/h',
                    'Viento'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClimaMetric(IconData icon, String value, String label) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildClimaChip(ThemeData theme, IconData icon, String label,
      String value, {String? sub}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
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
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface)),
                if (sub != null && sub.isNotEmpty)
                  Text(sub,
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
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
    _carruselTimer?.cancel();
    _carruselController.dispose();
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.eco_outlined),
            selectedIcon: Icon(Icons.eco),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Estadísticas',
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // Pantalla 0: Inicio
          Stack(
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
                          'MicoScan',
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
                      _buildCarruselTarjetas(theme),
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
                      _buildGiiarCreditCard(context, theme),
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
      // Pantalla 1: Estadísticas
      const EstadisticasScreen(),
    ], // fin IndexedStack children
  ), // fin IndexedStack (body)
    )); // fin Scaffold + PopScope
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
        'icon': Icons.eco_rounded,
        'title': 'Sobre micorrizas',
        'description': 'Estructuras arbusculares',
        'color': Colors.purple,
      },
    ];

    final onTaps = [
      () => _abrirSegmentacionPrincipal(context),
      () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SobreMicorrizasScreen(theme: theme),
            ),
          ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.95,
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
    final isNovedad = title == 'Sobre micorrizas';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: color.withOpacity(0.2),
        highlightColor: color.withOpacity(0.08),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFE5E7EB),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF2FF),
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
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
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


class SobreMicorrizasScreen extends StatefulWidget {
  final ThemeData theme;

  const SobreMicorrizasScreen({super.key, required this.theme});

  @override
  State<SobreMicorrizasScreen> createState() => _SobreMicorrizasScreenState();
}

class _SobreMicorrizasScreenState extends State<SobreMicorrizasScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _activeQuizQuestion = 0;
  int? _selectedQuizAnswer;
  bool _quizSubmitted = false;
  int _quizScore = 0;

  // Quiz Questions Data
  final List<Map<String, dynamic>> _quizQuestions = [
    {
      'question': '¿Qué estructura es el centro de intercambio metabólico donde se transfieren los nutrientes?',
      'options': ['Hifas extrarradicales', 'Vesículas terminales', 'Arbúsculos ramificados'],
      'correctIndex': 2,
      'explanation': '¡Correcto! Los arbúsculos crean una enorme superficie de contacto para el intercambio activo de nutrientes entre la planta y el hongo.',
    },
    {
      'question': '¿Cuál es la función principal de las vesículas fúngicas?',
      'options': ['Explorar el suelo en busca de agua', 'Almacenamiento de triacilgliceroles y energía', 'Apresar nematodos patógenos'],
      'correctIndex': 1,
      'explanation': '¡Correcto! Las vesículas actúan como órganos de reserva cargados de lípidos y polifosfatos para periodos de latencia vegetal.',
    },
    {
      'question': '¿Qué compuesto de tinción se une a la quitina fúngica tiñendo el micelio de azul?',
      'options': ['Hidróxido de potasio (KOH)', 'Azul de Tripán', 'Ácido Clorhídrico (HCl)'],
      'correctIndex': 1,
      'explanation': '¡Correcto! El Azul de Tripán al 0.05% tiñe selectivamente las paredes de quitina fúngica de un color azul intenso.',
    },
    {
      'question': '¿Cuál es el primer paso en la colonización radicular de los hongos HMA?',
      'options': ['Penetración de la pared cortical', 'Germinación e inducción por exudados radiculares', 'Fusión nuclear con las células de la planta'],
      'correctIndex': 1,
      'explanation': '¡Correcto! La germinación de las esporas fúngicas se estimula mediante exudados químicos (como estrigolactonas) liberados por la raíz hospedera.',
    },
    {
      'question': '¿Qué es la glomalina y cuál es su beneficio principal en el suelo?',
      'options': ['Una hormona de crecimiento vegetal', 'Una glicoproteína insoluble que estabiliza y cementa los agregados del suelo', 'Un veneno contra insectos succionadores'],
      'correctIndex': 1,
      'explanation': '¡Correcto! La glomalina es secretada por las hifas extrarradicales, actuando como un pegamento que une las partículas del suelo y combate la erosión.',
    },
    {
      'question': '¿Cuál es el ciclo de vida útil estimado para un arbúsculo metabólicamente activo?',
      'options': ['De 5 a 12 días', 'Aproximadamente 6 meses', 'Todo el periodo vegetativo del cultivo'],
      'correctIndex': 0,
      'explanation': '¡Correcto! Los arbúsculos tienen un ciclo dinámico muy efímero de 5 a 12 días, colapsando para liberar nutrientes residuales a la planta.',
    }
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _resetQuiz() {
    setState(() {
      _activeQuizQuestion = 0;
      _selectedQuizAnswer = null;
      _quizSubmitted = false;
      _quizScore = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Guía de Micorrizas'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.onPrimary,
          indicatorWeight: 3.5,
          labelColor: theme.colorScheme.onPrimary,
          unselectedLabelColor: theme.colorScheme.onPrimary.withOpacity(0.6),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
          tabs: const [
            Tab(icon: Icon(Icons.eco_rounded), text: 'Simbiosis'),
            Tab(icon: Icon(Icons.lens_blur_rounded), text: 'Estructuras'),
            Tab(icon: Icon(Icons.science_rounded), text: 'Laboratorio'),
            Tab(icon: Icon(Icons.psychology_rounded), text: 'Trivia'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSimbiosisTab(),
          _buildEstructurasTab(),
          _buildLaboratorioTab(),
          _buildTriviaTab(),
        ],
      ),
    );
  }

  // TAB 1: SIMBIOSIS GENERAL
  Widget _buildSimbiosisTab() {
    final theme = widget.theme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          elevation: 0,
          color: theme.colorScheme.primaryContainer.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.15)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.eco_rounded, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Simbiosis Ancestral',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'La micorriza arbuscular (HMA) es una asociación simbiótica mutualista ancestral que data de hace más de 450 millones de años, fundamental para la colonización terrestre de las plantas.\n\nSe establece entre hongos del filo Glomeromycota y las raíces de más del 80% de las familias botánicas terrestres. En esta relación de beneficio mutuo, el hongo suministra agua y nutrientes del suelo (especialmente fósforo) y la planta provee carbohidratos.',
                  style: TextStyle(fontSize: 15, height: 1.5, color: theme.colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Beneficios Clave',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 10),
        _buildBenefitItem(
          Icons.water_drop_rounded,
          'Tolerancia Sequía',
          'Las hifas extrarradicales exploran micro-poros profundos aumentando la absorción hídrica de los cultivos.',
          theme.colorScheme.primary,
        ),
        _buildBenefitItem(
          Icons.shield_rounded,
          'Protección Fitosanitaria',
          'Dificulta la colonización de nematodos y patógenos como Fusarium induciendo defensas en la raíz.',
          theme.colorScheme.primary,
        ),
        _buildBenefitItem(
          Icons.auto_awesome_rounded,
          'Estructura y Salud del Suelo',
          'El hongo secreta glomalina, estabilizando agregados físicos y combatiendo la erosión del suelo.',
          theme.colorScheme.primary,
        ),
        _buildBenefitItem(
          Icons.energy_savings_leaf_rounded,
          'Nutrición y Ahorro de Insumos',
          'Optimiza la asimilación del fósforo natural fijo, permitiendo reducir la aplicación de fertilizantes químicos sintéticos.',
          theme.colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildBenefitItem(IconData icon, String title, String body, Color iconColor) {
    final theme = widget.theme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.8)),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // TAB 2: EXPLORADOR INTERACTIVO DE ESTRUCTURAS
  Widget _buildEstructurasTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildInteractiveStructureCard(
          '1. Arbúsculo (La Interfaz)',
          'Los arbúsculos son estructuras ramificadas intracelulares arborescentes donde ocurre el intercambio de fósforo, nitrógeno y carbono entre planta y hongo.',
          'Duración: Su ciclo de vida es efímero (5-12 días), tras lo cual se disuelven reabasteciendo a la célula cortical radicular.',
          const Color(0xFFDC1E1E), // Rojo
          Icons.grain_rounded,
        ),
        _buildInteractiveStructureCard(
          '2. Vesícula (El Almacén)',
          'Órganos ovoides intercelulares e intracelulares con paredes gruesas cargados con triacilgliceroles, lípidos y polifosfatos.',
          'Supervivencia: Actúan como el principal reservorio de energía del hongo ante periodos de senescencia o estrés vegetal.',
          const Color(0xFF1E64FF), // Azul
          Icons.lens_blur_rounded,
        ),
        _buildInteractiveStructureCard(
          '3. Hifa (La Red de Exploración)',
          'Conductos microscópicos de quitina divididos en micelio extrarradical (explora el suelo) e intrarradical (transporta nutrientes por la corteza).',
          'Eficiencia: Multiplican hasta 100 veces el alcance físico de absorción de las raíces de la planta.',
          const Color(0xFF14C828), // Verde
          Icons.alt_route_rounded,
        ),
      ],
    );
  }

  Widget _buildInteractiveStructureCard(
    String title,
    String description,
    String note,
    Color accentColor,
    IconData icon,
  ) {
    final theme = widget.theme;
    return StatefulBuilder(
      builder: (context, setStateCard) {
        bool isExpanded = false;
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: accentColor.withOpacity(0.3), width: 1.5),
          ),
          child: InkWell(
            onTap: () {
              setStateCard(() {
                isExpanded = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: accentColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(fontSize: 14, height: 1.5, color: theme.colorScheme.onSurface.withOpacity(0.85)),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 12),
                    Divider(color: accentColor.withOpacity(0.15)),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: accentColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            note,
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // TAB 3: PASOS DE LABORATORIO
  Widget _buildLaboratorioTab() {
    final theme = widget.theme;
    final steps = [
      {
        'title': '1. Clarificación (KOH)',
        'desc': 'Se sumergen las raíces en Hidróxido de Potasio (KOH al 10%) a 90°C. Esto degrada el citoplasma y pigmentos de la raíz sin destruir las estructuras de quitina fúngica.',
        'icon': Icons.opacity_rounded,
      },
      {
        'title': '2. Acidificación (HCl)',
        'desc': 'Las raíces clarificadas se neutralizan con Ácido Clorhídrico (HCl al 1%) para facilitar la adhesión química del colorante posterior.',
        'icon': Icons.science_rounded,
      },
      {
        'title': '3. Tinción (Azul de Tripán)',
        'desc': 'Se calientan las raíces teñidas en una solución ácida de Azul de Tripán al 0.05%. El reactivo tiñe de color azul intenso las hifas, vesículas y arbúsculos fúngicos.',
        'icon': Icons.colorize_rounded,
      }
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Protocolo de Laboratorio',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 12),
        ...List.generate(steps.length, (idx) {
          final s = steps[idx];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(s['icon'] as IconData, color: theme.colorScheme.onPrimary, size: 20),
                    ),
                    if (idx < steps.length - 1)
                      Container(
                        width: 2.5,
                        height: 90,
                        color: theme.colorScheme.primary.withOpacity(0.3),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.1)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s['title'] as String,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s['desc'] as String,
                            style: TextStyle(fontSize: 14, height: 1.45, color: theme.colorScheme.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // TAB 4: TRIVIA INTERACTIVA
  Widget _buildTriviaTab() {
    final theme = widget.theme;
    if (_activeQuizQuestion >= _quizQuestions.length) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 72),
            const SizedBox(height: 16),
            Text(
              '¡Desafío Completado!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Tu puntuación es de $_quizScore de ${_quizQuestions.length} respuestas correctas.',
              style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface.withOpacity(0.8)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _resetQuiz,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Reintentar Trivia'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          ],
        ),
      );
    }

    final q = _quizQuestions[_activeQuizQuestion];
    final options = q['options'] as List<String>;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pregunta ${_activeQuizQuestion + 1}/${_quizQuestions.length}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
            ),
            Text(
              'Puntos: $_quizScore',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (_activeQuizQuestion + 1) / _quizQuestions.length,
          backgroundColor: theme.colorScheme.outline.withOpacity(0.15),
          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 20),
        Text(
          q['question'] as String,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 20),
        ...List.generate(options.length, (idx) {
          final isSelected = _selectedQuizAnswer == idx;
          final isCorrect = idx == q['correctIndex'];
          
          Color cardColor = theme.colorScheme.surfaceContainerLow;
          Color borderColor = theme.colorScheme.outline.withOpacity(0.15);

          if (_quizSubmitted) {
            if (isCorrect) {
              cardColor = Colors.green.shade50;
              borderColor = Colors.green.shade400;
            } else if (isSelected) {
              cardColor = Colors.red.shade50;
              borderColor = Colors.red.shade400;
            }
          } else if (isSelected) {
            cardColor = theme.colorScheme.primaryContainer.withOpacity(0.3);
            borderColor = theme.colorScheme.primary;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: isSelected || _quizSubmitted ? 2.0 : 1.0),
            ),
            child: InkWell(
              onTap: _quizSubmitted ? null : () {
                setState(() {
                  _selectedQuizAnswer = idx;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      String.fromCharCode(65 + idx) + '.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        options[idx],
                        style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 20),
        if (!_quizSubmitted)
          ElevatedButton(
            onPressed: _selectedQuizAnswer == null ? null : () {
              setState(() {
                _quizSubmitted = true;
                if (_selectedQuizAnswer == q['correctIndex']) {
                  _quizScore++;
                }
              });
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Enviar Respuesta'),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _selectedQuizAnswer == q['correctIndex']
                  ? Colors.green.shade50
                  : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedQuizAnswer == q['correctIndex']
                    ? Colors.green.shade200
                    : Colors.amber.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedQuizAnswer == q['correctIndex'] ? '¡Correcto!' : 'Respuesta incorrecta',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _selectedQuizAnswer == q['correctIndex'] ? Colors.green.shade800 : Colors.amber.shade800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  q['explanation'] as String,
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _activeQuizQuestion++;
                _selectedQuizAnswer = null;
                _quizSubmitted = false;
              });
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              _activeQuizQuestion == _quizQuestions.length - 1 ? 'Ver Puntuación' : 'Siguiente Pregunta',
            ),
          )
        ]
      ],
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
