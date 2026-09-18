import 'dart:async';
import 'dart:convert';
//import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
//import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/app_flavor.dart';
import 'package:geofence/iot_list_page.dart';
import 'package:geofence/iot_monitors_types.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/operators_page.dart';
import 'package:geofence/shop_page.dart';
import 'package:geofence/third_party_iot_page.dart';
//import 'package:google_maps_flutter/google_maps_flutter.dart';
//import 'package:http/http.dart' as http;
//import 'dart:io';
//import 'package:image_picker/image_picker.dart';
//import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geofence/utils.dart';
//import 'package:path_provider/path_provider.dart';
//import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mqtt_service.dart';
import 'edit_profile_pic_page.dart';

class _BaseMonitorUiState {
  TabController? tabController;
  List<ScrollController> scrollControllers = [];
  List<GlobalKey<IotDistanceWheelTypeState>> tabKeys = [];
  bool hasScrolled = false;
}

class IotMonitorsPage extends StatefulWidget {
  const IotMonitorsPage({super.key});

  @override
  IotMonitorsPageState createState() => IotMonitorsPageState();
}

class IotMonitorsPageState extends State<IotMonitorsPage> with TickerProviderStateMixin {
  StreamSubscription<String>? _mqttSubscription;
  TabController? _baseTabController;
  final Map<String, _BaseMonitorUiState> _baseUi = {};
  final int _selectedIndex = 0;
  bool scanBusy = false;
  bool _pairRequest = false;
  bool _connectRequest = false;
  bool _findRequest = false;
  bool _wifiRequest = false;
  bool _calibrateRequest = false;
  bool _syncRequest = false;
  bool _swapDialogOpen = false;
  String? _pendingMonitorCmd;
  List<BluetoothDevice> lstPairedDevices = [
    BluetoothDevice.fromId("00:11:22:33:44:55"),
    BluetoothDevice.fromId("11:11:22:33:44:55"),
  ];
  Timer? _timeout;
  final Map<String, bool> _subscriptionActiveCache = {};
  DateTime? _subscriptionCacheAt;
  DateTime? _lastSubWarningAt;
  bool _sonoffTabEnabled = false;

  bool get _showSonoff =>
      AppConfig.showThirdPartyIot && _sonoffTabEnabled;
  int get _sonoffOffset => _showSonoff ? 1 : 0;

  bool get _onSonoffTab {
    if (!_showSonoff || _baseTabController == null) return false;
    return _baseTabController!.index == _baseTabController!.length - 1;
  }

  String get _sonoffTabPrefsKey {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return 'sonoff_tab_enabled_$uid';
  }

  String get _ewelinkLinkedPrefsKey {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return 'ewelink_linked_$uid';
  }

  void _selectSonoffTab() {
    if (!_showSonoff || _baseTabController == null) return;
    _baseTabController!.animateTo(_baseTabController!.length - 1);
  }

  Future<void> _loadSonoffTabVisibility() async {
    if (!AppConfig.showThirdPartyIot) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_sonoffTabPrefsKey) == true;
      final linked = prefs.getBool(_ewelinkLinkedPrefsKey) == true;
      if (!mounted) return;
      if (enabled || linked) {
        setState(() => _sonoffTabEnabled = true);
      }
    } catch (_) {}
  }

  Future<void> _enableSonoffTab({bool select = true}) async {
    if (!AppConfig.showThirdPartyIot) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sonoffTabPrefsKey, true);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _sonoffTabEnabled = true);
    if (select) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selectSonoffTab();
      });
    }
  }

  Future<void> _disableSonoffTab() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sonoffTabPrefsKey, false);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _sonoffTabEnabled = false);
  }

  _BaseMonitorUiState _uiForBase(String baseDocId) {
    return _baseUi.putIfAbsent(baseDocId, () => _BaseMonitorUiState());
  }

  BaseStationData? _currentBase(BaseStationService baseService) {
    if (_baseTabController == null || baseService.lstBaseStations.isEmpty) {
      return null;
    }
    if (_onSonoffTab) return null;
    final idx = _baseTabController!.index.clamp(
      0,
      baseService.lstBaseStations.length - 1,
    );
    return baseService.lstBaseStations[idx];
  }

  List<MonitorSettings> _monitorsForBase(
    MonitorSettingsService monitorService,
    String baseDocId,
  ) {
    return monitorService.getMonitorsForBase(baseDocId);
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadSonoffTabVisibility();
      if (AppConfig.enableBluetooth) {
        _getBluetoothDevices();
      }
    });

    // Listen even if the base was connected on another page. Leaving Base
    // Stations cancels that page's MQTT subscription.
    _mqttStartListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    _baseTabController?.removeListener(_onBaseTabChanged);
    _baseTabController?.dispose();
    for (final ui in _baseUi.values) {
      ui.tabController?.dispose();
      for (final controller in ui.scrollControllers) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  // Timers
  void _startTimeout(int sec) {
    _timeout?.cancel();

    _timeout = Timer(Duration(seconds: sec), () {
      if (!mounted) return;
      final pending = _pendingMonitorCmd;
      _pendingMonitorCmd = null;
      MyGlobalMessage.show(
        'Timeout',
        pending == mqttCmdFind
            ? 'Find was sent, but the monitor did not reply.\n'
                'Check Monitor ID and that the IoT is online and communicating.'
            : pending == mqttCmdSendWifi
                ? 'No reply from base for WiFi push.\n'
                    'Check communication with the base; IoT must be in Bluetooth range of the Pi.'
                : pending == mqttCmdCalibrate
                    ? 'No reply from wheel for calibration.\n'
                        'Check Monitor ID, Wi‑Fi communication, and that calibration mode was completed on the wheel.'
                    : pending == mqttCmdSyncSettings
                        ? 'No reply from wheel for Sync.\n'
                            'Check Monitor ID and that the IoT is online and communicating.'
                        : 'No Reply From Base Station',
        MyMessageType.warning,
      );
    });
  }

  void _showSubscriptionRequired(MonitorSettings monitor) {
    final now = DateTime.now();
    if (_lastSubWarningAt != null &&
        now.difference(_lastSubWarningAt!) < const Duration(seconds: 8)) {
      return;
    }
    _lastSubWarningAt = now;
    final name = monitor.monitorName.trim().isNotEmpty
        ? monitor.monitorName
        : 'This distance wheel';
    MyGlobalMessage.show(
      'Subscription required',
      '$name needs an active subscription before it can be used.\n'
          'Link one under Monitor Info, or renew it on the Subscriptions screen.',
      MyMessageType.warning,
    );
  }

  Future<bool> _isSubscriptionOrderActive(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return false;
    final now = DateTime.now();
    if (_subscriptionCacheAt != null &&
        now.difference(_subscriptionCacheAt!) < const Duration(seconds: 30) &&
        _subscriptionActiveCache.containsKey(id)) {
      return _subscriptionActiveCache[id]!;
    }
    try {
      final uid = currentDataOwnerUid();
      if (uid == null) return false;
      final snap = await FirebaseFirestore.instance
          .collection(collectionUsers)
          .doc(uid)
          .collection(collectionShopOrders)
          .doc(id)
          .get();
      if (!snap.exists) {
        _subscriptionActiveCache[id] = false;
        _subscriptionCacheAt = now;
        return false;
      }
      final data = snap.data() ?? {};
      final status =
          (data['subscriptionStatus'] ?? '').toString().toLowerCase();
      final cancelled = status == 'cancelled' || status == 'canceled';
      final token = (data['subscriptionToken'] ?? data['payfastToken'] ?? '')
          .toString()
          .trim();
      final active = !cancelled &&
          (token.isNotEmpty || data['hasSubscription'] == true);
      _subscriptionActiveCache[id] = active;
      _subscriptionCacheAt = now;
      return active;
    } catch (_) {
      // Fail closed for wheels if we cannot verify.
      return false;
    }
  }

  Future<bool> _ensureActiveWheelSubscription(
    MonitorSettings monitor, {
    bool disconnectIfInvalid = true,
    bool showMessage = true,
  }) async {
    if (monitor.monitorType != monitorTypeWheel) return true;

    final orderId = monitor.subscriptionOrderId.trim();
    if (orderId.isEmpty) {
      if (showMessage) _showSubscriptionRequired(monitor);
      if (disconnectIfInvalid && monitor.isConnectedToIot) {
        await _disconnectIot(monitor);
      }
      return false;
    }

    final active = await _isSubscriptionOrderActive(orderId);
    if (active) return true;

    _subscriptionActiveCache[orderId] = false;
    monitor.subscriptionOrderId = '';
    monitor.subscriptionToken = '';
    await context.read<MonitorSettingsService>().save(
          monitor,
          showSavedMessage: false,
        );
    if (showMessage) _showSubscriptionRequired(monitor);
    if (disconnectIfInvalid &&
        (monitor.isConnectedToIot || monitor.isConnectingToIot)) {
      await _disconnectIot(monitor);
    }
    return false;
  }

  // MQTT
  void _mqttStartListener() {
    if (_mqttSubscription != null) return;

    _mqttSubscription = MqttService().messageStream.listen((msg) async {
      debugPrint('MQTT RX(IOT): $msg');

      Map<String, dynamic> jsonData;
      try {
        final decoded = jsonDecode(msg);
        if (decoded is! Map) return;
        jsonData = Map<String, dynamic>.from(decoded);
      } catch (e) {
        printDebugMsg('MQTT RX(IOT) not JSON: $e');
        return;
      }

      final cmd = jsonData[mqttJsonCmd];
      final fromId = jsonData[mqttJsonFromDeviceId];

      if(!mounted) return;
      final monitorService = context.read<MonitorSettingsService>();
      final baseService = context.read<BaseStationService>();
      final currentBase = _currentBase(baseService);
      if (currentBase == null) return;

      final baseMonitors =
          _monitorsForBase(monitorService, currentBase.docId);

      MonitorSettings currentMonitor() {
        if (fromId != null) {
          final id = fromId.toString();
          for (final m in baseMonitors) {
            if (m.monitorId == id) return m;
          }
        }
        final ui = _uiForBase(currentBase.docId);
        if (ui.tabController != null &&
            ui.tabController!.index >= 0 &&
            ui.tabController!.index < baseMonitors.length) {
          return baseMonitors[ui.tabController!.index];
        }
        if (baseMonitors.isNotEmpty) return baseMonitors.first;
        return MonitorSettings(baseStationDocId: currentBase.docId);
      }

      Future<bool> gateWheel(MonitorSettings monitor) async {
        if (monitor.monitorType != monitorTypeWheel) return true;
        return _ensureActiveWheelSubscription(monitor);
      }

      // Pair - Set Device ID
      if (cmd == mqttCmdDiscover) {
        scanBusy = false;
        final ui = _uiForBase(currentBase.docId);
        if (ui.tabController == null || baseMonitors.isEmpty) return;
        final monitor = baseMonitors[ui.tabController!.index];
        final String iotId = fromId.toString();

        MonitorSettings? monitorOld;
        for (final m in baseMonitors) {
          if (m.monitorId == iotId) {
            monitorOld = m;
            break;
          }
        }

        final bool needsSwap =
            monitorOld != null && monitorOld.monDocId != monitor.monDocId;

        // Always answer IoT immediately so swap / new / same behave the same.
        if (!needsSwap && monitorOld == null) {
          setState(() {
            monitor.monitorId = iotId;
          });
          _saveMonitor(monitor);
        }

        _replyFoundMonitor(monitor, iotId);

        if (needsSwap) {
          if (_swapDialogOpen) return;
          _swapDialogOpen = true;
          final MonitorSettings otherMonitor = monitorOld;

          myQuestionAlertBox(
            context: context,
            header: "Monitor Alert",
            message:
            "$iotId exists in Monitor: '${otherMonitor.monitorName}'.\n"
                "Do you want to change the monitor to this one?\n"
                "The other monitor will be disconnected",
            onPress: () async {
              setState(() {
                monitor.monitorId = iotId;
                otherMonitor.monitorId = "none";
              });

              final service = context.read<MonitorSettingsService>();
              await service.save(monitor, showSavedMessage: false);
              await service.save(otherMonitor, showSavedMessage: false);

              if (!mounted) return;
              MyGlobalMessage.show("Device Found", iotId, MyMessageType.info);
              _swapDialogOpen = false;
            },
          ).whenComplete(() {
            _swapDialogOpen = false;
          });
          return;
        }

        MyGlobalMessage.show("Device Found", iotId, MyMessageType.info);
      }

      if (cmd == mqttCmdDiscover ||
          (cmd == mqttCmdAck && _pendingMonitorCmd == mqttCmdDiscover)) {
        _timeout?.cancel();
        if (cmd == mqttCmdAck) _pendingMonitorCmd = null;
      }

      // Connecting to IOT Monitor
      if(cmd == mqttCmdConnectMonitor ||
          (cmd == mqttCmdAck && _pendingMonitorCmd == mqttCmdConnectMonitor)){
        final monitor = currentMonitor();
        if (!await gateWheel(monitor)) return;
        _timeout?.cancel();
        _pendingMonitorCmd = null;
        monitor.wheelDistance = 0;
        monitor.wheelTicks = 0;
        monitorService.setConnectingToIot(monitor.monitorId, false);
        monitorService.setConnectedToIot(monitor.monitorId, true);
        _updateLiveConnected(
          currentBase.docId,
          baseMonitors,
          connected: true,
          monitorDeviceId: monitor.monitorId,
        );
        final ui = _uiForBase(currentBase.docId);
        final index = ui.tabController?.index ?? 0;
        if (index >= 0 && index < ui.tabKeys.length) {
          ui.tabKeys[index].currentState?.updateDistance(0);
          ui.tabKeys[index].currentState?.updateTicks(0);
        }
        debugPrint('IOT Connected');
      }

      // DisConnecting from IOT Monitor (app button or IoT keypad)
      if(cmd == mqttCmdDisconnectMonitor ||
          cmd == mqttCmdDisconnect ||
          (cmd == mqttCmdAck && _pendingMonitorCmd == mqttCmdDisconnectMonitor)){
        _timeout?.cancel();
        _pendingMonitorCmd = null;
        final monitor = currentMonitor();
        monitorService.setConnectedToIot(monitor.monitorId, false);
        _updateLiveConnected(
          currentBase.docId,
          baseMonitors,
          connected: false,
          monitorDeviceId: monitor.monitorId,
        );
        debugPrint('IOT Disconnected');
      }

      // Find Monitor (IoT beep/flash ack)
      if (cmd == mqttCmdFind) {
        _timeout?.cancel();
        _pendingMonitorCmd = null;
        debugPrint('IOT Find ack');
        MyGlobalSnackBar.show('Device found — listen for beeps');
      }

      // Base accepted force WiFi BLE push
      if (cmd == mqttCmdSendWifi) {
        _timeout?.cancel();
        _pendingMonitorCmd = null;
        debugPrint('SEND_WIFI ack from base');
        MyGlobalSnackBar.show('Base pushing WiFi over Bluetooth…');
      }

      // Calibration result from wheel (#CALIBRATE only — not #ACK)
      if (cmd == mqttCmdCalibrate) {
        _timeout?.cancel();
        _pendingMonitorCmd = null;
        final monitor = currentMonitor();
        monitorService.setConnectedToIot(monitor.monitorId, true);

        final payload = jsonData[mqttJsonPayload];
        final ticks = _parseCalibrationTicks(payload);
        if (ticks != null) {
          await _applyCalibrationResult(
            currentBase.docId,
            monitor,
            ticks,
          );
        } else {
          MyGlobalMessage.show(
            'Calibration',
            'Wheel replied but no tick count was received.\n'
                'Update the wheel and base station software, then try again.',
            MyMessageType.warning,
          );
        }
        debugPrint('IOT calibration reply: $payload');
      }

      // Sync settings ack from wheel (#SYNC_SETTINGS)
      if (cmd == mqttCmdSyncSettings) {
        if (_pendingMonitorCmd != mqttCmdSyncSettings) return;
        _timeout?.cancel();
        _pendingMonitorCmd = null;
        final payload = jsonData[mqttJsonPayload];
        String ticksText = '';
        if (payload is Map) {
          final map = Map<String, dynamic>.from(payload);
          final ticks = map[mqttJsonTicksPerM];
          if (ticks != null) {
            ticksText = '\nTicks/m on wheel: $ticks';
          }
        }
        MyGlobalMessage.show(
          'Sync',
          'Settings received by wheel.$ticksText',
          MyMessageType.success,
        );
        debugPrint('IOT SYNC_SETTINGS ack: $payload');
      }

      // IOT Monitor Live Data
      if (cmd == mqttCmdLiveMonitorData) {
        final payload = jsonData[mqttJsonPayload];
        if (payload is! Map) return;

        final map = Map<String, dynamic>.from(payload);
        final dist = _parseLiveNum(map[mqttJsonWheelDistance]);
        final ticks = _parseLiveInt(map[mqttJsonWheelTicks]);

        final liveMonitor = currentMonitor();
        if (liveMonitor.monitorType == monitorTypeWheel &&
            !await gateWheel(liveMonitor)) {
          return;
        }
        if (!liveMonitor.isConnectedToIot) {
          monitorService.setConnectingToIot(liveMonitor.monitorId, false);
          monitorService.setConnectedToIot(liveMonitor.monitorId, true);
          _updateLiveConnected(
            currentBase.docId,
            baseMonitors,
            connected: true,
            monitorDeviceId: liveMonitor.monitorId,
          );
        }

        if (dist != null || ticks != null) {
          _updateWheelDistance(
            currentBase.docId,
            baseMonitors,
            distance: dist,
            ticks: ticks,
            monitorDeviceId: fromId?.toString(),
          );
        }
      }

      // Connect Base (from Base)
      if (cmd == mqttCmdConnectBase) {
        if(!mounted) return;
        _timeout?.cancel();
        context.read<SettingsService>().setIsBaseConnected(true);
        final base = currentBase;
        base.isConnected = true;

        if(_pairRequest){
          _pairRequest = false;
          _pairMonitor();
        }

        if(_connectRequest){
          _connectRequest = false;
          final ui = _uiForBase(base.docId);
          if (ui.tabController != null && baseMonitors.isNotEmpty) {
            _connectIot(baseMonitors[ui.tabController!.index]);
          }
        }

        if(_findRequest){
          _findRequest = false;
          final ui = _uiForBase(base.docId);
          if (ui.tabController != null && baseMonitors.isNotEmpty) {
            _findIot(baseMonitors[ui.tabController!.index]);
          }
        }

        if(_wifiRequest){
          _wifiRequest = false;
          final ui = _uiForBase(base.docId);
          if (ui.tabController != null && baseMonitors.isNotEmpty) {
            _sendWifiCreds(baseMonitors[ui.tabController!.index]);
          }
        }

        if (_calibrateRequest) {
          _calibrateRequest = false;
          final ui = _uiForBase(base.docId);
          if (ui.tabController != null && baseMonitors.isNotEmpty) {
            _calibrateIot(baseMonitors[ui.tabController!.index]);
          }
        }

        if (_syncRequest) {
          _syncRequest = false;
          final ui = _uiForBase(base.docId);
          if (ui.tabController != null && baseMonitors.isNotEmpty) {
            _syncTicksPerMToIot(baseMonitors[ui.tabController!.index]);
          }
        }

        final payload = jsonData[mqttJsonPayload];
        final savedCreds = await MqttCredentialsPreferences.saveFromPayload(
          payload: payload,
          baseId: base.bluetoothName,
        );
        if (savedCreds) {
          printDebugMsg('MQTT credentials saved for ${base.bluetoothName}');
        }

        MyGlobalSnackBar.show("Connected: ${base.ipAddress}");
      }
    });
  }
  Future<bool> _mqttConnectBase(BaseStationData base) async {
    final ip = base.ipAddress.trim();
    final deviceId = base.bluetoothName.trim();

    if (ip.isEmpty || ip == '0:0:0:0' || deviceId.isEmpty) {
      MyGlobalMessage.show(
        'Base Station',
        'Set IP address and Bluetooth ID for "${base.baseName}" on the Base Stations page.',
        MyMessageType.info,
      );
      return false;
    }

    final host = MqttService.normalizeHost(ip);
    await MqttCredentialsPreferences.syncFromFirestore(base.bluetoothName);

    bool isReady = await MqttService().restartService(
      host,
      baseId: base.bluetoothName,
    );

    if(isReady) {
      _mqttStartListener();
      _startTimeout(5);

      MqttService().tx(
        base.bluetoothName,
        mqttCmdConnectBase,
        {fireUid: currentDataOwnerUid()},
        mqttTopicFromAndroid,
      );
      return true;
    }

    // Failed
    final detail = MqttService().lastError;
    MyGlobalMessage.show(
      "Wifi connection FAILED",
      detail ??
          "Check that the base station is powered ON and on the same Wi‑Fi.",
      MyMessageType.warning,
    );
    setState(() {
      base.isConnected = false;
    });

    return false;
  }

  // Methods
  double? _parseLiveNum(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  int? _parseLiveInt(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  int? _parseCalibrationTicks(dynamic payload) {
    if (payload is! Map) return null;
    final map = Map<String, dynamic>.from(payload);
    for (final key in const [mqttJsonWheelTicks, 'wheel_ticks']) {
      final raw = map[key];
      if (raw is num) return raw.toInt();
      if (raw is String) {
        final parsed = int.tryParse(raw.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Future<void> _applyCalibrationResult(
    String baseDocId,
    MonitorSettings monitor,
    int ticks,
  ) async {
    final calDist = monitor.calibrationDistance;
    if (calDist <= 0) {
      MyGlobalMessage.show(
        'Calibration',
        'Enter the measured distance (meters) before calibrating.',
        MyMessageType.warning,
      );
      return;
    }
    if (ticks <= 0) {
      MyGlobalMessage.show(
        'Calibration',
        'Wheel reported zero ticks.\n'
            'On the wheel: finish calibration (START → roll distance → STOP, '
            'until "Calibrate END"), then press Calibrate in the app.\n'
            'If this persists, update the wheel firmware.',
        MyMessageType.warning,
      );
      return;
    }

    final newTicksPerM = ticks / calDist;
    monitor.ticks = ticks;
    monitor.ticksPerM = newTicksPerM;

    await context.read<MonitorSettingsService>().save(monitor);
    if (!mounted) return;

    setState(() {});
    final baseMonitors =
        context.read<MonitorSettingsService>().getMonitorsForBase(baseDocId);
    _updateWheelDistance(
      baseDocId,
      baseMonitors,
      distance: calDist.toDouble(),
      ticks: ticks,
      monitorDeviceId: monitor.monitorId,
    );
    final syncedToWheel =
        _pushMonitorSettingsToIot(monitor, monitor.monitorId);
    final ticksPerMText = newTicksPerM == newTicksPerM.roundToDouble()
        ? '${newTicksPerM.toInt()}'
        : newTicksPerM.toStringAsFixed(2);
    var successBody = 'Distance: $calDist\n'
        'Ticks: $ticks\n'
        'Ticks/m: $ticksPerMText';
    if (!syncedToWheel) {
      successBody +=
          '\n\nCould not sync ticks/m to the wheel.\n'
          'Press Connect on the monitor to apply.';
    }
    MyGlobalMessage.show(
      'Calibration Successful',
      successBody,
      MyMessageType.success,
    );
  }

  Future<bool> _calibrateIot(MonitorSettings monitor) async {
    if (!await _ensureActiveWheelSubscription(monitor)) return false;
    final settingService = context.read<SettingsService>();
    if (settingService.isBaseStationConnected == false) {
      MyGlobalMessage.show(
        'Connection',
        'Please connect to a Base Station first',
        MyMessageType.info,
      );
      return false;
    }

    if (monitor.calibrationDistance <= 0) {
      MyGlobalMessage.show(
        'Calibration',
        'Enter the measured distance in meters, then press Calibrate.',
        MyMessageType.info,
      );
      return false;
    }

    if (monitor.monitorId.isEmpty || monitor.monitorId == 'none') {
      MyGlobalMessage.show(
        'Monitor Not Found',
        "No monitor ID found. Please PAIR first.",
        MyMessageType.info,
      );
      return false;
    }

    final payload = {
      mqttJsonIotType: monitor.monitorType,
      mqttJsonTicksPerM: monitor.ticksPerM,
      mqttJsonCalibrationDistance: monitor.calibrationDistance,
    };

    if (!MqttService().isBrokerConnected) {
      MyGlobalMessage.show(
        'Connection',
        MqttService().lastError ??
            'Communication is not connected. Connect to the base station and try again.',
        MyMessageType.warning,
      );
      return false;
    }

    _mqttStartListener();
    _pendingMonitorCmd = mqttCmdCalibrate;
    _startTimeout(15);
    final sent = MqttService().tx(
      monitor.monitorId,
      mqttCmdCalibrate,
      payload,
      mqttTopicFromAndroid,
    );
    if (!sent) {
      _timeout?.cancel();
      _pendingMonitorCmd = null;
      MyGlobalMessage.show(
        'Calibration',
        MqttService().lastError ?? 'Could not send calibration request.',
        MyMessageType.warning,
      );
      return false;
    }

    MyGlobalSnackBar.show('Calibration request sent — waiting for wheel…');
    return true;
  }
  Future<bool> _pairMonitor() async {
    final settingsService = context.read<SettingsService>();
    if (settingsService.isBaseStationConnected == false) {
      MyGlobalMessage.show(
        "Connection",
        "Please connect to a Base Station first",
        MyMessageType.info,
      );
      return false;
    }

    final monitorService = context.read<MonitorSettingsService>();
    final base = _currentBase(context.read<BaseStationService>());
    if (base == null) return false;
    final baseMonitors = _monitorsForBase(monitorService, base.docId);
    if (baseMonitors.isEmpty) return false;

    final ui = _uiForBase(base.docId);
    final tabIndex = ui.tabController?.index ?? 0;
    final safeIndex = tabIndex.clamp(0, baseMonitors.length - 1);

    final payload = {
      mqttJsonIotType: baseMonitors[safeIndex].monitorType,
    };

    if(MqttService().isConnected){
      _mqttStartListener();
      _pendingMonitorCmd = mqttCmdDiscover;
      _startTimeout(8);
      MqttService().tx("", mqttCmdDiscover, payload, mqttTopicFromAndroid);
    }
    return true;
  }

  /// Ask the base to push WiFi/MQTT credentials to the IoT over Bluetooth.
  Future<bool> _sendWifiCreds(MonitorSettings monitor) async {
    final settingService = context.read<SettingsService>();
    final id = monitor.monitorId.trim();
    // Empty / none → base pushes to all currently BLE-connected IoTs.
    final toId = (id.isEmpty || id == 'none') ? '' : id;

    if (!settingService.isBaseStationConnected ||
        !MqttService().isBrokerConnected) {
      _wifiRequest = true;
      final base = _currentBase(context.read<BaseStationService>());
      if (base == null) {
        _wifiRequest = false;
        return false;
      }
      final ok = await _mqttConnectBase(base);
      if (!ok) {
        _wifiRequest = false;
        return false;
      }
      return true;
    }

    _mqttStartListener();
    _pendingMonitorCmd = mqttCmdSendWifi;
    _startTimeout(10);
    final sent = MqttService().tx(
      toId,
      mqttCmdSendWifi,
      {
        mqttJsonIotType: monitor.monitorType,
      },
      mqttTopicFromAndroid,
    );
    if (!sent) {
      _timeout?.cancel();
      _pendingMonitorCmd = null;
      MyGlobalMessage.show(
        'WiFi',
        MqttService().lastError ??
            'Could not request WiFi push. Reconnect to the base and try again.',
        MyMessageType.warning,
      );
      return false;
    }
    MyGlobalSnackBar.show(
      toId.isEmpty
          ? 'Requesting WiFi push to all BLE IoTs…'
          : 'Requesting WiFi push → $toId',
    );
    return true;
  }

  bool _pushMonitorSettingsToIot(
    MonitorSettings monitor,
    String toDeviceId,
  ) {
    if (!MqttService().isBrokerConnected) return false;
    final deviceId = toDeviceId.trim();
    if (deviceId.isEmpty || deviceId == 'none') return false;

    final payload = <String, dynamic>{
      mqttJsonIotType: monitor.monitorType,
      mqttJsonTicksPerM: monitor.ticksPerM,
    };

    if (monitor.monDocId.isNotEmpty) {
      final userId = context.read<UserDataService>().userdata?.userID ??
          currentDataOwnerUid();
      if (userId == null || userId.isEmpty) return false;

      payload[mqttJsonUserDocId] = userId;
      payload[mqttJsonMonitorDocId] = monitor.monDocId;
      payload[mqttJsonBaseStationDocId] = monitor.baseStationDocId;
      payload[mqttJsonIotName] = monitor.monitorName;
    }

    return MqttService().tx(
      deviceId,
      mqttCmdFoundMonitor,
      payload,
      mqttTopicFromAndroid,
    );
  }

  void _replyFoundMonitor(MonitorSettings monitor, String toDeviceId) {
    _pushMonitorSettingsToIot(monitor, toDeviceId);
  }

  Future<void> _syncTicksPerMToIot(MonitorSettings monitor) async {
    if (!await _ensureActiveWheelSubscription(monitor)) return;
    final id = monitor.monitorId.trim();
    if (id.isEmpty || id == 'none') {
      MyGlobalMessage.show(
        'Monitor Not Found',
        'No monitor ID found. Please PAIR first.',
        MyMessageType.info,
      );
      return;
    }

    final settingService = context.read<SettingsService>();
    if (!settingService.isBaseStationConnected ||
        !MqttService().isBrokerConnected) {
      _syncRequest = true;
      final base = _currentBase(context.read<BaseStationService>());
      if (base == null) {
        _syncRequest = false;
        return;
      }
      final ok = await _mqttConnectBase(base);
      if (!ok) {
        _syncRequest = false;
      }
      // CONNECT_BASE ack will call _syncTicksPerMToIot again via _syncRequest.
      return;
    }

    final payload = <String, dynamic>{
      mqttJsonIotType: monitor.monitorType,
      mqttJsonTicksPerM: monitor.ticksPerM,
    };

    _mqttStartListener();
    _pendingMonitorCmd = mqttCmdSyncSettings;
    _startTimeout(10);
    final sent = MqttService().tx(
      id,
      mqttCmdSyncSettings,
      payload,
      mqttTopicFromAndroid,
    );
    if (!sent) {
      _timeout?.cancel();
      _pendingMonitorCmd = null;
      MyGlobalMessage.show(
        'Sync',
        MqttService().lastError ??
            'Could not sync ticks/m to the wheel.',
        MyMessageType.warning,
      );
      return;
    }
    MyGlobalSnackBar.show('Syncing ticks/m to wheel…');
  }
  Future<bool> _connectIot(MonitorSettings monitor)async{
    if (!await _ensureActiveWheelSubscription(monitor)) return false;
    final settingService = context.read<SettingsService>();
    if(settingService.isBaseStationConnected == false){
      MyGlobalMessage.show("Connection", "Please connect to a Base Station first", MyMessageType.info);
      return false;
    }

    final payload = {
      mqttJsonIotType: monitor.monitorType,
      mqttJsonTicksPerM: monitor.ticksPerM,
    };

    if (!MqttService().isBrokerConnected) {
      MyGlobalMessage.show(
        'Connection',
        MqttService().lastError ??
            'Communication is not connected. Connect to the base station and try again.',
        MyMessageType.warning,
      );
      return false;
    }

    _mqttStartListener();
    _pendingMonitorCmd = mqttCmdConnectMonitor;
    _startTimeout(8);
    final sent = MqttService().tx(
      monitor.monitorId,
      mqttCmdConnectMonitor,
      payload,
      mqttTopicFromAndroid,
    );
    if (sent) {
      // Optimistic UI — Firestore snapshots were wiping this flag before.
      context.read<MonitorSettingsService>().setConnectingToIot(
            monitor.monitorId,
            false,
          );
      context.read<MonitorSettingsService>().setConnectedToIot(
            monitor.monitorId,
            true,
          );
      final base = _currentBase(context.read<BaseStationService>());
      if (base != null) {
        final monitors = context
            .read<MonitorSettingsService>()
            .getMonitorsForBase(base.docId);
        _updateLiveConnected(
          base.docId,
          monitors,
          connected: true,
          monitorDeviceId: monitor.monitorId,
        );
      }
    }
    return sent;
  }
  Future<bool> _disconnectIot(MonitorSettings monitor)async{
    final settingService = context.read<SettingsService>();
    if(settingService.isBaseStationConnected == false){
      MyGlobalMessage.show("Connection", "Please connect to a Base Station first", MyMessageType.info);
      return false;
    }

    if(MqttService().isConnected){
      _mqttStartListener();
      _pendingMonitorCmd = mqttCmdDisconnectMonitor;
      _startTimeout(8);
      final sent = MqttService().tx(
        monitor.monitorId,
        mqttCmdDisconnectMonitor,
        '',
        mqttTopicFromAndroid,
      );
      if (sent) {
        context.read<MonitorSettingsService>().setConnectedToIot(
              monitor.monitorId,
              false,
            );
        final base = _currentBase(context.read<BaseStationService>());
        if (base != null) {
          final monitors = context
              .read<MonitorSettingsService>()
              .getMonitorsForBase(base.docId);
          _updateLiveConnected(
            base.docId,
            monitors,
            connected: false,
            monitorDeviceId: monitor.monitorId,
          );
        }
      }
      return sent;
    }
    return true;
  }

  Future<bool> _findIot(MonitorSettings monitor) async {
    final settingService = context.read<SettingsService>();
    final id = monitor.monitorId.trim();
    if (id.isEmpty || id == 'none') {
      MyGlobalMessage.show(
        'Monitor Not Found',
        'No monitor ID found. Please PAIR first.',
        MyMessageType.info,
      );
      return false;
    }

    // Base UI flag can stay true after the WebSocket dropped — reconnect.
    if (!settingService.isBaseStationConnected ||
        !MqttService().isBrokerConnected) {
      _findRequest = true;
      final base = _currentBase(context.read<BaseStationService>());
      if (base == null) {
        _findRequest = false;
        return false;
      }
      final ok = await _mqttConnectBase(base);
      if (!ok) {
        _findRequest = false;
        return false;
      }
      // CONNECT_BASE ack will call _findIot again via _findRequest.
      return true;
    }

    _mqttStartListener();
    _pendingMonitorCmd = mqttCmdFind;
    _startTimeout(8);
    final sent = MqttService().tx(
      id,
      mqttCmdFind,
      {
        mqttJsonIotType: monitor.monitorType,
        'beeps': 4,
        'ledFlashes': 10,
        'ledCount': 3,
        'simultaneous': true,
      },
      mqttTopicFromAndroid,
    );
    if (!sent) {
      _timeout?.cancel();
      _pendingMonitorCmd = null;
      MyGlobalMessage.show(
        'Find',
        MqttService().lastError ??
            'Could not send Find. Reconnect to the base and try again.',
        MyMessageType.warning,
      );
      return false;
    }
    MyGlobalSnackBar.show('Find sent to base → $id');
    return true;
  }

  void _onBotNavBarTap(
    int index,
    MonitorSettingsService monService,
    BaseStationData base,
  ) {
    final baseMonitors = _monitorsForBase(monService, base.docId);
    final ui = _uiForBase(base.docId);

    // Add
    if (index == 0) _addMonitor(base.docId);

    // Delete
    if (index == 1) {
      if (baseMonitors.isEmpty || ui.tabController == null) return;
      final mon = baseMonitors[ui.tabController!.index];

      myQuestionAlertBox(
        context: context,
        header: "Delete",
        message: "${mon.monitorName}\n${mon.reg}\n\nAre you sure?",
        onPress: () {
          _markMonitorForDelete(mon);
        },
      );
    }

    // Tags
    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OperatorsPage()),
      );
    }
  }
  Future<void> _getBluetoothDevices() async {
    if (!AppConfig.enableBluetooth) {
      lstPairedDevices = [];
      return;
    }
    lstPairedDevices = await getBluetoothDevices();
  }
  void _saveMonitor(MonitorSettings monitor) async {
    final monitorService = context.read<MonitorSettingsService>();
    await monitorService.save(monitor);
  }
  void _addMonitor(String baseStationDocId) async {
    if (!mounted) return;

    final selectedType = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const IotListPage()),
    );
    if (!mounted || selectedType == null || selectedType.isEmpty) return;

    // SONOFF is managed on its own tab — don't create a monitor document.
    if (selectedType == monitorTypeSonoff) {
      await _enableSonoffTab();
      return;
    }

    const implementedTypes = {
      monitorTypeVehicle,
      monitorTypeWheel,
    };
    if (!implementedTypes.contains(selectedType)) {
      MyGlobalMessage.show(
        'IoT Type',
        'Not implemented yet',
        MyMessageType.info,
      );
      return;
    }

    final uid = currentDataOwnerUid();
    if (uid == null) return;

    final monitor = MonitorSettings(
      monitorName: 'New $selectedType',
      monitorType: selectedType,
      baseStationDocId: baseStationDocId,
    );

    final doc =
        await userBaseMonitorsRef(uid, baseStationDocId).add(monitor.toMap());

    if (!mounted) return;
    final ui = _uiForBase(baseStationDocId);
    final monitorService = context.read<MonitorSettingsService>();
    final baseMonitors = _monitorsForBase(monitorService, baseStationDocId);

    if (ui.tabController != null && baseMonitors.isNotEmpty) {
      final newIndex = baseMonitors.indexWhere((d) => d.monDocId == doc.id);
      if (newIndex != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ui.tabController!.animateTo(newIndex);
        });
      }
    }
  }
  Future<void> _markMonitorForDelete(MonitorSettings monitor) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || monitor.baseStationDocId.isEmpty) return;

      await userMonitorRef(
        user.uid,
        monitor.baseStationDocId,
        monitor.monDocId,
      ).set({fireMonitorMarkedToDelete: true}, SetOptions(merge: true));

      if (!mounted) return;
      final monitorService = context.read<MonitorSettingsService>();
      final baseMonitors =
          _monitorsForBase(monitorService, monitor.baseStationDocId);
      final ui = _uiForBase(monitor.baseStationDocId);

      setState(() {
        ui.tabController?.dispose();

        if (baseMonitors.isNotEmpty) {
          ui.tabController = TabController(
            length: baseMonitors.length,
            vsync: this,
          );

          int newIndex = 0;
          if (ui.tabController!.index >= baseMonitors.length) {
            newIndex = baseMonitors.length - 1;
          } else {
            newIndex = ui.tabController!.index;
          }
          ui.tabController!.animateTo(newIndex);
        } else {
          ui.tabController = null;
        }
      });

      MyGlobalSnackBar.show('Marked for delete');
    } catch (e) {
      printDebugMsg('Error marking monitor for delete: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete Failed: $e')),
        );
      }
    }
  }
  void _updateBaseTabs(int baseCount) {
    final length = baseCount + _sonoffOffset;
    if (length == 0) {
      _baseTabController?.removeListener(_onBaseTabChanged);
      _baseTabController?.dispose();
      _baseTabController = null;
      return;
    }

    if (_baseTabController == null || _baseTabController!.length != length) {
      final oldIndex = _baseTabController?.index ?? 0;
      _baseTabController?.removeListener(_onBaseTabChanged);
      _baseTabController?.dispose();
      _baseTabController = TabController(
        length: length,
        vsync: this,
        initialIndex: oldIndex.clamp(0, length - 1),
      );
      _baseTabController!.addListener(_onBaseTabChanged);
    }
  }

  void _updateMonitorTabs(String baseDocId, int length) {
    final ui = _uiForBase(baseDocId);
    if (length == 0) {
      if (ui.scrollControllers.isNotEmpty) {
        for (final c in ui.scrollControllers) {
          c.dispose();
        }
        ui.scrollControllers = [];
      }
      ui.tabController?.dispose();
      ui.tabController = null;
      return;
    }

    if (ui.tabController == null || ui.tabController!.length != length) {
      final oldIndex = ui.tabController?.index ?? 0;
      ui.tabController?.dispose();
      ui.tabController = TabController(
        length: length,
        vsync: this,
        initialIndex: oldIndex.clamp(0, length - 1),
      );
    }

    if (ui.tabKeys.length < length) {
      final toAdd = length - ui.tabKeys.length;
      ui.tabKeys.addAll(
        List.generate(toAdd, (_) => GlobalKey<IotDistanceWheelTypeState>()),
      );
    }

    if (ui.scrollControllers.length != length) {
      if (ui.scrollControllers.length < length) {
        final toAdd = length - ui.scrollControllers.length;
        ui.scrollControllers
            .addAll(List.generate(toAdd, (_) => ScrollController()));
      } else {
        while (ui.scrollControllers.length > length) {
          ui.scrollControllers.last.dispose();
          ui.scrollControllers.removeLast();
        }
      }
    }
  }
  void _scrollToBottomOnce(ScrollController scrollController) {
    Future.delayed(Duration.zero, () {
      // Callback runs after widget is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients && scrollController.position.hasContentDimensions) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }
  void _updateWheelDistance(
    String baseDocId,
    List<MonitorSettings> monitors, {
    double? distance,
    int? ticks,
    String? monitorDeviceId,
  }) {
    if (distance == null && ticks == null) return;

    final ui = _uiForBase(baseDocId);
    var index = ui.tabController?.index ?? 0;
    if (monitorDeviceId != null && monitorDeviceId.isNotEmpty) {
      final match = monitors.indexWhere((m) => m.monitorId == monitorDeviceId);
      if (match >= 0) index = match;
    }

    if (index < 0 ||
        index >= ui.tabKeys.length ||
        index >= monitors.length) {
      return;
    }

    final monitor = monitors[index];
    if (distance != null) monitor.wheelDistance = distance;
    if (ticks != null) monitor.wheelTicks = ticks;

    final state = ui.tabKeys[index].currentState;
    if (distance != null) state?.updateDistance(distance);
    if (ticks != null) state?.updateTicks(ticks);
  }

  void _updateLiveConnected(
    String baseDocId,
    List<MonitorSettings> monitors, {
    required bool connected,
    String? monitorDeviceId,
  }) {
    final ui = _uiForBase(baseDocId);
    var index = ui.tabController?.index ?? 0;
    if (monitorDeviceId != null && monitorDeviceId.isNotEmpty) {
      final match = monitors.indexWhere((m) => m.monitorId == monitorDeviceId);
      if (match >= 0) index = match;
    }

    if (index < 0 ||
        index >= ui.tabKeys.length ||
        index >= monitors.length) {
      return;
    }

    final monitor = monitors[index];
    monitor.isConnectedToIot = connected;
    monitor.isConnectingToIot = false;
    ui.tabKeys[index].currentState?.updateLiveConnected(connected);
  }

  Widget _buildBody(
    MonitorSettings monitor,
    Key key,
    BaseStationData base,
  ) {
    try {
      switch (monitor.monitorType) {
        case monitorTypeVehicle:
          return IotVehicleType(
            monitorData: monitor,
            lstPairedDevices: lstPairedDevices,

            // Vehicle Name
            onChangedVehicleName: (value) {
              setState(() {
                monitor.monitorName= value;
                _saveMonitor(monitor);
              });
          },

            // Fuel Consumption
            onChangedFuelConsumption: (value) {
              setState(() {
                monitor.fuelConsumption =
                    double.tryParse(value) ?? monitor.fuelConsumption;
                _saveMonitor(monitor);
              });
            },

            // Registration
            onChangedReg: (value) {
              setState(() {
                monitor.reg = value;
                _saveMonitor(monitor);
              });
            },

            // Bluetooth
            onChangedBluetooth: (BluetoothDevice? device) {
              setState(() {
                monitor.bluetoothDeviceName =  device?.platformName ?? '';
                monitor.bluetoothMac =  device?.remoteId.toString() ?? '';
                _saveMonitor(monitor);
              });
            },
          );
  
        case monitorTypeWheel:
          return IotDistanceWheelType(
            key: key,
            monitorData: monitor,

            // Name
            onChangedName: (value){
              setState(() {
                setState(() {
                  monitor.monitorName = value;
                  _saveMonitor(monitor);
                });
              });
            },

            // Monitor ID
            onChangedMonId: (value){
              setState(() {
                monitor.monitorId = value;
                _saveMonitor(monitor);
              });
            },

            // Ticks per Meter
            onChangedTicksPerM: (value) async {
              final newTicksPerM = double.tryParse(value.trim());
              if (newTicksPerM == null) {
                MyGlobalMessage.show(
                  'Ticks per Meter',
                  'Enter a valid number.',
                  MyMessageType.warning,
                );
                return;
              }
              final double oldTicksPerM = monitor.ticksPerM;
              if (oldTicksPerM == newTicksPerM) return;

              setState(() {
                monitor.ticksPerM = newTicksPerM;
              });

              final monitorService = context.read<MonitorSettingsService>();
              await monitorService.save(monitor);
              if (!mounted) return;
            },

            // Pair Monitor
            onTapPair: () async {
              if (await _mqttConnectBase(base)) {
                _pairRequest = true;
              }
            },

            // Force base to send WiFi/MQTT creds over BLE
            onTapSendWifi: () async {
              await _sendWifiCreds(monitor);
            },

            // Find Monitor (beep + flash on the paired IoT)
            onTapFind: () async {
              await _findIot(monitor);
            },

            // Sync ticks/m to wheel
            onTapSyncTicksPerM: () async {
              await _syncTicksPerMToIot(monitor);
            },

            // Calibrate Monitor
            onTapCalibrate: () async {
              if (!context.read<SettingsService>().isBaseStationConnected ||
                  !MqttService().isBrokerConnected) {
                _calibrateRequest = true;
                if (!await _mqttConnectBase(base)) {
                  _calibrateRequest = false;
                }
                return;
              }

              await _calibrateIot(monitor);
            },

            // Connect Monitor
            onTapConnect: () async {
              if (monitor.monitorId.isEmpty || monitor.monitorId == 'none') {
                MyGlobalMessage.show(
                  "Monitor Not Found",
                  "No monitor ID found. Please PAIR first",
                  MyMessageType.info,
                );
                return;
              }

              final ui = _uiForBase(base.docId);
              final monitorService = context.read<MonitorSettingsService>();
              if (context.read<SettingsService>().isBaseStationConnected) {
                if (monitor.isConnectedToIot) {
                  await _disconnectIot(monitor);
                } else {
                  monitorService.setConnectingToIot(monitor.monitorId, true);
                  ui.hasScrolled = false;
                  await _connectIot(monitor);
                }
              } else {
                _connectRequest = true;
                await _mqttConnectBase(base);
              }
            },
          );

        case monitorTypeSonoff:
          return const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              height: 520,
              child: SonoffIotPanel(embedded: true, active: true),
            ),
          );

        default:
          return Center(
            child: Text("Unknown Selection",
                style:TextStyle(color: Colors.white)
            ),
          );
      }
    } catch (e){
      return myProgressCircle();
    }
  }

  void _onBaseTabChanged() {
    if (_baseTabController == null || _baseTabController!.indexIsChanging) {
      return;
    }
    setState(() {
      _pairRequest = false;
      _connectRequest = false;
      _findRequest = false;
      _wifiRequest = false;
      _syncRequest = false;
      _pendingMonitorCmd = null;
      _timeout?.cancel();
    });
  }

  Widget _buildBaseMonitorsPanel(
    BaseStationData base,
    MonitorSettingsService monitors,
  ) {
    final baseMonitors = _monitorsForBase(monitors, base.docId);
    final ui = _uiForBase(base.docId);
    _updateMonitorTabs(base.docId, baseMonitors.length);

    if (ui.tabController != null &&
        baseMonitors.isNotEmpty &&
        baseMonitors[ui.tabController!.index].isConnectedToIot &&
        !ui.hasScrolled) {
      ui.hasScrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ui.tabController == null) return;
        _scrollToBottomOnce(ui.scrollControllers[ui.tabController!.index]);
      });
    }

    if (baseMonitors.isEmpty) {
      return myCenterMsg('No iOT Devices');
    }

    return Column(
      children: [
        Material(
          color: colorAppBar,
          child: TabBar(
            controller: ui.tabController,
            isScrollable: true,
            indicatorColor: colorOrange,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            tabs: baseMonitors.map((doc) => Tab(text: doc.monitorName)).toList(),
          ),
        ),
        Expanded(
          child: Container(
            color: colorAppBackground,
            child: TabBarView(
              controller: ui.tabController,
              children: List.generate(baseMonitors.length, (index) {
                final monitor = baseMonitors[index];

                return ListView(
                  controller: ui.scrollControllers[index],
                  padding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 0),
                  children: [
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border.all(
                            color: Colors.transparent,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(1),
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: GestureDetector(
                                    onTap: () async {
                                      final (ProfilePicData? profilePic) =
                                          await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              EditProfilePicPage(
                                            docId: monitor.monDocId,
                                            imageURL: monitor.imageURL,
                                            imageFilename:
                                                monitor.imageFilename,
                                            profileType: profileTypeOperator,
                                          ),
                                        ),
                                      );
                                      if (profilePic?.imageURL != null &&
                                          profilePic!.update) {
                                        setState(() {
                                          monitor.imageURL =
                                              profilePic.imageURL;
                                          monitor.imageFilename =
                                              profilePic.imageFilename;
                                        });
                                        context
                                            .read<MonitorSettingsService>()
                                            .save(monitor);
                                      }
                                    },
                                    child: Builder(
                                      builder: (context) {
                                        final hasPhoto =
                                            monitor.imageURL != null &&
                                                monitor.imageURL!.isNotEmpty;
                                        if (kIsWeb) {
                                          return hasPhoto
                                              ? NetworkCircleAvatar(
                                                  imageUrl: monitor.imageURL,
                                                  version:
                                                      monitor.imageFilename,
                                                  radius: 55,
                                                  backgroundColor:
                                                      Colors.transparent,
                                                )
                                              : CircleAvatar(
                                                  radius: 55,
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  backgroundImage:
                                                      getMonitorImage(monitor),
                                                );
                                        }
                                        final displayUrl =
                                            resolvedNetworkImageUrl(
                                          monitor.imageURL,
                                          version: monitor.imageFilename,
                                        );
                                        return CircleAvatar(
                                          radius: 55,
                                          backgroundColor: Colors.transparent,
                                          backgroundImage: hasPhoto
                                              ? CachedNetworkImageProvider(
                                                  displayUrl,
                                                ) as ImageProvider
                                              : getMonitorImage(monitor),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    GestureDetector(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MyText(text: monitor.monitorType!, fontsize: 20),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white,
                            size: 30,
                          ),
                        ],
                      ),
                      onTap: () async {
                        final selectedType = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const IotListPage(),
                          ),
                        );
                        if (selectedType == monitorTypeSonoff) {
                          await _enableSonoffTab();
                          return;
                        }
                        if (selectedType != null && selectedType is String) {
                          setState(() {
                            monitor.monitorType = selectedType;
                            context
                                .read<MonitorSettingsService>()
                                .save(monitor);
                          });
                        }
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 10,
                        right: 10,
                        bottom: 10,
                      ),
                      child: Divider(color: Colors.blue, thickness: 1),
                    ),
                    if (ui.tabKeys.isNotEmpty)
                      _buildBody(monitor, ui.tabKeys[index], base),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<MonitorSettingsService, SettingsService, BaseStationService>(
      builder: (context, monitors, settings, baseService, _) {
        if (monitors.isLoading ||
            baseService.isLoading ||
            settings.isLoading ||
            settings.isConnecting) {
          return myProgressCircle();
        }

        _updateBaseTabs(baseService.lstBaseStations.length);
        final currentBase = _currentBase(baseService);
        final currentBaseMonitors = currentBase == null
            ? <MonitorSettings>[]
            : _monitorsForBase(monitors, currentBase.docId);
        final onSonoff = _onSonoffTab;
        final hasAnyTabs = _baseTabController != null;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: colorAppBar,
            foregroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                myAppbarTitle("iOT Devices"),
                myConnectionStatus(settings: settings),
              ],
            ),
            bottom: hasAnyTabs
                ? TabBar(
                    controller: _baseTabController,
                    isScrollable: true,
                    indicatorColor: Colors.blueAccent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      ...baseService.lstBaseStations
                          .map((b) => Tab(text: b.baseName)),
                      if (_showSonoff)
                        const Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.electrical_services, size: 18),
                              SizedBox(width: 6),
                              Text('SONOFF'),
                            ],
                          ),
                        ),
                    ],
                  )
                : null,
          ),
          bottomNavigationBar: (currentBase == null || onSonoff)
              ? null
              : BottomNavigationBar(
                  currentIndex: _selectedIndex,
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: colorAppBar,
                  unselectedItemColor: Colors.white,
                  selectedItemColor: Colors.white,
                  onTap: (index) {
                    _onBotNavBarTap(index, monitors, currentBase);
                  },
                  items: [
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.add, color: Colors.white),
                      label: 'Add',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(
                        Icons.delete_forever,
                        color: currentBaseMonitors.isEmpty
                            ? Colors.grey
                            : Colors.white,
                      ),
                      label: 'Delete',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.person, color: Colors.white),
                      label: 'Tags',
                    ),
                  ],
                ),
          body: !hasAnyTabs
              ? myCenterMsg(
                  'No Base Stations. Add one on the Base Stations page.',
                )
              : TabBarView(
                  controller: _baseTabController,
                  children: [
                    ...baseService.lstBaseStations.map(
                      (baseStation) => _buildBaseMonitorsPanel(
                        baseStation,
                        monitors,
                      ),
                    ),
                    if (_showSonoff)
                      SonoffIotPanel(
                        embedded: true,
                        active: onSonoff,
                        onRemoved: _disableSonoffTab,
                      ),
                  ],
                ),
        );
      },
    );
  }
}
