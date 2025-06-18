import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/utils.dart';
import 'package:permission_handler/permission_handler.dart';

class vehiclesAddPage extends StatefulWidget {
  final DocumentSnapshot? vehicle;
  final String? tabHeader;

  const vehiclesAddPage({
    super.key,
    this.vehicle,
    this.tabHeader,
  });

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

  List<BluetoothDevice> pairedDevices = [
  //   BluetoothDevice.fromId("00:11:22:33:44:55"),
  //   BluetoothDevice.fromId("00:11:22:33:44:65"),
  //   BluetoothDevice.fromId("00:11:22:33:44:75"),
  //   BluetoothDevice.fromId("00:11:22:33:44:85"),
  //   BluetoothDevice.fromId("00:11:22:33:44:95"),
   ];
  BluetoothDevice? selectedDevice;
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  void saveVehicle(DocumentSnapshot? vehicle) async {
    if (UserDataService().userdata?.userID != null) {
      if(vehicle == null){
        // Save
        await _firestore
            .collection(CollectionUsers)
            .doc(UserDataService().userdata!.userID)
            .collection(CollectionVehicles)
            .add({
          SettingVehicleName: _vehicleNameController.text,
          SettingVehicleFuelConsumption: double.parse(_fuelConsumptionController.text),
          SettingVehicleReg: _vehicleRegController.text,
          SettingVehicleBlueDeviceName: _bluetoothDeviceName,
          SettingVehicleBlueMac: _bluetoothMAC,
        });
      }
      else{
        // Update
        await _firestore
            .collection(CollectionUsers)
            .doc(UserDataService().userdata!.userID)
            .collection(CollectionVehicles)
            .doc(vehicle.id)
            .update({
          SettingVehicleName: _vehicleNameController.text,
          SettingVehicleFuelConsumption: double.parse(_fuelConsumptionController.text),
          SettingVehicleReg: _vehicleRegController.text,
          SettingVehicleBlueDeviceName: _bluetoothDeviceName,
          SettingVehicleBlueMac: _bluetoothMAC,
        });
      }
    }
  }
  void loadSettings() {
    _vehicleNameController = TextEditingController(
         text: widget.vehicle != null ? widget.vehicle![SettingVehicleName] : ''
     );

     _fuelConsumptionController = TextEditingController(
         text: widget.vehicle != null ? widget.vehicle![SettingVehicleFuelConsumption].toString() : ''
     );

     _vehicleRegController = TextEditingController(
         text: widget.vehicle != null ? widget.vehicle![SettingVehicleReg] : ''
     );

     _bluetoothDeviceName = widget.vehicle != null ? widget.vehicle![SettingVehicleBlueDeviceName] : "";
     _bluetoothMAC = widget.vehicle != null ? widget.vehicle![SettingVehicleBlueMac] : "";
  }
  void testBluetooth(){
    showDialog(
      context: context,
      builder: (context){
        return AlertDialog(
          icon: Icon(Icons.bluetooth, color: Colors.blue),
          backgroundColor: APP_TILE_COLOR,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: Colors.blue,
              width: 2,
            )
          ),
          title: Text(
            'Test Bluetooth',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16)
          ),
          content: Text( 'Turn off vehicle bluetooth connection. '
            'Wait 5 seconds then turn bluetooth connection on'
            'Wait for the phone to make bluetooth connection. On success, this screen will turn green ',
            softWrap: true,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                style: TextStyle(color: Colors.blue),
              )
            ),
          ],
        );
      },
    );
  }

  Future<void> _initializeBluetooth() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Check if Bluetooth is supported
      if (await FlutterBluePlus.isSupported == false) {
        setState(() {
          errorMessage = "Bluetooth not supported by this device";
          isLoading = false;
        });
        return;
      }

      // Request permissions
      await _requestPermissions();

      // Check if Bluetooth is on
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        setState(() {
          errorMessage = "Please turn on Bluetooth";
          isLoading = false;
        });
        return;
      }

      // Get bonded/paired devices
      await _loadPairedDevices();
    } catch (e) {
      setState(() {
        errorMessage = "Error initializing Bluetooth: $e";
        isLoading = false;
      });
    }
  }
  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();

    // Check if any critical permissions were denied
    if (permissions[Permission.bluetoothConnect] != PermissionStatus.granted ||
        permissions[Permission.bluetoothScan] != PermissionStatus.granted) {
      throw Exception("Bluetooth permissions not granted");
    }
  }
  Future<void> _loadPairedDevices() async {
    try {
      // Get system devices (bonded/paired devices)
      List<BluetoothDevice> systemDevices = await FlutterBluePlus.bondedDevices;

      setState(() {
        pairedDevices = systemDevices;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = "Error loading paired devices: $e";
        isLoading = false;
      });
    }
  }
  Future<void> _refreshDevices() async {
    await _loadPairedDevices();
  }
  String _getDeviceDisplayName(BluetoothDevice device) {
    String name = device.platformName.isNotEmpty
        ? device.platformName
        : device.remoteId.toString();
    return "$name (${device.remoteId})";
  }

  @override
  Widget build(BuildContext context) {

    loadSettings();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
        foregroundColor: Colors.white,
        title: MyAppbarTitle(widget.vehicle == null ? 'Add Vehicles' : 'Edit Vehicle'),
      ),
      body: Container(
        color: APP_BACKGROUND_COLOR,
        child:  Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Vehicle Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8,vertical: 5,),
                child: Card(
                  color: APP_BACKGROUND_COLOR,
                  shadowColor: APP_TILE_COLOR,
                  borderOnForeground: true,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Header
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 15,horizontal: 10),
                        child: Text('Vehicle Information',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),

                      // Vehicle Name
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        child: MyTextFormField(
                          backgroundColor: APP_BACKGROUND_COLOR,
                          foregroundColor: Colors.white,
                          controller: _vehicleNameController,
                          hintText: "Enter value here",
                          labelText: "Vehicle Name",
                          onFieldSubmitted: (value){
                          },
                        ),
                      ),

                      // FuelConsumption
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        child: MyTextFormField(
                          backgroundColor: APP_BACKGROUND_COLOR,
                          foregroundColor: Colors.white,
                          controller: _fuelConsumptionController,
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
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        child: MyTextFormField(
                          backgroundColor: APP_BACKGROUND_COLOR,
                          foregroundColor: Colors.white,
                          controller: _vehicleRegController,
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
              ),

              SizedBox(height: 20),

              // Bluetooth
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Card(
                  color: APP_BACKGROUND_COLOR,
                  shadowColor: APP_TILE_COLOR,
                  borderOnForeground: true,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),

                  ),
                  elevation: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Header
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 15,horizontal: 10),
                        child: Text('Bluetooth',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),

                      // Help text
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: Text('Use bluetooth connection in the vehicle to get vehicle ID. '
                            'Select which bluetooth connection to use in the vehicles. '
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
                            testBluetooth();
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
                                  _bluetoothMAC = device.remoteId.toString();
                                  _bluetoothDeviceName = device.platformName;
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
                  ),
                ),
              ),
            ],
          ),
        ),
      floatingActionButton: FloatingActionButton(
          onPressed: (){
            saveVehicle(widget.vehicle);
          },
        backgroundColor: COLOR_ORANGE,
        child: Icon(
          Icons.save,
          color: Colors.white,
        size: 35,
        ),
      ),
    );
  }
}
