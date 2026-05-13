import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';

class iotListPage extends StatefulWidget {
  const iotListPage({super.key});

  @override
  State<iotListPage> createState() => _iotListPageState();
}

class _iotListPageState extends State<iotListPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        title: MyAppbarTitle('IoT List'),
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
      ),
      body: ListView(
         children: [
            SizedBox(height: 20),

            // Measuring Wheel
            MyCustomTileWithPic(
              imagePath: iconWheel,
              header: 'Distance Wheel',
              description: 'Manual push wheel for measuring distance. Monitors operator with full cloud report',
              widget: widget,
              onTap: (){
                Navigator.pop(context, monitorTypeWheel);
              },
            ),

            // Vehicle tracking (Diesel rebate)
            MyCustomTileWithPic(
                imagePath: iconVehicle,
                header: 'Vehicle Tracker',
                description: 'Track vehicle movement. Set geofence perimeter. Get full report for diesel rebate',
                widget: widget,
                onTap: (){
                  Navigator.pop(context, monitorTypeVehicle);
                },
            ),

            // Fleet tracking
            MyCustomTileWithPic(
                imagePath: iconFleet,
                header: 'Fleet Tracker',
                description: 'Track entire fleet. Monitor breakdowns, speed limits alerts, logistics, driver statistics.',
                widget: widget,
                onTap: (){
                  Navigator.pop(context, monitorTypeFleet);
                },
            ),

            // Machine
            MyCustomTileWithPic(
                imagePath: iconMachine,
                header: 'Machine Monitor',
                description: 'Monitor machine running hours. Set geofence perimeter. Get full report for diesel rebate',
                widget: widget,
                onTap: (){
                Navigator.pop(context, monitorTypeMachine);
                },
            ),

            // Trailer plug wiring
            MyCustomTileWithPic(
                imagePath: iconTrailer,
                header: 'Trailer Plug Wiring',
                description: 'Test trailer plug wiring according to SABS 1327/1981 standard. Auto create a legal sign off certificate.',
                widget: widget,
                onTap: (){
                  Navigator.pop(context, monitorTypeTrailer);
                },
            ),
          ],
        ),
    );
  }
}
