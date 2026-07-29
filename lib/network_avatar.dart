import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'network_avatar_stub.dart'
    if (dart.library.html) 'network_avatar_web.dart' as web_img;

const String _defaultProfileAsset = 'assets/profile.png';
const Color _defaultAvatarBg = Color.fromARGB(202, 139, 229, 245);

String _withCacheBust(String url, String? version) {
  final u = url.trim();
  if (u.isEmpty) return u;
  final v = version?.trim() ?? '';
  if (v.isEmpty) return u;
  final sep = u.contains('?') ? '&' : '?';
  return '$u${sep}v=${Uri.encodeComponent(v)}';
}

/// Shared image helper:
/// - **Android / iOS / desktop:** [CachedNetworkImage] / [CachedNetworkImageProvider]
/// - **Web:** HTML `<img>` (CanvasKit cannot read Firebase/Google bytes without CORS)
class NetworkAvatar extends StatelessWidget {
  final String? imageUrl;
  /// Optional (e.g. imageFilename) so updated photos bypass browser/CDN cache.
  final String? version;
  final double size;
  final String fallbackAsset;
  final BoxFit fit;

  const NetworkAvatar({
    super.key,
    required this.imageUrl,
    this.version,
    this.size = 48,
    this.fallbackAsset = _defaultProfileAsset,
    this.fit = BoxFit.cover,
  });

  bool get _hasUrl => imageUrl != null && imageUrl!.trim().isNotEmpty;

  String get _resolvedUrl => _withCacheBust(imageUrl ?? '', version);

  /// Use with [CircleAvatar.backgroundImage] on non-web only.
  static ImageProvider imageProvider(
    String? imageUrl, {
    String? version,
    String fallbackAsset = _defaultProfileAsset,
  }) {
    final url = _withCacheBust(imageUrl ?? '', version);
    if (url.isEmpty) {
      return AssetImage(fallbackAsset);
    }
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

    final url = _resolvedUrl;

    // ---- WEB ----
    if (kIsWeb) {
      return IgnorePointer(
        child: web_img.buildWebNetworkImage(
          url: url,
          width: size,
          height: size,
          fit: fit,
        ),
      );
    }

    // ---- ANDROID / iOS / desktop ----
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: version?.isNotEmpty == true ? version : url,
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
  final String? version;
  final double radius;
  final String fallbackAsset;
  final Color? backgroundColor;

  const NetworkCircleAvatar({
    super.key,
    required this.imageUrl,
    this.version,
    this.radius = 18,
    this.fallbackAsset = _defaultProfileAsset,
    this.backgroundColor,
  });

  bool get _hasUrl => imageUrl != null && imageUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    if (kIsWeb) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? _defaultAvatarBg,
        child: ClipOval(
          child: IgnorePointer(
            child: NetworkAvatar(
              imageUrl: imageUrl,
              version: version,
              size: size,
              fallbackAsset: fallbackAsset,
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? _defaultAvatarBg,
      backgroundImage: _hasUrl
          ? NetworkAvatar.imageProvider(imageUrl, version: version)
          : AssetImage(fallbackAsset) as ImageProvider,
    );
  }
}
