import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
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
import 'package:provider/provider.dart';

import 'MqttService.dart';

class IotMonitorsPage extends StatefulWidget {
  const IotMonitorsPage({super.key});

  @override
  _IotMonitorsPageState createState() => _IotMonitorsPageState();
}

class _IotMonitorsPageState extends State<IotMonitorsPage> with TickerProviderStateMixin {
  late SettingsService settingService;
  late MonitorService monitorService;

  final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>> _docFutures = {};
  int _selectedIndex = 0;
  bool scanBusy = false;

  bool _isLoading = true;
  TabController? _tabController;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  List<BluetoothDevice> lstPairedDevices = [
    BluetoothDevice.fromId("00:11:22:33:44:55"),
    BluetoothDevice.fromId("11:11:22:33:44:55"),
  ];


  void initState() {
    super.initState();

    _getBondedDevices();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      settingService = context.read<SettingsService>();
      monitorService = context.read<MonitorService>();

      _tabController = TabController(
        length: monitorService.lstMonitors.length,
        vsync: this,
      );

      if(settingService.fireSettings!.connectedDeviceIp.isNotEmpty && !settingService.isBaseStationConnected) {
        mqttConnect(settingService.fireSettings!.connectedDeviceIp);

        settingService.update(
          isBaseStationConnected: true
        );
      }
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _getBondedDevices() async {
    try {
      List<BluetoothDevice> devices = await FlutterBluePlus.bondedDevices;

      // Sort by name (optional)
      devices.sort(
          (a, b) => (a.platformName ?? '').compareTo(b.platformName ?? ''));

      setState(() {
        lstPairedDevices = devices;
      });
    } catch (e) {
      print('Error getting paired devices: $e');
    }
  }
  void _saveMonitor(MonitorData monitor) async {
    if (_tabController == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(uid)
        .collection(CollectionMonitors);

      await ref.doc(monitor.docId).set(
        monitor.toMap(),
        SetOptions(merge: true),              // UPDATE
      );

    await monitorService.load();

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
  }
  void _addMonitor() async {
    if (!mounted) return;

    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(uid)
        .collection(CollectionMonitors);

    final monitor = MonitorData(
      monitorName: 'New Monitor',
    );

    final doc = await ref.add(monitor.toMap());
    await monitorService.load();
    if (!mounted) return;

    if (_tabController != null &&  monitorService.lstMonitors.isNotEmpty) {
      final newIndex = monitorService.lstMonitors.indexWhere((d) => d.docId == doc.id);
      if (newIndex != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _tabController!.animateTo(newIndex);
        });
      }
    }
  }
  Future<void> _deleteMonitor(MonitorData monitor) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;

      // 1️⃣ Delete from Firestore
      await FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(user?.uid)
          .collection(CollectionMonitors)
          .doc(monitor.docId)
          .delete();

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
  void _editVehicle(DocumentSnapshot vehicle) {
    _showVehicleDialog(vehicle: vehicle);
  }
  Future<DocumentSnapshot<Map<String, dynamic>>> _getDocFuture(MonitorData monitor) {
    String? uid = FirebaseAuth.instance.currentUser?.uid;

    return _docFutures.putIfAbsent(
        monitor.docId,
            () => FirebaseFirestore.instance
            .collection(CollectionUsers)
            .doc(uid)
            .collection(CollectionMonitors)
            .doc(monitor.docId)
            .get()
    );
  }
  void _deleteMonitorDialog() async {
    int index = _tabController!.index;
    final monitor = monitorService.lstMonitors[index];

    showDialog(
        context: context,
        builder: (context) {
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
            title: const MyText(text: "Delete", color: Colors.white),
            content: MyText(
              text:
                  "${monitor.monitorName}\n${monitor.reg}\n\nAre you sure?",
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
                    color: Colors.white,
                    fontsize: 20,
                  ),
                  onPressed: () async {
                    _deleteMonitor(monitor);
                    Navigator.pop(context);
                  }),
            ],
          );
        });
  }
  void _showVehicleDialog({DocumentSnapshot? vehicle}) {
    TextEditingController nameController = TextEditingController(
        text: vehicle != null ? vehicle[SettingMonName] : '');

    TextEditingController fuelController = TextEditingController(
        text: vehicle != null
            ? vehicle[SettingMonFuelConsumption].toString()
            : '');

    TextEditingController regController = TextEditingController(
        text: vehicle != null ? vehicle[SettingMonReg] : '');

    showDialog(
      context: context,
      builder: (context) {
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
          title: Text(
            vehicle == null ? 'Add Vehicle' : 'Edit Vehicle',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Vehicle Name
              TextField(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'Vehicle Name',
                    labelStyle: TextStyle(color: Colors.grey)),
              ),

              // Fuel Consumption
              TextField(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
                controller: fuelController,
                decoration: const InputDecoration(
                    labelText: 'Fuel Consumption (L/100km)',
                    labelStyle: TextStyle(color: Colors.grey)),
                keyboardType: TextInputType.number,
              ),

              // Reg Number
              TextField(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
                controller: regController,
                decoration: const InputDecoration(
                    labelText: 'Registration Number',
                    labelStyle: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
          actions: [
            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white70,
                  fontFamily: "Poppins",
                  fontSize: 20,
                ),
              ),
            ),

            // Save Button
            TextButton(
              onPressed: () async {
                User? user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  if (vehicle == null) {
                    // Add new vehicle
                    await FirebaseFirestore.instance
                        .collection(CollectionUsers)
                        .doc(user.uid)
                        .collection(CollectionMonitors)
                        .add({
                      SettingMonName: nameController.text,
                      SettingMonFuelConsumption:
                          double.parse(fuelController.text),
                      SettingMonReg: regController.text,
                    });
                  } else {
                    // Update existing vehicle
                    await FirebaseFirestore.instance
                        .collection(CollectionUsers)
                        .doc(user.uid)
                        .collection(CollectionMonitors)
                        .doc(vehicle.id)
                        .update({
                      SettingMonName: nameController.text,
                      SettingMonFuelConsumption:
                          double.parse(fuelController.text),
                      SettingMonReg: regController.text,
                    });
                  }
                  Navigator.pop(context);
                }
              },
              child: Text(
                vehicle == null ? 'Add' : 'Update',
                style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: "Poppins",
                  fontSize: 20,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  Future<void> _pickAndUploadImage({ImageSource? source}) async {
    if (source == null) return;

    try {
      if (_tabController == null) return;
      final monitor = monitorService.lstMonitors[_tabController!.index];

      final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isEmpty) return;

      // Pick File
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) return;

      final String path =
          '$CollectionUsers/$uid/$CollectionMonitors/${monitor.docId}_${DateTime.now().millisecondsSinceEpoch}.png';
      final Reference ref = FirebaseStorage.instance.ref().child(path);
      final File file = File(picked.path);

      // Show loading indicator
      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
      });

      // Delete old image From Firebase
      final oldUrl = monitor.image;
      if (oldUrl != null && oldUrl.toString().isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(oldUrl).delete();
        } catch (e) {
          // Ignore if file doesn't exist
        }
      }

      // Delete old image From Firebase
      final directory = await getApplicationDocumentsDirectory();
      String filename = getFileNameFromUrl(oldUrl);
      final localPath = '${directory.path}/$filename';
      final localFile = File(localPath);
      if (await localFile.exists()) {
        localFile.delete();
      }

      // Upload with progress listener
      final uploadTask =
          ref.putFile(file, SettableMetadata(contentType: 'image/png'));
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        setState(() => _uploadProgress = progress);
      });

      // Wait until upload completes
      await uploadTask;
      final String downloadUrl = await ref.getDownloadURL();

      // Update Firestore with the new image URL
      await FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(uid)
          .collection(CollectionMonitors)
          .doc(monitor.docId)
          .update({SettingMonPicture: downloadUrl});

      await monitorService.load();

      MyGlobalSnackBar.show('Image uploaded successfully!');
    } on FirebaseException catch (e) {
      MyGlobalSnackBar.show('Firebase error: ${e.message}');
    } catch (e) {
      MyGlobalSnackBar.show('Image upload failed: $e');
    } finally {
      // Hide loading indicator
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
      });
    }
  }
  Future<File?> saveNetworkImageLocally( BuildContext context, String vehicleId, String downloadUrl) async {
    try {
      final networkImage = NetworkImage(downloadUrl);

      // Load the image
      final completer = Completer<ui.Image>();
      networkImage.resolve(const ImageConfiguration()).addListener(
        ImageStreamListener((ImageInfo info, bool _) {
          completer.complete(info.image);
        }),
      );
      final ui.Image image = await completer.future;

      // Convert to bytes
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final bytes = byteData.buffer.asUint8List();

      // Save to local file
      final directory = await getApplicationDocumentsDirectory();
      String filename = getFileNameFromUrl(downloadUrl);
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(bytes);

      //MyAlertDialog(context, "Save to Path", '${directory.path}/$vehicleId.png');

      return file;
    } catch (e) {
      debugPrint('Error saving network image: $e');
      return null;
    }
  }
  Future<void> _deleteLocalVehicleImage(String vehicleId) async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/$vehicleId.jpg';
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
  String getFileNameFromUrl(String? downloadUrl) {
    try {
      if (downloadUrl == null) return "";

      final uri = Uri.parse(downloadUrl);
      final segments = uri.pathSegments;

      // The last segment is the file name URL-encoded
      final encodedFileName = segments.last;
      final fileName =
          Uri.decodeFull(encodedFileName); // decode %2F and other chars
      int i = fileName.lastIndexOf('/');
      String s = fileName.substring(i + 1, fileName.length);

      return s;
    } catch (e) {
      debugPrint('Error extracting file name: $e');
      return '';
    }
  }
  Future<ImageProvider<Object>> _getMonitorImageProvider( BuildContext context, String vehicleId, MonitorData? monitor) async {
    if (_isUploading) return AssetImage('assets/noImage.jpg');
    String downloadUrl = monitor?.image ?? '';
    String monType = monitor?.monitorType ?? '';

    final directory = await getApplicationDocumentsDirectory();
    String filename = getFileNameFromUrl(downloadUrl);
    final localPath = '${directory.path}/$filename';
    final localFile = File(localPath);
    try {

      // Try local image first
      if (await localFile.exists()) {
        //MyAlertDialog(context, "Load from Path", localPath);
        return FileImage(localFile);
      }

      // If no local file, download from Firebase
      if (downloadUrl == null || downloadUrl.isEmpty) {

        // Finally - Load Default
        switch (monType) {
          case MonTypeVehicle:
            return AssetImage('assets/red_pickup2.png');

          case MonTypeWheel:
            return AssetImage('assets/distanceWheel.jpg');

          case MonTypeMobileMachineMon:
            return AssetImage('assets/tractor.jpg');

          case MonTypeStationaryMachineMon:
            return AssetImage('assets/generator.jpg');

          default:
            return AssetImage('assets/noImage.jpg');
        }
      }
      // Load from FireStore
      await saveNetworkImageLocally(context, vehicleId, downloadUrl);
      return NetworkImage(downloadUrl);

    } catch (e) {
      debugPrint('Download error: $e');
      return AssetImage('assets/noImage.jpg');
    }
  }
  Future<bool> isWifiConnected(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: Duration(seconds: 2));
      socket.destroy();
      return true;   // Connected!
    } catch (e) {
      return false;  // Cannot reach Pi
    }
  }
  Future<bool> _scanMonitor(String ip)async{
    if(settingService.isBaseStationConnected == false){
      MyAlertDialog(context, "Connection", "Please connect to a Base Station first");
      return false;
    }

    Mqtt_Service.onMessage(MQTT_TOPIC_TO_ANDROID, (msg) {
      print("MQTT RX: $msg");

      Map<String, dynamic> jsonData = jsonDecode(msg);

      // Scan Monitor
      if(scanBusy){
        scanBusy = false;

        if(jsonData[MQTT_JSON_CMD] == MQTT_CMD_SCAN_MONITOR){
          String json = jsonData[MQTT_JSON_PAYLOAD];
          Mqtt_Service.tx(MQTT_CMD_FOUND_MONITOR,json,MQTT_TOPIC_FROM_ANDROID);

          final monitor = monitorService.lstMonitors[_tabController!.index];
          final String monID = jsonData[MQTT_JSON_PAYLOAD];
          final MonitorData? monitorOld = monitorService.lstMonitors.firstWhere(
                (m) => m.monitorId == monID,
            orElse: () => null as MonitorData,
          );

          if(monitorOld != null){
            MyQuestionAlertBox(context: context,
                message: "$monID exists in Monitor: '${monitorOld.monitorName}'.\nDo you want to change the monitor to this one\nThe other monitor will be disconnected",
                onPress: (){
                  setState(() {
                    monitor.monitorId = monID;
                    monitorOld.monitorId = "none";
                    _saveMonitor(monitor);
                    _saveMonitor(monitorOld);
                  });
                }
            );
          }
          else {
            setState(() {
              monitor.monitorId = monID;
              _saveMonitor(monitor);
            });
            MyAlertDialog(context, "Device Found", monID);
          }
        }
      }
    });

    Mqtt_Service.tx(MQTT_CMD_SCAN_MONITOR,'',MQTT_TOPIC_FROM_ANDROID);
    return true;
  }
  Future<bool> mqttConnect(String ip)async{
    if(!await isWifiConnected(ip, 1883)) {
      print("Wifi Fail");
      return false;
    }

    Mqtt_Service.ipAdr = ip;
    await Mqtt_Service.init();

    if(!await Mqtt_Service.connect()) {
      MyGlobalSnackBar.show("MQTT Connection FAILED");
      return false;
    }

    // Callback Listener
    Mqtt_Service.setupMessageListener();
    Mqtt_Service.onMessage(MQTT_TOPIC_TO_ANDROID, (msg) {
      print("MQTT RX: $msg");
    });

    MyGlobalSnackBar.show("Connected: " + ip);
    return true;
  }

  Widget _buildbody(MonitorData monitor) {
    try{

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

            // Scan Monitor
            onTapScan: (){
              if(settingService.fireSettings!.connectedDeviceIp.isEmpty){
                MyAlertDialog(context, "Connection", "No IP Address found. Select Base Station, then connect");
              }
              else{
                scanBusy = true;
                _scanMonitor(settingService.fireSettings!.connectedDeviceIp);
                MyGlobalSnackBar.show("Scanning for monitors: " + settingService.fireSettings!.connectedDeviceIp);
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

    return Consumer2<MonitorService, SettingsService>(
      builder: (context, _monitor, _settings, _){

        if (_monitor.lstMonitors.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: APP_BAR_COLOR,
              foregroundColor: Colors.white,
              title: MyAppbarTitle('Monitors'),
            ),
            bottomNavigationBar: BottomAppBar(
              color: APP_BACKGROUND_COLOR,
              shape: const CircularNotchedRectangle(), // optional if using FAB
              notchMargin: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Center(
                        child: MyIcon(
                          text: "Add",
                          icon: Icons.add,
                          iconColor: Colors.grey,
                          textColor: Colors.white,
                          iconSize: 25,
                          onTap: () {
                            _addMonitor();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            body: Center(
              child: Text("No Monitors Found"),
            ),
          );
        }

        if (_monitor.isLoading) {
          return MyProgressCircle();
        }

        _tabController ??= TabController(length: _monitor.lstMonitors.length, vsync: this);
        if (_tabController!.length != _monitor.lstMonitors.length) {
          _tabController = TabController(length: _monitor.lstMonitors.length, vsync: this);
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: APP_BAR_COLOR,
            foregroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Montors' ,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.normal,
                    fontFamily: 'Poppins',
                    color: Colors.white,
                  ),
                ),

                Text(
                  _settings.isBaseStationConnected != true
                      ? "No Connection"
                      : _settings.fireSettings == null
                      ? "Loading ..."
                      : _settings.fireSettings!.connectedDevice,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey,
                  ),
                ),
                // },
                //),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: Colors.blueAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              tabs: _monitor.lstMonitors
                  .map((doc) => Tab(text: doc.monitorName ?? "New Item"))
                  .toList(),
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedIndex,
              backgroundColor: APP_BAR_COLOR,
              unselectedItemColor: Colors.grey,
              selectedItemColor: Colors.grey,
              onTap: (index) {
                if (index == 1 && _monitor.lstMonitors.isEmpty) return;
                setState(() => _selectedIndex = index);
                if(index == 0)_addMonitor();
                if(index == 1)_deleteMonitorDialog();
              },
              items: [
                // Add Button
                BottomNavigationBarItem(
                    icon: Icon(Icons.add),
                    label: 'Add',
                    backgroundColor: Colors.grey
                ),

                // Delete Button
                if(_monitor.lstMonitors.isNotEmpty)
                  BottomNavigationBarItem(
                    icon: Icon(Icons.delete_forever),
                    label: 'Delete',
                    backgroundColor: Colors.grey,
                  ),
              ]
          ),

          body: Container(
            color: APP_BACKGROUND_COLOR,
            child: TabBarView(
              controller: _tabController,
              children: _monitor.lstMonitors.map((monitor) {
                final _docId = monitor.docId;
                return FutureBuilder<ImageProvider<Object>>(
                    future: _getMonitorImageProvider(context, _docId, monitor),
                    builder: (context, imgSnapshot) {

                      if (imgSnapshot.connectionState == ConnectionState.waiting) {
                        return MyProgressCircle();
                      }

                      if (imgSnapshot.hasError) {
                        return const Center(child: Icon(Icons.error));
                      }

                      final ImageProvider<Object> imageProvider =
                          imgSnapshot.data ?? const AssetImage('assets/noImage.jpg');

                      return ListView(
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
                                    // Vehicle Picture
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.all(4), // border thickness
                                        decoration: BoxDecoration(
                                          color:
                                          Colors.blue, // border color
                                          shape: BoxShape.circle,
                                        ),
                                        child: _isUploading

                                        // Uploading
                                            ? CircleAvatar(
                                          radius: 70,
                                          backgroundColor:
                                          Colors.grey.shade200,
                                          child: Center(
                                            child: Text('Uploading... ${(100 * _uploadProgress).toStringAsFixed(0)}%'),
                                          ),
                                        )

                                        // Load Picture
                                            : CircleAvatar(
                                          radius: 70,
                                          backgroundColor:   Colors.grey.shade200,
                                          backgroundImage:   imageProvider,
                                        ),
                                      ),
                                    ),

                                    // Floating circular buttons on top-right
                                    Positioned(
                                      top: 1,
                                      bottom: 1,
                                      right: 8,
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                        children: [

                                          // Load Image
                                          MyCircleIconButton(
                                            icon: Icons.photo_camera,
                                            onPressed: () =>
                                                _pickAndUploadImage(
                                                    source:
                                                    ImageSource.camera),
                                          ),

                                          const SizedBox(height: 5),

                                          // Take Photo
                                          MyCircleIconButton(
                                            icon: Icons.photo_library,
                                            onPressed: () =>
                                                _pickAndUploadImage(
                                                    source: ImageSource
                                                        .gallery),
                                          ),

                                          const SizedBox(height: 5),

                                          // Delete Pic
                                          MyCircleIconButton(
                                            icon: Icons.delete,
                                            onPressed: () => {
                                              if(monitor.image != '' ){
                                                MyQuestionAlertBox(
                                                    context: context,
                                                    message: 'Delete Current Picture?',
                                                    onPress:(){
                                                      setState(() {
                                                        monitor.image = '';
                                                        _saveMonitor(monitor);
                                                      });
                                                    }
                                                )
                                              }
                                            },
                                          ),
                                        ],
                                      ),
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

                          // Monitor Type
                          Padding(
                              padding:
                              const EdgeInsets.fromLTRB(10, 0, 10, 20),
                              child: MyDropdown(
                                onChange: (value) {
                                  setState(() {
                                    monitor.monitorType = value;
                                    _saveMonitor(monitor);
                                  });
                                },
                                value: monitor.monitorType!,
                              )
                          ),

                          //--------------------------------------------------------------
                          // Monitor Types
                          //--------------------------------------------------------------
                          _buildbody(monitor)

                        ],
                      );
                      // }
                      //);
                    });
              },
              ).toList(),
            ),
          ),
        );

      });

    }
}
