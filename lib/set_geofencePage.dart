import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geofence/utils.dart';
import 'package:geofence/gpsServices.dart';

class setGeoFence extends StatefulWidget {
  const setGeoFence({super.key});

  @override
  State<setGeoFence> createState() => _setGeoFenceState();
}

class _setGeoFenceState extends State<setGeoFence> {
  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  String Version = 'GeoFence 1.9';
  late GoogleMapController _googleMapController;
  LatLng? tappedLocation;
  LatLng currentLocation = LatLng(-29.6, 30.3);
  final defaultLocation = LatLng(-29.6, 30.3);
  Set<Polygon> _geoPolygon = {};
  Set<Polyline> _geoPolyline = {};
  Set<Marker> _geoMarkers = {};
  List<Point> _geoFence = [];
  bool isStreetView = false;
  bool isSetGeoFence = false;
  bool isAddingGeoPoints = false;

  int _currentIndex = 0;
  Future<Position>? currentPosition;

  Future<void> _getLocation() async {
    writeLog('GetLocation');
    Position pos = await determinePosition();

    setState(() {
      currentLocation = LatLng(pos.latitude, pos.longitude);
      GlobalSnackBar.show('Got Location');

      _geoMarkers.add(
        Marker(
          markerId: MarkerId("myLocation"),
          position: LatLng(pos.latitude, pos.longitude),
        ),
      );
    });

    _googleMapController.animateCamera(
      CameraUpdate.newLatLngZoom(currentLocation!, 16),
    );
  }

  static const _initCameraPosition =
      CameraPosition(target: LatLng(-29.6, 30.3), zoom: 12);

  void _onMapTap(LatLng location) {
    var position;

    print('Map onTap');
    setState(() {
      tappedLocation = location;

      if (isSetGeoFence) {
        _addGeofencePoint(location);
        //_createSquareGeofence(location);
        isSetGeoFence = false;
      }
    });

    Point testPoint =
        Point(tappedLocation!.latitude, tappedLocation!.longitude);
    if (isPointInsidePolygon(testPoint, _geoFence))
      position = "Inside";
    else
      position = "Outside";

    _snackbar(
        "Tapped Location: Lat: ${location.latitude}, Lng: ${location.longitude}\r$position");
  }

  void _snackbar(var text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _onBotNavbarTap(int index) {
    if (index == 0) {
      isSetGeoFence = true;
    }
    if (index == 3) {
      // Debug
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => MyTextTile(
                  text: debugLog,
                  color: Colors.black12,
                )),
      );
    }
    setState(() {
      _currentIndex = index;
    });
  }

  void _createSquareGeofencePolygon(LatLng center) {
    double size = 0.01; // Approximate size of the square in degrees
    setState(() {
      _geoPolygon.clear();
      _geoPolygon.add(
        Polygon(
          polygonId: PolygonId("geofence"),
          points: [
            LatLng(center.latitude + size, center.longitude - size),
            LatLng(center.latitude + size, center.longitude + size),
            LatLng(center.latitude - size, center.longitude + size),
            LatLng(center.latitude - size, center.longitude - size),
          ],
          strokeWidth: 2,
          strokeColor: Colors.blue,
          fillColor: Colors.blue.withOpacity(0.3),
        ),
      );

      _geoFence = [
        Point(center.latitude + size, center.longitude - size), // A
        Point(center.latitude + size, center.longitude + size), // B
        Point(center.latitude - size, center.longitude + size), // C
        Point(center.latitude - size, center.longitude - size), // D
      ];
    });
  }

  void _createSquareGeofence(LatLng center) {
    double size = 0.005; // Approximate size of the square in degrees
    setState(() {
      _geoMarkers.clear();
      _geoPolyline.clear();

      _geoMarkers.add(
        Marker(
          markerId: MarkerId("geofence1"),
          position: LatLng(center.latitude, center.longitude),
        ),
      );

      _geoPolyline.add(Polyline(
          polylineId: PolylineId("polyline1"),
          points: [
            LatLng(center.latitude + size, center.longitude - size), // A
            LatLng(center.latitude + size, center.longitude + size), // B
            LatLng(center.latitude - size, center.longitude + size), // C
            LatLng(center.latitude - size, center.longitude - size), // D
            LatLng(center.latitude + size, center.longitude - size), // A
          ],
          width: 3,
          color: Colors.red));

      _geoFence = [
        Point(center.latitude + size, center.longitude - size), // A
        Point(center.latitude + size, center.longitude + size), // B
        Point(center.latitude - size, center.longitude + size), // C
        Point(center.latitude - size, center.longitude - size), // D
      ];
    });
  }

  void _addGeofencePoint(LatLng newPoint) {
    setState(() {
      //_geoMarkers.clear();
      _geoPolyline.clear();

      // if(_geoMarkers.isEmpty){
      //   _geoMarkers.add(
      //     Marker(
      //       markerId: MarkerId("GeoFence1"),
      //       position: LatLng(newPoint.latitude, newPoint.longitude),
      //     ),
      //   );
      // }

      if (_geoPolyline.isNotEmpty) {
        Polyline existingPolyline = _geoPolyline.first;

        // Create a new list of points by adding the new point
        List<LatLng> updatedPoints = List.from(existingPolyline.points)..add(newPoint);

        // Replace the old polyline with a new one
        _geoPolyline.remove(existingPolyline);
        _geoPolyline.add(Polyline(
          polylineId: existingPolyline.polylineId,
          points: updatedPoints,
          color: Colors.blue,
          width: 3,
        ));

        _geoFence = List.from(_geoFence)..add(Point(newPoint.latitude, newPoint.longitude));

        //_geoFence = [
        //Point(newPoint.latitude, newPoint.longitude), // A
        //];
      }
    });
  }
  void _toggleStreetView() {
    setState(() {
      isStreetView = !isStreetView;
    });
  }

  @override
  void dispose() {
    _googleMapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Version),
        actions: [
          IconButton(onPressed: _toggleStreetView, icon: Icon(Icons.streetview))
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          showUnselectedLabels: true,
          onTap: _onBotNavbarTap,
          items: const [
            BottomNavigationBarItem(backgroundColor: Colors.blue, icon: Icon(Icons.add), label: 'Set'),
            BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'Edit'),
            BottomNavigationBarItem(icon: Icon(Icons.delete_forever), label: 'Delete'),
            BottomNavigationBarItem(icon: Icon(Icons.bug_report_rounded), label: 'Debug')
          ]),
      body: GoogleMap(
        zoomControlsEnabled: false,
        initialCameraPosition: CameraPosition(
          target: currentLocation ??
              LatLng(-29.6, 30.3), // Default to San Francisco
          zoom: 10,
        ),
        onMapCreated: (controller) => _googleMapController = controller,
        onTap: _onMapTap,
        //polygons: _geoPolygon,
        markers: _geoMarkers,
        polylines: _geoPolyline,
        mapType: isStreetView ? MapType.satellite : MapType.normal,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.black,
        onPressed: () => _googleMapController.animateCamera(
              CameraUpdate.newCameraPosition(CameraPosition(target: currentLocation,zoom: 16))),
        child: const Text('Origin'),
      ),
    );
  }
}
