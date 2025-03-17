import 'package:flutter/material.dart';
import 'package:geofence/GeofencePage.dart';
import 'package:geofence/set_geofencePage.dart';
import 'package:geofence/utils.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

String Version = 'GeoFence 1.9';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    userData.addListener(() {
      setState(() {}); // Rebuild the UI when UserData changes
    });
  }

  @override
  void Dispose() {
    userData.removeListener(() {
      setState(() {});
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
         LoginHeader(),

          SizedBox(height: 50),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              myCustomTileWithPic(
                  imagePath: 'assets/track.jpg',
                  text: 'Track',
                  widget: GeoFenceScreen(), //setGeoFence(),
              ),

              SizedBox(width: 10),

              myCustomTileWithPic(
                imagePath: 'assets/geofence.jpg',
                text: 'GeoFence',
                widget: GeoFenceScreen(),
              ),
            ],
          ),
        ],
      )
    );
  }
}
