import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';

// Vehicle
class IotVehicleType extends StatefulWidget {
  final MonitorData monitorData;
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
                  backgroundColor: APP_BACKGROUND_COLOR,
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
                  backgroundColor: APP_BACKGROUND_COLOR,
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
                  backgroundColor: APP_BACKGROUND_COLOR,
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
            data: Theme.of(context).copyWith(canvasColor: APP_TILE_COLOR),
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
  final MonitorData monitorData;
  final Function(String) onChangedName;
  final Function(String) onChangedTicksPerM;
  final Function(String) onChangedMonId;
  final Function() onTapScan;

  const IotDistanceWheelType({
    super.key,
    required this.monitorData,
    required this.onChangedName,
    required this.onChangedTicksPerM,
    required this.onChangedMonId,
    required this.onTapScan
  });

  @override
  State<IotDistanceWheelType> createState() => _IotDistanceWheelTypeState();
}
class _IotDistanceWheelTypeState extends State<IotDistanceWheelType> {
  late TextEditingController _controllerName;
  late TextEditingController _controllerId;
  late TextEditingController _controllerTicks;
  late TextEditingController _controllerDistance;
  late SettingsService settingService;

  @override
  void initState() {
    super.initState();
    _controllerId = TextEditingController(text: widget.monitorData.monitorId);
    _controllerName = TextEditingController(text: widget.monitorData.monitorName);
    _controllerTicks = TextEditingController(text: widget.monitorData.ticksPerM.toString());
    _controllerDistance = TextEditingController(text: widget.monitorData.wheelDistance.toString());

  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settingService = context.read<SettingsService>();
  }

  @override
  void didUpdateWidget(covariant IotDistanceWheelType oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update text only if monitorId changes externally
    if (oldWidget.monitorData.monitorId != widget.monitorData.monitorId) {
      _controllerId.text = widget.monitorData.monitorId;
    }

    if (oldWidget.monitorData.monitorName != widget.monitorData.monitorName) {
      _controllerName.text = widget.monitorData.monitorName;
    }

    if (oldWidget.monitorData.ticksPerM != widget.monitorData.ticksPerM) {
      _controllerTicks.text = widget.monitorData.ticksPerM.toString();
    }

    if (oldWidget.monitorData.wheelDistance != widget.monitorData.wheelDistance) {
      _controllerDistance.text = widget.monitorData.wheelDistance.toString();
    }
  }

  @override
  void dispose() {
    _controllerId.dispose();
    _controllerDistance.dispose();
    _controllerName.dispose();
    _controllerTicks.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // Wheel Name
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: MyTextFormField(
            backgroundColor: APP_BACKGROUND_COLOR,
            foregroundColor: Colors.white,
            controller: _controllerName,
            hintText: "Enter value here",
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
                  backgroundColor: APP_BACKGROUND_COLOR,
                  foregroundColor: Colors.white,
                  controller: _controllerId,
                  hintText: "Select Monitor",
                  labelText: "Monitor ID",
                  onFieldSubmitted: widget.onChangedMonId,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: InkWell(
                  onTap: widget.onTapScan,
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
                      Text("Scan",
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
            backgroundColor: APP_BACKGROUND_COLOR,
            foregroundColor: Colors.white,
            controller: _controllerTicks,
            hintText: "Enter value here",
            labelText: "Ticks per Meter",
            onFieldSubmitted: widget.onChangedTicksPerM,
          ),
        ),

        SizedBox(height: 30),

        // Go Live + Connect Button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              // Debug Header
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15,10,15,10),
                  child: MyTextHeader(
                      text: "Go Live",
                      color:widget.monitorData.isConnected
                          ? Colors.white
                          : Colors.grey,
                      linecolor: widget.monitorData.isConnected
                        ? Colors.blue
                        : Colors.grey
                  ),
                ),
              ),

              SizedBox(width: 15),

              // Connect Button
              InkWell(
                  onTap: widget.onTapScan,
                  child: Column(
                    children: [
                      Icon(
                        Icons.online_prediction_sharp,
                        size: 30,
                        color: settingService.isBaseStationConnected
                          ? widget.monitorData.isConnected
                            ? Colors.greenAccent
                            : Colors.lightBlueAccent
                          : Colors.grey
                      ),
                      SizedBox(width: 10),
                      Text("Connect",
                        style: TextStyle(
                            color: settingService.isBaseStationConnected
                              ? Colors.white
                              : Colors.grey
                        ),
                      )
                    ],
                  )
              ),
            ],
          ),
        ),

        // Distance
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: MyTextFormField(
            backgroundColor: APP_BACKGROUND_COLOR,
            foregroundColor: Colors.white,
            controller: _controllerDistance,
            hintText: "Waiting for movement",
            labelText: "Distance",
          ),
        ),
      ],
    );
  }
}
