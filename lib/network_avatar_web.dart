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
  return _WebNetworkImage(
    key: ValueKey(url),
    url: url,
    width: width,
    height: height,
    fit: fit,
  );
}

class _WebNetworkImage extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;

  const _WebNetworkImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.fit,
  });

  @override
  State<_WebNetworkImage> createState() => _WebNetworkImageState();
}

class _WebNetworkImageState extends State<_WebNetworkImage> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType =
        'geofence-img-${widget.url.hashCode}-${widget.width.toInt()}-${widget.height.toInt()}-${DateTime.now().microsecondsSinceEpoch}';
    _register();
  }

  @override
  void didUpdateWidget(covariant _WebNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // URL change is handled by parent Key forcing a new State.
  }

  void _register() {
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final img = html.ImageElement()
        ..src = widget.url
        ..draggable = false
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = _cssObjectFit(widget.fit)
        ..style.display = 'block';
      return img;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey(widget.url),
      width: widget.width,
      height: widget.height,
      child: HtmlElementView(
        key: ValueKey('html-${widget.url}'),
        viewType: _viewType,
      ),
    );
  }
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
