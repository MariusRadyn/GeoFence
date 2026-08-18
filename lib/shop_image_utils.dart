import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Catalog photos are stored and displayed as square 500×500 px JPEGs.
const int shopProductImagePx = 500;

Uint8List? normalizeShopImageBytes(
  Uint8List bytes, {
  required int cropX,
  required int cropY,
  required int cropSide,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final side = cropSide.clamp(1, math.min(decoded.width, decoded.height)).toInt();
  final x = cropX.clamp(0, decoded.width - side).toInt();
  final y = cropY.clamp(0, decoded.height - side).toInt();

  final cropped = img.copyCrop(
    decoded,
    x: x,
    y: y,
    width: side,
    height: side,
  );
  final resized = img.copyResize(
    cropped,
    width: shopProductImagePx,
    height: shopProductImagePx,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
}

/// Center square crop for gallery picks (no interactive crop UI).
Uint8List? normalizeShopImageBytesCenterCrop(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final side = math.min(decoded.width, decoded.height);
  final x = ((decoded.width - side) / 2).round();
  final y = ((decoded.height - side) / 2).round();
  return normalizeShopImageBytes(bytes, cropX: x, cropY: y, cropSide: side);
}
