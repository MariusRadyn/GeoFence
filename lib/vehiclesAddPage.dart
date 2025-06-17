import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/utils.dart';

class vehiclesAddPage extends StatefulWidget {
  const vehiclesAddPage({super.key});

  @override
  State<vehiclesAddPage> createState() => _vehiclesAddPageState();
}

class _vehiclesAddPageState extends State<vehiclesAddPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  TextEditingController _vehicleNameController = TextEditingController();
  TextEditingController _fuelConsumptionController = TextEditingController();
  TextEditingController _vehicleRegController = TextEditingController();
  String _bluetoothDeviceName = "";
  String _bluetoothMAC = "";

  List<BluetoothDevice> pairedDevices = [];
  BluetoothDevice? selectedDevice;
  bool isLoading = false;
  String? errorMessage;

  void saveVehicle() async {
    if (UserDataService().userdata?.userID != null) {
      await _firestore
          .collection(CollectionUsers)
          .doc(UserDataService().userdata!.userID)
          .collection(CollectionVehicles)
          .add({
        'name': _vehicleNameController.text,
        'fuelConsumption': double.parse(_fuelConsumptionController.text),
        'registrationNumber': _vehicleRegController.text,
        'bluetoothDeviceName': _bluetoothDeviceName,
        'bluetoothMAC': _bluetoothMAC,
      });
    }
  }
  void updateVehicle(String vehicleID) async{
    if (UserDataService().userdata?.userID != null) {
      await _firestore
          .collection(CollectionUsers)
          .doc(UserDataService().userdata!.userID)
          .collection(CollectionVehicles)
          .doc(vehicleID)
          .update({
        'name': _vehicleNameController.text,
        'fuelConsumption': double.parse(_fuelConsumptionController.text),
        'registrationNumber': _fuelConsumptionController.text,
        'bluetoothDeviceName': _bluetoothDeviceName,
        'bluetoothMAC': _bluetoothMAC,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
        foregroundColor: Colors.white,
        title: MyAppbarTitle('Add Vehicles'),
      ),
      body: Container(
        color: APP_BACKGROUND_COLOR,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Vehicle Name
              MyTextFormField(
                backgroundColor: APP_BACKGROUND_COLOR,
                foregroundColor: Colors.white,
                controller: _vehicleNameController,
                hintText: "Enter vehicle name here",
                labelText: "Vehicle Name",
                onFieldSubmitted: (value){
                },
              ),
              SizedBox(height: 5),

              // FuelConsumption
              MyTextFormField(
                backgroundColor: APP_BACKGROUND_COLOR,
                foregroundColor: Colors.white,
                controller: _fuelConsumptionController,
                hintText: "Enter fuel consumption here",
                labelText: "Consumption",
                onFieldSubmitted: (value){
                },
              ),
              SizedBox(height: 5),

              // Reg Number
              MyTextFormField(
                backgroundColor: APP_BACKGROUND_COLOR,
                foregroundColor: Colors.white,
                controller: _vehicleRegController,
                hintText: "Enter registration number here",
                labelText: "Registration Number",
                onFieldSubmitted: (value){
                },
              ),
              SizedBox(height: 20),

              // Bluetooth
              DropdownButtonFormField<BluetoothDevice>(
                value: selectedDevice,
                decoration: InputDecoration(
                  labelText: 'Select Bluetooth Device',
                  labelStyle: TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.bluetooth,color: Colors.blueAccent,),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
                hint: const Text('Choose a paired device', style: TextStyle(color: Colors.grey),),

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
                    selectedDevice = device;
                  });
                  //if (onDeviceSelected != null) {
                  //  onDeviceSelected!(device);
                  //}
                },
                isExpanded: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
