import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/shop_image_utils.dart';
import 'package:geofence/utils.dart';

/// Square catalog image — fixed slot, [BoxFit.cover] (never sizes the tile to the image).
class ShopProductImage extends StatelessWidget {
  final String? imageUrl;
  final Uint8List? bytes;
  /// When null, fills the parent square. Capped at [shopProductImagePx].
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = _slotSize(constraints);
        final fillW = side != null
            ? slot
            : (constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : slot);
        final fillH = side != null
            ? slot
            : (constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? constraints.maxHeight
                : slot);

        return SizedBox(
          width: fillW,
          height: fillH,
          child: ClipRect(
            child: bytes != null
                ? Image.memory(
                    bytes!,
                    width: fillW,
                    height: fillH,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                : NetworkAvatar(
                    imageUrl: imageUrl,
                    size: math.max(fillW, fillH),
                    fit: BoxFit.cover,
                    fallbackAsset: fallbackAsset,
                  ),
          ),
        );
      },
    );
  }

  double _slotSize(BoxConstraints constraints) {
    if (side != null) {
      return side!.clamp(1.0, shopProductImagePx.toDouble());
    }
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    var slot = w;
    if (h.isFinite && h > 0 && h < slot) slot = h;
    if (!slot.isFinite || slot <= 0) slot = shopProductImagePx.toDouble();
    return slot.clamp(1.0, shopProductImagePx.toDouble());
  }
}
