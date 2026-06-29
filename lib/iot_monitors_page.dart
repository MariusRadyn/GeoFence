import 'dart:async';
import 'dart:convert';
//import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
//import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/iot_list_page.dart';
import 'package:geofence/iot_monitors_types.dart';
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

class IotMonitorsPage extends StatefulWidget {
  const IotMonitorsPage({super.key});

  @override
  IotMonitorsPageState createState() => IotMonitorsPageState();
}

class IotMonitorsPageState extends State<IotMonitorsPage> with TickerProviderStateMixin {
  StreamSubscription<String>? _mqttSubscription;
  TabController? _tabController;
  List<ScrollController> _scrollControllers = [];
  late final List<GlobalKey<IotDistanceWheelTypeState>> _tabKeys;

  VoidCallback? _baseListener;
  //final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>> _docFutures = {};
  final int _selectedIndex = 0;
  bool scanBusy = false;
  bool _hasScrolled = false;
  //final ImagePicker _imagePicker = ImagePicker();
  bool _pairRequest = false;
  bool _connectRequest = false;
  //bool _isUploading = false;
  //double _uploadProgress = 0.0;
  List<BluetoothDevice> lstPairedDevices = [
    BluetoothDevice.fromId("00:11:22:33:44:55"),
    BluetoothDevice.fromId("11:11:22:33:44:55"),
  ];
  Timer? _timeout;

  @override
  void initState() {
    super.initState();

    _tabKeys = [];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _getBluetoothDevices();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    if (_baseListener != null) {
      context.read<BaseStationService>().removeListener(_baseListener!);
      _baseListener = null;
    }
    _mqttSubscription?.cancel();
    _tabController?.dispose();
    for (var controller in _scrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // Timers
  void _startTimeout(int sec) {
    _timeout?.cancel();

    _timeout = Timer(Duration(seconds: sec), () {
      if (!mounted) return;
      MyGlobalMessage.show("Timeout", "No Reply From Base Station", MyMessageType.warning);
    });
  }

  // MQTT
  void _mqttStartListener() {
    if(_mqttSubscription != null) _mqttSubscription?.cancel();

    _mqttSubscription = MqttService().messageStream.listen((msg) {
      debugPrint('MQTT RX(IOT): $msg');

      final jsonData = jsonDecode(msg);
      final cmd = jsonData[mqttJsonCmd];
      final fromId = jsonData[mqttJsonFromDeviceId];

      if(!mounted) return;
      final monitorService = context.read<MonitorSettingsService>();

      // Pair - Set Device ID
      if (cmd == mqttCmdDiscover) {
        scanBusy = false;
        final monitor = monitorService.lstMonitors[_tabController!.index];

        MonitorSettings? monitorOld;
        for (final m in monitorService.lstMonitors) {
          if (m.monitorId == fromId) {
            monitorOld = m;
            break;
          }
        }

        if (monitorOld != null && monitorOld.monitorId != fromId) {
          myQuestionAlertBox(
            context: context,
            header: "Monitor Alert",
            message:
            "$fromId exists in Monitor: '${monitorOld.monitorName}'.\n"
                "Do you want to change the monitor to this one?\n"
                "The other monitor will be disconnected",
            onPress: () {
              setState(() {
                monitor.monitorId = fromId;
                monitorOld!.monitorId = "none";
              });
              _saveMonitor(monitor);
              _saveMonitor(monitorOld!);
            },
          );
        }

        if(monitorOld != null && monitorOld.monitorId == fromId){
          // Nothing changed
          MyGlobalMessage.show("Device found", fromId, MyMessageType.info);
        } else {

          // New Monitor
          setState(() {
            monitor.monitorId = fromId;
          });
          _saveMonitor(monitor);
          MyGlobalMessage.show("Device Found", fromId, MyMessageType.info);
        }

        final payload =  {
          mqttJsonUserDocId: context.read<UserDataService>().userdata!.userID,
          mqttJsonMonitorDocId: monitorService.lstMonitors[_selectedIndex].monDocId,
          mqttJsonIotName: monitorService.lstMonitors[_selectedIndex].monitorName,
          mqttJsonIotType: monitorService.lstMonitors[_selectedIndex].monitorType,
          mqttJsonTicksPerM: monitorService.lstMonitors[_selectedIndex].ticksPerM,
        };

        // Reply - Found Monitor
        MqttService().tx(
          monitor.monitorId,
          mqttCmdFoundMonitor,
          payload,
          mqttTopicFromAndroid,
        );
      }

      // Calibration Mode
      if(cmd == mqttCmdCalibrate){
        final monitor = monitorService.lstMonitors[_tabController!.index];
        monitorService.setConnectedToIot(monitor.monitorId, true);
        debugPrint('IOT in Calibration Mode');
      }

      // Connecting to IOT Monitor
      if(cmd == mqttCmdConnectMonitor){
        final monitor = monitorService.lstMonitors[_tabController!.index];
        monitorService.setConnectedToIot(monitor.monitorId, true);
        debugPrint('IOT Connected');
      }

      // DisConnecting from IOT Monitor
      if(cmd == mqttCmdDisconnectMonitor){
        final monitor = monitorService.lstMonitors[_tabController!.index];
        monitorService.setConnectedToIot(monitor.monitorId, false);
        debugPrint('IOT Connected');
      }

      // IOT Monitor Live Data
      if(cmd == mqttCmdLiveMonitorData){
        final monitor = monitorService.lstMonitors[_tabController!.index];
        final payload = jsonData[mqttJsonPayload];
        final dist = payload[mqttJsonWheelDistance];
        final ticks = payload[mqttJsonWheelTicks];

        if(dist is num && ticks is num) _updateWheelDistance(dist.toDouble(), ticks.toInt());
        debugPrint('Wheel distance: ${monitor.wheelDistance}');
      }

      // Connect Base (from Base)
      if (cmd == mqttCmdConnectBase) {
        _timeout?.cancel();
        context.read<SettingsService>().setIsBaseConnected(true);
        var ip = context.read<SettingsService>().fireSettings!.connectedDeviceIp;

        if(_pairRequest){
          _pairRequest = false;
          _pairMonitor(ip);
        }

        if(_connectRequest){
          _connectRequest = false;
          _connectIot(ip, monitorService.lstMonitors[_tabController!.index]);
        }

        var base = context.read<BaseStationService>().lstBaseStations.firstWhere((x) => x.ipAddress == ip);
        base.isConnected = true;

        MyGlobalSnackBar.show("Connected: $ip");
      }
    });
  }
  Future<bool> _mqttConnectBase () async {
    String? ip = context.read<SettingsService>().fireSettings?.connectedDeviceIp;
    String? deviceId = context.read<SettingsService>().fireSettings?.connectedDeviceId;

    if(ip == null || deviceId == null) {
      MyGlobalMessage.show(
          'Base Stations',
          'No previously connected base stations. Please set one in Base Stations page',
          MyMessageType.info
      );
      return false;
    }

    if(context.read<BaseStationService>().lstBaseStations.isEmpty){
      MyGlobalMessage.show(
          'Base Stations',
          'No Base Stations found. Please set one in Base Stations page',
          MyMessageType.info
      );
      return false;
    }

    BaseStationData base = context.read<BaseStationService>().lstBaseStations.firstWhere((x)  => x.bluetoothName == deviceId);

    if (!await MqttService().isBrokerReachable(ip)) {
      if (!mounted) return false;
      MyGlobalMessage.show(
        "Base Station Offline",
        "Check that the base station is powered on and on the same Wi‑Fi network.",
        MyMessageType.warning,
      );
      setState(() {
        base.isConnected = false;
      });
      context.read<SettingsService>().setIsBaseConnected(false);
      return false;
    }

    bool isReady = await MqttService().restartService(ip);

    if(isReady) {
      _mqttStartListener();
      _startTimeout(5);

      MqttService().tx(base.bluetoothName, mqttCmdConnectBase, {} ,mqttTopicFromAndroid);
      return true;
    }

    // Failed
    MyGlobalMessage.show("Warning", "Wifi connection FAILED", MyMessageType.warning);
    setState(() {
      base.isConnected = false;
    });

    return false;
  }

  // Methods
  Future<bool> _calibrateIot(String ip, MonitorSettings monitor) async {
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
      MqttService().tx(monitor.monitorId, mqttCmdCalibrate, payload ,mqttTopicFromAndroid);
    }
    return true;
  }
  Future<bool> _pairMonitor(String ip)async{
    final settingsService = context.read<SettingsService>();
    final monitorService = context.read<MonitorSettingsService>();

    if(settingsService.isBaseStationConnected == false){
      MyGlobalMessage.show("Connection", "Please connect to a Base Station first", MyMessageType.info);
      return false;
    }

    final payload =  {
      mqttJsonIotType: monitorService.lstMonitors[_selectedIndex].monitorType,
    };

    if(MqttService().isConnected){
      MqttService().tx("", mqttCmdDiscover, payload, mqttTopicFromAndroid);
    }
    return true;
  }
  Future<bool> _connectIot(String ip, MonitorSettings monitor)async{
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
      MqttService().tx(monitor.monitorId, mqttCmdDisconnectMonitor, '' ,mqttTopicFromAndroid);
    }
    return true;
  }
  void _onBotNavBarTap(int index, MonitorSettingsService monService) {
    // Add
    if(index == 0)_addMonitor();

    // Delete
    if(index == 1) {
      if (monService.lstMonitors.isEmpty) return;
      final mon = monService.lstMonitors[ _tabController!.index];

      myQuestionAlertBox(
          context: context,
          header: "Delete",
          message: "${mon.monitorName}\n${mon.reg}\n\nAre you sure?",
          onPress: (){
            _deleteMonitor(mon);
          }
      );
    }
  }
  Future<void> _getBluetoothDevices() async {
    lstPairedDevices = await getBluetoothDevices();
  }
  void _saveMonitor(MonitorSettings monitor) async {
    if (_tabController == null) return;
    final monitorService = context.read<MonitorSettingsService>();
    monitorService.save(monitor);
    await monitorService.load();

    MyGlobalSnackBar.show('Saved');
  }
  void _addMonitor() async {
    if (!mounted) return;

    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseFirestore.instance
        .collection(collectionUsers)
        .doc(uid)
        .collection(collectionMonitors);

    final monitor = MonitorSettings(
      monitorName: 'New Monitor',
    );

    final doc = await ref.add(monitor.toMap());

    if(!mounted) return;
    final monitorService = context.read<MonitorSettingsService>();
    await monitorService.load();
    if (!mounted) return;

    if (_tabController != null &&  monitorService.lstMonitors.isNotEmpty) {
      final newIndex = monitorService.lstMonitors.indexWhere((d) => d.monDocId == doc.id);
      if (newIndex != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _tabController!.animateTo(newIndex);
        });
      }
    }
  }
  Future<void> _deleteMonitor(MonitorSettings monitor) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;

      // 1️⃣ Delete from Firestore
      await FirebaseFirestore.instance
          .collection(collectionUsers)
          .doc(user?.uid)
          .collection(collectionMonitors)
          .doc(monitor.monDocId)
          .delete();

      if(!mounted) return;
      final monitorService = context.read<MonitorSettingsService>();
      await monitorService.load();
      
      setState(() {
        _tabController?.dispose();

        if (monitorService.lstMonitors.isNotEmpty) {
          _tabController = TabController(
            length: monitorService.lstMonitors.length,
            vsync: this,
          );

          // 5️⃣ Ensure a safe tab is selected
          int newIndex = 0;
          if (_tabController!.index >= monitorService.lstMonitors.length) {
            newIndex = monitorService.lstMonitors.length - 1;
          } else {
            newIndex = _tabController!.index;
          }
          _tabController!.animateTo(newIndex);
        } else {
          _tabController = null;
        }
      });
    } catch (e) {
      printDebugMsg('Error deleting vehicle: $e');
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete Failed: $e')),
        );
      }
    }
  }

  void _updateTabs(int length) {
    if (length == 0) {
      if (_scrollControllers.isNotEmpty) {
        for (var c in _scrollControllers) {
          c.dispose();
        }
        _scrollControllers = [];
      }
      return;
    }

    if (_tabController == null || _tabController!.length != length) {
      final oldIndex = _tabController?.index ?? 0;

      _tabController?.dispose();
      _tabController = TabController(
        length: length,
        vsync: this,
        initialIndex: oldIndex.clamp(0, length - 1),
      );
    }

    if (_tabKeys.length < length){
      final toAdd = length - _tabKeys.length;
      _tabKeys.addAll(
        List.generate(toAdd, (_) => GlobalKey<IotDistanceWheelTypeState>()),
      );
    }

    // Manage scroll controllers
    if (_scrollControllers.length != length) {
      if (_scrollControllers.length < length) {
        // Add new ones
        final toAdd = length - _scrollControllers.length;
        _scrollControllers.addAll(List.generate(toAdd, (_) => ScrollController()));
      } else {
        // Remove extra ones
        while (_scrollControllers.length > length) {
          _scrollControllers.last.dispose();
          _scrollControllers.removeLast();
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
  void _updateWheelDistance(double distance, int ticks) {
    if(_tabController == null) return;
    if (_tabController!.index < 0 || _tabController!.index >= _tabKeys.length) return;

    _tabKeys[_tabController!.index].currentState?.updateDistance(distance);
    _tabKeys[_tabController!.index].currentState?.updateTicks(ticks);
  }

  /// Reads 'ticks' and 'ticksPerM' from a document in 'iotData',
  /// calculates the distance, and updates the document atomically.
  // Future<void> _updateIotDistance(String documentId) async {
  //   final FirebaseFirestore firestore = FirebaseFirestore.instance;
  //   final DocumentReference docRef = firestore.collection('iotData').doc(documentId);

  //   try {
  //     // Using a transaction to ensure atomic read-write operations
  //     await firestore.runTransaction((transaction) async {
  //       final DocumentSnapshot snapshot = await transaction.get(docRef);

  //       if (!snapshot.exists) {
  //         throw FirebaseException(
  //           plugin: 'cloud_firestore',
  //           message: "Document $documentId not found in 'iotData' collection.",
  //         );
  //       }

  //       // Extract values dynamically and cast safely to num
  //       final num ticks = snapshot.get('ticks') ?? 0;
  //       final num ticksPerM = snapshot.get('ticksPerM') ?? 1; // Default to 1 to avoid division by zero

  //       // Calculate distance = ticks / ticksPerM
  //       final double calculatedDistance = ticksPerM != 0 
  //           ? ticks.toDouble() / ticksPerM.toDouble() 
  //           : 0.0;

  //       // Atomically write the calculated distance back to the document
  //       transaction.update(docRef, {
  //         'distance': calculatedDistance,
  //         'lastUpdated': FieldValue.serverTimestamp(), // Optional: track when it was updated
  //       });
  //     });
      
  //     print("Distance updated successfully for document: $documentId");
  //   } catch (e) {
  //     print("Failed to update distance: $e");
  //   }
  // }

  Widget _buildBody(MonitorSettings monitor, Key key) {
    try{
      final settingService = context.read<SettingsService>();

      switch(monitor.monitorType){
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
                monitor.fuelConsumption =  value as double;
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
            onTapPair: () async{
              if (await _mqttConnectBase()) {
                _pairRequest = true;
              }
            },

            // Calibrate Monitor
            onTapCalibrate: () async {
              if(monitor.monitorId.isEmpty){
                MyGlobalMessage.show("Monitor Not Found", "No monitor ID found. Please press 'Pair' button", MyMessageType.info);
                return;
              }

              if(!context.read<SettingsService>().isBaseStationConnected) {
                _connectRequest = true;
                if(!await _mqttConnectBase()) return;
              }

              await _calibrateIot(settingService.fireSettings!.connectedDeviceIp, monitor);
            },

            // Connect Monitor
            onTapConnect: () async {
              if(monitor.monitorId.isEmpty){
                MyGlobalMessage.show("Monitor Not Found", "No monitor ID found. Please press 'Pair' button", MyMessageType.info);
                return;
              }

              if(context.read<SettingsService>().isBaseStationConnected) {
                if(monitor.isConnectedToIot){
                  monitor.isConnectedToIot = false;
                  _disconnectIot(monitor);
                } else {
                  monitor.isConnectedToIot = false;
                  monitor.isConnectingToIot = true;
                  _hasScrolled = false;
                  _connectIot(settingService.fireSettings!.connectedDeviceIp, monitor);
                }
              }
              else {
                _connectRequest = true;
                await _mqttConnectBase();
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

  @override
  Widget build(BuildContext context) {
    return Consumer3<MonitorSettingsService, SettingsService, BaseStationService>(
      builder: (context, monitors, settings, base,_){
        if (monitors.isLoading || base.isLoading || settings.isLoading || settings.isConnecting) {
          return myProgressCircle();
        }
        
        if (_tabController != null && monitors.lstMonitors[_tabController!.index].isConnectedToIot && !_hasScrolled) {
          _hasScrolled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottomOnce(_scrollControllers[_tabController!.index]);
          });
        }

        _updateTabs(monitors.lstMonitors.length);

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
            bottom: monitors.lstMonitors.isNotEmpty
                ? TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: Colors.blueAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              tabs: monitors.lstMonitors
                  .map((doc) => Tab(text: doc.monitorName))
                  .toList(),
            )
                :null
          ),
          bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedIndex,
              backgroundColor: colorAppBar,
              unselectedItemColor: Colors.white,
              selectedItemColor: Colors.white,
              onTap: (index) {
                _onBotNavBarTap(index, monitors);
              },
              items: [
                // Add Button
                BottomNavigationBarItem(
                    icon: Icon(
                      Icons.add,
                      color: Colors.white
                    ),
                    label: 'Add'
                ),

                // Delete Button
                BottomNavigationBarItem(
                  icon: Icon(
                    Icons.delete_forever,
                    color: monitors.lstMonitors.isEmpty
                        ? Colors.grey
                        : Colors.white,
                  ),
                  label: 'Delete',
                ),
              ]
          ),

          body: monitors.lstMonitors.isEmpty
            ?  myCenterMsg('No iOT Monitors')
              :Container(
            color: colorAppBackground,
            child: TabBarView(
              controller: _tabController,
              children: List.generate(monitors.lstMonitors.length, (index){
                final monitor = monitors.lstMonitors[index];

                      return ListView(
                        controller: _scrollControllers[index],
                        padding: const EdgeInsets.symmetric( vertical: 20, horizontal: 0),
                        children: [

                          // Picture header Container
                          Center(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                border: Border.all( color: Colors.transparent, width: 1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  children: [

                                    // iOT Monitor Picture
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.all(1), // border thickness
                                        decoration: BoxDecoration(
                                          color: Colors.blue, // border color
                                          shape: BoxShape.circle,
                                        ),
                                        child:GestureDetector(
                                          onTap: () async {
                                            final (ProfilePicData? profilePic) = await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => EditProfilePicPage(
                                                  docId: monitor.monDocId,
                                                  imageURL: monitor.imageURL,
                                                  imageFilename: monitor.imageFilename,
                                                  profileType: profileTypeOperator,
                                                ),
                                              ),
                                            );
                                            if(profilePic?.imageURL != null && profilePic!.update){
                                              setState(() {
                                                monitor.imageURL = profilePic.imageURL;
                                                monitor.imageFilename = profilePic.imageFilename;

                                              });
                                              context.read<MonitorSettingsService>().save(monitor);
                                            }
                                          },
                                          child: CircleAvatar(
                                            radius: 55,
                                            backgroundColor: Colors.transparent,
                                            child: CircleAvatar(
                                              radius: 55,
                                              backgroundImage:  monitor.imageURL != null &&  monitor.imageURL!.isNotEmpty
                                                  ? CachedNetworkImageProvider(monitor.imageURL!) as ImageProvider
                                                  : getMonitorImage(monitor),

                                            ),
                                          ),
                                        ),
                                      )
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: 15),

                          // Select Monitor Type
                          GestureDetector(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                MyText(text: monitor.monitorType!, fontsize: 20),

                                Icon(
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
                                builder: (context) => IotListPage()
                                ),
                              );

                              // Only update if the user actually picked something
                              // (prevents errors if they hit the back button)
                              if (selectedType != null && selectedType is String) {
                                setState(() {
                                  monitor.monitorType = selectedType;

                                  // Optional: Save the change to your service/database immediately
                                  context.read<MonitorSettingsService>().save(monitor);
                                });
                              }
                            },
                          ),

                          Padding(
                            padding: const EdgeInsets.only(left: 10, right: 10, bottom: 10),
                            child: Divider(color: Colors.blue,thickness: 1,),
                          ),

                          //--------------------------------------------------------------
                          // Monitor Types
                          //--------------------------------------------------------------
                          if(_tabKeys.isNotEmpty) _buildBody(monitor,_tabKeys[index])
                        ],
                      );

                },
              ).toList(),
            ),
          ),
        );
      });
    }
}
