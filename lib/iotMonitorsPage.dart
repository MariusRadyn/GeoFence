import 'dart:async';
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

import 'MqttService.dart';

class IotMonitorsPage extends StatefulWidget {
  const IotMonitorsPage({super.key});

  @override
  _IotMonitorsPageState createState() => _IotMonitorsPageState();
}

class _IotMonitorsPageState extends State<IotMonitorsPage>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  TabController? _tabController;
  final ImagePicker _imagePicker = ImagePicker();
  final Map<String, Map<String, dynamic>> mapMonitorData = {};
  List<DocumentSnapshot<Map<String, dynamic>>> lstMonitorData = [];
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  //BluetoothDevice? selectedDevice;
  //BluetoothData bluetoothData = BluetoothData();
  List<BluetoothDevice> lstPairedDevices = [
    BluetoothDevice.fromId("00:11:22:33:44:55"),
    BluetoothDevice.fromId("11:11:22:33:44:55"),
  ];

  void initState() {
    super.initState();
    _fetchMonitors();
    _getBondedDevices();
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
  Future<void> _fetchMonitors() async {
    try {
      String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(uid)
          .collection(CollectionMonitors)
          .get();

      setState(() {
        lstMonitorData = snapshot.docs;
        mapMonitorData.clear();

        for (var doc in lstMonitorData) {
          mapMonitorData[doc.id] = doc.data() ?? {};
        }

        if (lstMonitorData.length > 0) {
          if (_tabController != null) {
            _tabController?.dispose();
          }
          _tabController =
              TabController(length: lstMonitorData.length, vsync: this);
        }

        _isLoading = false;
      });
    } catch (e) {
      MyGlobalSnackBar.show('Image upload failed: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  void _saveCurrentMonitor() async {
    if (_tabController == null) return;

    User? user = FirebaseAuth.instance.currentUser;
    final currentIndex = _tabController!.index;
    final vehicleDoc = lstMonitorData[currentIndex];
    final settingsToSave = mapMonitorData[vehicleDoc.id]!;

    await FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(user?.uid)
        .collection(CollectionMonitors)
        .doc(vehicleDoc.id)
        .update(settingsToSave);

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Vehicle saved')));
  }
  void _addMonitor() async {
    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(uid)
        .collection(CollectionMonitors)
        .doc();

    final newMonitor = {
      SettingMonType: MonTypeVehicle,
      SettingMonName: 'New Item',
      SettingMonReg: 'None',
      SettingMonFuelConsumption: 0,
      SettingRebateValue: 0,
      SettingMonID : 'none',
      SettingMonBlueDeviceName : '',
      SettingMonBlueMac:'',
      SettingMonPicture:'',
      SettingMonTicksPerM: SettingMonDefaultTicksPerM,
    };

    doc.set(newMonitor);
    await _fetchMonitors();

    if (_tabController != null && lstMonitorData.isNotEmpty) {
      final newIndex = lstMonitorData.indexWhere((d) => d.id == doc.id);
      if (newIndex != -1) {
        _tabController!.animateTo(newIndex);
      }
    }
  }
  void _editVehicle(DocumentSnapshot vehicle) {
    _showVehicleDialog(vehicle: vehicle);
  }
  Future<void> _deleteVehicle() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      int index = _tabController!.index;
      final docId = lstMonitorData[index].id;

      // 1️⃣ Delete from Firestore
      await FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(user?.uid)
          .collection(CollectionMonitors)
          .doc(docId)
          .delete();

      setState(() {
        lstMonitorData.removeWhere((d) => d.id == docId);
        mapMonitorData.remove(docId);

        _tabController?.dispose();

        if (lstMonitorData.isNotEmpty) {
          _tabController = TabController(
            length: lstMonitorData.length,
            vsync: this,
          );

          // 5️⃣ Ensure a safe tab is selected
          int newIndex = 0;
          if (_tabController!.index >= lstMonitorData.length) {
            newIndex = lstMonitorData.length - 1;
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
        SnackBar(content: Text('Failed to delete vehicle: $e')),
      );
    }
  }
  void _deleteVehicleDialog() async {
    int index = _tabController!.index;
    final vehicle = lstMonitorData[index];

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
                  "${vehicle[SettingMonName]}\n${vehicle[SettingMonReg]}\n\nAre you sure?",
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
                    _deleteVehicle();
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
  Future<void> _pickAndUploadImageOLD({ImageSource? source}) async {
    if (source == null) return;
    try {
      if (_tabController == null) return;
      final vehicleDoc = lstMonitorData[_tabController!.index];

      final XFile? picked =
          await _imagePicker.pickImage(source: source!, imageQuality: 85);
      if (picked == null) return;

      final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isEmpty) return;

      final String path =
          '$CollectionUsers/$uid/$CollectionMonitors/${vehicleDoc.id}.jpg';
      final Reference ref = FirebaseStorage.instance.ref().child(path);
      final File file = File(picked.path);

      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final String downloadUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(uid)
          .collection(CollectionMonitors)
          .doc(vehicleDoc.id)
          .update({SettingMonPicture: downloadUrl});
      setState(() {});
    } catch (e) {
      MyGlobalSnackBar.show('Image upload failed: $e');
    }
  }
  Future<void> _pickAndUploadImage({ImageSource? source}) async {
    if (source == null) return;

    try {
      if (_tabController == null) return;
      final vehicleDoc = lstMonitorData[_tabController!.index];

      final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isEmpty) return;

      // Pick File
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) return;

      final String path =
          '$CollectionUsers/$uid/$CollectionMonitors/${vehicleDoc.id}_${DateTime.now().millisecondsSinceEpoch}.png';
      final Reference ref = FirebaseStorage.instance.ref().child(path);
      final File file = File(picked.path);

      // Show loading indicator
      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
      });

      // Delete old image From Firebase
      final oldUrl = vehicleDoc[SettingMonPicture];
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
          .doc(vehicleDoc.id)
          .update({SettingMonPicture: downloadUrl});

      await _fetchMonitors();

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
  Future<ImageProvider<Object>?> _getMonitorImageProvider( BuildContext context, String vehicleId, Map<String,dynamic>? monitor) async {
    if (_isUploading) return null;
    String downloadUrl = monitor?[SettingMonPicture] ?? '';
    String montype = monitor?[SettingMonType] ?? '';

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
        switch (montype) {
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
      return null;
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
    if(!await isWifiConnected(ip, 1883))
    {
      print("Wifi Fail");
      return false;
    }

    final mqtt = MqttService(ipAdr : ip);
    await mqtt.init();

    if(!await mqtt.connect()){
      MyGlobalSnackBar.show("MQTT Connection FAILED");
      return false;
    }

    // Callback Listener
    mqtt.setupMessageListener();
    mqtt.onMessage(MQTT_TOPIC_TO_ANDROID, (msg) {
      print("MQTT RX: $msg");
    });

    mqtt.tx("#REQ_MONITOR",MQTT_TOPIC_FROM_ANDROID);
    mqtt.disconnect();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;

    if (_isLoading) {
      return MyProgressCircle();
    }

    if (lstMonitorData.length == 0) {
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

    return StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection(CollectionUsers)
            .doc(FirebaseAuth.instance.currentUser?.uid)
            .collection(CollectionMonitors)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return MyProgressCircle();
          }

          final docs = snapshot.data!.docs;
          lstMonitorData = docs;

          // Recreate controller if length changes
          _tabController ??= TabController(length: docs.length, vsync: this);
          if (_tabController!.length != docs.length) {
            _tabController = TabController(length: docs.length, vsync: this);
          }

          return Scaffold(
            appBar: AppBar(
              backgroundColor: APP_BAR_COLOR,
              foregroundColor: Colors.white,
              title: MyAppbarTitle('Monitors'),
              bottom: TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: Colors.blueAccent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                tabs: lstMonitorData
                    .map((doc) => Tab(text: doc['name'] ?? doc.id))
                    .toList(),
              ),
            ),
            floatingActionButton: lstMonitorData.length == 0
                ? FloatingActionButton(
                    heroTag: "addMonitor",
                    onPressed: _addMonitor,
                    backgroundColor: COLOR_ORANGE,
                    mini: true,
                    child: Icon(
                      Icons.add,
                      color: Colors.white,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Delete Monitor
                      FloatingActionButton(
                        heroTag: "deleteMonitor",
                        onPressed: _deleteVehicleDialog,
                        backgroundColor: COLOR_ORANGE,
                        mini: true,
                        isExtended: false,
                        child: Icon(
                          Icons.delete_forever,
                          color: Colors.white,
                        ),
                      ),

                      SizedBox(height: 10),

                      // Add Monitor
                      FloatingActionButton(
                        heroTag: "addMonitor2",
                        onPressed: _addMonitor,
                        backgroundColor: COLOR_ORANGE,
                        mini: true,
                        child: Icon(
                          Icons.add,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
            body: Container(
              color: APP_BACKGROUND_COLOR,
              child: TabBarView(
                controller: _tabController,
                children: lstMonitorData.map(
                  (doc) {
                    final _docId = doc.id;
                    final monitor = mapMonitorData[_docId]!;

                    return FutureBuilder(
                        future: _getMonitorImageProvider(
                            context, _docId, monitor),
                        builder: (context, imgSnapshot) {
                          if (imgSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return MyProgressCircle();
                          }

                          ImageProvider<Object> imageProvider =
                              imgSnapshot.data ??
                                  const AssetImage('assets/noImage.jpg');

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
                                                  if(monitor[SettingMonPicture] != null && monitor[SettingMonPicture] != '' ){
                                                    MyQuestionAlertBox(
                                                        context: context,
                                                        message: 'Delete Current Picture?',
                                                      onPress:(){
                                                          setState(() {
                                                            monitor[SettingMonPicture] = '';
                                                            _saveCurrentMonitor();
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
                                      final vehicleDoc =
                                          lstMonitorData[_tabController!.index];
                                      final docId = vehicleDoc.id;

                                      setState(() {
                                        mapMonitorData[docId]?[SettingMonType] = value;
                                        _saveCurrentMonitor();
                                      });
                                    },
                                    value: SettingMonitorTypeList.contains(
                                            monitor[SettingMonType])
                                        ? monitor[SettingMonType]
                                        : null,
                                  )
                              ),

                              //--------------------------------------------------------------
                              // Monitor Types
                              //--------------------------------------------------------------
                              _buildbody(monitor, doc)

                            ],
                          );
                        });
                  },
                ).toList(),
              ),
            ),
          );
        });
  }

  Widget _buildbody(Map<String, dynamic> monitor, DocumentSnapshot<Map<String, dynamic>> doc){
    try{
      switch(monitor[SettingMonType]){
        case MonTypeVehicle:
          return IotVehicleType(
            mapMonitorData: mapMonitorData,
            lstPairedDevices: lstPairedDevices,
            doc: doc,

            // Vehicle Name
            monitorName: monitor[SettingMonName],
            onChangedVehicleName: (value) {
              setState(() {
                final vehicleDoc =
                lstMonitorData[_tabController!.index];
                final docId = vehicleDoc.id;

                setState(() {
                  mapMonitorData[docId]
                  ?[SettingMonName] = value;
                  _saveCurrentMonitor();
                });
              });
            },

            // Fuel Consumption
            monitorFuelConsumption: monitor[SettingMonFuelConsumption].toString(),
            onChangedFuelConsumption: (value) {
              final vehicleDoc =
              lstMonitorData[_tabController!.index];
              final docId = vehicleDoc.id;

              setState(() {
                mapMonitorData[docId]
                ?[SettingMonFuelConsumption] =  value;
                _saveCurrentMonitor();
              });
            },

            // Registration
            monitorReg: monitor[SettingMonReg],
            onChangedReg: (value) {
              final vehicleDoc =
              lstMonitorData[_tabController!.index];
              final docId = vehicleDoc.id;

              setState(() {
                mapMonitorData[docId]?[SettingMonReg] =
                    value;
                _saveCurrentMonitor();
              });
            },

            // Bluetooth
            onChangedBluetooth: (BluetoothDevice? device) {
              setState(() {
                final vehicleDoc =
                lstMonitorData[_tabController!.index];
                final docId = vehicleDoc.id;

                setState(() {
                  mapMonitorData[docId]
                  ?[SettingMonBlueDeviceName] =
                      device?.platformName;
                  mapMonitorData[docId]
                  ?[SettingMonBlueMac] =
                      device?.remoteId.toString();
                  _saveCurrentMonitor();
                });
              });
            },
          );

        case MonTypeWheel:
          return IotDistanceWheelType(

            // Name
            name: monitor[SettingMonName],
            onChangedName: (value){
              setState(() {
                final vehicleDoc = lstMonitorData[_tabController!.index];
                final docId = vehicleDoc.id;

                setState(() {
                  mapMonitorData[docId]
                  ?[SettingMonName] = value;
                  _saveCurrentMonitor();
                });
              });
            },

            // Monitor ID
            monId: monitor[SettingMonID],
            onChangedMonId: (value){
              setState(() {
                final vehicleDoc = lstMonitorData[_tabController!.index];
                final docId = vehicleDoc.id;

                setState(() {
                  mapMonitorData[docId]
                  ?[SettingMonID] = value;
                  _saveCurrentMonitor();
                });
              });
            },

            // Ticker per Meter
            ticksPerM: monitor[SettingMonTicksPerM].toString(),
            onChangedTicksPerM: (value){
              setState(() {
                final vehicleDoc = lstMonitorData[_tabController!.index];
                final docId = vehicleDoc.id;

                setState(() {
                  mapMonitorData[docId]
                  ?[SettingMonTicksPerM] = value;
                  _saveCurrentMonitor();
                });
              });
            },

            // Scan Monitor
            onTapScan: (){
              _scanMonitor(ip)
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
}
