import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geofence/utils.dart';

// Vehicle
class IotVehicleType extends StatefulWidget {
  final Map<String, Map<String, dynamic>> mapMonitorData;
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final String monitorName;
  final Function(String) onChangedVehicleName;
  final String monitorFuelConsumption;
  final Function(String) onChangedFuelConsumption;
  final String monitorReg;
  final Function(String) onChangedReg;
  final Function(BluetoothDevice?) onChangedBluetooth;
  final List<BluetoothDevice> lstPairedDevices;

  IotVehicleType({
    super.key,
    required this.mapMonitorData,
    required this.doc,
    required this.monitorName,
    required this.onChangedVehicleName,
    required this.monitorFuelConsumption,
    required this.onChangedFuelConsumption,
    required this.monitorReg,
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
                  controller: TextEditingController(text: widget.monitorName),
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
                  controller: TextEditingController(text:  widget.monitorFuelConsumption),
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
                  controller: TextEditingController(text: widget.monitorReg),
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
                final docMap = widget.doc.data() ?? {};
                String? savedMac = docMap[SettingServerBlueMac] as String?;
                if (savedMac == null) return null;

                // Find the matching paired device
                return widget.lstPairedDevices.firstWhereOrNull(
                      (d) => d.remoteId.toString() == savedMac,
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
              // onChanged: (BluetoothDevice? device) {
              //   setState(() {
              //     final vehicleDoc = lstMonitorData[_tabController!.index];
              //     final docId = vehicleDoc.id;
              //
              //     setState(() {
              //       mapMonitorData[docId]?[SettingMonitorBlueDeviceName] = device?.platformName;
              //       mapMonitorData[docId]?[SettingMonitorBlueMac] = device?.remoteId.toString();
              //       _saveCurrentMonitor();
              //     });
              //   });
              // },
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
  final String name;
  final Function(String) onChangedName;
  final String ticksPerM;
  final Function(String) onChangedTicksPerM;
  final String monId;
  final Function(String) onChangedMonId;
  final Function() onTapScan;

  const IotDistanceWheelType({
    super.key,
    required this.name,
    required this.onChangedName,
    this.ticksPerM = '',
    required this.onChangedTicksPerM,
    this.monId = '',
    required this.onChangedMonId,
    required this.onTapScan

  });

  @override
  State<IotDistanceWheelType> createState() => _IotDistanceWheelTypeState();
}
class _IotDistanceWheelTypeState extends State<IotDistanceWheelType> {
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
            controller: TextEditingController(text: widget.name),
            hintText: "Enter value here",
            labelText: "Wheel Name",
            onFieldSubmitted: widget.onChangedName,
          ),
        ),

        SizedBox(height: 5),

        // ID
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: MyTextFormField(
            backgroundColor: APP_BACKGROUND_COLOR,
            foregroundColor: Colors.white,
            controller: TextEditingController(text: widget.monId),
            hintText: "Select Monitor",
            labelText: "Monitor ID",
            onFieldSubmitted: widget.onChangedMonId,
          ),
        ),

        SizedBox(height: 5),

        // Ticks per M
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: MyTextFormField(
            backgroundColor: APP_BACKGROUND_COLOR,
            foregroundColor: Colors.white,
            controller: TextEditingController(text: widget.ticksPerM.toString()),
            hintText: "Enter value here",
            labelText: "Ticks per Meter",
            onFieldSubmitted: widget.onChangedTicksPerM,
          ),
        ),

        SizedBox(height: 10),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              InkWell(
                  onTap: widget.onTapScan,
                  child: Row(children: [
                    Icon(
                      Icons.connected_tv,
                      size: 50,
                      color: Colors.lightBlueAccent ,
                    ),
                    SizedBox(width: 10),
                    Text("Scan Monitor",
                      style: TextStyle(color: Colors.white),
                    )
                  ], )
                //icon: Icon( Icons.connected_tv),
                //color: Colors.lightBlueAccent,
                //iconSize: 50,
              ),
            ],
          ),
        )
      ],
    );
  }
}
