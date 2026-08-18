import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geofence/shop_image_utils.dart';
import 'package:geofence/utils.dart';
import 'package:image/image.dart' as img;

/// Camera flow: drag the 500×500 crop square over the photo before saving.
class ShopImageCropPage extends StatefulWidget {
  final Uint8List imageBytes;

  const ShopImageCropPage({super.key, required this.imageBytes});

  @override
  State<ShopImageCropPage> createState() => _ShopImageCropPageState();
}

class _ShopImageCropPageState extends State<ShopImageCropPage> {
  img.Image? _decoded;
  Offset _cropOffset = Offset.zero;
  int _cropSide = 0;

  @override
  void initState() {
    super.initState();
    final decoded = img.decodeImage(widget.imageBytes);
    if (decoded == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    final side = math.min(decoded.width, decoded.height);
    _decoded = decoded;
    _cropSide = side;
    _cropOffset = Offset(
      (decoded.width - side) / 2,
      (decoded.height - side) / 2,
    );
  }

  void _onPan(DragUpdateDetails details, double scale) {
    if (_decoded == null) return;
    setState(() {
      final maxX = (_decoded!.width - _cropSide).toDouble();
      final maxY = (_decoded!.height - _cropSide).toDouble();
      _cropOffset = Offset(
        (_cropOffset.dx + details.delta.dx / scale).clamp(0, maxX),
        (_cropOffset.dy + details.delta.dy / scale).clamp(0, maxY),
      );
    });
  }

  void _confirm() {
    final normalized = normalizeShopImageBytes(
      widget.imageBytes,
      cropX: _cropOffset.dx.round(),
      cropY: _cropOffset.dy.round(),
      cropSide: _cropSide,
    );
    Navigator.pop(context, normalized);
  }

  @override
  Widget build(BuildContext context) {
    final decoded = _decoded;
    if (decoded == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: myProgressCircle()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        title: myAppbarTitle('Crop photo'),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: const Text(
              'Use photo',
              style: TextStyle(
                color: colorOrange,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight - 72;
          final scale = math.min(
            maxW / decoded.width,
            maxH / decoded.height,
          );
          final displayW = decoded.width * scale;
          final displayH = decoded.height * scale;
          final imageLeft = (maxW - displayW) / 2;
          final imageTop = (maxH - displayH) / 2;
          final cropLeft = imageLeft + _cropOffset.dx * scale;
          final cropTop = imageTop + _cropOffset.dy * scale;
          final cropSize = _cropSide * scale;

          return Column(
            children: [
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onPanUpdate: (d) => _onPan(d, scale),
                    child: SizedBox(
                      width: maxW,
                      height: maxH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: imageLeft,
                            top: imageTop,
                            width: displayW,
                            height: displayH,
                            child: Image.memory(
                              widget.imageBytes,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CropOverlayPainter(
                                cropRect: Rect.fromLTWH(
                                  cropLeft,
                                  cropTop,
                                  cropSize,
                                  cropSize,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: cropLeft,
                            top: cropTop,
                            width: cropSize,
                            height: cropSize,
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: colorOrange,
                                    width: 2.5,
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$shopProductImagePx × $shopProductImagePx',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Text(
                  'Drag the square to choose what appears in the shop '
                  '($shopProductImagePx×$shopProductImagePx px).',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;

  _CropOverlayPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}
