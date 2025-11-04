import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geofence/utils.dart';
import 'package:geofence/vehiclesAddPage.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});

  @override
  _VehiclesPageState createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> with TickerProviderStateMixin{
  bool isLoading = true;
  TabController? _tabController;

  final ImagePicker _imagePicker = ImagePicker();

  final Map<String, Map<String, dynamic>> mapVehicleData = {};
  List<DocumentSnapshot<Map<String, dynamic>>> lstVehicleData = [];

  BluetoothDevice? selectedDevice;
  BluetoothData bluetoothData = BluetoothData();
  List<BluetoothDevice> pairedDevices = [
    //   BluetoothDevice.fromId("00:11:22:33:44:55"),
  ];

  void initState() {
    super.initState();
    _fetchVehicles();
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
      devices.sort((a, b) => (a.platformName ?? '').compareTo(b.platformName ?? ''));

      setState(() {
        pairedDevices = devices;
      });

    } catch (e) {
      print('Error getting paired devices: $e');
    }
  }
  Future<void> _fetchVehicles() async {
    try{
      String? uid = FirebaseAuth.instance.currentUser?.uid;
      if(uid == null) return;

      final snapshot =  await  FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(uid)
          .collection(CollectionVehicles)
          .get();

      setState(() {
        lstVehicleData = snapshot.docs;
        mapVehicleData.clear();

        for (var doc in lstVehicleData) {
          mapVehicleData[doc.id] = doc.data() ?? {};
        }

        if(lstVehicleData.length > 0) {
          if(_tabController != null){
            _tabController?.dispose();
          }
            _tabController = TabController(
            length: lstVehicleData.length,
            vsync: this
          );
        }

        isLoading = false;

      });
    }
    catch (e){
      GlobalSnackBar.show('Image upload failed: $e');
      setState(() {isLoading = false;});
    }
  }
  void _saveCurrentVehicle() async {
    if(_tabController == null) return;

    User? user = FirebaseAuth.instance.currentUser;
    final currentIndex = _tabController!.index;
    final vehicleDoc = lstVehicleData[currentIndex];
    final settingsToSave = mapVehicleData[vehicleDoc.id]!;

    await FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(user?.uid)
        .collection(CollectionVehicles)
        .doc(vehicleDoc.id)
        .update(settingsToSave);

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Vehicle saved')));
  }
  void _addVehicle() async {
    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if(uid == null) return;

    final doc =  await  FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(uid)
        .collection(CollectionVehicles)
        .doc();

    final newVehicle = {
      SettingVehicleName: 'New Vehicle',
      SettingVehicleReg: 'None',
      SettingVehicleFuelConsumption: 0,
      SettingRebateValue:0
    };

    doc.set(newVehicle);
    await _fetchVehicles();

    if (_tabController != null && lstVehicleData.isNotEmpty) {
      final newIndex = lstVehicleData.indexWhere((d) => d.id == doc.id);
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
      final docId = lstVehicleData[index].id;

      // 1️⃣ Delete from Firestore
      await FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(user?.uid)
          .collection(CollectionVehicles)
          .doc(docId)
          .delete();

      setState(() {
        lstVehicleData.removeWhere((d) => d.id == docId);
        mapVehicleData.remove(docId);

        _tabController?.dispose();

        if (lstVehicleData.isNotEmpty) {
          _tabController = TabController(
            length: lstVehicleData.length,
            vsync: this,
          );

          // 5️⃣ Ensure a safe tab is selected
          int newIndex = 0;
          if (_tabController!.index >= lstVehicleData.length) {
            newIndex = lstVehicleData.length - 1;
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
    final vehicle = lstVehicleData[index];

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
                text: "${vehicle[SettingVehicleName]}\n${vehicle[SettingVehicleReg]}\n\nAre you sure?",
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
                    _deleteVehicle();
                    Navigator.pop(context);
                }
              ),
            ],
          );
        }
    );
  }
  void _showVehicleDialog({DocumentSnapshot? vehicle}) {
    TextEditingController nameController = TextEditingController(
        text: vehicle != null ? vehicle[SettingVehicleName] : '');

    TextEditingController fuelController = TextEditingController(
        text: vehicle != null ? vehicle[SettingVehicleFuelConsumption].toString() : '');

    TextEditingController regController = TextEditingController(
        text: vehicle != null ? vehicle[SettingVehicleReg] : '');

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
                    labelStyle: TextStyle(color: Colors.grey)
                ),

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
                    labelStyle: TextStyle(color: Colors.grey)
                ),
                keyboardType: TextInputType.number,
              ),

              // Reg Number
              TextField(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),controller: regController,
                decoration: const InputDecoration(
                    labelText: 'Registration Number',labelStyle:
                    TextStyle(color: Colors.grey)
                ),
              ),
            ],
          ),
          actions: [

            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:const Text(
                'Cancel',
                style: TextStyle(
                  color:  Colors.white70,
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
                        .collection(CollectionVehicles)
                        .add({
                      SettingVehicleName: nameController.text,
                      SettingVehicleFuelConsumption : double.parse(fuelController.text),
                      SettingVehicleReg: regController.text,
                    });
                  } else {
                    // Update existing vehicle
                    await FirebaseFirestore.instance
                        .collection(CollectionUsers)
                        .doc(user.uid)
                        .collection(CollectionVehicles)
                        .doc(vehicle.id)
                        .update({
                      SettingVehicleName: nameController.text,
                      SettingVehicleFuelConsumption : double.parse(fuelController.text),
                      SettingVehicleReg: regController.text,
                    });
                  }
                  Navigator.pop(context);
                }
              },
              child: Text(
                vehicle == null ? 'Add' : 'Update',
                style: const TextStyle(
                  color:  Colors.white70,
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
  Future<void> _pickAndUploadImage({QueryDocumentSnapshot? vehicleDoc, ImageSource? source }) async {
    if(source == null || vehicleDoc == null) return;
    try {

      final XFile? picked = await _imagePicker.pickImage(source: source!, imageQuality: 85);
      if (picked == null) return;

      final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isEmpty) return;

      final String path = 'users/$uid/vehicles/${vehicleDoc.id}.jpg';
      final Reference ref = FirebaseStorage.instance.ref().child(path);
      final File file = File(picked.path);

      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final String downloadUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection(CollectionUsers)
          .doc(uid)
          .collection(CollectionVehicles)
          .doc(vehicleDoc.id)
          .update({SettingVehiclePicture: downloadUrl});
      setState(() {});
    } catch (e) {
      GlobalSnackBar.show('Image upload failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if(lstVehicleData.length == 0) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: APP_BAR_COLOR,
          foregroundColor: Colors.white,
          title: MyAppbarTitle('Vehicles'),
        ),
        bottomNavigationBar: BottomAppBar(
          color: APP_BAR_COLOR,
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
                      onTap: (){
                        _addVehicle();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Center(
          child: Text("No Vehicles Found"),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
        foregroundColor: Colors.white,
        title: MyAppbarTitle('Vehicles'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.blueAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: lstVehicleData
              .map((doc) => Tab(text: doc['name'] ?? doc.id))
              .toList(),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: APP_BAR_COLOR,
        shape: const CircularNotchedRectangle(), // optional if using FAB
        notchMargin: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Save
                Expanded(
                  child: MyIcon(
                    text: "Save",
                    icon: Icons.save,
                    iconColor: Colors.grey,
                    textColor: Colors.white,
                    iconSize: 25,
                    onTap: (){
                      _saveCurrentVehicle();
                    },
                  ),
                ),
                // Add
                Expanded(
                  child: MyIcon(
                    text: "Add",
                    icon: Icons.add,
                    iconColor: Colors.grey,
                    textColor: Colors.white,
                    iconSize: 25,
                    onTap: (){
                      _addVehicle();
                      },
                  ),
                ),
                // Delete
                Expanded(
                  child: MyIcon(
                    text: "Delete",
                    icon: Icons.delete,
                    iconColor: Colors.grey,
                    textColor: Colors.white,
                    iconSize: 25,
                    onTap: (){
                      _deleteVehicleDialog();
                    },
                  ),
                )
              ],
            ),
          ),
        ),
      ),
      body: Container(
        color: APP_BACKGROUND_COLOR,
        child: TabBarView(
          controller: _tabController,
          children: lstVehicleData.map((doc){
            final _docId = doc.id;
            final vehicle = mapVehicleData[_docId]!;
              return ListView(
                 padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 0),
                 children: [

                   // Picture header Container
                   Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      child: Container(
                         decoration: BoxDecoration(
                           color: Colors.transparent,
                           border: Border.all(color: Colors.transparent, width: 1),
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
                                       color: Colors.white, // border color
                                       shape: BoxShape.circle,
                                     ),
                                     child: CircleAvatar(
                                       radius: 80,
                                       backgroundColor: Colors.grey.shade200,
                                       backgroundImage: vehicle[SettingVehiclePicture] != null && vehicle[SettingVehiclePicture].isNotEmpty
                                           ? NetworkImage(vehicle[SettingVehiclePicture])
                                           : null,
                                       child: (vehicle[SettingVehiclePicture] == null || vehicle[SettingVehiclePicture].isEmpty)
                                           ? const Icon(Icons.directions_car, size: 60, color: Colors.grey)
                                           : null,
                                     ),
                                   ),
                                 ),

                                 // Floating circular buttons on top-right
                                 Positioned(
                                   bottom: 8,
                                   right: 8,
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.end,
                                     children: [
                                       MyCircleIconButton(
                                         icon: Icons.photo_camera,
                                         onPressed: (){},
                                         //onPressed: () => _pickAndUploadImage(vehicleDoc: vehicleDoc, source: ImageSource.camera),
                                       ),

                                       const SizedBox(height: 8),

                                       MyCircleIconButton(
                                         icon: Icons.photo_library,
                                         onPressed: (){},
                                         //onPressed: () => _pickAndUploadImage(vehicleDoc: vehicleDoc, source: ImageSource.gallery),
                                       ),

                                       const SizedBox(height: 8),

                                       MyCircleIconButton(
                                         icon: Icons.delete,
                                         onPressed: () => (),
                                       ),
                                     ],
                                   ),
                                 ),
                               ],
                             ),
                            ),
                           ),
                         ),

                   SizedBox(height: 10),

                   // Vehicle Info
                   Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8,vertical: 5,),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          // Header
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                            child: MyTextHeader(
                              text: 'Vehicle Information',
                              color: Colors.white,
                              fontsize: 16,
                            ),
                          ),

                          // Vehicle Name
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
                            child: MyTextFormField(
                              backgroundColor: APP_BACKGROUND_COLOR,
                              foregroundColor: Colors.white,
                              controller: TextEditingController(text: vehicle[SettingVehicleName]),
                              hintText: "Enter value here",
                              labelText: "Vehicle Name",
                              onChanged: (value) {

                                },
                              onFieldSubmitted: (value){
                                setState(() {
                                  final vehicleDoc = lstVehicleData[_tabController!.index];
                                  final docId = vehicleDoc.id;
                                  mapVehicleData[docId]?['name'] = value;
                                });
                              },
                            ),
                          ),

                          // FuelConsumption
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
                            child: MyTextFormField(
                              backgroundColor: APP_BACKGROUND_COLOR,
                              foregroundColor: Colors.white,
                              controller: TextEditingController(text:  vehicle[SettingVehicleFuelConsumption].toString()),
                              hintText: "Enter value here",
                              labelText: "Consumption",
                              suffix: "l/100Km",
                              inputType: TextInputType.number,
                              onFieldSubmitted: (value){
                              },
                            ),
                          ),

                          // Reg Number
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
                            child: MyTextFormField(
                              backgroundColor: APP_BACKGROUND_COLOR,
                              foregroundColor: Colors.white,
                              controller: TextEditingController(text: vehicle[SettingVehicleReg]),
                              hintText: "Enter value here",
                              labelText: "Registration Number",
                              onFieldSubmitted: (value){
                              },
                            ),
                          ),
                          SizedBox(height: 10),
                        ],
                      ),
                     ),

                   // Bluetooth Header
                   Padding(
                    padding: EdgeInsets.symmetric(vertical: 15,horizontal: 5),
                      child: MyTextHeader(
                        text:'Bluetooth',
                        color: Colors.white,
                        fontsize: 16,
                      ),
                    ),

                  // Help text
                    Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Text('Use bluetooth connection in the vehicle to get vehicle ID. '
                        'Select which bluetooth connection to use in the vehicle. '
                        'If the list is empty you need to pair to a bluetooth device first. '
                        'The list is of paired devices, NOT connected devices ',
                      softWrap: true,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white
                      ),
                    ),
                  ),

                    SizedBox(height: 10),

                   // Test Bluetooth
                   Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15.0),
                      child: GestureDetector(
                        child: Text("Test Bluetooth Connection",
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 14,
                          ),
                        ),

                        onTap: (){
                          //testBluetooth();
                        },
                      ),
                    ),

                    SizedBox(height: 10),

                   // Select Bluetooth
                   Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10,vertical: 20),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              // Set items list background color
                                canvasColor: APP_TILE_COLOR
                            ),
                            child: DropdownButtonFormField<BluetoothDevice>(
                              value: selectedDevice,
                              style: TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Select Bluetooth Device',
                                labelStyle: TextStyle(color: Colors.grey),
                                fillColor: APP_BACKGROUND_COLOR,
                                filled: true,
                                prefixIcon: const Icon(
                                  Icons.bluetooth,
                                  color: Colors.blueAccent,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              ),
                              hint: Text(pairedDevices.isEmpty ? 'No paired devices' : 'Choose a paired device',
                                style: TextStyle(color: Colors.grey),
                              ),

                              items: pairedDevices.map((BluetoothDevice device) {
                                return DropdownMenuItem<BluetoothDevice>(
                                  value: device,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.bluetooth,
                                        size: 20,
                                        color: device.isConnected ? Colors.green : Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              device.platformName.isNotEmpty
                                                  ? device.platformName
                                                  : 'Unknown Device',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              device.remoteId.toString(),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (BluetoothDevice? device) {
                                setState(() {
                                  if(device != null){
                                    selectedDevice = device;
                                    bluetoothData.id = device.remoteId.toString();
                                    bluetoothData.name = device.platformName;
                                  }
                                });
                                //if (onDeviceSelected != null) {
                                //  onDeviceSelected!(device);
                                //}
                              },
                              isExpanded: true,
                            ),
                          ),
                   ),
                 ],
              );
            },
         ).toList(),
       ),
      ),
    );
  }
}
