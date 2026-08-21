import 'package:flutter/material.dart';

/// Stub for non-web: never used when [kIsWeb] is false.
Widget buildWebNetworkImage({
  required String url,
  required double width,
  required double height,
  required BoxFit fit,
  String? fallbackAsset,
}) {
  throw UnsupportedError('Web network image is only available on web');
}
