import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;

import '../../core/ui/ui_kit.dart';

/// Opens the camera and returns the first barcode it reads, or null.
///
/// Windows cameras do not stream frames to Flutter, so the scanner grabs a
/// still every few hundred milliseconds and decodes it with zxing-cpp
/// (native, ~25 ms per frame). Product barcodes (EAN/UPC/Code 128/…) and QR
/// codes are supported.
Future<String?> scanWithCamera(
  BuildContext context, {
  String title = 'Scan barcode',
}) => showDialog<String>(
  context: context,
  builder: (_) => _CameraScannerDialog(title: title),
);

/// Small camera button for text fields.
class CameraScanButton extends StatelessWidget {
  const CameraScanButton({required this.onScanned, super.key});
  final ValueChanged<String> onScanned;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Scan with camera',
    icon: const Icon(Icons.photo_camera_outlined),
    onPressed: () async {
      final code = await scanWithCamera(context);
      if (code != null && code.isNotEmpty) onScanned(code);
    },
  );
}

enum _State { starting, scanning, noCamera, failed }

class _CameraScannerDialog extends StatefulWidget {
  const _CameraScannerDialog({required this.title});
  final String title;

  @override
  State<_CameraScannerDialog> createState() => _CameraScannerDialogState();
}

class _CameraScannerDialogState extends State<_CameraScannerDialog> {
  List<CameraDescription> _cameras = const [];
  CameraDescription? _camera;
  CameraController? _controller;
  _State _state = _State.starting;
  String? _error;
  bool _closing = false;
  int _attempts = 0;
  final _manual = TextEditingController();

  static final _params = zxing.DecodeParams(
    format: zxing.Format.any,
    tryHarder: true,
    tryRotate: true,
    tryInverted: true,
    maxSize: 1280,
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _closing = true;
    _manual.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start([CameraDescription? camera]) async {
    setState(() {
      _state = _State.starting;
      _error = null;
    });
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _state = _State.noCamera);
        return;
      }
      final selected =
          camera ??
          _cameras
              .where((c) => c.lensDirection == CameraLensDirection.back)
              .firstOrNull ??
          _cameras.first;
      final previous = _controller;
      _controller = null;
      await previous?.dispose();
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = selected;
        _controller = controller;
        _state = _State.scanning;
      });
      unawaited(_loop(controller));
    } catch (error) {
      if (mounted) {
        setState(() {
          _state = _State.failed;
          _error = friendlyError(error);
        });
      }
    }
  }

  /// Repeatedly captures a frame and decodes it until a code is found.
  Future<void> _loop(CameraController controller) async {
    while (mounted && !_closing && identical(_controller, controller)) {
      XFile? photo;
      try {
        photo = await controller.takePicture();
        final result = await zxing.zx.readBarcodeImagePathString(
          photo.path,
          _params,
        );
        final text = result.text?.trim();
        if (result.isValid && text != null && text.isNotEmpty) {
          await SystemSound.play(SystemSoundType.click);
          if (mounted && !_closing) {
            _closing = true;
            Navigator.pop(context, text);
          }
          return;
        }
      } catch (_) {
        // A dropped frame is normal; try the next one.
      } finally {
        if (photo != null) {
          try {
            await File(photo.path).delete();
          } catch (_) {}
        }
      }
      if (mounted) setState(() => _attempts++);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  void _submitManual() {
    final code = _manual.text.trim();
    if (code.isNotEmpty) {
      _closing = true;
      Navigator.pop(context, code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 12),
              child: Row(
                children: [
                  const IconTile(icon: Icons.qr_code_scanner_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: context.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_cameras.length > 1)
                    AppSelect<String>(
                      width: 220,
                      value: _camera?.name,
                      items: [
                        for (final camera in _cameras)
                          SelectItem(
                            camera.name,
                            camera.name.split('<').first.trim(),
                            icon: Icons.videocam_outlined,
                          ),
                      ],
                      onChanged: (name) => _start(
                        _cameras.firstWhere((camera) => camera.name == name),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Close (Esc)',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 16 / 10,
              child: ColoredBox(
                color: Colors.black,
                child: switch (_state) {
                  _State.starting => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  _State.noCamera => const _Message(
                    icon: Icons.videocam_off_outlined,
                    text: 'No camera found. Connect a webcam or type the code below.',
                  ),
                  _State.failed => _Message(
                    icon: Icons.error_outline_rounded,
                    text:
                        'The camera could not start. Check Windows camera privacy settings.\n${_error ?? ''}',
                  ),
                  _State.scanning when controller != null => Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: controller.value.previewSize?.width ?? 1280,
                          height: controller.value.previewSize?.height ?? 720,
                          child: CameraPreview(controller),
                        ),
                      ),
                      const _ScanOverlay(),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 14,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              _attempts == 0
                                  ? 'Hold the barcode inside the frame'
                                  : 'Scanning… keep the barcode steady and well lit',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manual,
                      autofocus: _state != _State.scanning,
                      decoration: const InputDecoration(
                        hintText: 'Or type / scan the code here',
                        prefixIcon: Icon(Icons.keyboard_alt_outlined),
                      ),
                      onSubmitted: (_) => _submitManual(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _submitManual,
                    child: const Text('Use code'),
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 44),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

/// Darkened surround with a bright scan window and animated laser line.
class _ScanOverlay extends StatefulWidget {
  const _ScanOverlay();
  @override
  State<_ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<_ScanOverlay>
    with SingleTickerProviderStateMixin {
  late final _line = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth * 0.72;
      final h = constraints.maxHeight * 0.46;
      final left = (constraints.maxWidth - w) / 2;
      final top = (constraints.maxHeight - h) / 2;
      final accent = context.colors.primary;
      return Stack(
        children: [
          Positioned.fill(
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black45,
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    left: left,
                    top: top,
                    width: w,
                    height: h,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: w,
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent, width: 3),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _line,
            builder: (context, _) => Positioned(
              left: left + 12,
              width: w - 24,
              top: top + 10 + (h - 20) * _line.value,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
