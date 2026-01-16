import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'Bluetooth2.dart';
import 'MqttService.dart';
//import 'package:lan_scanner/lan_scanner.dart';
//import 'package:network_info_plus/network_info_plus.dart';
//import 'Bluetooth2.dart';

class BaseStationPage extends StatefulWidget {
  final String userId;

  const BaseStationPage({
    super.key,
    required this.userId
  });

  @override
  State<BaseStationPage> createState() => _BaseStationState();
}

class _BaseStationState extends State<BaseStationPage> with TickerProviderStateMixin{
  late SettingsService settingsService;
  late BaseStationService baseService;

  bool Debug = false;
  bool isLoading = true;
  TabController? _tabController;
  int _selectedIndex = 0;

  final Map<String, TextEditingController> _controllersName = {};
  final Map<String, TextEditingController> _controllersDesc = {};
  final Map<String, TextEditingController> _controllersBluetooth = {};
  final Map<String, TextEditingController> _controllersIpAddress = {};

  final FlutterTts _flutterTts = FlutterTts();
  String? bluetoothValue;
  bool isScanning = false;
  bool isSetBTVehicleID = false;
  bool isSetBTMonitor = false;

  List<ScanResult> lstAvailableDevices = [];
  ScanResult? selectedAvailableDevice;

  BluetoothDevice? pairedDevice;
  BluetoothDevice? selectedDevice;
  List<BluetoothDevice> lstPairedDevices = [
    BluetoothDevice.fromId("00:11:22:33:44:55"),
    BluetoothDevice.fromId("11:11:22:33:44:55"),
  ];

  @override
  void initState() {
    super.initState();

    _getBondedDevices();
    _initTts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      settingsService = context.read<SettingsService>();
      baseService = context.read<BaseStationService>();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    for(final c in _controllersName.values){c.dispose();}
    for(final c in _controllersDesc.values){c.dispose();}
    for(final c in _controllersIpAddress.values){c.dispose();}
    for(final c in _controllersBluetooth.values){c.dispose();}

    _flutterTts.stop();
    _tabController?.dispose();

    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> updateSettingFields(Map<String, dynamic> updates) async {
    await settingsService.updateFireSettingsFields(updates);
  }
  void getVoices() async {
    List<dynamic> voices = await _flutterTts.getVoices;
    print("Available Voices: $voices");
  }
  void _initTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }
  void _saveBase(BaseStationData base) async {
    if (_tabController == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(uid)
        .collection(CollectionServers);

    await ref.doc(base.docId).set(
      base.toMap(),
      SetOptions(merge: true),              // UPDATE
    );

    // await _fetchBaseStations();
    await baseService.load();

    if (_tabController != null &&  baseService.lstBaseStations.isNotEmpty) {
      final newIndex = baseService.lstBaseStations.indexWhere((d) => d.docId == base.docId);
      if (newIndex != -1) {
        _tabController!.animateTo(newIndex);
      }
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
  }
  void _addBase() async {
    if (!mounted) return;

    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(uid)
        .collection(CollectionServers);

    final base = BaseStationData(
      baseName: 'New Base',
    );

    final doc = await ref.add(base.toMap());
    //await _fetchBaseStations();
    await baseService.load();

    if (_tabController != null &&  baseService.lstBaseStations.isNotEmpty) {
      final newIndex = baseService.lstBaseStations.indexWhere((d) => d.docId == doc.id);
      if (newIndex != -1) {
        _tabController!.animateTo(newIndex);
      }
    }
  }
  void _deleteBaseDialog() async {
    int index = _tabController!.index;
    final base = baseService.lstBaseStations[index];

    showDialog(
        context: context,
        builder: (context){
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(
                color: Colors.blue, // Border color
                width: 2, // Border width
              ),
            ),
            backgroundColor: APP_TILE_COLOR,
            shadowColor: Colors.black,
            title: const MyText(
                text: "Delete",
                color: Colors.white
            ),
            content: MyText(
              text: "${base.baseName}\nAre you sure?",
              color: Colors.grey,
              fontsize: 18,
            ),
            actions: [
              TextButton(
                child: const MyText(
                  text: 'No',
                  fontsize: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                  child: const MyText(
                    text: 'Yes',
                    color:  Colors.white,
                    fontsize: 20,
                  ),

                  onPressed: () async {
                    _deleteBase(base);
                    Navigator.pop(context);
                  }
              ),
            ],
          );
        }
    );
  }
  Future<void> _deleteBase(BaseStationData base) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;

      // 1️⃣ Delete from Firestore
      await FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(user?.uid)
          .collection(CollectionServers)
          .doc(base.docId)
          .delete();

      //await _fetchBaseStations();
      await baseService.load();

      setState(() {
        _tabController?.dispose();

        if (baseService.lstBaseStations.isNotEmpty) {
          _tabController = TabController(
            length: baseService.lstBaseStations.length,
            vsync: this,
          );

          // 5️⃣ Ensure a safe tab is selected
          int newIndex = 0;
          if (_tabController!.index >= baseService.lstBaseStations.length) {
            newIndex = baseService.lstBaseStations.length - 1;
          } else {
            newIndex = _tabController!.index;
          }
          _tabController!.animateTo(newIndex);

          _controllersBluetooth.remove(base.docId)?.dispose();
          _controllersDesc.remove(base.docId)?.dispose();
          _controllersName.remove(base.docId)?.dispose();
          _controllersIpAddress.remove(base.docId)?.dispose();

        } else {
          _tabController = null;
        }
      });
    } catch (e) {
      print('Error deleting: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete Failed: $e')),
      );
    }
  }

  Future<void> _getBondedDevices() async {
    try {
      List<BluetoothDevice> devices = await FlutterBluePlus.bondedDevices;

      // Sort by name (optional)
      devices.sort((a, b) => (a.platformName ?? '').compareTo(b.platformName ?? ''));

      setState(() {
        lstPairedDevices = devices;

        // Debug - Set Manual List
        if(Debug){
          lstPairedDevices = [
            BluetoothDevice(
              remoteId: DeviceIdentifier("00:11:22:33:44:55"),
            ),
            BluetoothDevice(
              remoteId: DeviceIdentifier("AA:BB:CC:DD:EE:FF"),
            ),
          ];
        }
      });

    } catch (e) {
      print('Error getting paired devices: $e');
    }
  }
  void _showBluetoothDevicesPopup(BaseStationData base) {
    showDialog(
      context: context,
      barrierDismissible: true, // tap outside to close
      builder: (context) => Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: APP_TILE_COLOR,
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: lstPairedDevices.isEmpty
                ? const Center(
              child: MyText(
                text: 'No Bluetooth devices found',
                color: Colors.white,
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: lstPairedDevices.length,
              itemBuilder: (context, index) {
                final device = lstPairedDevices[index];

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 2,
                  color: APP_BACKGROUND_COLOR,
                  shadowColor: Colors.blue,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth, color: Colors.blue),
                    title: MyText(
                      fontsize: 14,
                        text: device.platformName.isNotEmpty
                        ? device.platformName
                        : 'Unknown Device'),
                    subtitle: MyText(
                      fontsize: 12,
                      color: Colors.grey,
                      text: device.remoteId.str
                    ),
                    trailing: ElevatedButton(
                      child: const Text('Select',
                        style: TextStyle(
                            color: Colors.white
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        backgroundColor: Colors.blue
                      ),
                      onPressed: () {
                        setState(() {
                            selectedDevice = device;

                            base.bluetoothName = selectedDevice?.platformName ?? '';
                            base.bluetoothMac = selectedDevice?.remoteId.toString() ?? '';
                            _saveBase(base);

                          //mapBaseStationsData[docId]?[SettingBaseBlueDeviceName] = selectedDevice?.platformName;
                            //mapBaseStationsData[docId]?[SettingBaseBlueMac] = selectedDevice?.remoteId.toString();
                            //_saveCurrentBaseStation();
                        });

                        print('Selected: ${device.platformName}');
                        Navigator.of(context).pop();
                      },

                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
  Future<void> sendTextToDevice(BluetoothDevice device, String message) async {
    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid.str.toLowerCase() == BT_SERVICE_UUID) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.uuid.toString().toLowerCase() == BT_CHAR_UUID) {
            await characteristic.write(utf8.encode(message), withoutResponse: true);
            print("Message sent: $message");
          }
        }
      }
    }
  }
  void connectBluetoothDevice(String mac) async {
    FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
    print("Connecting... Bluetooth $mac");

    for(BluetoothDevice bt in lstPairedDevices ){
      if(bt.remoteId.str == mac){
        String btNname = bt.platformName;
        await FlutterBluePlus.stopScan();
        await bt.connect();
        print("Connected $btNname");
        await sendTextToDevice(bt, "Hello Raspberry Pi!");
        break;
      }
    }

    print("BT Connection Not Found");
  }

  // Controllers
  void _updateTabController(int length) {
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
  }
  TextEditingController _getControllerName(BaseStationData station) {
    return _controllersName.putIfAbsent(
      station.docId,
          () => TextEditingController(text: station.baseName),
    );
  }
  TextEditingController _getControllerDesc(BaseStationData station) {
    return _controllersDesc.putIfAbsent(
      station.docId,
          () => TextEditingController(text: station.baseDesc),
    );
  }
  TextEditingController _getControllerBluetooth(BaseStationData station) {
    return _controllersBluetooth.putIfAbsent(
      station.docId,
          () => TextEditingController(text: station.bluetoothName),
    );
  }
  TextEditingController _getControllerIpAdr(BaseStationData station) {
    final controller = _controllersIpAddress.putIfAbsent(
      station.docId,
          () => TextEditingController(text: station.ipAddress),
    );

    if (controller.text != station.ipAddress) {
      controller.text = station.ipAddress;
    }

    return controller;
  }

  @override
  Widget build(BuildContext context){

      return Consumer2<BaseStationService, SettingsService>(
        builder: (_ , _baseService , _settingsService, __){
          if (_baseService.isLoading) {
            return MyProgressCircle();
          }

          _updateTabController(_baseService.lstBaseStations.length);


          return Scaffold(
            appBar: AppBar(
              backgroundColor: APP_BAR_COLOR,
              foregroundColor: Colors.white,
              title: MyAppbarTitle('Base Stations'),
            ),
            backgroundColor: APP_BACKGROUND_COLOR,
            bottomNavigationBar: BottomNavigationBar(
                currentIndex: _selectedIndex,
                backgroundColor: APP_BAR_COLOR,
                unselectedItemColor: Colors.grey,
                selectedItemColor: Colors.grey,
                onTap: (index) {
                  if (index == 1 && _baseService.lstBaseStations.isEmpty) return;
                  setState(() => _selectedIndex = index);
                  if(index == 0) _addBase();
                  if(index == 1) _deleteBaseDialog();
                },
                items: [
                  // Add Button
                  BottomNavigationBarItem(
                      icon: Icon(Icons.add),
                      label: 'Add',
                      backgroundColor: Colors.grey
                  ),

                  // Delete Button
                  if(_baseService.lstBaseStations.isNotEmpty)
                    BottomNavigationBarItem(
                      icon: Icon(Icons.delete_forever),
                      label: 'Delete',
                      backgroundColor: Colors.grey,
                    ),
                ]
            ),

            body: (_baseService.lstBaseStations.isEmpty)

            // (Body) No Base Stations
                ? Container(
              color: APP_BACKGROUND_COLOR,
              child: Center(
                child: Text('No Base Stations',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )

            // (Body) Has Base Stations
                : Column(
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.blue,
                  tabs: _baseService.lstBaseStations
                      .map((base) => Tab(text: base.baseName))
                      .toList(),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children:  List.generate(_baseService.lstBaseStations.length, (index){ //_baseService.lstBaseStations.map((base)  {
                      final base = _baseService.lstBaseStations[index];

                      final _controllerName = _getControllerName(base);
                      final _controllerDesc = _getControllerDesc(base);
                      final _controllerIPAddress = _getControllerIpAdr(base);
                      final _controllerBluetooth = _getControllerBluetooth(base);

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(5),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              // Hint Text
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text("GeoFence supports multiple base stations. Each base station "
                                    "has it's own server. In your phone bluetooth settingsService, connect to the server."
                                    "Then select it from this list",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,),
                                  softWrap: true,
                                ),
                              ),

                              // Name
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                                child: MyTextFormField(
                                  isReadOnly: false,
                                  backgroundColor: APP_BACKGROUND_COLOR,
                                  foregroundColor: Colors.white,
                                  controller: _controllerName,
                                  hintText: "Base Station Name",
                                  labelText: "Name",
                                  onChanged: (value) {},
                                  onFieldSubmitted: (value){
                                    setState(() {
                                      base.baseName = value;
                                      _saveBase(base);
                                    });
                                  },
                                ),
                              ),

                              // Description
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                                child: MyTextFormField(
                                  backgroundColor: APP_BACKGROUND_COLOR,
                                  foregroundColor: Colors.white,
                                  controller: _controllerDesc,
                                  hintText: "Enter value here",
                                  labelText: "Description",
                                  onChanged: (value) {

                                  },
                                  onFieldSubmitted: (value){
                                    setState(() {
                                      base.baseDesc = value;
                                      _baseService.setIpAddress(base, value);
                                      _saveBase(base);
                                    });
                                  },
                                ),
                              ),

                              // Bluetooth ID
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: MyTextFormField(
                                        isReadOnly: true,
                                        backgroundColor: APP_BACKGROUND_COLOR,
                                        foregroundColor: Colors.white,
                                        controller: _controllerBluetooth,
                                        hintText: "Bluetooth Identification",
                                        labelText: "Identification",
                                        onChanged: (value) {},
                                        onFieldSubmitted: (value){

                                        },
                                      ),
                                    ),

                                    SizedBox(width: 10),

                                    // Bluetooth Button
                                    OutlinedButton(
                                        child: Icon(Icons.bluetooth,color: Colors.lightBlueAccent),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: Colors.blue, width: 2),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: (){
                                          _showBluetoothDevicesPopup(base);
                                        }
                                    )
                                  ],
                                ),
                              ),

                              // IP Address
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                                child: MyTextFormField(
                                  isReadOnly: false,
                                  backgroundColor: APP_BACKGROUND_COLOR,
                                  foregroundColor: Colors.white,
                                  controller: _controllerIPAddress,
                                  hintText: "none",
                                  labelText: "IP Address",
                                  onChanged: (value) {},
                                  onFieldSubmitted: (value){},
                                ),
                              ),

                              // Pull IP Address from Cloud
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 10),
                                child: InkWell(
                                  child: Text("Request IP Address",
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontSize: 14,
                                    ),
                                  ),

                                  onTap: () async {
                                    final bluetoothName = base.bluetoothName;

                                    if(bluetoothName == ""){
                                      myMessageBox(
                                          context,
                                          "No Identification Selected"
                                      );
                                      return;
                                    }

                                    final docSnap = await FirebaseFirestore.instance
                                        .collection(CollectionClients)
                                        .doc(bluetoothName)
                                        .get();

                                    if(docSnap.data() == null){
                                      MyGlobalSnackBar.show('No IP Address Found for: $bluetoothName');
                                      return;
                                    }

                                    final ipAdr = docSnap.get(SettingClientIpAdr);
                                    if(ipAdr == ""){
                                      MyGlobalSnackBar.show('No IP Address Found');
                                      return;
                                    }

                                    print('IP Address: $ipAdr');
                                    MyGlobalSnackBar.show('IP Address: $ipAdr');

                                    setState(() {
                                      base.ipAddress = ipAdr;
                                      _saveBase(base);

                                      settingsService.updateFireSettingsFields({
                                        SettingConnectedDevice : base.baseName,
                                        SettingConnectedDeviceIp : ipAdr
                                      });
                                    });
                                  },
                                ),
                              ),

                              // Connect Button
                              Row(
                                children: [
                                  InkWell(
                                      onTap: () async {
                                        final ip = base.ipAddress ;

                                        if(ip == ""){
                                          myMessageBox(context, "No IP Address");
                                          return;
                                        }

                                        // Connect MQTT
                                        if(base.isConnected == false){
                                          if(await _settingsService.mqttConnect(ip)) {

                                            // Pass
                                            setState(() {
                                              base.isConnected = true;

                                              settingsService.updateFireSettingsFields({
                                                SettingConnectedDevice : base.baseName,
                                                SettingConnectedDeviceIp : ip
                                              });
                                            });

                                          } else {

                                            // Failed
                                            myMessageBox(context, "Wifi Connection FAILED");
                                            setState(() {
                                              base.isConnected = false;
                                            });
                                            return;
                                          }
                                        }
                                        else {
                                          // Disconnect
                                          _settingsService.mqttDisconnect();

                                          setState(() {
                                            base.isConnected = false;
                                          });
                                        }
                                      },
                                      child: Row(children: [
                                        Icon(
                                          Icons.connected_tv,
                                          size: 50,
                                          color: base.isConnected == true
                                              ? Colors.lightGreenAccent
                                              : Colors.grey ,
                                        ),
                                        SizedBox(width: 10),
                                        Text("Connect",
                                          style: TextStyle(color: Colors.white),
                                        )
                                      ], )
                                    //icon: Icon( Icons.connected_tv),
                                    //color: Colors.lightBlueAccent,
                                    //iconSize: 50,
                                  ),
                                ],
                              )
                            ]
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        });

  }
}


// Future<void> _getPairedDevices() async {
//   try {
//     List<BluetoothDevice> devices = await FlutterBluePlus.connectedDevices;
//     setState(() {
//       lstPairedDevices = devices;
//
//       if(devices.length == 0){
//         lstPairedDevices = [
//           BluetoothDevice(remoteId: DeviceIdentifier("00:00:00:00:00:00")),
//         ];
//       }
//
//       // Debug - Set Manual List
//       if(Debug){
//         lstPairedDevices = [
//           BluetoothDevice(
//             remoteId: DeviceIdentifier("00:11:22:33:44:55"),
//           ),
//           BluetoothDevice(
//             remoteId: DeviceIdentifier("AA:BB:CC:DD:EE:FF"),
//           ),
//         ];
//       }
//     });
//   } catch (e) {
//     print('Error getting connected devices: $e');
//   }
// }
// void _getAvailableDevices() async {
//   lstAvailableDevices.clear();
//
//   FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
//
//   FlutterBluePlus.scanResults.listen((results) {
//     setState(() {
//       lstAvailableDevices = results;
//     });
//   });
// }
// Future<void> _startScan() async {
//   if (await FlutterBluePlus.isSupported == false) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Bluetooth not supported')),
//     );
//     return;
//   }
//
//   setState(() {
//     isScanning = true;
//     lstAvailableDevices.clear();
//   });
//
//   // Listen to scan results
//   FlutterBluePlus.scanResults.listen((results) {
//     setState(() {
//       lstAvailableDevices = results;
//     });
//   });
//
//   // Start scanning
//   await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));
//
//   setState(() {
//     isScanning = false;
//   });
// }
// Future<void> _stopScan() async {
//   await FlutterBluePlus.stopScan();
//   setState(() {
//     isScanning = false;
//   });
// }
// Future<void> _connectToDevice(BluetoothDevice device) async {
//   try {
//     await device.connect();
//     setState(() {
//       //pairedDevice = device;
//     });
//
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Connected to ${device.name}')),
//     );
//
//     // Discover services after connection
//     List<BluetoothService> services = await device.discoverServices();
//     print('Discovered ${services.length} services');
//
//   } catch (e) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Failed to connect: $e')),
//     );
//   }
// }
// Future<void> _disconnect() async {
//   if (pairedDevice != null) {
//     await pairedDevice!.disconnect();
//     setState(() {
//       pairedDevice = null;
//     });
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Disconnected')),
//     );
//   }
// }
// Future<void> _requestPermissions() async {
//   await [
//     Permission.bluetooth,
//     Permission.bluetoothScan,
//     Permission.bluetoothConnect,
//     Permission.location,
//   ].request();
// }
//