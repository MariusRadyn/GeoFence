import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/firebase.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/utils.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

class EditProfilePicPage extends StatefulWidget {
  final String? imageURL;
  final String? imageFilename;
  final String docId;
  final String profileType;

  const EditProfilePicPage({
    required this.docId,
    required this.profileType,
    this.imageURL,
    this.imageFilename,
    super.key,
  });

  @override
  State<EditProfilePicPage> createState() => _EditProfilePicPageState();
}

class _EditProfilePicPageState extends State<EditProfilePicPage> {
  static const String _originalFilename = 'source_original.jpg';

  String? currentImageUrl;
  String? currentImgFilename;
  Uint8List? _originalBytes;
  Uint8List? _localPreviewBytes;
  bool isLoading = false;
  int _selectedIndex = 0;
  ProfilePicData profilePicData = ProfilePicData(update: false);

  @override
  void initState() {
    super.initState();
    currentImageUrl = widget.imageURL;
    currentImgFilename = widget.imageFilename;
  }

  void _warnUploading() {
    MyGlobalMessage.show(
      'Please wait',
      'Your photo is still uploading. Don’t leave until it finishes.',
      MyMessageType.warning,
    );
  }

  void _popWithResult() {
    if (isLoading) {
      _warnUploading();
      return;
    }
    Navigator.pop<ProfilePicData>(context, profilePicData);
  }

  Reference _storageChild(String filename) {
    return FirebaseStorage.instance
        .ref()
        .child(widget.profileType)
        .child(widget.docId)
        .child(filename);
  }

  Future<void> _selectImage({ImageSource? source}) async {
    if (isLoading || source == null) return;
    final ImagePicker imagePicker = ImagePicker();

    try {
      final XFile? pick = await imagePicker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (pick == null) return;

      final bytes = await pick.readAsBytes();
      if (!mounted) return;

      await _cropAndSave(bytes, replaceOriginal: true);
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      MyGlobalSnackBar.show('Image Error: $e\n$st');
    }
  }

  /// Tap the preview to re-open the cropper with the original photo.
  Future<void> _reeditFromOriginal() async {
    if (isLoading) return;

    try {
      Uint8List? bytes = _originalBytes;

      if (bytes == null) {
        setState(() => isLoading = true);
        bytes = await _loadOriginalBytes();
        if (!mounted) return;
        setState(() => isLoading = false);
      }

      if (bytes == null) {
        MyGlobalSnackBar.show(
          'No original photo to edit. Pick a new image first.',
        );
        return;
      }

      _originalBytes = bytes;
      await _cropAndSave(bytes, replaceOriginal: false);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => isLoading = false);
      MyGlobalSnackBar.show('Image Error: $e\n$st');
    }
  }

  Future<Uint8List?> _loadOriginalBytes() async {
    try {
      final data = await _storageChild(_originalFilename).getData(15 * 1024 * 1024);
      if (data != null && data.isNotEmpty) return data;
    } catch (_) {
      // Fall through — try cropped image as last resort.
    }

    final url = currentImageUrl;
    if (url == null || url.isEmpty) return null;

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _cropAndSave(
    Uint8List originalBytes, {
    required bool replaceOriginal,
  }) async {
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => ProfilePicCropPage(imageBytes: originalBytes),
      ),
    );

    if (cropped == null || !mounted) return;

    final thumb = createThumbnail(cropped);

    setState(() {
      isLoading = true;
      _localPreviewBytes = thumb;
      if (replaceOriginal) {
        _originalBytes = originalBytes;
      }
    });
    MyGlobalSnackBar.show('Uploading photo…');

    try {
      if (replaceOriginal) {
        await _uploadOriginal(originalBytes);
      }
      await _updateImage(thumb);
      if (!mounted) return;
      MyGlobalSnackBar.show('Photo saved');
    } catch (e, st) {
      if (!mounted) return;
      MyGlobalSnackBar.show('Upload failed: $e\n$st');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _uploadOriginal(Uint8List bytes) async {
    final metadata = SettableMetadata(contentType: 'image/jpeg');
    await _storageChild(_originalFilename).putData(bytes, metadata);
  }

  Future<void> _fireDeleteImage({
    required String filename,
    required String docId,
  }) async {
    try {
      await fireStoreDeleteFile("${widget.profileType}/$docId/$filename");
    } catch (e, st) {
      MyGlobalSnackBar.show('Image Error: $e\n$st');
    }
  }

  Future<String> _fireUploadImage({
    required Uint8List bytes,
    required String docId,
  }) async {
    final String name =
        'Image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    profilePicData.imageFilename = name;
    profilePicData.update = true;

    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
    );

    // putData works on web + mobile; putFile does not work on web.
    await _storageChild(name).putData(bytes, metadata);

    return _storageChild(name).getDownloadURL();
  }

  Uint8List createThumbnail(Uint8List originalBytes) {
    final image = img.decodeImage(originalBytes)!;
    final thumbnail = img.copyResize(image, width: 200, height: 200);
    return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 85));
  }

  Future<void> _updateImage(Uint8List bytes) async {
    // Upload the new file first so leaving mid-upload cannot delete the old one.
    final oldFilename = currentImgFilename;
    final imgURL = await _fireUploadImage(bytes: bytes, docId: widget.docId);
    final newFilename = profilePicData.imageFilename;

    if (!mounted) return;
    setState(() {
      currentImageUrl = imgURL;
      currentImgFilename = newFilename;
      profilePicData.imageURL = imgURL;
      _localPreviewBytes = null;
    });

    if (oldFilename != null &&
        oldFilename.isNotEmpty &&
        oldFilename != newFilename) {
      await _fireDeleteImage(
        filename: oldFilename,
        docId: widget.docId,
      );
    }
  }

  Future<void> _deleteImage() async {
    if (isLoading) return;
    if (currentImgFilename == null || currentImgFilename!.isEmpty) return;

    setState(() {
      isLoading = true;
    });
    try {
      await _fireDeleteImage(
        filename: currentImgFilename!,
        docId: widget.docId,
      );
      try {
        await _fireDeleteImage(
          filename: _originalFilename,
          docId: widget.docId,
        );
      } catch (_) {}

      setState(() {
        currentImageUrl = null;
        currentImgFilename = null;
        _originalBytes = null;
        _localPreviewBytes = null;
        profilePicData.imageURL = "";
        profilePicData.imageFilename = "";
        profilePicData.update = true;
        isLoading = false;
      });
    } catch (e) {
      MyGlobalMessage.show('Delete Image: ', '$e', MyMessageType.error);
      setState(() {
        isLoading = false;
      });
    }
  }

  Widget _buildPreview() {
    final hasLocal = _localPreviewBytes != null && _localPreviewBytes!.isNotEmpty;
    final preview = hasLocal
        ? Image.memory(
            _localPreviewBytes!,
            fit: BoxFit.contain,
            width: 280,
            height: 280,
            gaplessPlayback: true,
          )
        : kIsWeb
            ? NetworkAvatar(
                imageUrl: currentImageUrl,
                size: 280,
                fit: BoxFit.contain,
              )
            : Image(
                image: currentImageUrl != null && currentImageUrl!.isNotEmpty
                    ? CachedNetworkImageProvider(currentImageUrl!)
                        as ImageProvider
                    : const AssetImage(iconProfile) as ImageProvider,
                fit: BoxFit.contain,
                width: 280,
                height: 280,
              );

    final hasPic = hasLocal ||
        (currentImageUrl != null && currentImageUrl!.isNotEmpty);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: (!isLoading && hasPic && !hasLocal) ? _reeditFromOriginal : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipOval(child: preview),
              if (hasPic && !isLoading && !hasLocal)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.crop,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasPic && !isLoading && !hasLocal) ...[
          const SizedBox(height: 12),
          Text(
            'Tap photo to adjust crop',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isLoading,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !isLoading) return;
        _warnUploading();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: colorAppBar,
          foregroundColor: Colors.white,
          title: myAppbarTitle('Profile Picture'),
          leading: IconButton(
            onPressed: _popWithResult,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          backgroundColor: colorAppBar,
          unselectedItemColor: Colors.grey,
          selectedItemColor: Colors.grey,
          onTap: isLoading
              ? null
              : (index) async {
                  setState(() => _selectedIndex = index);
                  if (index == 0) {
                    if (kIsWeb) {
                      // Camera often unavailable in browsers — fall back to gallery.
                      await _selectImage(source: ImageSource.gallery);
                    } else {
                      await _selectImage(source: ImageSource.camera);
                    }
                  }
                  if (index == 1) await _selectImage(source: ImageSource.gallery);
                  if (index == 2) await _deleteImage();
                },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_outlined),
              label: 'Camera',
              backgroundColor: Colors.grey,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.image),
              label: 'Image',
              backgroundColor: Colors.grey,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.delete_forever),
              label: 'Delete',
              backgroundColor: Colors.grey,
            ),
          ],
        ),
        backgroundColor: colorAppBackground,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildPreview(),
              ),
            ),
            if (isLoading)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.55),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      myProgressCircle(),
                      const SizedBox(height: 16),
                      const MyText(
                        text: 'Uploading photo…',
                        color: Colors.white,
                        fontsize: 16,
                      ),
                      const SizedBox(height: 8),
                      MyText(
                        text: 'Please wait — don’t leave this screen',
                        color: Colors.white.withValues(alpha: 0.75),
                        fontsize: 13,
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
}

/// Pan / pinch / slider zoom cropper. Returns square JPEG bytes of the frame.
class ProfilePicCropPage extends StatefulWidget {
  final Uint8List imageBytes;

  const ProfilePicCropPage({required this.imageBytes, super.key});

  @override
  State<ProfilePicCropPage> createState() => _ProfilePicCropPageState();
}

class _ProfilePicCropPageState extends State<ProfilePicCropPage> {
  ui.Image? _decoded;
  double _scale = 1.0;
  /// Crop circle size as a fraction of the shorter view side (0.35–0.92).
  double _cropFactor = 0.72;
  Offset _offset = Offset.zero;

  Offset _startFocal = Offset.zero;
  Offset _startOffset = Offset.zero;
  double _startScale = 1.0;

  /// `panZoom` moves/scales the photo; `resizeFrame` changes circle size.
  _CropGestureMode _gestureMode = _CropGestureMode.panZoom;

  bool _busy = false;
  Size _viewSize = Size.zero;

  static const double _minScale = 1.0;
  static const double _maxScale = 5.0;
  static const double _minCropFactor = 0.32;
  static const double _maxCropFactor = 0.92;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _decoded = frame.image;
    });
  }

  double get _cropDiameter {
    final side = math.min(_viewSize.width, _viewSize.height);
    return side * _cropFactor;
  }

  /// Scale so the image always covers the crop circle at zoom = 1.
  double get _baseCoverScale {
    final image = _decoded;
    if (image == null || _viewSize == Size.zero) return 1.0;
    final crop = _cropDiameter;
    return math.max(crop / image.width, crop / image.height);
  }

  Size get _baseImageSize {
    final image = _decoded;
    if (image == null) return Size.zero;
    final s = _baseCoverScale;
    return Size(image.width * s, image.height * s);
  }

  bool _isNearCropEdge(Offset localPos) {
    final center = Offset(_viewSize.width / 2, _viewSize.height / 2);
    final dist = (localPos - center).distance;
    final r = _cropDiameter / 2;
    return (dist - r).abs() <= 28;
  }

  void _clampOffset() {
    final image = _decoded;
    if (image == null || _viewSize == Size.zero) return;

    final display = _baseImageSize * _scale;
    final crop = _cropDiameter;

    final maxDx = math.max(0.0, (display.width - crop) / 2);
    final maxDy = math.max(0.0, (display.height - crop) / 2);

    _offset = Offset(
      _offset.dx.clamp(-maxDx, maxDx),
      _offset.dy.clamp(-maxDy, maxDy),
    );
  }

  Future<void> _confirm() async {
    if (_decoded == null || _busy) return;

    setState(() => _busy = true);

    try {
      final cropped = await _cropBytes();
      if (!mounted) return;
      Navigator.of(context).pop(cropped);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      MyGlobalSnackBar.show('Crop failed: $e');
    }
  }

  Future<Uint8List> _cropBytes() async {
    final uiImage = _decoded!;
    final crop = _cropDiameter;
    final totalScale = _baseCoverScale * _scale;

    final displayW = uiImage.width * totalScale;
    final displayH = uiImage.height * totalScale;

    final viewCenter = Offset(_viewSize.width / 2, _viewSize.height / 2);
    final imgLeft = viewCenter.dx - displayW / 2 + _offset.dx;
    final imgTop = viewCenter.dy - displayH / 2 + _offset.dy;

    final circleLeft = viewCenter.dx - crop / 2;
    final circleTop = viewCenter.dy - crop / 2;

    var srcX = (circleLeft - imgLeft) / totalScale;
    var srcY = (circleTop - imgTop) / totalScale;
    var srcSize = crop / totalScale;

    srcX = srcX.clamp(0.0, uiImage.width.toDouble() - 1);
    srcY = srcY.clamp(0.0, uiImage.height.toDouble() - 1);
    srcSize = srcSize.clamp(
      1.0,
      math.min(uiImage.width - srcX, uiImage.height - srcY),
    );

    final decoded = img.decodeImage(widget.imageBytes);
    if (decoded == null) {
      throw StateError('Could not decode image for crop');
    }

    final x = srcX.round().clamp(0, decoded.width - 1).toInt();
    final y = srcY.round().clamp(0, decoded.height - 1).toInt();
    final size = srcSize
        .round()
        .clamp(1, math.min(decoded.width - x, decoded.height - y))
        .toInt();

    final square = img.copyCrop(
      decoded,
      x: x,
      y: y,
      width: size,
      height: size,
    );

    return Uint8List.fromList(img.encodeJpg(square, quality: 90));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Adjust photo'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _busy || _decoded == null ? null : _confirm,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Use photo',
                    style: TextStyle(color: Colors.lightBlueAccent),
                  ),
          ),
        ],
      ),
      body: _decoded == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _viewSize =
                          Size(constraints.maxWidth, constraints.maxHeight);
                      final crop = _cropDiameter;
                      final base = _baseImageSize;

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (details) {
                          _startFocal = details.localFocalPoint;
                          _startOffset = _offset;
                          _startScale = _scale;

                          if (details.pointerCount >= 2) {
                            _gestureMode = _CropGestureMode.panZoom;
                          } else if (_isNearCropEdge(details.localFocalPoint)) {
                            _gestureMode = _CropGestureMode.resizeFrame;
                          } else {
                            _gestureMode = _CropGestureMode.panZoom;
                          }
                        },
                        onScaleUpdate: (details) {
                          setState(() {
                            if (_gestureMode == _CropGestureMode.resizeFrame &&
                                details.pointerCount < 2) {
                              // Drag circle edge to resize (distance from center).
                              final center = Offset(
                                _viewSize.width / 2,
                                _viewSize.height / 2,
                              );
                              final dist =
                                  (details.localFocalPoint - center).distance;
                              final side = math.min(
                                _viewSize.width,
                                _viewSize.height,
                              );
                              _cropFactor = ((dist * 2) / side)
                                  .clamp(_minCropFactor, _maxCropFactor);
                              _clampOffset();
                              return;
                            }

                            // Uniform zoom from pinch scale (not width/height stretch).
                            if (details.pointerCount >= 2) {
                              _scale = (_startScale * details.scale)
                                  .clamp(_minScale, _maxScale);
                            }

                            final delta =
                                details.localFocalPoint - _startFocal;
                            _offset = _startOffset + delta;
                            _clampOffset();
                          });
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Photo — aspect locked; zoom via Transform.scale
                            Center(
                              child: Transform.translate(
                                offset: _offset,
                                child: Transform.scale(
                                  scale: _scale,
                                  child: Image.memory(
                                    widget.imageBytes,
                                    width: base.width,
                                    height: base.height,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.medium,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ),
                            ),

                            CustomPaint(
                              painter: _CircleCropOverlayPainter(
                                diameter: crop,
                                borderColor: Colors.white,
                                showHandles: true,
                              ),
                            ),

                            const Positioned(
                              left: 16,
                              right: 16,
                              bottom: 12,
                              child: Text(
                                'Drag photo to move · Pinch to zoom · Drag circle edge to resize',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.circle_outlined,
                                color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 70,
                              child: Text(
                                'Frame',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                value: _cropFactor,
                                min: _minCropFactor,
                                max: _maxCropFactor,
                                activeColor: Colors.lightBlueAccent,
                                onChanged: (v) {
                                  setState(() {
                                    _cropFactor = v;
                                    _clampOffset();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.zoom_in,
                                color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 70,
                              child: Text(
                                'Zoom',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                value: _scale,
                                min: _minScale,
                                max: _maxScale,
                                activeColor: Colors.lightBlueAccent,
                                onChanged: (v) {
                                  setState(() {
                                    _scale = v;
                                    _clampOffset();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

enum _CropGestureMode { panZoom, resizeFrame }

class _CircleCropOverlayPainter extends CustomPainter {
  final double diameter;
  final Color borderColor;
  final bool showHandles;

  _CircleCropOverlayPainter({
    required this.diameter,
    required this.borderColor,
    this.showHandles = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = diameter / 2;

    final overlay = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final cutout = Path.combine(PathOperation.difference, overlay, hole);

    canvas.drawPath(
      cutout,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    if (showHandles) {
      final handlePaint = Paint()..color = Colors.lightBlueAccent;
      final handleBorder = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      const handleR = 7.0;
      final handles = <Offset>[
        Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius),
        Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy),
      ];
      for (final h in handles) {
        canvas.drawCircle(h, handleR, handlePaint);
        canvas.drawCircle(h, handleR, handleBorder);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CircleCropOverlayPainter oldDelegate) {
    return oldDelegate.diameter != diameter ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.showHandles != showHandles;
  }
}
