import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// RF-01: captura con cámara trasera y vista previa antes de confirmar.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  bool _inicializando = true;
  String? _error;
  String? _capturaPath;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _error = 'Permiso de cámara denegado.';
        _inicializando = false;
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _inicializando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudo iniciar la cámara: $e';
        _inicializando = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _tomarFoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final file = await controller.takePicture();
      setState(() => _capturaPath = file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al capturar: $e')),
      );
    }
  }

  void _confirmar() {
    if (_capturaPath != null) {
      Navigator.pop(context, _capturaPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Captura microscópica (RF-01)')),
      body: _inicializando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : _capturaPath != null
                  ? _buildPreview()
                  : _buildLivePreview(),
      floatingActionButton: _capturaPath == null && _controller != null
          ? FloatingActionButton(
              onPressed: _tomarFoto,
              child: const Icon(Icons.camera_alt_rounded),
            )
          : null,
    );
  }

  Widget _buildLivePreview() {
    final controller = _controller!;
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CameraPreview(controller),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Cámara trasera activa. Captura mínima recomendada 224×224 px.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(_capturaPath!), fit: BoxFit.contain),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _capturaPath = null),
                  child: const Text('Repetir'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _confirmar,
                  child: const Text('Usar foto'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
