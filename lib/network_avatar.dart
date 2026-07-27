import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'network_avatar_stub.dart'
    if (dart.library.html) 'network_avatar_web.dart' as web_img;

const String _defaultProfileAsset = 'assets/profile.png';
const Color _defaultAvatarBg = Color.fromARGB(202, 139, 229, 245);

/// Shared image helper:
/// - **Android / iOS / desktop:** [CachedNetworkImage] / [CachedNetworkImageProvider]
/// - **Web:** HTML `<img>` (CanvasKit cannot read Firebase/Google bytes without CORS)
class NetworkAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String fallbackAsset;
  final BoxFit fit;

  const NetworkAvatar({
    super.key,
    required this.imageUrl,
    this.size = 48,
    this.fallbackAsset = _defaultProfileAsset,
    this.fit = BoxFit.cover,
  });

  bool get _hasUrl => imageUrl != null && imageUrl!.trim().isNotEmpty;

  /// Use with [CircleAvatar.backgroundImage] on non-web only.
  /// Returns null on web — use [NetworkAvatar] / [NetworkCircleAvatar] instead.
  static ImageProvider imageProvider(
    String? imageUrl, {
    String fallbackAsset = _defaultProfileAsset,
  }) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) {
      return AssetImage(fallbackAsset);
    }
    // CachedNetworkImageProvider is for Android/mobile — not web CORS path.
    if (kIsWeb) {
      return AssetImage(fallbackAsset);
    }
    return CachedNetworkImageProvider(url);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasUrl) {
      return Image.asset(
        fallbackAsset,
        width: size,
        height: size,
        fit: fit,
      );
    }

    // ---- WEB ----
    if (kIsWeb) {
      // HtmlElementView eats gestures; ignore so parent GestureDetector works.
      return IgnorePointer(
        child: web_img.buildWebNetworkImage(
          url: imageUrl!.trim(),
          width: size,
          height: size,
          fit: fit,
        ),
      );
    }

    // ---- ANDROID / iOS / desktop ----
    return CachedNetworkImage(
      imageUrl: imageUrl!.trim(),
      width: size,
      height: size,
      fit: fit,
      placeholder: (_, __) => Image.asset(
        fallbackAsset,
        width: size,
        height: size,
        fit: fit,
      ),
      errorWidget: (_, __, ___) => Image.asset(
        fallbackAsset,
        width: size,
        height: size,
        fit: fit,
      ),
    );
  }
}

/// Circular avatar with platform switch (CachedNetworkImage on Android, HTML on web).
class NetworkCircleAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final String fallbackAsset;
  final Color? backgroundColor;

  const NetworkCircleAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 18,
    this.fallbackAsset = _defaultProfileAsset,
    this.backgroundColor,
  });

  bool get _hasUrl => imageUrl != null && imageUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    // ---- WEB: HTML <img> inside circle ----
    if (kIsWeb) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? _defaultAvatarBg,
        child: ClipOval(
          child: IgnorePointer(
            child: NetworkAvatar(
              imageUrl: imageUrl,
              size: size,
              fallbackAsset: fallbackAsset,
            ),
          ),
        ),
      );
    }

    // ---- ANDROID: CachedNetworkImageProvider (same as before) ----
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? _defaultAvatarBg,
      backgroundImage: _hasUrl
          ? CachedNetworkImageProvider(imageUrl!.trim()) as ImageProvider
          : AssetImage(fallbackAsset) as ImageProvider,
    );
  }
}
