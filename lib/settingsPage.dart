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
  late SettingsService settings;

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
      settings = context.read<SettingsService>();

      setState(() {
          _logPointPerMeterController.text = settings.fireSettings!.logPointPerMeter.toString();
          _rebateValueController.text = settings.fireSettings!.rebateValuePerLiter.toString();
        });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!mounted) return;
    //_settingsService = Provider.of<SettingsService>(context, listen: false);

    //final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

    // You could set up listeners here or perform one-time operations
    // that depend on inherited widgets
    //if (!_didInitListeners) {
    //  SettingsService().addListener(_updateControllerValues);
      //settingsProvider.addListener(_updateControllerValues);
    //  _didInitListeners = true;
    //}

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
     //_settingsService.removeListener(_updateControllerValues);
    }
    super.dispose();
  }

  Future<void> updateSettingFields(Map<String, dynamic> updates) async {
    await SettingsService().updateFireSettingsFields(updates);
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
                 settings.updateFireSettingsFields({
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
                  value: settings.fireSettings!.isVoicePromptOn,
                  label: 'Voice Prompt',
                  subtitle: 'Allow me to give you vocal feedback',
                  onChanged: (bool value)=>
                  {
                    //setState(() {
                    //  _isVoicePromptOn = value;
                    //}),
                    settings.updateFireSettingsFields({SettingIsVoicePromptOn: value}),

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
}
