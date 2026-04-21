import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/iotMonitorsTypes.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geofence/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'MqttService.dart';
import 'editProfilePicPage.dart';

class IotMonitorsPage extends StatefulWidget {
  const IotMonitorsPage({super.key});

  @override
  _IotMonitorsPageState createState() => _IotMonitorsPageState();
}

class _IotMonitorsPageState extends State<IotMonitorsPage> with TickerProviderStateMixin {
  final mqttService = MqttService();
  late StreamSubscription<String> _mqttSubscription;
  TabController? _tabController;
  late List<ScrollController> _scrollControllers;
  late final List<GlobalKey<IotDistanceWheelTypeState>> _tabKeys;

  VoidCallback? _baseListener;
  final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>> _docFutures = {};
  final int _selectedIndex = 0;
  bool scanBusy = false;
  bool _hasScrolled = false;
  final ImagePicker _imagePicker = ImagePicker();
  bool _listenerStarted = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  List<BluetoothDevice> lstPairedDevices = [
    BluetoothDevice.fromId("00:11:22:33:44:55"),
    BluetoothDevice.fromId("11:11:22:33:44:55"),
  ];

  @override
  void initState() {
    super.initState();

    _startMqttListener();
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
    _mqttSubscription.cancel();
    _tabController?.dispose();
    super.dispose();
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
        .collection(CollectionUsers)
        .doc(uid)
        .collection(CollectionMonitors);

    final monitor = MonitorSettings(
      monitorName: 'New Monitor',
    );

    final doc = await ref.add(monitor.toMap());

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
          .collection(CollectionUsers)
          .doc(user?.uid)
          .collection(CollectionMonitors)
          .doc(monitor.monDocId)
          .delete();

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
      print('Error deleting vehicle: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete Failed: $e')),
      );
    }
  }
  ImageProvider<Object> _getMonitorImage(MonitorSettings monitor) {
    if (monitor.imageURL == null || monitor.imageURL!.isEmpty ) {
      switch (monitor.monitorType) {
        case MonTypeVehicle:
          return AssetImage(IMAGE_VEHICLE);

        case MonTypeWheel:
          return AssetImage(IMAGE_WHEEL);

        case MonTypeMobileMachineMon:
          return AssetImage(IMAGE_MOBILE_MACHINE);

        case MonTypeStationaryMachineMon:
          return AssetImage(IMAGE_STATIONARY_MACHINE);

        default:
          return AssetImage(IMAGE_NO_IMAGE);
      }
    }
    else {
      return AssetImage(IMAGE_NO_IMAGE);
    }
  }
  void _updateTabs(int length) {
    if (length == 0) return;

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

    final monitorService = context.read<MonitorSettingsService>();
    _scrollControllers=List.generate(monitorService.lstMonitors.length, (_) => ScrollController());;

  }
  void _scrollToBottomOnce(ScrollController _scrollController) {
    Future.delayed(Duration.zero, () {
      // Callback runs after widget is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }
  void _updateWheelDistance(double distance) {
    if(_tabController == null) return;
    if (_tabController!.index < 0 || _tabController!.index >= _tabKeys.length) return;

    _tabKeys[_tabController!.index].currentState?.updateDistance(distance);
  }

  // MQTT
  void _startMqttListener() {
    _mqttSubscription = mqttService.messageStream.listen((msg) {
      debugPrint('MQTT RX: $msg');

      final jsonData = jsonDecode(msg);
      final cmd = jsonData[MQTT_JSON_CMD];
      final fromId = jsonData[MQTT_JSON_FROM_DEVICE_ID];

      if(!mounted) return;
      final monitorService = context.read<MonitorSettingsService>();

      // Pair - Set Device ID
      if (cmd == MQTT_CMD_DISCOVER) {
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
          MyQuestionAlertBox(
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
        } if(monitorOld != null && monitorOld.monitorId == fromId){

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
          MQTT_JSON_USER_DOC_ID: context.read<UserDataService>().userdata!.userID,
          MQTT_JSON_MON_DOC_ID: monitorService.lstMonitors[_selectedIndex].monDocId,
          MQTT_JSON_IOT_NAME: monitorService.lstMonitors[_selectedIndex].monitorName,
          MQTT_JSON_IOT_TYPE: monitorService.lstMonitors[_selectedIndex].monitorType,
          MQTT_JSON_TICKS_PER_M: monitorService.lstMonitors[_selectedIndex].ticksPerM,
        };

        // Reply - Found Monitor
        mqttService.tx(
          monitor.monitorId,
          MQTT_CMD_FOUND_MONITOR,
          payload,
          MQTT_TOPIC_FROM_ANDROID,
        );
      }

      // Connecting to IOT Monitor
      if(cmd == MQTT_CMD_CONNECT_MONITOR){
        final monitor = monitorService.lstMonitors[_tabController!.index];
        monitorService.setConnectedToIot(monitor.monitorId, true);
        debugPrint('IOT Connected');
      }

      // DisConnecting from IOT Monitor
      if(cmd == MQTT_CMD_DISCONNECT_MONITOR){
        final monitor = monitorService.lstMonitors[_tabController!.index];
        monitorService.setConnectedToIot(monitor.monitorId, false);
        debugPrint('IOT Connected');
      }

      // IOT Monitor Data
      if(cmd == MQTT_CMD_LIVE_MONITOR_DATA){
        final monitor = monitorService.lstMonitors[_tabController!.index];
        final payload = jsonData[MQTT_JSON_PAYLOAD];
        final value = payload[MQTT_JSON_WHEEL_DISTANCE];

        if(value is num) _updateWheelDistance(value.toDouble());
        debugPrint('Wheel distance: ${monitor.wheelDistance}');
      }
    });
  }

  // void _setupMqttListener() {
  //   _baseListener = () async {
  //     if (context.read<BaseStationService>().isLoading) {
  //       printMsg("MQTT listener WAIT - baseService busy Loading");
  //       return;
  //     }
  //
  //     if( !_listenerStarted){
  //       final ip = context.read<SettingsService>().fireSettings?.connectedDeviceIp;
  //       if (ip == null || ip.isEmpty) return;
  //
  //       // This will only run once
  //       mqttService.init(ipAdr: ip);
  //
  //       if(!mqttService.isConnected){
  //         final ok = await context.read<SettingsService>().mqttConnect(ip);
  //         if(!mounted) return;
  //
  //         if (ok) {
  //           context.read<BaseStationService>().setConnectedByIp(ip, true);
  //
  //           if (!_listenerStarted && mqttService.isConnected) {
  //             _listenerStarted = true;
  //             mqttService.setupMessageListener();
  //             mqttService.onMessage( MQTT_TOPIC_TO_ANDROID, _onMqttMessage);
  //             printMsg("MQTT Listener Started");
  //           }
  //           else {
  //             printMsg("MQTT listener - already Started");
  //           }
  //         }
  //         else{
  //           return;
  //         }
  //       }
  //     }
  //   };
  //
  //   context.read<BaseStationService>().addListener(_baseListener!);
  // }


  Future<bool> _scanMonitor(String ip)async{
    final settingsService = context.read<SettingsService>();
    final monitorService = context.read<MonitorSettingsService>();

    if(settingsService.isBaseStationConnected == false){
      MyGlobalMessage.show("Connection", "Please connect to a Base Station first", MyMessageType.info);
      return false;
    }

    final payload =  {
      MQTT_JSON_IOT_TYPE: monitorService.lstMonitors[_selectedIndex].monitorType,
    };

    if(mqttService.isConnected){
      mqttService.tx("", MQTT_CMD_DISCOVER, payload, MQTT_TOPIC_FROM_ANDROID);
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
      MQTT_JSON_IOT_TYPE: monitor.monitorType,
      MQTT_JSON_TICKS_PER_M: monitor.ticksPerM,
    };

    if(mqttService.isConnected){
      mqttService.tx(monitor.monitorId, MQTT_CMD_CONNECT_MONITOR, payload ,MQTT_TOPIC_FROM_ANDROID);
    }
    return true;
  }
  Future<bool> _disconnectIot(MonitorSettings monitor)async{
    final settingService = context.read<SettingsService>();
    if(settingService.isBaseStationConnected == false){
      MyGlobalMessage.show("Connection", "Please connect to a Base Station first", MyMessageType.info);
      return false;
    }

    if(mqttService.isConnected){
      mqttService.tx(monitor.monitorId, MQTT_CMD_DISCONNECT_MONITOR, '' ,MQTT_TOPIC_FROM_ANDROID);
    }
    return true;
  }
  void onBotNavBarTap(int index, MonitorSettingsService monService) {
    // Add
    if(index == 0)_addMonitor();

    // Delete
    if(index == 1) {
      if (monService.lstMonitors.isEmpty) return;
      final mon = monService.lstMonitors[ _tabController!.index];

      MyQuestionAlertBox(
          context: context,
          header: "Delete",
          message: "${mon.monitorName}\n${mon.reg}\n\nAre you sure?",
          onPress: (){
            _deleteMonitor(mon);
          }
      );
    }
  }

  Widget _buildBody(MonitorSettings monitor, Key key) {
    try{
      final settingService = context.read<SettingsService>();

      switch(monitor.monitorType){
        case MonTypeVehicle:
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

        case MonTypeWheel:
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

            // Ticker per Meter
            onChangedTicksPerM: (value){
              setState(() {
                monitor.ticksPerM = double.parse(value);
                _saveMonitor(monitor);
              });
            },

            // Scan Monitor ID
            onTapScan: (){
              if(settingService.fireSettings!.connectedDeviceIp.isEmpty){
                MyGlobalMessage.show("Base Station", "No IP address found. \nGoto Base Station page then click 'Request IP Adr'", MyMessageType.info);
              }
              else if(settingService.isBaseStationConnected == false){
                MyGlobalMessage.show("Base Station", "You are not connected to a Base Station.\nGoto Base Station page then click 'Request IP Adr'\nThen click 'Connect'", MyMessageType.info);
                return false;
              }
              else{
                scanBusy = true;
                _scanMonitor(settingService.fireSettings!.connectedDeviceIp);
                MyGlobalSnackBar.show("Scanning for monitors: " + settingService.fireSettings!.connectedDeviceIp);
              }
            },

            // Connect Monitor
            onTapConnect: (){
              if(settingService.fireSettings!.connectedDeviceIp.isEmpty){
                MyGlobalMessage.show("Connection", "No IP Address found. Select Base Station, then connect", MyMessageType.info);
              }
              else{
                if(monitor.monitorId.isEmpty){
                  MyGlobalMessage.show("Monitor Not Found", "No monitor ID found. Please press scan button", MyMessageType.info);
                }else {
                  if(monitor.isConnectedToIot){
                    monitor.isConnectedToIot = false;
                    _disconnectIot(monitor);
                  }else{
                    monitor.isConnectedToIot = false;
                    monitor.isConnectingToIot = true;
                    _hasScrolled = false;
                    _connectIot(settingService.fireSettings!.connectedDeviceIp, monitor);
                    //MyGlobalSnackBar.show("Scanning for monitors: " + settingService.fireSettings!.connectedDeviceIp);
                  }
                }
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
      return MyProgressCircle();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<MonitorSettingsService, SettingsService, BaseStationService>(
      builder: (context, monitorService, settingsService, baseService,_){
        if (monitorService.isLoading || baseService.isLoading || settingsService.isLoading || settingsService.isConnecting) {
          return MyProgressCircle();
        }
        
        if (_tabController != null && monitorService.lstMonitors[_tabController!.index].isConnectedToIot && !_hasScrolled) {
          _hasScrolled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottomOnce(_scrollControllers[_tabController!.index]);
          });
        }

        _updateTabs(monitorService.lstMonitors.length);

        return Scaffold(
          appBar: AppBar(
            backgroundColor: APP_BAR_COLOR,
            foregroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('iOT Monitors' ,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.normal,
                    fontFamily: 'Poppins',
                    color: Colors.white,
                  ),
                ),

                Text(
                  settingsService.isBaseStationConnected != true
                      ? "No Connection"
                      : settingsService.fireSettings == null
                      ? "Loading ..."
                      : settingsService.fireSettings!.connectedDevice,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey,
                  ),
                ),
              ],
            ),
            bottom: monitorService.lstMonitors.isNotEmpty
                ? TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: Colors.blueAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              tabs: monitorService.lstMonitors
                  .map((doc) => Tab(text: doc.monitorName ?? "New Item"))
                  .toList(),
            )
                :null
          ),
          bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedIndex,
              backgroundColor: APP_BAR_COLOR,
              unselectedItemColor: Colors.white,
              selectedItemColor: Colors.white,
              onTap: (index) {
                onBotNavBarTap(index, monitorService);
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
                    color: monitorService.lstMonitors.isEmpty
                        ? Colors.grey
                        : Colors.white,
                  ),
                  label: 'Delete',
                ),
              ]
          ),

          body: monitorService.lstMonitors.isEmpty
            ?  MyCenterMsg('No iOT Monitors')
              :Container(
            color: APP_BACKGROUND_COLOR,
            child: TabBarView(
              controller: _tabController,
              children: List.generate(monitorService.lstMonitors.length, (index){
                //final _docId = monitorService.lstMonitors[index].monDocId;
                final monitor = monitorService.lstMonitors[index];

                // return FutureBuilder<ImageProvider<Object>>(
                //     future: _getMonitorImageProvider(context, _docId, monitor),
                //     builder: (context, imgSnapshot) {
                //
                //       if (imgSnapshot.connectionState == ConnectionState.waiting) {
                //         return MyProgressCircle();
                //       }
                //
                //       if (imgSnapshot.hasError) {
                //         return const Center(child: Icon(Icons.error));
                //       }
                //
                //       final ImageProvider<Object> imageProvider =
                           //imgSnapshot.data ?? const AssetImage(IMAGE_NO_IMAGE);

                      return ListView(
                        controller: _scrollControllers[index],
                        padding: const EdgeInsets.symmetric(
                            vertical: 20, horizontal: 0),
                        children: [

                          // Picture header Container
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12.0, vertical: 8.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                border: Border.all(
                                    color: Colors.transparent, width: 1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  children: [

                                    // iOT Monitor Picture
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.all(4), // border thickness
                                        decoration: BoxDecoration(
                                          color:
                                          Colors.blue, // border color
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
                                            backgroundColor: Colors.white,
                                            child: CircleAvatar(
                                              backgroundImage:  monitor.imageURL != null &&  monitor.imageURL!.isNotEmpty
                                                  ? CachedNetworkImageProvider(monitor.imageURL!) as ImageProvider
                                                  : _getMonitorImage(monitor),
                                              radius: 50,
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

                          SizedBox(height: 5),

                          // Progress Bar
                          _isUploading
                              ? Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 100),
                            child: LinearProgressIndicator(
                              value: _uploadProgress,
                              minHeight: 6,
                              valueColor:
                              const AlwaysStoppedAnimation<Color>(
                                  Colors.blue),
                            ),
                          )
                              : SizedBox(height: 5),

                          // Monitor Type Dropdown
                          Padding(
                              padding:
                              const EdgeInsets.fromLTRB(10, 0, 10, 20),
                              child: MyDropdown(
                                label: 'Monitor Type',
                                value: monitor.monitorType!,
                                lstDropdownValues: settingMonitorTypeList,
                                onChange: (value) {
                                  setState(() {
                                    monitor.monitorType = value;
                                    _saveMonitor(monitor);
                                  });
                                },
                              )
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
