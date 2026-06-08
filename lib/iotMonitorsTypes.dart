import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';

// Vehicle
class IotVehicleType extends StatefulWidget {
  final MonitorSettings monitorData;
  final Function(String) onChangedVehicleName;
  final Function(String) onChangedFuelConsumption;
  final Function(String) onChangedReg;
  final Function(BluetoothDevice?) onChangedBluetooth;
  final List<BluetoothDevice> lstPairedDevices;

  IotVehicleType({
    super.key,
    required this.monitorData,
    required this.onChangedVehicleName,
    required this.onChangedFuelConsumption,
    required this.onChangedReg,
    required this.lstPairedDevices,
    required this.onChangedBluetooth
  });

  @override
  State<IotVehicleType> createState() => _IotVehicleTypeState();
}
class _IotVehicleTypeState extends State<IotVehicleType> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        // Vehicle Info
        Padding(
          padding: const EdgeInsets.fromLTRB(8,0,8,5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Vehicle Name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: MyTextFormField(
                  backgroundColor: colorAppBackground,
                  foregroundColor: Colors.white,
                  controller: TextEditingController(text: widget.monitorData.monitorName),
                  hintText: "Enter value here",
                  labelText: "Vehicle Name",
                  onFieldSubmitted: widget.onChangedVehicleName,
               ),
              ),

              // FuelConsumption
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: MyTextFormField(
                  backgroundColor: colorAppBackground,
                  foregroundColor: Colors.white,
                  controller: TextEditingController(text:  widget.monitorData.fuelConsumption.toString()),
                  hintText: "Enter value here",
                  labelText: "Consumption",
                  suffix: "l/100Km",
                  inputType: TextInputType.number,
                  onFieldSubmitted: widget.onChangedFuelConsumption,
                ),
              ),

              // Reg Number
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: MyTextFormField(
                  backgroundColor: colorAppBackground,
                  foregroundColor: Colors.white,
                  controller: TextEditingController(text: widget.monitorData.reg),
                  hintText: "Enter value here",
                  labelText: "Registration Number",
                  onFieldSubmitted: widget.onChangedReg,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 10),

        // Vehicle ID Header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: MyTextHeader(
            text:'Vehicle ID',
            color: Colors.white,
            fontsize: 16,
          ),
        ),

        SizedBox(height: 5),

        // Help text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Text('Use bluetooth connection in the monitor to get monitor ID. '
              'Select which bluetooth connection to use in the monitor. '
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

        SizedBox(height: 5),

        // Select Bluetooth
        Padding( padding: const EdgeInsets.symmetric(horizontal: 10,vertical: 20),
          child: Theme(
            data: Theme.of(context).copyWith(canvasColor: colorAppTitle),
            child: DropdownButtonFormField<BluetoothDevice>(
              value: (() {

                // Find the matching paired device
                return widget.lstPairedDevices.firstWhereOrNull(
                      (d) => d.remoteId.toString() == widget.monitorData.bluetoothMac,
                );
              })(),

              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                isDense: false,
                labelText: 'Select Bluetooth',
                labelStyle: TextStyle(color: Colors.grey),
                fillColor: colorAppBackground,
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
                //contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              hint: Text(widget.lstPairedDevices.isEmpty ? 'No paired devices' : 'Choose a paired device',
                style: TextStyle(color: Colors.grey),
              ),
              items: widget.lstPairedDevices.map((BluetoothDevice device) {
                return DropdownMenuItem<BluetoothDevice>(
                  value: device,
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            device.platformName.isNotEmpty
                                ? device.platformName
                                : 'Unknown Device',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: widget.onChangedBluetooth,
              isExpanded: true,
            ),
          ),
        ),

      ],
    );
  }
}

// Wheel
class IotDistanceWheelType extends StatefulWidget {
  final MonitorSettings monitorData;
  final Function(String) onChangedName;
  final Function(String) onChangedTicksPerM;
  final Function(String) onChangedTicks;
  final Function(String) onChangedMonId;
  final Function() onTapPair;
  final Function() onTapConnect;
  final Function() onTapCalibrate;

  const IotDistanceWheelType({
    super.key,
    required this.monitorData,
    required this.onChangedName,
    required this.onChangedTicksPerM,
    required this.onChangedTicks,
    required this.onChangedMonId,
    required this.onTapPair,
    required this.onTapConnect,
    required this.onTapCalibrate,
  });

  @override
  State<IotDistanceWheelType> createState() => IotDistanceWheelTypeState();
}
class IotDistanceWheelTypeState extends State<IotDistanceWheelType> {
  late SettingsService settingService;
  late final TextEditingController _controllerName;
  late final TextEditingController _controllerId;
  late final TextEditingController _controllerTicksPerM;
  late final TextEditingController _controllerTicks;
  late final TextEditingController _controllerDistance;
  late final TextEditingController _controllerCalDistance;
  late FocusNode _focusNodeName;
  late FocusNode _focusNodeID;
  late FocusNode _focusNodeTicksPerM;
  late FocusNode _focusNodeCalDistance;
  
  Color colorSetupTile = colorTileLight;
  Color colorCalibrateTile = colorTileLight;
  Color colorLiveTile = colorTileLight;
  
  @override
  void initState() {
    super.initState();
     _controllerId = TextEditingController(text: widget.monitorData.monitorId);
     _controllerName = TextEditingController(text: widget.monitorData.monitorName);
     _controllerTicksPerM = TextEditingController(text: widget.monitorData.ticksPerM.toString());
     _controllerTicks = TextEditingController(text: widget.monitorData.ticks.toString());
     _controllerDistance = TextEditingController(text: widget.monitorData.wheelDistance.toString());
     _controllerCalDistance = TextEditingController(text: widget.monitorData.calibrationDistance.toString());

    _focusNodeName = FocusNode();
    _focusNodeID = FocusNode();
    _focusNodeTicksPerM = FocusNode();
    _focusNodeCalDistance = FocusNode();

    // Add listeners to trigger save on focus loss
    _focusNodeName.addListener(() => _handleFocusChange(_focusNodeName, 'name'));
    _focusNodeID.addListener(() => _handleFocusChange(_focusNodeID, 'id'));
    _focusNodeTicksPerM.addListener(() => _handleFocusChange(_focusNodeTicksPerM, 'ticksPerM'));
    _focusNodeCalDistance.addListener(() => _handleFocusChange(_focusNodeCalDistance, 'calDistance'));

    WidgetsBinding.instance.addPostFrameCallback((_) {
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settingService = context.watch<SettingsService>();
  }

  @override
  void didUpdateWidget(covariant IotDistanceWheelType oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _controllerId.dispose();
    _controllerDistance.dispose();
    _controllerName.dispose();
    _controllerTicksPerM.dispose();
    _controllerTicks.dispose();

    _focusNodeName.dispose();
    _focusNodeID.dispose();
    _focusNodeTicksPerM.dispose();
    _focusNodeCalDistance.dispose();

    super.dispose();
  }

  void _handleFocusChange(FocusNode node, String field) {
    if (!node.hasFocus) {
      setState(() {
        if (field == 'name') widget.monitorData.monitorName = _controllerName.text;
        if (field == 'id') widget.monitorData.monitorId = _controllerId.text;
        if (field == 'ticksPerM') widget.monitorData.ticksPerM = double.parse(_controllerTicksPerM.text);
        if (field == 'calDistance') widget.monitorData.calibrationDistance = int.parse(_controllerCalDistance.text);

        context.read<MonitorSettingsService>().save(widget.monitorData);
      });
    }
  }
  
  // Public methods for parent to update text Controllers
  void updateDistance(double value) {
    if (!mounted) return;
    _controllerDistance.text = value.toStringAsFixed(2);
  }
  void updateCalDistance(int value) {
    if (!mounted) return;
    _controllerCalDistance.text = value.toStringAsFixed(2);
  }
  void updateTicks(int value) {
    if (!mounted) return;
    setState(() {
      _controllerTicks.text = value.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
       
        // Setup Tile ----------------------------------
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: colorSetupTile,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.grey,
                width: 0.5
                ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          child: 
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5 ),
              child: Column(
                children: [
                  
                  // Setup
                  MyText(
                    text: "Setup", 
                    fontsize: 18
                  ),

                   SizedBox(height: 15),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MyText(
                          fontsize: 14,
                          color: Colors.grey,
                          text:
                            '1. Only 1 Wheel at a time can be in PAIR mode\n'
                            '2. On Wheel, Press \'Stop\' 6 times\n'
                            '3. Check if Wheel enters PAIR mode\n'
                            '4. In App, press \'Pair\'\n'    
                        ),     
                      ],
                    ),
                  ),
                  
                  // Monitor Info
                  Padding(
                    padding: const EdgeInsets.only(top: 10,left: 8),
                    child: MyTextHeader(text:"Monitor Info"),
                  ),

                  // Wheel Name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: MyTextFormField(
                      focusNode: _focusNodeName,
                      backgroundColor: colorSetupTile,
                      foregroundColor: Colors.white,
                      controller: _controllerName,
                      hintText: "none",
                      labelText: "Wheel Name",
                      onFieldSubmitted: widget.onChangedName,
                    ),
                  ),
              
                  SizedBox(height: 5),
              
                  // ID + Scan Button
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: MyTextFormField(
                            focusNode: _focusNodeID,
                            backgroundColor: colorSetupTile,
                            foregroundColor: Colors.white,
                            controller: _controllerId,
                            hintText: "none",
                            labelText: "Monitor ID",
                            onFieldSubmitted: widget.onChangedMonId,
                          ),
                        ),
                      ),
              
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: InkWell(
                            onTap: widget.onTapPair,
                            child: Column(
                              children: [
                                Icon(
                                  Icons.connected_tv,
                                  size: 30,
                                  color: settingService.isBaseStationConnected
                                      ? Colors.lightBlueAccent
                                      : Colors.grey ,
                                ),
                                SizedBox(width: 10),
                                Text("Pair",
                                  style: TextStyle(
                                      color: settingService.isBaseStationConnected
                                        ? Colors.white
                                        : Colors.grey
                                  ),
                                )
                              ],
                            )
                        ),
                      ),
                    ],
                  ),
              
                  SizedBox(height: 5),
              
                  // Ticks per M
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: MyTextFormField(
                      focusNode: _focusNodeTicksPerM,
                      backgroundColor: colorSetupTile,
                      foregroundColor: Colors.white,
                      controller: _controllerTicksPerM,
                      hintText: "none",
                      labelText: "Ticks per Meter",
                      onFieldSubmitted: widget.onChangedTicksPerM,
                    ),
                  ),

                  SizedBox(height: 20,)
                ],
              ),
            ),  
          ),
        ),
        SizedBox(height: 20),
        
        // Calibrate Tile ------------------------------
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
             decoration: BoxDecoration(
                color: colorCalibrateTile,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.grey,
                  width: 0.5
                  ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // Calibrate Header
                  Center(
                    child: MyText(
                      text: "Calibrate", 
                      fontsize: 18
                    ),
                  ),

                  SizedBox(height: 15),

                  // Instructions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MyText(
                          fontsize: 14,
                          color: Colors.grey,
                          text:
                            '1. Enter the calibration distance\n'
                            '2. Pre measure this exact distance\n'
                            '3. On Wheel, Press \'Start\' 6 times\n'
                            '4. Check if Wheel enters calibration mode\n'
                            '5. On the Wheel, press \'Start\'\n'
                            '6. Move Wheel the exact distance\n'
                            '7. On the Wheel, press \'Stop\'\n'
                            '8. Take wheel back into WIFI range\n'
                            '9. In the App press \'Calibrate\'\n'    
                        ),     
                      ],
                    ),
                  ),
                  
                  // Status
                  // Padding(
                  //   padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  //   child: MyConnectionStatus(
                  //     settings: settingService, 
                  //     size: 14
                  //     ),
                  // ),

                  // Calibration Data Header
                  Padding(
                    padding: const EdgeInsets.only(top: 10,left: 8),
                    child: MyTextHeader(text:"Calibration Data"),
                  ),
                 
                  // Ticks
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: MyTextFormField(
                        backgroundColor: colorCalibrateTile,
                        foregroundColor: Colors.white,
                        controller: _controllerTicks,
                        hintText: "—",
                        labelText: "Ticks",
                        isReadOnly: true,
                        showLine: false,
                      ),
                  ),                 
                
                  // Calibration Distance
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: MyTextFormField(
                            focusNode: _focusNodeCalDistance,
                            backgroundColor: colorCalibrateTile,
                            foregroundColor: Colors.white,
                            controller: _controllerCalDistance,
                            labelText: "Calibration Distance",
                          ),
                        ),
                      ),

                       Padding(
                         padding: const EdgeInsets.symmetric(horizontal: 8.0),
                         child: InkWell(
                          onTap: widget.onTapCalibrate,
                          child: Column(
                            children: [
                              Icon(
                                Icons.online_prediction_sharp,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? widget.monitorData.isConnectedToIot
                                        ? Colors.greenAccent
                                        : Colors.lightBlueAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "Calibrate",
                                style: TextStyle(
                                  color: settingService.isBaseStationConnected
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                                               ),
                       ),
                    
                    ],
                  ),
          
                  SizedBox(height: 10),

                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 20),
       
        // Live Mode Tile ------------------------------
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
             decoration: BoxDecoration(
                color: colorLiveTile,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.grey,
                  width: 0.5
                  ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // Live Monitor
                  Center(
                    child: MyText(
                      text: "Live Monitor", 
                      fontsize: 18
                    ),
                  ),
                  SizedBox(height: 15),

                  // Instructions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MyText(
                          fontsize: 14,
                          color: Colors.grey,
                          text:
                            '1. Press \'Connect\' to start the live monitor\n'
                            '2. Move Wheel\n'
                        ),     
                      ],
                    ),
                  ),
                   
                  // Live Monitor Header
                  Padding(
                    padding: const EdgeInsets.only(top: 10,left: 8),
                    child: MyTextHeader(text:"Live Data"),
                  ),
                 
                  // Live Monitor Distance / Connect Button
                  Row(
                    children: [
                      
                      // Distance
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: MyTextFormField(
                            backgroundColor: colorCalibrateTile,
                            foregroundColor: Colors.white,
                            controller: _controllerDistance,
                            labelText: "Distance",
                          ),
                        ),
                      ),

                      // Connect Button
                      Padding(
                         padding: const EdgeInsets.symmetric(horizontal: 8.0),
                         child: InkWell(
                          onTap: widget.onTapConnect,
                          child: Column(
                            children: [
                              Icon(
                                Icons.online_prediction_sharp,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? widget.monitorData.isConnectedToIot
                                        ? Colors.greenAccent
                                        : Colors.lightBlueAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "Connect",
                                style: TextStyle(
                                  color: settingService.isBaseStationConnected
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                                               ),
                       ),
                    
                    ],
                  ),
          
                  SizedBox(height: 10),

                ],
              ),
            ),
          ),
        )
      ],  
    );
    
  }
}
