import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/shop_image_utils.dart';
import 'package:geofence/utils.dart';

/// Square catalog image — always **1:1**, [BoxFit.cover] (never letterboxes).
class ShopProductImage extends StatelessWidget {
  final String? imageUrl;
  final Uint8List? bytes;

  /// Optional fixed side length. When null, fills the parent width and
  /// locks height via [AspectRatio] 1:1.
  final double? side;
  final String fallbackAsset;

  const ShopProductImage({
    super.key,
    this.imageUrl,
    this.bytes,
    this.side,
    this.fallbackAsset = iconShopNoImage,
  });

  @override
  Widget build(BuildContext context) {
    final fixed = side;
    if (fixed != null) {
      final s = fixed.clamp(1.0, shopProductImagePx.toDouble());
      return SizedBox(
        width: s,
        height: s,
        child: _squareImage(s),
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          var s = w;
          if (h.isFinite && h > 0 && h < s) s = h;
          if (!s.isFinite || s <= 0) s = shopProductImagePx.toDouble();
          return _squareImage(s);
        },
      ),
    );
  }

  Widget _squareImage(double s) {
    return ClipRect(
      child: SizedBox(
        width: s,
        height: s,
        child: bytes != null
            ? Image.memory(
                bytes!,
                width: s,
                height: s,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                gaplessPlayback: true,
              )
            : NetworkAvatar(
                imageUrl: imageUrl,
                size: s,
                fit: BoxFit.cover,
                fallbackAsset: fallbackAsset,
              ),
      ),
    );
  }
}
