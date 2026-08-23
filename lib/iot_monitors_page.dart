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
  //final ImagePicker _imagePicker = ImagePicker();
  bool scanBusy = false;
  bool _pairRequest = false;
  bool _connectRequest = false;
  bool _findRequest = false;
  bool _wifiRequest = false;
  bool _swapDialogOpen = false;
  String? _pendingMonitorCmd;
  //bool _isUploading = false;
  //double _uploadProgress = 0.0;
  List<BluetoothDevice> lstPairedDevices = [
    BluetoothDevice.fromId("00:11:22:33:44:55"),
    BluetoothDevice.fromId("11:11:22:33:44:55"),
  ];
  Timer? _timeout;

  _BaseMonitorUiState _uiForBase(String baseDocId) {
    return _baseUi.putIfAbsent(baseDocId, () => _BaseMonitorUiState());
  }

  BaseStationData? _currentBase(BaseStationService baseService) {
    if (_baseTabController == null ||
        baseService.lstBaseStations.isEmpty) {
      return null;
    }
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
                'Check Monitor ID and that the IoT is online on Wi‑Fi/MQTT.'
            : pending == mqttCmdSendWifi
                ? 'No reply from base for WiFi push.\n'
                    'Check MQTT connection; IoT must be in BLE range of the Pi.'
                : 'No Reply From Base Station',
        MyMessageType.warning,
      );
    });
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
        _timeout?.cancel();
        _pendingMonitorCmd = null;
        final monitor = currentMonitor();
        monitorService.setConnectedToIot(monitor.monitorId, true);
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

      // Calibration Mode
      if(cmd == mqttCmdCalibrate ||
          (cmd == mqttCmdAck && _pendingMonitorCmd == mqttCmdCalibrate)){
        _timeout?.cancel();
        _pendingMonitorCmd = null;
        final monitor = currentMonitor();
        monitorService.setConnectedToIot(monitor.monitorId, true);
        debugPrint('IOT in Calibration Mode');
      }

      // IOT Monitor Live Data
      if(cmd == mqttCmdLiveMonitorData){
        final monitor = currentMonitor();
        final payload = jsonData[mqttJsonPayload];
        final dist = payload[mqttJsonWheelDistance];
        final ticks = payload[mqttJsonWheelTicks];

        if(dist is num && ticks is num) {
          _updateWheelDistance(
            currentBase.docId,
            dist.toDouble(),
            ticks.toInt(),
          );
        }
        debugPrint('Wheel distance: ${monitor.wheelDistance}');
      }

      // Connect Base (from Base)
      if (cmd == mqttCmdConnectBase) {
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
        {fireUid: FirebaseAuth.instance.currentUser?.uid},
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
  Future<bool> _calibrateIot(MonitorSettings monitor) async {
    final settingService = context.read<SettingsService>();
    if(settingService.isBaseStationConnected == false){
      MyGlobalMessage.show("Connection", "Please connect to a Base Station first", MyMessageType.info);
      return false;
    }

    final payload = {
      mqttJsonIotType: monitor.monitorType,
      mqttJsonTicksPerM: monitor.ticksPerM,
    };

    if(MqttService().isConnected){
      _mqttStartListener();
      _pendingMonitorCmd = mqttCmdCalibrate;
      _startTimeout(8);
      MqttService().tx(monitor.monitorId, mqttCmdCalibrate, payload ,mqttTopicFromAndroid);
    }
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

  void _replyFoundMonitor(MonitorSettings monitor, String toDeviceId) {
    if (!MqttService().isConnected) return;
    if (toDeviceId.isEmpty || toDeviceId == 'none') return;

    final userId = context.read<UserDataService>().userdata?.userID;
    if (userId == null) return;

    final payload = {
      mqttJsonUserDocId: userId,
      mqttJsonMonitorDocId: monitor.monDocId,
      mqttJsonIotName: monitor.monitorName,
      mqttJsonIotType: monitor.monitorType,
      mqttJsonTicksPerM: monitor.ticksPerM,
    };

    MqttService().tx(
      toDeviceId,
      mqttCmdFoundMonitor,
      payload,
      mqttTopicFromAndroid,
    );
  }
  Future<bool> _connectIot(MonitorSettings monitor)async{
    final settingService = context.read<SettingsService>();
    if(settingService.isBaseStationConnected == false){
      MyGlobalMessage.show("Connection", "Please connect to a Base Station first", MyMessageType.info);
      return false;
    }

    final payload = {
      mqttJsonIotType: monitor.monitorType,
      mqttJsonTicksPerM: monitor.ticksPerM,
    };

    if(MqttService().isConnected){
      _mqttStartListener();
      _pendingMonitorCmd = mqttCmdConnectMonitor;
      _startTimeout(8);
      MqttService().tx(monitor.monitorId, mqttCmdConnectMonitor, payload ,mqttTopicFromAndroid);
    }
    return true;
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
      MqttService().tx(monitor.monitorId, mqttCmdDisconnectMonitor, '' ,mqttTopicFromAndroid);
    }
    return true;
  }

  Future<bool> _findIot(MonitorSettings monitor) async {
    final settingService = context.read<SettingsService>();
    final id = monitor.monitorId.trim();
    if (id.isEmpty || id == 'none') {
      MyGlobalMessage.show(
        'Monitor Not Found',
        'No monitor ID found. Please press Pair first.',
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
            'Could not publish Find. Reconnect to the base and try again.',
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

    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final monitor = MonitorSettings(
      monitorName: 'New Monitor',
      baseStationDocId: baseStationDocId,
    );

    final doc = await userBaseMonitorsRef(uid, baseStationDocId).add(monitor.toMap());

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
  void _updateBaseTabs(int length) {
    if (length == 0) {
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
  void _updateWheelDistance(String baseDocId, double distance, int ticks) {
    final ui = _uiForBase(baseDocId);
    if (ui.tabController == null) return;
    if (ui.tabController!.index < 0 ||
        ui.tabController!.index >= ui.tabKeys.length) {
      return;
    }

    ui.tabKeys[ui.tabController!.index].currentState?.updateDistance(distance);
    ui.tabKeys[ui.tabController!.index].currentState?.updateTicks(ticks);
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
              final double oldTicksPerM = monitor.ticksPerM;
              final double newTicksPerM = double.parse(value);
              if (oldTicksPerM == newTicksPerM) return;

              setState(() {
                monitor.ticksPerM = newTicksPerM;
              });

              final monitorService = context.read<MonitorSettingsService>();
              await monitorService.save(monitor);
              if (!mounted) return;
            },

            // Ticks
            onChangedTicks: (value){
              setState(() {
                monitor.ticks = int.parse(value);
                //_saveMonitor(monitor);
              });
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

            // Calibrate Monitor
            onTapCalibrate: () async {
              if (monitor.monitorId.isEmpty) {
                MyGlobalMessage.show(
                  "Monitor Not Found",
                  "No monitor ID found. Please press 'Pair' button",
                  MyMessageType.info,
                );
                return;
              }

              if (!context.read<SettingsService>().isBaseStationConnected) {
                _connectRequest = true;
                if (!await _mqttConnectBase(base)) return;
              }

              await _calibrateIot(monitor);
            },

            // Connect Monitor
            onTapConnect: () async {
              if (monitor.monitorId.isEmpty) {
                MyGlobalMessage.show(
                  "Monitor Not Found",
                  "No monitor ID found. Please press 'Pair' button",
                  MyMessageType.info,
                );
                return;
              }

              final ui = _uiForBase(base.docId);
              if (context.read<SettingsService>().isBaseStationConnected) {
                if (monitor.isConnectedToIot) {
                  monitor.isConnectedToIot = false;
                  _disconnectIot(monitor);
                } else {
                  monitor.isConnectedToIot = false;
                  monitor.isConnectingToIot = true;
                  ui.hasScrolled = false;
                  _connectIot(monitor);
                }
              } else {
                _connectRequest = true;
                await _mqttConnectBase(base);
              }
            },
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
      return myCenterMsg('No iOT Monitors');
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
                            builder: (context) => IotListPage(),
                          ),
                        );
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

        return Scaffold(
          appBar: AppBar(
            backgroundColor: colorAppBar,
            foregroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                myAppbarTitle("iOT Monitors"),
                myConnectionStatus(settings: settings),
              ],
            ),
            bottom: baseService.lstBaseStations.isNotEmpty
                ? TabBar(
                    controller: _baseTabController,
                    isScrollable: true,
                    indicatorColor: Colors.blueAccent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    tabs: baseService.lstBaseStations
                        .map((b) => Tab(text: b.baseName))
                        .toList(),
                  )
                : null,
          ),
          bottomNavigationBar: currentBase == null
              ? null
              : BottomNavigationBar(
                  currentIndex: _selectedIndex,
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
                  ],
                ),
          body: baseService.lstBaseStations.isEmpty
              ? myCenterMsg(
                  'No Base Stations. Add one on the Base Stations page.',
                )
              : TabBarView(
                  controller: _baseTabController,
                  children: baseService.lstBaseStations
                      .map(
                        (baseStation) => _buildBaseMonitorsPanel(
                          baseStation,
                          monitors,
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }
}
