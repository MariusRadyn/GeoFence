import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

class OperatorWageSummary {
  OperatorWageSummary({
    required this.name,
    required this.distanceM,
    required this.rate,
    required this.logs,
    required this.owed,
  });

  final String name;
  final double distanceM;
  final double rate;
  final int logs;
  final double owed;
}

class OperatorWageDetail {
  OperatorWageDetail({
    required this.timestamp,
    required this.operatorName,
    required this.monitorName,
    required this.lines,
    required this.ticks,
    required this.distanceM,
    required this.rate,
    required this.owed,
  });

  final DateTime timestamp;
  final String operatorName;
  final String monitorName;
  final int lines;
  final num ticks;
  final double distanceM;
  final double rate;
  final double owed;
}

class WagesExcelExport {
  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');
  static final DateFormat _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');
  static const MethodChannel _downloadsChannel =
      MethodChannel('limitless.iot.trinity/downloads');

  /// Returns the saved location, or `null` when there is nothing to export.
  static Future<String?> exportAndShare({
    required DateTime from,
    required DateTime to,
    required List<QueryDocumentSnapshot> docs,
    required OperatorService operators,
    required MonitorSettingsService monitors,
  }) async {
    final summaries = <String, OperatorWageSummary>{};
    final details = <OperatorWageDetail>[];

    for (final doc in docs) {
      if (!doc.exists) continue;

      final String monId =
          '${(doc.data() as Map<String, dynamic>)[fireIotMonDocId] ?? ''}';
      final monitor = monitors.getMonitorById(monId);
      if (monitor == null || monitor.monitorType != monitorTypeWheel) continue;

      final String opId =
          '${(doc.data() as Map<String, dynamic>)[fireIotOperatorDocId] ?? ''}';
      final operator = operators.getOperatorById(opId);
      final String opName = operator == null
          ? 'Unknown Operator'
          : '${operator.name} ${operator.surname}'.trim();

      num lines = 0;
      num ticks = 0;
      double dist = 0;
      final double rate = operator?.rate ?? 0;
      double owed = 0;

      try {
        lines = doc.get(fireIotLines) ?? 0;
        ticks = doc.get(fireIotTicks) ?? 0;
        if (monitor.ticksPerM != 0) {
          dist = lines * (ticks / monitor.ticksPerM);
        }
        owed = dist * rate;
      } catch (e) {
        printDebugMsg('Wages export row skip: $e');
        continue;
      }

      final key = operator?.docId ?? 'unknown-$opName';
      final existing = summaries[key];
      if (existing == null) {
        summaries[key] = OperatorWageSummary(
          name: opName.isEmpty ? 'Unknown Operator' : opName,
          distanceM: dist,
          rate: rate,
          logs: 1,
          owed: owed,
        );
      } else {
        summaries[key] = OperatorWageSummary(
          name: existing.name,
          distanceM: existing.distanceM + dist,
          rate: existing.rate,
          logs: existing.logs + 1,
          owed: existing.owed + owed,
        );
      }

      DateTime ts = DateTime.now();
      try {
        final raw = doc.get(fireIotTimestamp);
        if (raw is Timestamp) ts = raw.toDate();
      } catch (_) {}

      details.add(
        OperatorWageDetail(
          timestamp: ts,
          operatorName: opName.isEmpty ? 'Unknown Operator' : opName,
          monitorName: monitor.monitorName,
          lines: lines.toInt(),
          ticks: ticks,
          distanceM: dist,
          rate: rate,
          owed: owed,
        ),
      );
    }

    final sortedSummaries = summaries.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    details.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (sortedSummaries.isEmpty) {
      return null;
    }

    final bytes = await _buildWorkbookBytes(
      from: from,
      to: to,
      summaries: sortedSummaries,
      details: details,
    );

    final fileName =
        'Limitless_Wages_${_dateFmt.format(from)}_to_${_dateFmt.format(to)}.xlsx';
    final baseName = fileName.replaceAll('.xlsx', '');

    if (kIsWeb) {
      // Browser download via blob — Web Share API is unreliable on hosted sites.
      await FileSaver.instance.saveFile(
        name: baseName,
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      return 'Downloads/$fileName';
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Needed only on Android 9 and below for public Downloads writes.
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
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
        downloadFallbackEnabled: true,
        subject: 'Limitless IOT Wages Report',
        text: 'Wages report ${_dateFmt.format(from)} to ${_dateFmt.format(to)}',
      ),
    );
    return fileName;
  }

  static Future<Uint8List> _buildWorkbookBytes({
    required DateTime from,
    required DateTime to,
    required List<OperatorWageSummary> summaries,
    required List<OperatorWageDetail> details,
  }) async {
    final workbook = Workbook();
    final summarySheet = workbook.worksheets[0];
    summarySheet.name = 'Operator Summary';

    final logoData = await rootBundle.load(iconLimitlessLogo);
    final Picture picture = summarySheet.pictures.addStream(1,6,logoData.buffer.asUint8List(),);
    picture.width = 90;
    picture.height = 90;

    summarySheet.getRangeByName('A1').setText('Limitless IoT');
    summarySheet.getRangeByName('A1').cellStyle
      ..bold = true
      ..fontSize = 18
      ..fontColor = '#1A237E';

    summarySheet.getRangeByName('A2').setText('Wages Report — Operator Details');
    summarySheet.getRangeByName('A2').cellStyle
      ..bold = true
      ..fontSize = 14;

    summarySheet.getRangeByName('A3').setText(
          'Period: ${_dateFmt.format(from)}  to  ${_dateFmt.format(to)}',
        );
    summarySheet.getRangeByName('A4').setText(
          'Generated: ${_dateTimeFmt.format(DateTime.now())}',
        );

    const headerRow = 6;
    final headers = <String>[
      '#',
      'Operator',
      'Distance Measured (m)',
      'Rate (R/m)',
      'Logs',
      'Amount Owed (R)',
    ];
    for (var i = 0; i < headers.length; i++) {
      final cell = summarySheet.getRangeByIndex(headerRow, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle
        ..bold = true
        ..backColor = '#1A237E'
        ..fontColor = '#FFFFFF'
        ..hAlign = HAlignType.center;
    }

    double totalDistance = 0;
    double totalOwed = 0;
    int totalLogs = 0;

    for (var i = 0; i < summaries.length; i++) {
      final row = headerRow + 1 + i;
      final s = summaries[i];
      totalDistance += s.distanceM;
      totalOwed += s.owed;
      totalLogs += s.logs;

      summarySheet.getRangeByIndex(row, 1).setNumber((i + 1).toDouble());
      summarySheet.getRangeByIndex(row, 2).setText(s.name);
      summarySheet.getRangeByIndex(row, 3).setNumber(
            double.parse(s.distanceM.toStringAsFixed(2)),
          );
      summarySheet.getRangeByIndex(row, 4).setNumber(
            double.parse(s.rate.toStringAsFixed(2)),
          );
      summarySheet.getRangeByIndex(row, 5).setNumber(s.logs.toDouble());
      summarySheet.getRangeByIndex(row, 6).setNumber(
            double.parse(s.owed.toStringAsFixed(2)),
          );
    }

    final totalRow = headerRow + 1 + summaries.length;
    summarySheet.getRangeByIndex(totalRow, 1).setText('');
    summarySheet.getRangeByIndex(totalRow, 2).setText('TOTAL');
    summarySheet.getRangeByIndex(totalRow, 2).cellStyle.bold = true;
    summarySheet.getRangeByIndex(totalRow, 3).setNumber(
          double.parse(totalDistance.toStringAsFixed(2)),
        );
    summarySheet.getRangeByIndex(totalRow, 3).cellStyle.bold = true;
    summarySheet.getRangeByIndex(totalRow, 5).setNumber(totalLogs.toDouble());
    summarySheet.getRangeByIndex(totalRow, 5).cellStyle.bold = true;
    summarySheet.getRangeByIndex(totalRow, 6).setNumber(
          double.parse(totalOwed.toStringAsFixed(2)),
        );
    summarySheet.getRangeByIndex(totalRow, 6).cellStyle
      ..bold = true
      ..backColor = '#E8F5E9';

    summarySheet.getRangeByIndex(1, 1).columnWidth = 12;
    summarySheet.getRangeByIndex(1, 2).columnWidth = 28;
    summarySheet.getRangeByIndex(1, 3).columnWidth = 22;
    summarySheet.getRangeByIndex(1, 4).columnWidth = 14;
    summarySheet.getRangeByIndex(1, 5).columnWidth = 10;
    summarySheet.getRangeByIndex(1, 6).columnWidth = 18;

    final detailSheet = workbook.worksheets.addWithName('Measurement Details');
    final detailHeaders = <String>[
      'Date / Time',
      'Operator',
      'Monitor',
      'Lines',
      'Ticks',
      'Distance (m)',
      'Rate (R/m)',
      'Amount Owed (R)',
    ];
    for (var i = 0; i < detailHeaders.length; i++) {
      final cell = detailSheet.getRangeByIndex(1, i + 1);
      cell.setText(detailHeaders[i]);
      cell.cellStyle
        ..bold = true
        ..backColor = '#1A237E'
        ..fontColor = '#FFFFFF'
        ..hAlign = HAlignType.center;
    }

    for (var i = 0; i < details.length; i++) {
      final row = i + 2;
      final d = details[i];
      detailSheet.getRangeByIndex(row, 1).setText(_dateTimeFmt.format(d.timestamp));
      detailSheet.getRangeByIndex(row, 2).setText(d.operatorName);
      detailSheet.getRangeByIndex(row, 3).setText(d.monitorName);
      detailSheet.getRangeByIndex(row, 4).setNumber(d.lines.toDouble());
      detailSheet.getRangeByIndex(row, 5).setNumber(d.ticks.toDouble());
      detailSheet.getRangeByIndex(row, 6).setNumber(
            double.parse(d.distanceM.toStringAsFixed(2)),
          );
      detailSheet.getRangeByIndex(row, 7).setNumber(
            double.parse(d.rate.toStringAsFixed(2)),
          );
      detailSheet.getRangeByIndex(row, 8).setNumber(
            double.parse(d.owed.toStringAsFixed(2)),
          );
    }

    detailSheet.getRangeByIndex(1, 1).columnWidth = 18;
    detailSheet.getRangeByIndex(1, 2).columnWidth = 28;
    detailSheet.getRangeByIndex(1, 3).columnWidth = 20;
    detailSheet.getRangeByIndex(1, 4).columnWidth = 10;
    detailSheet.getRangeByIndex(1, 5).columnWidth = 10;
    detailSheet.getRangeByIndex(1, 6).columnWidth = 14;
    detailSheet.getRangeByIndex(1, 7).columnWidth = 12;
    detailSheet.getRangeByIndex(1, 8).columnWidth = 16;

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();
    return Uint8List.fromList(bytes);
  }
}
