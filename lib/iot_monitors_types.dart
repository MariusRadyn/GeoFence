//import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/app_flavor.dart';
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

  const IotVehicleType({
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
  late final TextEditingController _controllerName;
  late final TextEditingController _controllerFuel;
  late final TextEditingController _controllerReg;
  late final FocusNode _focusNodeName;
  late final FocusNode _focusNodeFuel;
  late final FocusNode _focusNodeReg;

  @override
  void initState() {
    super.initState();
    _controllerName =
        TextEditingController(text: widget.monitorData.monitorName);
    _controllerFuel = TextEditingController(
        text: widget.monitorData.fuelConsumption.toString());
    _controllerReg = TextEditingController(text: widget.monitorData.reg);

    _focusNodeName = FocusNode();
    _focusNodeFuel = FocusNode();
    _focusNodeReg = FocusNode();

    _focusNodeName
        .addListener(() => _handleFocusChange(_focusNodeName, 'name'));
    _focusNodeFuel
        .addListener(() => _handleFocusChange(_focusNodeFuel, 'fuel'));
    _focusNodeReg
        .addListener(() => _handleFocusChange(_focusNodeReg, 'reg'));
  }

  @override
  void didUpdateWidget(covariant IotVehicleType oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_focusNodeName.hasFocus &&
        _controllerName.text != widget.monitorData.monitorName) {
      _controllerName.text = widget.monitorData.monitorName;
    }
    if (!_focusNodeFuel.hasFocus &&
        _controllerFuel.text !=
            widget.monitorData.fuelConsumption.toString()) {
      _controllerFuel.text = widget.monitorData.fuelConsumption.toString();
    }
    if (!_focusNodeReg.hasFocus &&
        _controllerReg.text != widget.monitorData.reg) {
      _controllerReg.text = widget.monitorData.reg;
    }
  }

  @override
  void dispose() {
    _controllerName.dispose();
    _controllerFuel.dispose();
    _controllerReg.dispose();
    _focusNodeName.dispose();
    _focusNodeFuel.dispose();
    _focusNodeReg.dispose();
    super.dispose();
  }

  void _handleFocusChange(FocusNode node, String field) {
    if (node.hasFocus) return;

    switch (field) {
      case 'name':
        widget.onChangedVehicleName(_controllerName.text);
        break;
      case 'fuel':
        widget.onChangedFuelConsumption(_controllerFuel.text);
        break;
      case 'reg':
        widget.onChangedReg(_controllerReg.text);
        break;
    }
  }

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
                  focusNode: _focusNodeName,
                  backgroundColor: colorAppBackground,
                  foregroundColor: Colors.white,
                  controller: _controllerName,
                  hintText: "Enter value here",
                  labelText: "Vehicle Name",
                  onFieldSubmitted: widget.onChangedVehicleName,
               ),
              ),

              // FuelConsumption
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: MyTextFormField(
                  focusNode: _focusNodeFuel,
                  backgroundColor: colorAppBackground,
                  foregroundColor: Colors.white,
                  controller: _controllerFuel,
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
                  focusNode: _focusNodeReg,
                  backgroundColor: colorAppBackground,
                  foregroundColor: Colors.white,
                  controller: _controllerReg,
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

        if (AppConfig.enableBluetooth) ...[
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
                initialValue: (() {

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

      ],
    );
  }
}

// Wheel
class IotDistanceWheelType extends StatefulWidget {
  final MonitorSettings monitorData;
  final Function(String) onChangedName;
  final Function(String) onChangedTicksPerM;
  final Function(String) onChangedMonId;
  final Function() onTapPair;
  final Function() onTapSendWifi;
  final Function() onTapFind;
  final Function() onTapSyncTicksPerM;
  final Function() onTapConnect;
  final Function() onTapCalibrate;

  const IotDistanceWheelType({
    super.key,
    required this.monitorData,
    required this.onChangedName,
    required this.onChangedTicksPerM,
    required this.onChangedMonId,
    required this.onTapPair,
    required this.onTapSendWifi,
    required this.onTapFind,
    required this.onTapSyncTicksPerM,
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
  late final TextEditingController _controllerDistance;
  late final TextEditingController _controllerWheelTicks;
  late final TextEditingController _controllerCalDistance;
  late FocusNode _focusNodeName;
  late FocusNode _focusNodeID;
  late FocusNode _focusNodeTicksPerM;
  late FocusNode _focusNodeCalDistance;
  bool _pairButtonPressed = false;
  bool _wifiButtonPressed = false;
  bool _findButtonPressed = false;
  bool _syncButtonPressed = false;
  bool _calibrateButtonPressed = false;
  bool _connectButtonPressed = false;
  
  Color colorSetupTile = colorAppBackground;
  Color colorCalibrateTile = colorAppBackground;
  Color colorLiveTile = colorAppBackground;
  
  @override
  void initState() {
    super.initState();
     _controllerId = TextEditingController(text: widget.monitorData.monitorId);
     _controllerName = TextEditingController(text: widget.monitorData.monitorName);
     _controllerTicksPerM = TextEditingController(text: widget.monitorData.ticksPerM.toString());
     _controllerDistance = TextEditingController(text: widget.monitorData.wheelDistance.toString());
     _controllerWheelTicks = TextEditingController(text: widget.monitorData.wheelTicks.toString());
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

  Future<void> _animateTap(
    FutureOr<void> Function() action,
    void Function(bool) setPressed,
  ) async {
    setState(() => setPressed(true));
    try {
      await action();
    } finally {
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) setState(() => setPressed(false));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settingService = context.watch<SettingsService>();
    // Rebuild Connect/Disconnect label when live IoT connection changes.
    context.watch<MonitorSettingsService>();
  }

  @override
  void didUpdateWidget(covariant IotDistanceWheelType oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Keep text fields in sync when parent updates monitor data (e.g. pair/swap).
    if (_controllerId.text != widget.monitorData.monitorId) {
      _controllerId.text = widget.monitorData.monitorId;
    }
    if (!_focusNodeName.hasFocus &&
        _controllerName.text != widget.monitorData.monitorName) {
      _controllerName.text = widget.monitorData.monitorName;
    }
    if (!_focusNodeTicksPerM.hasFocus &&
        _controllerTicksPerM.text != widget.monitorData.ticksPerM.toString()) {
      _controllerTicksPerM.text = widget.monitorData.ticksPerM.toString();
    }
    if (!_focusNodeCalDistance.hasFocus &&
        _controllerCalDistance.text !=
            widget.monitorData.calibrationDistance.toString()) {
      _controllerCalDistance.text =
          widget.monitorData.calibrationDistance.toString();
    }
    if (_controllerDistance.text !=
        widget.monitorData.wheelDistance.toString()) {
      _controllerDistance.text = widget.monitorData.wheelDistance.toString();
    }
    if (_controllerWheelTicks.text !=
        widget.monitorData.wheelTicks.toString()) {
      _controllerWheelTicks.text = widget.monitorData.wheelTicks.toString();
    }
  }

  @override
  void dispose() {
    _controllerId.dispose();
    _controllerDistance.dispose();
    _controllerWheelTicks.dispose();
    _controllerName.dispose();
    _controllerTicksPerM.dispose();

    _focusNodeName.dispose();
    _focusNodeID.dispose();
    _focusNodeTicksPerM.dispose();
    _focusNodeCalDistance.dispose();

    super.dispose();
  }

  void _handleFocusChange(FocusNode node, String field) {
    if (!node.hasFocus) {
      if (field == 'ticksPerM') {
        widget.onChangedTicksPerM(_controllerTicksPerM.text);
        return;
      }

      setState(() {
        if (field == 'name') widget.monitorData.monitorName = _controllerName.text;
        if (field == 'id') widget.monitorData.monitorId = _controllerId.text;
        if (field == 'calDistance') widget.monitorData.calibrationDistance = int.parse(_controllerCalDistance.text);

        context.read<MonitorSettingsService>().save(widget.monitorData);
      });
    }
  }
  
  // Public methods for parent to update text Controllers
  void updateDistance(double value) {
    if (!mounted) return;
    setState(() {
      widget.monitorData.wheelDistance = value;
      _controllerDistance.text = value.toStringAsFixed(2);
    });
  }

  void updateTicks(int value) {
    if (!mounted) return;
    setState(() {
      widget.monitorData.wheelTicks = value;
      _controllerWheelTicks.text = value.toString();
    });
  }

  void updateLiveConnected(bool connected) {
    if (!mounted) return;
    setState(() {
      widget.monitorData.isConnectedToIot = connected;
      widget.monitorData.isConnectingToIot = false;
    });
  }
  void updateCalDistance(int value) {
    if (!mounted) return;
    _controllerCalDistance.text = value.toStringAsFixed(2);
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // Setup
                  Center(
                    child: MyText(
                      text: "Setup", 
                      fontsize: 18
                    ),
                  ),

                  SizedBox(height: 15),

                  // Instructions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: MyText(
                        fontsize: 14,
                        color: Colors.grey,
                        text:
                          '1. Only 1 wheel at a time can be in \'PAIR\' mode\n'
                          '2. On the wheel, press \'STOP\' 6 times\n'
                          '3. Allow wheel to connect to Base\n'
                          '4. Wait until LCD says \'Click PAIR in App\'\n'
                          '5. Click \'PAIR\'\n'
                          'WiFi: force base to push WiFi/MQTT over Bluetooth\n',
                      ),
                     ),
                  ),
                  
                  // Monitor Info
                  Padding(
                    padding: const EdgeInsets.only(top: 10,left: 8, right: 8),
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
                        padding: const EdgeInsets.only(right: 8),
                        child: animatedActionButton(
                          pressed: _pairButtonPressed,
                          onTap: () => _animateTap(
                            widget.onTapPair,
                            (v) => _pairButtonPressed = v,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.connected_tv,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? Colors.lightBlueAccent
                                    : Colors.grey ,
                              ),
                              const SizedBox(height: 10),
                              Text("Pair",
                                style: TextStyle(
                                    color: settingService.isBaseStationConnected
                                      ? Colors.white
                                      : Colors.grey
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: animatedActionButton(
                          pressed: _wifiButtonPressed,
                          onTap: () => _animateTap(
                            () {
                              final typed = _controllerId.text.trim();
                              if (typed.isNotEmpty) {
                                widget.monitorData.monitorId = typed;
                              }
                              return widget.onTapSendWifi();
                            },
                            (v) => _wifiButtonPressed = v,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.wifi,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? Colors.lightBlueAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Cred",
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
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: animatedActionButton(
                          pressed: _findButtonPressed,
                          onTap: () => _animateTap(
                            () {
                              // Flush ID text into the model before Find.
                              final typed = _controllerId.text.trim();
                              if (typed.isNotEmpty) {
                                widget.monitorData.monitorId = typed;
                              }
                              return widget.onTapFind();
                            },
                            (v) => _findButtonPressed = v,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.sensors,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? Colors.lightBlueAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Find",
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
              
                  SizedBox(height: 5),
              
                  // Ticks per M + Sync
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: MyTextFormField(
                            focusNode: _focusNodeTicksPerM,
                            backgroundColor: colorSetupTile,
                            foregroundColor: Colors.white,
                            controller: _controllerTicksPerM,
                            hintText: "none",
                            labelText: "Ticks per Meter",
                            onFieldSubmitted: widget.onChangedTicksPerM,
                            inputType: TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: animatedActionButton(
                          pressed: _syncButtonPressed,
                          onTap: () => _animateTap(
                            () async {
                              final value = _controllerTicksPerM.text.trim();
                              if (value.isNotEmpty) {
                                await widget.onChangedTicksPerM(value);
                              }
                              return widget.onTapSyncTicksPerM();
                            },
                            (v) => _syncButtonPressed = v,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.sync,
                                size: 30,
                                color: settingService.isBaseStationConnected
                                    ? Colors.lightBlueAccent
                                    : Colors.grey,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Sync",
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
                            '3. On the wheel, press \'START\' 5 times\n'
                            '4. Check LCD if the wheel enters \'CALIBRATION\' mode\n'
                            '5. On the wheel, press \'START\'\n'
                            '6. Move the wheel the exact distance\n'
                            '7. On the wheel, press \'STOP\'\n'
                            '8. Take wheel back into WIFI range\n'
                            '9. In the App press \'CALIBRATE\'\n'    
                        ),     
                      ],
                    ),
                  ),

                  // Calibration Data Header
                  Padding(
                    padding: const EdgeInsets.only(top: 10,left: 8, right: 8),
                    child: MyTextHeader(text:"Calibration Data"),
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
                         child: animatedActionButton(
                          pressed: _calibrateButtonPressed,
                          onTap: () => _animateTap(
                            () async {
                              FocusScope.of(context).unfocus();
                              final text = _controllerCalDistance.text.trim();
                              final parsed = int.tryParse(text) ??
                                  double.tryParse(text)?.round();
                              if (parsed != null && parsed > 0) {
                                widget.monitorData.calibrationDistance = parsed;
                                await context
                                    .read<MonitorSettingsService>()
                                    .save(widget.monitorData);
                              }
                              await widget.onTapCalibrate();
                            },
                            (v) => _calibrateButtonPressed = v,
                          ),
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
                              const SizedBox(height: 10),
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
                            '1. Press Connect or Disconnect for live monitor\n'
                            '2. Move the wheel\n'
                        ),     
                      ],
                    ),
                  ),
                   
                  // Live Monitor Header
                  Padding(
                    padding: const EdgeInsets.only(top: 10,left: 8, right: 8),
                    child: MyTextHeader(text:"Live Data"),
                  ),
                 
                  // Live Monitor Ticks / Distance / Connect Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: MyTextFormField(
                                backgroundColor: colorCalibrateTile,
                                foregroundColor: Colors.white,
                                controller: _controllerWheelTicks,
                                labelText: "Ticks",
                                isReadOnly: true,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: MyTextFormField(
                                backgroundColor: colorCalibrateTile,
                                foregroundColor: Colors.white,
                                controller: _controllerDistance,
                                labelText: "Distance",
                                isReadOnly: true,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Connect Button
                      Padding(
                         padding: const EdgeInsets.symmetric(horizontal: 8.0),
                         child: animatedActionButton(
                          pressed: _connectButtonPressed,
                          onTap: () => _animateTap(
                            widget.onTapConnect,
                            (v) => _connectButtonPressed = v,
                          ),
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
                              const SizedBox(height: 10),
                              Text(
                                widget.monitorData.isConnectedToIot
                                    ? "Disconnect"
                                    : "Connect",
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
