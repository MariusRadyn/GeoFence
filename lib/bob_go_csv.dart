import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

/// CSV Bob Go can import under Orders → Import CSV.
///
/// Bob Go maps columns on the first upload, then remembers the mapping.
/// Headers match the labels on that screen so auto-match is likely.
class BobGoCsv {
  static const MethodChannel _downloadsChannel =
      MethodChannel('limitless.iot.trinity/downloads');

  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');

  static const List<String> headers = [
    'Order number',
    'Order date',
    'Payment status',
    'First name',
    'Last name',
    'Company name',
    'Email',
    'Mobile number',
    'Street address',
    'Suburb',
    'City',
    'Postal code',
    'Country',
    'SKU',
    'Product title',
    'Quantity',
    'Price',
    'Weight (kg)',
    'Length (cm)',
    'Width (cm)',
    'Height (cm)',
    'Declared value',
  ];

  static String build({
    required List<Map<String, dynamic>> orders,
  }) {
    final rows = <List<String>>[headers];
    for (final order in orders) {
      rows.addAll(_orderRows(order));
    }
    final body = rows.map((row) => row.map(_escape).join(',')).join('\r\n');
    return '\uFEFF$body\r\n';
  }

  static List<List<String>> _orderRows(Map<String, dynamic> order) {
    final orderId = '${order['orderId'] ?? ''}'.trim();
    final shipping = Map<String, dynamic>.from(
      order['shipping'] is Map ? order['shipping'] as Map : const {},
    );
    final names = _splitName('${shipping['fullName'] ?? ''}');
    final items = (order['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => _asInt(item['quantity']) > 0)
        .toList();
    final date = _formatDate(order['createdAt'] ?? order['paidAt']);
    final declared = _money(order['subtotal'] ?? order['total']);
    final status = _paymentStatus(order['status']?.toString());

    final lineItems = items.isEmpty
        ? [
            <String, dynamic>{
              'productId': orderId,
              'name': 'Parcel',
              'quantity': 1,
              'price': order['subtotal'] ?? order['total'] ?? 0,
            },
          ]
        : items;

    return lineItems.map((item) {
      return [
        orderId,
        date,
        status,
        names.$1,
        names.$2,
        '',
        '${shipping['email'] ?? order['email'] ?? ''}'.trim(),
        '${shipping['phone'] ?? ''}'.trim(),
        '${shipping['street'] ?? shipping['street_address'] ?? ''}'.trim(),
        '${shipping['suburb'] ?? ''}'.trim(),
        '${shipping['city'] ?? ''}'.trim(),
        '${shipping['postalCode'] ?? shipping['code'] ?? ''}'.trim(),
        'South Africa',
        '${item['productId'] ?? ''}'.trim(),
        '${item['name'] ?? 'Item'}'.trim(),
        '${_asInt(item['quantity'], 1)}',
        _money(item['price'] ?? item['catalogPrice']),
        _num(item['weightKg']),
        _num(item['lengthCm']),
        _num(item['widthCm']),
        _num(item['heightCm']),
        declared,
      ];
    }).toList();
  }

  static String _paymentStatus(String? status) {
    return switch (status) {
      'pending_payment' => 'Unpaid',
      'cancelled' => 'Cancelled',
      _ => 'Paid',
    };
  }

  static (String, String) _splitName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return ('', '');
    if (parts.length == 1) return (parts.first, '');
    return (parts.first, parts.sublist(1).join(' '));
  }

  static String _formatDate(dynamic value) {
    if (value is Timestamp) return _dateFmt.format(value.toDate());
    if (value is DateTime) return _dateFmt.format(value);
    final text = '$value'.trim();
    if (text.isEmpty) return '';
    final parsed = DateTime.tryParse(text);
    return parsed == null ? text : _dateFmt.format(parsed.toLocal());
  }

  static String _money(dynamic value) {
    final n = _asDouble(value);
    if (n == 0) return '';
    return n.toStringAsFixed(2);
  }

  static String _num(dynamic value) {
    final n = _asDouble(value);
    if (n == 0) return '';
    return n.toString();
  }

  static double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static String _escape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String filenameFor({String? orderId}) {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    if (orderId == null || orderId.isEmpty) {
      return 'bobgo_orders_$stamp.csv';
    }
    final short =
        orderId.length > 8 ? orderId.substring(0, 8) : orderId;
    return 'bobgo_order_${short}_$stamp.csv';
  }

  static Future<String> save({
    required String csv,
    required String fileName,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final baseName = fileName.replaceAll(RegExp(r'\.csv$', caseSensitive: false), '');

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: baseName,
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      return 'Downloads/$fileName';
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.storage.request();
      final savedPath = await _downloadsChannel.invokeMethod<String>(
        'saveToDownloads',
        <String, dynamic>{
          'fileName': fileName,
          'bytes': bytes,
          'openAfterSave': true,
        },
      );
      return savedPath ?? 'Download/$fileName';
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'text/csv',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
        downloadFallbackEnabled: true,
        subject: 'Bob Go order import',
        text: 'Drag this CSV onto Bob Go → Orders → Import.',
      ),
    );
    return fileName;
  }
}
