import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/app_flavor.dart';
import 'package:geofence/utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Push operator tags to a GeoFenceIOT wheel over BLE (no WiFi / base).
/// Protocol matches GeoFenceIOT `ops:begin>` / `ops:data>` / `ops:end` / `ops:json>`.
class IotBleOperatorSync {
  IotBleOperatorSync._();

  static const String iotNamePrefix = 'iOT_';
  static const Duration _scanTimeout = Duration(seconds: 8);
  static const Duration _ackTimeout = Duration(seconds: 8);
  static const int _preferredMtu = 512;
  static const String _prefLastIotId = 'ble_last_iot_remote_id';
  static const String _prefLastIotName = 'ble_last_iot_name';

  static Timer? _autoSyncDebounce;
  static bool _autoSyncBusy = false;

  /// Build IoT `#OPERATORS` list payload (array of operator objects).
  static List<Map<String, dynamic>> buildOperatorsPayload(
    List<OperatorData> operators,
  ) {
    final list = <Map<String, dynamic>>[];
    for (final op in operators) {
      final tagId = (op.tagId ?? '').trim();
      if (tagId.isEmpty || tagId.toLowerCase() == 'none') continue;

      list.add({
        'name': op.name,
        'surname': op.surname,
        'accessLevel': isSupervisorAccessLevel(op.accessLevel)
            ? 'supervisor'
            : 'operator',
        'tagId': tagId,
        'docId': op.docId,
      });
    }
    return list;
  }

  static Future<bool> _ensureBleReady() async {
    if (kIsWeb || !AppConfig.enableBluetooth) {
      MyGlobalSnackBar.show('Bluetooth not available on this platform');
      return false;
    }
    if (await FlutterBluePlus.isSupported == false) {
      MyGlobalSnackBar.show('Bluetooth not supported on this device');
      return false;
    }

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    final granted = statuses.values.every((s) => s.isGranted);
    if (!granted) {
      MyGlobalSnackBar.show('Bluetooth Permission: Not Granted');
      return false;
    }

    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      MyGlobalSnackBar.show('Turn on Bluetooth');
      return false;
    }
    return true;
  }

  static bool _uuidMatches(Guid uuid, String expected) {
    final a = uuid.str.toLowerCase().replaceAll('-', '');
    final b = expected.toLowerCase().replaceAll('-', '');
    return a == b || a.endsWith(b) || b.endsWith(a);
  }

  static bool _isIotDevice(String name, List<Guid> serviceUuids) {
    final n = name.trim();
    if (n.toLowerCase().startsWith(iotNamePrefix.toLowerCase())) return true;
    return serviceUuids.any((u) => _uuidMatches(u, bluetoothServiceUuid));
  }

  /// Scan for nearby distance wheels (`iOT_*` / GeoFenceIOT service UUID).
  static Future<List<BluetoothDevice>> scanForIotDevices({
    Duration timeout = _scanTimeout,
  }) async {
    if (!await _ensureBleReady()) return [];

    final found = <String, BluetoothDevice>{};

    void collect(List<ScanResult> results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        if (_isIotDevice(name, r.advertisementData.serviceUuids)) {
          found[r.device.remoteId.str] = r.device;
        }
      }
    }

    StreamSubscription<List<ScanResult>>? sub;
    try {
      await FlutterBluePlus.stopScan();
      sub = FlutterBluePlus.scanResults.listen(collect);

      // Prefer filter by service UUID; many phones still need a plain scan.
      try {
        await FlutterBluePlus.startScan(
          withServices: [Guid(bluetoothServiceUuid)],
          timeout: timeout,
          androidUsesFineLocation: true,
        );
      } catch (_) {
        await FlutterBluePlus.startScan(
          timeout: timeout,
          androidUsesFineLocation: true,
        );
      }

      await FlutterBluePlus.isScanning
          .where((v) => v == false)
          .first
          .timeout(timeout + const Duration(seconds: 2));
    } catch (e) {
      printDebugMsg('IoT BLE scan error: $e');
    } finally {
      await FlutterBluePlus.stopScan();
      await sub?.cancel();
    }

    // If service-filtered scan found nothing, try an open scan once.
    if (found.isEmpty) {
      try {
        sub = FlutterBluePlus.scanResults.listen(collect);
        await FlutterBluePlus.startScan(
          timeout: timeout,
          androidUsesFineLocation: true,
        );
        await FlutterBluePlus.isScanning
            .where((v) => v == false)
            .first
            .timeout(timeout + const Duration(seconds: 2));
      } catch (e) {
        printDebugMsg('IoT BLE open scan error: $e');
      } finally {
        await FlutterBluePlus.stopScan();
        await sub?.cancel();
      }
    }

    final list = found.values.toList()
      ..sort((a, b) => deviceLabel(a).compareTo(deviceLabel(b)));
    return list;
  }

  static String deviceLabel(BluetoothDevice device) {
    final name = device.platformName.trim();
    if (name.isNotEmpty) return name;
    return device.remoteId.str;
  }

  /// Same style as PayFast checkout busy dialog (compact + blue border + orange spinner).
  static Future<void> showBusyDialog(
    BuildContext context, {
    required String message,
    String title = 'Bluetooth',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.blue, width: 2),
          ),
          backgroundColor: colorAppTitle,
          title: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MyText(text: title, color: Colors.white),
              ),
            ],
          ),
          content: MyText(
            text: message,
            color: Colors.grey,
            fontsize: 18,
          ),
        ),
      ),
    );
  }

  /// Pick an IoT from [devices]. Shows a hint + blue-bordered dialog when
  /// more than one wheel is nearby.
  static Future<BluetoothDevice?> showDevicePicker(
    BuildContext context,
    List<BluetoothDevice> devices, {
    String hint =
        'The selected IoT will beep twice and flash its blue LED. '
        'Present the tag on that wheel.',
  }) async {
    if (devices.isEmpty) return null;
    if (devices.length == 1) return devices.first;

    return showDialog<BluetoothDevice>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.blue, width: 2),
          ),
          backgroundColor: colorAppTitle,
          title: const MyText(text: 'Select Wheel', color: Colors.white),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue, width: 1.5),
                  ),
                  child: Text(
                    hint,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'Poppins',
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(dialogContext).size.height * 0.4,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Colors.white12),
                    itemBuilder: (context, index) {
                      final d = devices[index];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0,
                        ),
                        leading: const Icon(
                          Icons.bluetooth,
                          color: Colors.lightBlueAccent,
                          size: 22,
                        ),
                        title: Text(
                          deviceLabel(d),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        onTap: () => Navigator.pop(dialogContext, d),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const MyText(text: 'Cancel', fontsize: 18),
            ),
          ],
        );
      },
    );
  }

  /// Prefer a device whose advertised name matches [preferredName] (monitor id).
  /// If [strict] is true, only an exact name match is returned (no single-device fallback).
  static BluetoothDevice? preferDevice(
    List<BluetoothDevice> devices, {
    String? preferredName,
    bool strict = false,
  }) {
    final want = (preferredName ?? '').trim().toLowerCase();
    if (want.isNotEmpty) {
      for (final d in devices) {
        if (deviceLabel(d).toLowerCase() == want) return d;
      }
      if (!strict) {
        for (final d in devices) {
          if (deviceLabel(d).toLowerCase().contains(want)) return d;
        }
      }
    }
    if (strict) return null;
    return devices.length == 1 ? devices.first : null;
  }

  /// Exact advertised-name match for a paired monitor id (`iOT_…`).
  static BluetoothDevice? deviceForMonitorId(
    List<BluetoothDevice> devices,
    String monitorId,
  ) {
    return preferDevice(devices, preferredName: monitorId, strict: true);
  }

  static Future<void> rememberDevice(BluetoothDevice device) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastIotId, device.remoteId.str);
      await prefs.setString(_prefLastIotName, deviceLabel(device));
    } catch (e) {
      printDebugMsg('rememberDevice failed: $e');
    }
  }

  /// Debounced silent push after name edits. Uses last wheel, else the only
  /// nearby `iOT_*`. No picker — skips quietly if none found.
  static void scheduleAutoSync(
    List<OperatorData> operators, {
    String? operatorsVer,
  }) {
    if (kIsWeb || !AppConfig.enableBluetooth) return;
    _autoSyncDebounce?.cancel();
    _autoSyncDebounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(autoSyncOperators(operators, operatorsVer: operatorsVer));
    });
  }

  static Future<void> autoSyncOperators(
    List<OperatorData> operators, {
    String? operatorsVer,
  }) async {
    if (kIsWeb || !AppConfig.enableBluetooth) return;
    if (_autoSyncBusy) return;
    if (buildOperatorsPayload(operators).isEmpty) return;

    _autoSyncBusy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastId = (prefs.getString(_prefLastIotId) ?? '').trim();

      BluetoothDevice? target;

      // Prefer last wheel used for Sync / Read (no scan if connect works)
      if (lastId.isNotEmpty) {
        try {
          final remembered = BluetoothDevice.fromId(lastId);
          await pushOperators(
            device: remembered,
            operators: operators,
            operatorsVer: operatorsVer,
            onStatus: printDebugMsg,
          );
          await rememberDevice(remembered);
          MyGlobalSnackBar.show(
            'Wheel updated: ${deviceLabel(remembered)}',
          );
          return;
        } catch (e) {
          printDebugMsg('Auto sync last device failed: $e');
        }
      }

      final devices = await scanForIotDevices(
        timeout: const Duration(seconds: 4),
      );
      if (lastId.isNotEmpty) {
        for (final d in devices) {
          if (d.remoteId.str == lastId) {
            target = d;
            break;
          }
        }
      }
      target ??= devices.length == 1 ? devices.first : null;
      if (target == null) {
        printDebugMsg(
          'Auto BLE sync skipped (no last wheel / ${devices.length} nearby)',
        );
        return;
      }

      await pushOperators(
        device: target,
        operators: operators,
        operatorsVer: operatorsVer,
        onStatus: printDebugMsg,
      );
      await rememberDevice(target);
      MyGlobalSnackBar.show('Wheel updated: ${deviceLabel(target)}');
    } catch (e) {
      printDebugMsg('Auto BLE sync failed: $e');
    } finally {
      _autoSyncBusy = false;
    }
  }

  /// Push [operators] to [device]. Returns userCount from `OPS_OK>`, or throws.
  static Future<int> pushOperators({
    required BluetoothDevice device,
    required List<OperatorData> operators,
    String? operatorsVer,
    void Function(String status)? onStatus,
  }) async {
    if (!await _ensureBleReady()) {
      throw StateError('Bluetooth not ready');
    }

    final payloadList = buildOperatorsPayload(operators);
    if (payloadList.isEmpty) {
      throw StateError('No tags with valid Tag IDs to sync');
    }

    final ver = (operatorsVer == null || operatorsVer.isEmpty)
        ? DateTime.now().toUtc().millisecondsSinceEpoch.toString()
        : operatorsVer;

    final arrayJson = jsonEncode(payloadList);

    onStatus?.call('Connecting to ${deviceLabel(device)}…');

    var connectedHere = false;
    StreamSubscription<List<int>>? notifySub;
    try {
      if (!device.isConnected) {
        await device.connect(
          license: License.nonprofit,
          timeout: const Duration(seconds: 15),
          autoConnect: false,
        );
        connectedHere = true;
      }

      try {
        await device.requestMtu(_preferredMtu);
      } catch (e) {
        printDebugMsg('MTU request failed (continuing): $e');
      }

      onStatus?.call('Discovering services…');
      final services = await device.discoverServices();
      BluetoothService? service;
      for (final s in services) {
        if (_uuidMatches(s.uuid, bluetoothServiceUuid)) {
          service = s;
          break;
        }
      }
      if (service == null) {
        throw StateError('IoT BLE service not found on device');
      }

      BluetoothCharacteristic? char;
      for (final c in service.characteristics) {
        if (_uuidMatches(c.uuid, bluetoothCharUuid)) {
          char = c;
          break;
        }
      }
      if (char == null) {
        throw StateError('IoT BLE characteristic not found');
      }

      Completer<String>? waiting;

      void handleNotify(List<int> value) {
        final text = utf8.decode(value, allowMalformed: true).trim();
        if (text.isEmpty) return;
        printDebugMsg('IoT BLE notify: $text');
        if (text.startsWith('OPS_ERR>')) {
          final err = text.substring('OPS_ERR>'.length);
          if (waiting != null && !waiting!.isCompleted) {
            waiting!.completeError(StateError(err));
          }
          return;
        }
        if (waiting != null && !waiting!.isCompleted) {
          waiting!.complete(text);
        }
      }

      await char.setNotifyValue(true);
      notifySub = char.onValueReceived.listen(handleNotify);
      device.cancelWhenDisconnected(notifySub);

      Future<String> writeAndWait(
        List<int> bytes, {
        bool Function(String ack)? accept,
        String debugLabel = 'cmd',
      }) async {
        waiting = Completer<String>();
        await char!.write(bytes, withoutResponse: false);
        final ack = await waiting!.future.timeout(
          _ackTimeout,
          onTimeout: () =>
              throw TimeoutException('No BLE ack for $debugLabel'),
        );
        if (accept != null && !accept(ack)) {
          throw StateError('Unexpected ack: $ack');
        }
        return ack;
      }

      var mtu = 23;
      try {
        mtu = await device.mtu.first.timeout(const Duration(seconds: 2));
      } catch (_) {}
      // ATT write payload ≈ MTU - 3; reserve prefix "ops:data>"
      final maxChunk = (mtu - 3 - 9).clamp(20, 500);

      onStatus?.call('Sending ${payloadList.length} tag(s)…');

      // Always chunk — avoids large parse/FS work in a single BLE write callback
      // on the wheel (that path previously could reboot the ESP32).
      await writeAndWait(
        utf8.encode('ops:begin>$ver>${utf8.encode(arrayJson).length}'),
        debugLabel: 'ops:begin',
        accept: (a) => a.startsWith('OPS_ACK>BEGIN>'),
      );

      var offset = 0;
      final raw = utf8.encode(arrayJson);
      while (offset < raw.length) {
        final end =
            (offset + maxChunk < raw.length) ? offset + maxChunk : raw.length;
        final chunk = raw.sublist(offset, end);
        final cmdBytes = <int>[...utf8.encode('ops:data>'), ...chunk];
        final ack = await writeAndWait(
          cmdBytes,
          debugLabel: 'ops:data@$offset',
          accept: (a) => a.startsWith('OPS_ACK>RX>'),
        );
        assert(ack.startsWith('OPS_ACK>RX>'));
        offset = end;
        onStatus?.call('Sending… ${(offset * 100 / raw.length).round()}%');
      }

      final endAck = await writeAndWait(
        utf8.encode('ops:end'),
        debugLabel: 'ops:end',
        accept: (a) =>
            a.startsWith('OPS_ACK>END') || a.startsWith('OPS_OK>'),
      );
      if (endAck.startsWith('OPS_OK>')) {
        return int.tryParse(endAck.substring('OPS_OK>'.length)) ??
            payloadList.length;
      }

      waiting = Completer<String>();
      final ok = await waiting!.future.timeout(
        _ackTimeout,
        onTimeout: () => 'OPS_OK>${payloadList.length}',
      );
      if (ok.startsWith('OPS_ERR>')) {
        throw StateError(ok.substring('OPS_ERR>'.length));
      }
      if (ok.startsWith('OPS_OK>')) {
        return int.tryParse(ok.substring('OPS_OK>'.length)) ??
            payloadList.length;
      }
      return payloadList.length;
    } finally {
      await notifySub?.cancel();
      try {
        if (connectedHere && device.isConnected) {
          await device.disconnect();
        }
      } catch (_) {}
    }
  }

  /// Ask [device] to report the next Dallas tag over BLE (`tag:req` → `TAG_DATA>`).
  /// Returns the 16-char hex tag id. Keeps the link until a tag arrives or [listenTimeout].
  static Future<String> readTag({
    required BluetoothDevice device,
    Duration listenTimeout = const Duration(seconds: 45),
    void Function(String status)? onStatus,
  }) async {
    if (!await _ensureBleReady()) {
      throw StateError('Bluetooth not ready');
    }

    onStatus?.call('Connecting to ${deviceLabel(device)}…');

    var connectedHere = false;
    StreamSubscription<List<int>>? notifySub;
    try {
      if (!device.isConnected) {
        await device.connect(
          license: License.nonprofit,
          timeout: const Duration(seconds: 15),
          autoConnect: false,
        );
        connectedHere = true;
      }

      try {
        await device.requestMtu(_preferredMtu);
      } catch (e) {
        printDebugMsg('MTU request failed (continuing): $e');
      }

      onStatus?.call('Discovering services…');
      final services = await device.discoverServices();
      BluetoothService? service;
      for (final s in services) {
        if (_uuidMatches(s.uuid, bluetoothServiceUuid)) {
          service = s;
          break;
        }
      }
      if (service == null) {
        throw StateError('IoT BLE service not found on device');
      }

      BluetoothCharacteristic? char;
      for (final c in service.characteristics) {
        if (_uuidMatches(c.uuid, bluetoothCharUuid)) {
          char = c;
          break;
        }
      }
      if (char == null) {
        throw StateError('IoT BLE characteristic not found');
      }

      final tagCompleter = Completer<String>();
      final listenAck = Completer<void>();

      void handleNotify(List<int> value) {
        final text = utf8.decode(value, allowMalformed: true).trim();
        if (text.isEmpty) return;
        printDebugMsg('IoT BLE notify: $text');
        if (text.startsWith('TAG_ACK>LISTEN')) {
          if (!listenAck.isCompleted) listenAck.complete();
          return;
        }
        if (text.startsWith('TAG_DATA>')) {
          final tag = text.substring('TAG_DATA>'.length).trim().toUpperCase();
          if (tag.isNotEmpty && !tagCompleter.isCompleted) {
            tagCompleter.complete(tag);
          }
          return;
        }
        if (text.startsWith('TAG_ACK>TIMEOUT') ||
            text.startsWith('TAG_ACK>CANCEL')) {
          if (!tagCompleter.isCompleted) {
            tagCompleter.completeError(
              TimeoutException('Tag read cancelled or timed out on device'),
            );
          }
        }
      }

      // Subscribe before enabling notify (some Android stacks drop early values)
      notifySub = char.onValueReceived.listen(handleNotify);
      await char.setNotifyValue(true);
      // Brief settle so CCCD is active before tag:req
      await Future<void>.delayed(const Duration(milliseconds: 200));
      device.cancelWhenDisconnected(notifySub);

      onStatus?.call('Arming tag listen on ${deviceLabel(device)}…');
      await char.write(utf8.encode('tag:req'), withoutResponse: false);

      try {
        await listenAck.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            printDebugMsg('TAG_ACK>LISTEN not received — continuing anyway');
          },
        );
      } catch (_) {}

      onStatus?.call('Present tag on ${deviceLabel(device)}…');

      try {
        final tagId = await tagCompleter.future.timeout(
          listenTimeout,
          onTimeout: () =>
              throw TimeoutException('No tag presented within timeout'),
        );
        return tagId;
      } finally {
        try {
          await char.write(utf8.encode('tag:cancel'), withoutResponse: true);
        } catch (_) {}
      }
    } finally {
      await notifySub?.cancel();
      try {
        if (connectedHere && device.isConnected) {
          await device.disconnect();
        }
      } catch (_) {}
    }
  }

  /// Field calibrate over BLE (no WiFi / base).
  /// Prefers one-shot `cal:req><meters>` → `CAL_OK><ticks>><tpm>`.
  /// Falls back to `cal:req` + `set:tpm>` for older firmware.
  static Future<({int ticks, double ticksPerM, bool syncedTpm})> calibrate({
    required BluetoothDevice device,
    required double calibrationDistance,
    void Function(String status)? onStatus,
  }) async {
    if (calibrationDistance <= 0) {
      throw StateError('Enter the measured distance before calibrating');
    }
    if (!await _ensureBleReady()) {
      throw StateError('Bluetooth not ready');
    }

    onStatus?.call('Connecting to ${deviceLabel(device)}…');

    var connectedHere = false;
    StreamSubscription<List<int>>? notifySub;
    try {
      if (!device.isConnected) {
        await device.connect(
          license: License.nonprofit,
          timeout: const Duration(seconds: 15),
          autoConnect: false,
        );
        connectedHere = true;
      }

      try {
        await device.requestMtu(_preferredMtu);
      } catch (e) {
        printDebugMsg('MTU request failed (continuing): $e');
      }

      onStatus?.call('Discovering services…');
      final services = await device.discoverServices();
      BluetoothService? service;
      for (final s in services) {
        if (_uuidMatches(s.uuid, bluetoothServiceUuid)) {
          service = s;
          break;
        }
      }
      if (service == null) {
        throw StateError('IoT BLE service not found on device');
      }

      BluetoothCharacteristic? char;
      for (final c in service.characteristics) {
        if (_uuidMatches(c.uuid, bluetoothCharUuid)) {
          char = c;
          break;
        }
      }
      if (char == null) {
        throw StateError('IoT BLE characteristic not found');
      }

      Completer<String>? waiting;

      void handleNotify(List<int> value) {
        final text = utf8.decode(value, allowMalformed: true).trim();
        if (text.isEmpty) return;
        printDebugMsg('IoT BLE notify: $text');
        if (waiting != null && !waiting!.isCompleted) {
          waiting!.complete(text);
        }
      }

      notifySub = char.onValueReceived.listen(handleNotify);
      await char.setNotifyValue(true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      device.cancelWhenDisconnected(notifySub);

      Future<String> writeAndWait(String cmd, {String debugLabel = 'cmd'}) async {
        waiting = Completer<String>();
        await char!.write(utf8.encode(cmd), withoutResponse: false);
        return waiting!.future.timeout(
          _ackTimeout,
          onTimeout: () =>
              throw TimeoutException('No BLE ack for $debugLabel'),
        );
      }

      final distText = calibrationDistance == calibrationDistance.roundToDouble()
          ? '${calibrationDistance.toInt()}'
          : calibrationDistance.toStringAsFixed(3);

      onStatus?.call('Reading calibration ticks…');
      // One-shot: wheel applies ticks/m when meters are included.
      final calAck = await writeAndWait(
        'cal:req>$distText',
        debugLabel: 'cal:req',
      );
      if (calAck.startsWith('CAL_ERR>')) {
        final err = calAck.substring('CAL_ERR>'.length).trim();
        if (err == 'no_ticks') {
          throw StateError(
            'Wheel reported zero ticks. Finish calibration on the wheel '
            '(START → roll → STOP, until "Calibrate END"), then try again.',
          );
        }
        if (err == 'bad_tpm') {
          throw StateError(
            'Could not compute ticks/m from this run '
            '(distance: $distText m). Check the calibration distance. The tick count vs calibration distance is to low',
          );
        }
        throw StateError(err.isEmpty ? 'Calibration failed' : err);
      }
      if (!calAck.startsWith('CAL_OK>')) {
        throw StateError('Unexpected calibrate reply: $calAck');
      }

      final payload = calAck.substring('CAL_OK>'.length).trim();
      final parts = payload.split('>');
      final ticks = int.tryParse(parts.first.trim()) ?? 0;
      if (ticks <= 0) {
        throw StateError(
          'Wheel reported zero ticks. Finish calibration on the wheel, then try again.',
        );
      }

      var ticksPerM = ticks / calibrationDistance;
      var syncedTpm = false;

      // New firmware: CAL_OK><ticks>><tpm>
      if (parts.length >= 2) {
        final parsed = double.tryParse(parts[1].trim());
        if (parsed != null && parsed > 0) {
          ticksPerM = parsed;
          syncedTpm = true;
        }
      }

      // Older firmware (CAL_OK><ticks> only): push ticks/m separately.
      if (!syncedTpm) {
        final tpmText = ticksPerM == ticksPerM.roundToDouble()
            ? '${ticksPerM.toInt()}'
            : ticksPerM.toStringAsFixed(4);
        onStatus?.call('Pushing ticks/m ($tpmText)…');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        try {
          final setAck = await writeAndWait(
            'set:tpm>$tpmText',
            debugLabel: 'set:tpm',
          );
          if (setAck.startsWith('SET_ERR>')) {
            throw StateError(setAck.substring('SET_ERR>'.length));
          }
          if (!setAck.startsWith('SET_OK>')) {
            throw StateError('Unexpected set:tpm reply: $setAck');
          }
          syncedTpm = true;
        } catch (e) {
          printDebugMsg('BLE set:tpm failed: $e');
          // One retry — notify can drop right after CAL_OK UI/buzzer.
          await Future<void>.delayed(const Duration(milliseconds: 400));
          try {
            final setAck = await writeAndWait(
              'set:tpm>$tpmText',
              debugLabel: 'set:tpm-retry',
            );
            if (setAck.startsWith('SET_OK>')) {
              syncedTpm = true;
            } else {
              printDebugMsg('BLE set:tpm retry unexpected: $setAck');
            }
          } catch (e2) {
            printDebugMsg('BLE set:tpm retry failed: $e2');
          }
        }
      }

      return (ticks: ticks, ticksPerM: ticksPerM, syncedTpm: syncedTpm);
    } finally {
      await notifySub?.cancel();
      try {
        if (connectedHere && device.isConnected) {
          await device.disconnect();
        }
      } catch (_) {}
    }
  }
}
