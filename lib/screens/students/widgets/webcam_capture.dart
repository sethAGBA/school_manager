import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:camera/camera.dart';

class WebcamCapture extends StatefulWidget {
  final void Function(Uint8List imageBytes) onCapture;

  const WebcamCapture({required this.onCapture, Key? key}) : super(key: key);

  @override
  State<WebcamCapture> createState() => _WebcamCaptureState();
}

class _WebcamCaptureState extends State<WebcamCapture> {
  CameraController? _controller;
  bool _isLoading = true;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('Aucune caméra trouvée');
      }
      
      _controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur d\'accès à la caméra : $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isCapturing = true);
    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      widget.onCapture(bytes);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la capture : $e')),
        );
      }
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Prendre une photo'),
      content: _isLoading
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : _controller == null
              ? const Text('Aucune caméra disponible')
              : AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: CameraPreview(_controller!),
                ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _isLoading || _isCapturing ? null : _capturePhoto,
          child: _isCapturing 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Capturer'),
        ),
      ],
    );
  }
}