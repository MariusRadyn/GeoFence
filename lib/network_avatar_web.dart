// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Renders via an HTML <img>, so the browser displays the image without
/// CanvasKit needing CORS byte access (Firebase Storage / Google photos).
Widget buildWebNetworkImage({
  required String url,
  required double width,
  required double height,
  required BoxFit fit,
}) {
  final viewType =
      'geofence-img-${url.hashCode}-${width.toInt()}-${height.toInt()}';

  // Safe to re-register; last factory for this viewType wins.
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final img = html.ImageElement()
      ..src = url
      ..draggable = false
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = _cssObjectFit(fit)
      ..style.display = 'block';
    return img;
  });

  return SizedBox(
    width: width,
    height: height,
    child: HtmlElementView(viewType: viewType),
  );
}

String _cssObjectFit(BoxFit fit) {
  switch (fit) {
    case BoxFit.contain:
      return 'contain';
    case BoxFit.fill:
      return 'fill';
    case BoxFit.fitWidth:
    case BoxFit.fitHeight:
    case BoxFit.scaleDown:
      return 'scale-down';
    case BoxFit.none:
      return 'none';
    case BoxFit.cover:
      return 'cover';
  }
}
