// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// True on iPhone / iPad / iPod browsers (incl. Chrome/Firefox on iOS).
bool get isIosWebBrowser {
  final ua = html.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('ipod') ||
      // iPadOS 13+ can report as Macintosh with touch.
      (ua.contains('mac') && ua.contains('mobile'));
}

/// Renders network images on web without [HtmlElementView] platform views.
///
/// Raw platform views inside scrolling grids crash Safari on iOS. Prefer
/// [Image.network] with decode size limits instead.
Widget buildWebNetworkImage({
  required String url,
  required double width,
  required double height,
  required BoxFit fit,
  String? fallbackAsset,
}) {
  return _WebNetworkImage(
    key: ValueKey('net-$url-${width.toInt()}x${height.toInt()}'),
    url: url,
    width: width,
    height: height,
    fit: fit,
    fallbackAsset: fallbackAsset,
  );
}

class _WebNetworkImage extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  final String? fallbackAsset;

  const _WebNetworkImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.fit,
    this.fallbackAsset,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Cap decode size so scrolling a product grid does not OOM iOS Safari.
    final cacheW = math
        .max(1, (width * dpr).round())
        .clamp(1, 640);
    final cacheH = math
        .max(1, (height * dpr).round())
        .clamp(1, 640);

    // iOS Safari: HTML <img> / platform-view compositing while scrolling is
    // unstable. Decode into CanvasKit with a small cache size instead.
    // Requires Firebase Storage CORS (see cors.json / README).
    final strategy = isIosWebBrowser
        ? WebHtmlElementStrategy.never
        : WebHtmlElementStrategy.fallback;

    Widget fallback() {
      if (fallbackAsset == null || fallbackAsset!.isEmpty) {
        return ColoredBox(
          color: const Color(0xFF0F172A),
          child: SizedBox(width: width, height: height),
        );
      }
      return Image.asset(
        fallbackAsset!,
        width: width,
        height: height,
        fit: fit,
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheW,
        cacheHeight: cacheH,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        webHtmlElementStrategy: strategy,
        errorBuilder: (_, __, ___) => fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return fallback();
        },
      ),
    );
  }
}
