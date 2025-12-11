import 'dart:convert';
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

class SettingsPage extends StatefulWidget {
  final String userId;

  const SettingsPage({
    super.key,
    required this.userId
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with TickerProviderStateMixin{
  bool Debug = false;
  bool isLoading = true;
  TabController? _tabControllerMain;
  TabController? _tabControllerServers;
  late SettingsService _settingsService;

  final TextEditingController _logPointPerMeterController = TextEditingController();
  final TextEditingController _rebateValueController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();
  bool _didInitListeners = false;
  String? bluetoothValue;
  bool isScanning = false;
  bool isSetBTVehicleID = false;
  bool isSetBTMonitor = false;

  List<ScanResult> lstAvailableDevices = [];
  ScanResult? selectedAvailableDevice;

  final Map<String, Map<String, dynamic>> mapServerData = {};
  List<DocumentSnapshot<Map<String, dynamic>>> lstServerData = [];

  BluetoothDevice? pairedDevice;
  BluetoothDevice? selectedDevice;
  List<BluetoothDevice> lstPairedDevices = [
    BluetoothDevice.fromId("00:11:22:33:44:55"),
    BluetoothDevice.fromId("11:11:22:33:44:55"),
  ];


  @override
  void initState() {
    super.initState();

    //_getBondedDevices();
    _initTts();
    _fetchServers();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

        setState(() {
          _logPointPerMeterController.text = SettingsService().settings!.logPointPerMeter.toString();
          _rebateValueController.text = SettingsService().settings!.rebateValuePerLiter.toString();
        });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!mounted) return;
    _settingsService = Provider.of<SettingsService>(context, listen: false);

    //final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

    // You could set up listeners here or perform one-time operations
    // that depend on inherited widgets
    if (!_didInitListeners) {
      SettingsService().addListener(_updateControllerValues);
      //settingsProvider.addListener(_updateControllerValues);
      _didInitListeners = true;
    }

    // You can also immediately update values based on current provider state
    _updateControllerValues();
  }

  @override
  void dispose() {
    _logPointPerMeterController.dispose();
    _flutterTts.stop();
    _tabControllerMain?.dispose();
    _tabControllerServers?.dispose();

    FlutterBluePlus.stopScan();

    if (_didInitListeners) {
     _settingsService.removeListener(_updateControllerValues);
    }
    super.dispose();
  }

  Future<void> updateSettingFields(Map<String, dynamic> updates) async {
    await SettingsService().updateFields(updates);
  }
  void _updateControllerValues() {
    if(!mounted) return;

    //final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    //if (!settingsProvider.isLoading && mounted) {
    //  setState(() {
    //    _logPointPerMeterController.text = (settingsProvider.LogPointPerMeter).toString();
    //  });
    //}
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
  Future<void> _fetchServers() async {
    try{
      String? uid = FirebaseAuth.instance.currentUser?.uid;
      if(uid == null) return;

      final snapshot =  await  FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(uid)
          .collection(CollectionServers)
          .get();

      setState(() {
        lstServerData = snapshot.docs;
        mapServerData.clear();

        for (var doc in lstServerData) {
          mapServerData[doc.id] = doc.data() ?? {};
          print("Server Data: ");
          print(doc.data());
        }
        print("lstServeData Len: ");
        print(lstServerData.length);

        if(lstServerData.length > 0) {
          if(_tabControllerServers != null)  _tabControllerServers?.dispose();

          _tabControllerServers = TabController(
              length: lstServerData.length,
              vsync: this
          );
        }

        isLoading = false;
      });
    }
    catch (e){
      MyGlobalSnackBar.show('Load Server Data Failed: $e');
      setState(() {isLoading = false;});
    }
  }
  void _addServer() async {
    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(uid)
        .collection(CollectionServers)
        .doc();

    final newServer = {
      SettingServerName: 'New Server',
      SettingServerDesc: '',
      SettingServerIpAdr: '192.168.100.1',
      SettingServerBlueMac: '',
      SettingServerBlueDeviceName: '',
    };

    await doc.set(newServer);
    await _fetchServers();

    setState(() { });

    if (_tabControllerServers != null && lstServerData.isNotEmpty) {
      final newIndex = lstServerData.indexWhere((d) => d.id == doc.id);
      if (newIndex != -1) {
        _tabControllerServers!.animateTo(newIndex);
      }
    }
  }
  Future<void> _deleteServer() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      int index = _tabControllerServers!.index;
      final docId = lstServerData[index].id;

      // 1️⃣ Delete from Firestore
      await FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(user?.uid)
          .collection(CollectionServers)
          .doc(docId)
          .delete();

      setState(() {
        lstServerData.removeWhere((d) => d.id == docId);
        mapServerData.remove(docId);

        _tabControllerServers?.dispose();

        if (lstServerData.isNotEmpty) {
          _tabControllerServers = TabController(
            length: lstServerData.length,
            vsync: this,
          );

          // 5️⃣ Ensure a safe tab is selected
          int newIndex = 0;
          if (_tabControllerServers!.index >= lstServerData.length) {
            newIndex = lstServerData.length - 1;
          } else {
            newIndex = _tabControllerServers!.index;
          }
          _tabControllerServers!.animateTo(newIndex);
        } else {
          _tabControllerServers = null;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server Deleted')),
        );
      });
    } catch (e) {
      print('Error deleting Server: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete Server: $e')),
      );
    }
  }
  void _deleteServerDialog() async {
    int index = _tabControllerServers!.index;
    final server = lstServerData[index];

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
              text: "${server[SettingServerName]}\nAre you sure?",
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
                    _deleteServer();
                    Navigator.pop(context);
                  }
              ),
            ],
          );
        }
    );
  }
  void _saveCurrentServer() async {
    if(_tabControllerServers == null) return;

    User? user = FirebaseAuth.instance.currentUser;
    final currentIndex = _tabControllerServers!.index;
    final serverDoc = lstServerData[currentIndex];
    final settingsToSave = mapServerData[serverDoc.id]!;

    await FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(user?.uid)
        .collection(CollectionServers)
        .doc(serverDoc.id)
        .update(settingsToSave);

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
  }


  // Bluetooth
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
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
  Future<void> _getPairedDevices() async {
    try {
      List<BluetoothDevice> devices = await FlutterBluePlus.connectedDevices;
      setState(() {
        lstPairedDevices = devices;

        if(devices.length == 0){
          lstPairedDevices = [
            BluetoothDevice(remoteId: DeviceIdentifier("00:00:00:00:00:00")),
          ];
        }

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
      print('Error getting connected devices: $e');
    }
  }
  void _getAvailableDevices() async {
    lstAvailableDevices.clear();

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        lstAvailableDevices = results;
      });
    });
  }
  Future<void> _startScan() async {
    if (await FlutterBluePlus.isSupported == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth not supported')),
      );
      return;
    }

    setState(() {
      isScanning = true;
      lstAvailableDevices.clear();
    });

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        lstAvailableDevices = results;
      });
    });

    // Start scanning
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));

    setState(() {
      isScanning = false;
    });
  }
  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    setState(() {
      isScanning = false;
    });
  }
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        //pairedDevice = device;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${device.name}')),
      );

      // Discover services after connection
      List<BluetoothService> services = await device.discoverServices();
      print('Discovered ${services.length} services');

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }
  Future<void> _disconnect() async {
    if (pairedDevice != null) {
      await pairedDevice!.disconnect();
      setState(() {
        pairedDevice = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnected')),
      );
    }
  }
  void _showBluetoothDevicesPopup() {
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

                            final vehicleDoc = lstServerData[_tabControllerServers!.index];
                            final docId = vehicleDoc.id;

                            mapServerData[docId]?[SettingServerBlueDeviceName] = selectedDevice?.platformName;
                            mapServerData[docId]?[SettingServerBlueMac] = selectedDevice?.remoteId.toString();
                            _saveCurrentServer();
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

  @override
  Widget build(BuildContext context){
    return Consumer<SettingsService>(
      builder: (context, settings, child) {

        if (settings.isLoading || isLoading) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: APP_BAR_COLOR,
              foregroundColor: Colors.white,
              title: MyAppbarTitle('Settings'),
            ),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: APP_BACKGROUND_COLOR,
            appBar: AppBar(
              backgroundColor: APP_BAR_COLOR,
              foregroundColor: Colors.white,
              title: MyAppbarTitle('Settings'),
              actions: [

                // Save Button
                 IconButton(
                   icon:const Icon(
                     Icons.save,
                     size: 30
                   ),
                   onPressed: () {
                     settings.updateFields({
                       SettingLogPointPerMeter: int.parse(_logPointPerMeterController.text),
                       SettingRebateValue: double.parse(_rebateValueController.text),
                     });
                     MyGlobalSnackBar.show("Saved");
                   },
                ),
              ],
              bottom: TabBar(
                labelColor: Colors.white,
                  indicatorColor: Colors.blue,
                  unselectedLabelColor: Colors.grey,
                  tabs: [
                    Tab(text: "General"),
                    Tab(text: "Servers"),
                    Tab(text: "Monitors",)
                  ]),
            ),
            body: TabBarView(
                children: [

              // General Settings
              ListView(
                children: [
                  const SizedBox(height: 20),

                  // Rebate Value
                  MyTextOption(
                    controller: _rebateValueController,
                    label: 'Rebate Value',
                    description: "Rebate value per kilometer",
                    prefix: 'R',
                  ),

                  const SizedBox(height: 10),

                  // logPointPerMeter
                  MyTextOption(
                    controller: _logPointPerMeterController,
                    label: 'Log Location Interval',
                    description: "Record a map location everytime you move this far in meters",
                    suffix: 'm',
                  ),

                  const SizedBox(height: 10),

                  // isVoicePromptOn
                  MyToggleOption(
                      value: settings.settings!.isVoicePromptOn,
                      label: 'Voice Prompt',
                      subtitle: 'Allow me to give you vocal feedback',
                      onChanged: (bool value)=>
                      {
                        //setState(() {
                        //  _isVoicePromptOn = value;
                        //}),
                        settings.updateFields({SettingIsVoicePromptOn: value}),

                        if(value) {
                          _flutterTts.speak('Voice Prompt enabled'),
                        },
                      }
                  ),
                ],
              ),

              // Stations
              Center(
                child:  Text(
                  "Stations",
                  style:
                TextStyle(color: Colors.white),
                ),
              ),

              // Monitors
              Center(
                  child:  Text(
                    "Map",style:
                    TextStyle(color: Colors.white),
                  ),
              ),
            ])
          ),
        );
      }
    );
  }
}
