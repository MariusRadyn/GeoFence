import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geofence/MqttService.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BaseStationPage extends StatefulWidget {

  BaseStationPage({
    super.key,
  });

  @override
  State<BaseStationPage> createState() => _BaseStationState();
}

class _BaseStationState extends State<BaseStationPage> with TickerProviderStateMixin{
  bool Debug = false;
  bool isLoading = true;
  TabController? _tabController;
  int _selectedIndex = 0;
  Timer? _timeoutTimer;

  final Map<String, TextEditingController> _controllersName = {};
  final Map<String, TextEditingController> _controllersDesc = {};
  final Map<String, TextEditingController> _controllersBluetooth = {};
  final Map<String, TextEditingController> _controllersIpAddress = {};
  late TextEditingController _controllerName;
  late TextEditingController _controllerDesc;
  late TextEditingController _controllerBluetooth;
  late TextEditingController _controllerIpAddress;

  final FlutterTts _flutterTts = FlutterTts();
  String? bluetoothValue;
  bool isScanning = false;
  bool isSetBTVehicleID = false;
  bool isSetBTMonitor = false;

  List<ScanResult> lstAvailableDevices = [];
  ScanResult? selectedAvailableDevice;
  StreamSubscription<String>? _mqttSubscription;

  BluetoothDevice? pairedDevice;
  BluetoothDevice? selectedDevice;
  List<BluetoothDevice> lstPairedDevices = [
    BluetoothDevice.fromId("00:11:22:33:44:55"),
    BluetoothDevice.fromId("11:11:22:33:44:55"),
  ];

  late String oldBaseName;
  late String oldBaseDesc;
  late String oldBaseIp;

  late FocusNode _focusNodeName;
  late FocusNode _focusNodeDesc;
  late FocusNode _focusNodeIP;

  @override
  void initState() {
    super.initState();
    _getBluetoothDevices();
    _mqttStartListener();
    _initTts();

    _focusNodeName = FocusNode();
    _focusNodeDesc = FocusNode();
    _focusNodeIP = FocusNode();

    // 2. Add listeners to trigger save on focus loss
    _focusNodeName.addListener(() => _handleFocusChange(_focusNodeName, 'name'));
    _focusNodeDesc.addListener(() => _handleFocusChange(_focusNodeDesc, 'desc'));
    _focusNodeIP.addListener(() => _handleFocusChange(_focusNodeIP, 'ip'));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      //context.read<BaseStationService>().load();
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

    _focusNodeName.dispose();
    _focusNodeDesc.dispose();
    _focusNodeIP.dispose();

    _flutterTts.stop();
    _tabController?.dispose();
    _mqttSubscription?.cancel();

    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // Timer
  void _startTimeout(int sec) {
    _timeoutTimer?.cancel();
    if(_tabController == null) return;

    _timeoutTimer = Timer(Duration(seconds: sec), () async {
      if ( !context.read<BaseStationService>().lstBaseStations[_tabController!.index].isConnected) {
        MyGlobalMessage.show("Connection Timeout", "Base Station not found", MyMessageType.warning);
      }
    });
  }

  // MQTT
  void _mqttStartListener() {
    _mqttSubscription = MqttService().messageStream.listen((msg) {
      if(!mounted) return;

      debugPrint('MQTT RX: $msg');

      final jsonData = jsonDecode(msg);
      final cmd = jsonData[mqttJsonCmd];
      final fromId = jsonData[mqttJsonFromDeviceId];

      // Tag Data (from any IOT)
      if (cmd == mqttCmdPing) {
        _timeoutTimer!.cancel();

        // Pass
        var base = context.read<BaseStationService>().lstBaseStations[_tabController!.index];
        //var base = context.read<BaseStationService>().lstBaseStations.firstWhere((b) => b.bluetoothName == fromId);
        if(fromId != base.bluetoothName){
          MyGlobalMessage.show("Warning", "Expected Base Station: ${base.bluetoothName}\nFound: $fromId", MyMessageType.warning);
          return;
        }

        context.read<SettingsService>().updateFireSettingsFields({
          settingConnectedDevice : base.baseName,
          settingConnectedDeviceIp : base.ipAddress,
          settingConnectedDeviceId: base.bluetoothName
        });

        context.read<SettingsService>().setIsBaseConnected(true);

        setState(() {
          base.isConnected = true;
        });
      }
    });
  }
  Future<bool> _mqttConnectBase (BaseStationData base) async {
    await _mqttSubscription?.cancel();
    _mqttSubscription = null;

    bool isReady = await MqttService().restartService(base.ipAddress);

    if(isReady) {
      _mqttStartListener();
      _startTimeout(5);

      MqttService().tx(base.bluetoothName, mqttCmdPing, {} ,mqttTopicFromAndroid);
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
  void _handleFocusChange(FocusNode node, String field) {
    if (!node.hasFocus) {
      var base = context.read<BaseStationService>().lstBaseStations[_tabController!.index];

      setState(() {
        if (field == 'name') base.baseName = _controllerName.text;
        if (field == 'desc') base.baseDesc = _controllerDesc.text;
        if (field == 'ip') base.ipAddress = _controllerIpAddress.text;

        if(oldBaseName == base.baseName && oldBaseDesc == base.baseDesc && oldBaseIp == base.ipAddress) return;
        _saveBase(base);
      });
    }
  }
  Future<void> updateSettingFields(Map<String, dynamic> updates) async {
    SettingsService settingsService = context.read<SettingsService>();
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
    BaseStationService baseService = context.read<BaseStationService>();

    await baseService.save(base);

    if (_tabController != null &&  baseService.lstBaseStations.isNotEmpty) {
      final newIndex = baseService.lstBaseStations.indexWhere((d) => d.docId == base.docId);
      if (newIndex != -1) {
        _tabController!.animateTo(newIndex);
      }
    }
  }
  void _addBase() async {
    if (!mounted) return;

    BaseStationService baseService = context.read<BaseStationService>();
    final docId = await baseService.addNew();
  }
  void _deleteBaseDialog() async {
    int index = _tabController!.index;
    BaseStationService baseService = context.read<BaseStationService>();
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
            backgroundColor: colorAppTitle,
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
    BaseStationService baseService = context.read<BaseStationService>();
    await baseService.delete(base);

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
  }
  Future<void> _getBluetoothDevices() async {
      lstPairedDevices = await getBluetoothDevices();

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
            color: colorAppTitle,
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
                  color: colorAppBackground,
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
      if (service.uuid.str.toLowerCase() == bluetoothServiceUuid) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.uuid.toString().toLowerCase() == bluetoothCharUuid) {
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
        builder: (_ , baseService , settingsService, __){
          if (baseService.isLoading) {
            return MyProgressCircle();
          }
          _updateTabController(baseService.lstBaseStations.length);

          return Scaffold(
            appBar: AppBar(
              backgroundColor: colorAppBar,
              foregroundColor: Colors.white,
              title: MyAppbarTitle('Base Stations'),
            ),
            backgroundColor: colorAppBackground,
            bottomNavigationBar: BottomNavigationBar(
                currentIndex: _selectedIndex,
                backgroundColor: colorAppBar,
                unselectedItemColor: Colors.grey,
                selectedItemColor: Colors.grey,
                onTap: (index) {
                  if (index == 1 && baseService.lstBaseStations.isEmpty) return;
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
                  BottomNavigationBarItem(
                    icon: Icon(Icons.delete_forever),
                    label: 'Delete',
                    backgroundColor: Colors.grey,
                  ),

                ]
            ),

            body: (baseService.lstBaseStations.isEmpty)

            // (Body) No Base Stations
                ? MyCenterMsg('No Base Stations')

            // (Body) Has Base Stations
                : Column(
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.blue,
                  tabs: baseService.lstBaseStations
                      .map((base) => Tab(text: base.baseName))
                      .toList(),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children:  List.generate(baseService.lstBaseStations.length, (index){ //_baseService.lstBaseStations.map((base)  {
                      var currentBase = baseService.lstBaseStations[index];

                      _controllerName = _getControllerName(currentBase);
                      _controllerDesc = _getControllerDesc(currentBase);
                      _controllerIpAddress = _getControllerIpAdr(currentBase);
                      _controllerBluetooth = _getControllerBluetooth(currentBase);

                      oldBaseName = _controllerName.text;
                      oldBaseDesc = _controllerDesc.text;
                      oldBaseIp = _controllerIpAddress.text;

                      if(selectedDevice != null){
                        _controllerBluetooth.text = selectedDevice?.platformName ?? '';
                      }

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
                                  focusNode: _focusNodeName,
                                  isReadOnly: false,
                                  backgroundColor: colorAppBackground,
                                  foregroundColor: Colors.white,
                                  controller: _controllerName,
                                  hintText: "Base Station Name",
                                  labelText: "Name",
                                  onFieldSubmitted: (value){
                                    //setState(() {
                                    //  baseSelected.baseName = value;
                                    //  _saveBase(baseSelected);
                                    //});
                                  },
                                ),
                              ),

                              // Description
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                                child: MyTextFormField(
                                  focusNode: _focusNodeDesc,
                                  backgroundColor: colorAppBackground,
                                  foregroundColor: Colors.white,
                                  controller: _controllerDesc,
                                  hintText: "Enter value here",
                                  labelText: "Description",
                                  onFieldSubmitted: (value){
                                    setState(() {
                                      currentBase.baseDesc = value;
                                      //baseService.setIpAddress(baseSelected, value);
                                      _saveBase(currentBase);
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
                                        backgroundColor: colorAppBackground,
                                        foregroundColor: Colors.white,
                                        controller: _controllerBluetooth,
                                        hintText: "Bluetooth Identification",
                                        labelText: "Identification",

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
                                          _showBluetoothDevicesPopup(currentBase);
                                        }
                                    )
                                  ],
                                ),
                              ),

                              // IP Address
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                                child: MyTextFormField(
                                  focusNode: _focusNodeIP,
                                  isReadOnly: false,
                                  backgroundColor: colorAppBackground,
                                  foregroundColor: Colors.white,
                                  controller: _controllerIpAddress,
                                  hintText: "none",
                                  labelText: "IP Address",

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
                                    final bluetoothName = currentBase.bluetoothName;

                                    if(bluetoothName == ""){
                                      MyGlobalMessage.show("Warning", "No Identification Selected", MyMessageType.warning);
                                      return;
                                    }

                                    final docSnap = await FirebaseFirestore.instance
                                        .collection(collectionClients)
                                        .doc(bluetoothName)
                                        .get();

                                    if(docSnap.data() == null){
                                      MyGlobalSnackBar.show('No IP Address Found for: $bluetoothName');
                                      return;
                                    }

                                    final ipAdr = docSnap.get(settingClientIpAdr);
                                    if(ipAdr == ""){
                                      MyGlobalSnackBar.show('No IP Address Found');
                                      return;
                                    }

                                    print('IP Address: $ipAdr');
                                    MyGlobalSnackBar.show('IP Address: $ipAdr');

                                    setState(() {
                                      currentBase.ipAddress = ipAdr;
                                      _saveBase(currentBase);

                                      settingsService.updateFireSettingsFields({
                                        settingConnectedDevice : currentBase.baseName,
                                        settingConnectedDeviceIp : ipAdr,
                                        settingConnectedDeviceId: currentBase.bluetoothName
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
                                        if(currentBase.ipAddress == ""){
                                          MyGlobalMessage.show("Warning", "No IP Address", MyMessageType.warning);
                                          return;
                                        }

                                        if(currentBase.isConnected == false){
                                          // Connect MQTT
                                          _mqttConnectBase(currentBase);
                                        }
                                        else {
                                          // Disconnect
                                          setState(() {
                                            currentBase.isConnected = false;
                                          });

                                          settingsService.setIsBaseConnected(false);
                                        }
                                      },
                                      child: Row(children: [
                                        Icon(
                                          Icons.connected_tv,
                                          size: 50,
                                          color: currentBase.isConnected == true
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
