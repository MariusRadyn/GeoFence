import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';

class IotListPage extends StatefulWidget {
  const IotListPage({super.key});

  @override
  State<IotListPage> createState() => IotListPageState();
}

class IotListPageState extends State<IotListPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        title: myAppbarTitle('Select IoT Type'),
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),

          MyCustomTileWithPic(
            imagePath: iconThirdPartyIot,
            header: 'SONOFF',
            description:
                'Control SONOFF smart switches and relays through your linked eWeLink account. '
                'Link once in Limitless, then toggle devices here. Pair new hardware in the eWeLink app.',
            widget: widget,
            onTap: () {
              Navigator.pop(context, monitorTypeSonoff);
            },
          ),

          // Measuring Wheel
          MyCustomTileWithPic(
            imagePath: iconWheel,
            header: 'Distance Wheel',
            description:
                'Manual push wheel for measuring distance. Monitors operator with full cloud report',
            widget: widget,
            onTap: () {
              Navigator.pop(context, monitorTypeWheel);
            },
          ),

          // Vehicle tracking (Diesel rebate)
          MyCustomTileWithPic(
            imagePath: iconVehicle,
            header: 'Vehicle Tracker',
            description:
                'Track vehicle movement. Set geofence perimeter. Get full report for diesel rebate',
            widget: widget,
            onTap: () {
              Navigator.pop(context, monitorTypeVehicle);
            },
          ),

          // Fleet tracking
          MyCustomTileWithPic(
            imagePath: iconFleet,
            header: 'Fleet Tracker',
            headerSuffix: '(Coming Soon)',
            headerSuffixColor: colorOrange,
            description:
                'Track entire fleet. Monitor breakdowns, speed limits alerts, logistics, driver statistics.',
            widget: widget,
            onTap: () {
              Navigator.pop(context, monitorTypeFleet);
            },
          ),

          // Machine
          MyCustomTileWithPic(
            imagePath: iconMachine,
            header: 'Machine Monitor',
            headerSuffix: '(Coming Soon)',
            headerSuffixColor: colorOrange,
            description:
                'Monitor machine running hours. Set geofence perimeter. Get full report for diesel rebate',
            widget: widget,
            onTap: () {
              Navigator.pop(context, monitorTypeMachine);
            },
          ),

          // Trailer plug wiring
          MyCustomTileWithPic(
            imagePath: iconTrailer,
            header: 'Trailer Plug Wiring',
            headerSuffix: '(Coming Soon)',
            headerSuffixColor: colorOrange,
            description:
                'Test trailer plug wiring according to SABS 1327/1981 standard. Auto create a legal sign off certificate.',
            widget: widget,
            onTap: () {
              Navigator.pop(context, monitorTypeTrailer);
            },
          ),
        ],
      ),
    );
  }
}
