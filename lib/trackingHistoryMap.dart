import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geofence/utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


class TrackingHistoryMap extends StatefulWidget {
  final String? userId;
  final String? trackSessionId;

  const TrackingHistoryMap({
    required this.userId,
    required this.trackSessionId,
    super.key
  });

  @override
  State<TrackingHistoryMap> createState() => _TrackingHistoryMapState();
}

class _TrackingHistoryMapState extends State<TrackingHistoryMap> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  final Set<Polygon> _geofences = {};
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};
  final LatLng _currentLocation = const LatLng(-29.6, 30.3);
  bool _isLoading = false;
  int _polygonIdCounter = 0;
  Set<Polyline> _pathPolyline = {};
  bool markersOn = false;
  int _fencePntr = 0;

  List<LatLng> _trackSessionPoints = [];
  final List<Map<String, dynamic>> _geofenceData = [];
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _flutterTts = FlutterTts();
  final Map<String, bool> _insideGeofence = {};
  final List<FenceData> _geoFenceList = [];

  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(-29.0, 24.0), // Default to South Africa
    zoom: 6.0,
  );

  @override
  void initState() {
    super.initState();
    _initializeTracking();
  }

  Future<void> _getTrackSessionPoints() async{
    List<LatLng> lst = [];

    try{
      final locationsSnapshot = await firestore
          .collection(CollectionUsers)
          .doc(widget.userId)
          .collection(CollectionTrackingSessions)
          .doc(widget.trackSessionId)
          .collection(CollectionLocations)
          .orderBy('timestamp') // optional, if order matters
          .get();


      for (var doc in locationsSnapshot.docs) {
        final data = doc.data();
        lst.add(LatLng(data['latitude'], data['longitude']));
      }
    }catch (e){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading tracking locations: $e')),
      );
    }
    finally{
      setState(() {
        _trackSessionPoints = lst;
      });
    }
  }
  Future<void> _initializeTracking() async {
    printMsg("_loadGeoFences");
    await _loadGeoFences(context);
    printMsg("DONE");

    printMsg("_getTrackSessionPoints");
    await _getTrackSessionPoints();
    printMsg("DONE");

    printMsg("_loadTrackingPath");
    await _loadTrackingPath();
    printMsg("DONE");
  }
  Future<void> _loadGeoFences(BuildContext context) async {

    setState(() {
      _isLoading = true;
      _polygons.clear();
      _markers.clear();
    });
    try {
      final userId = widget.userId;// _userData.userID;// firebaseAuthService. _auth.currentUser!.uid;
      final geoFencesSnapshot = await firestore
          .collection(CollectionUsers)
          .doc(userId)
          .collection(CollectionGeoFences)
          .get();

      if (geoFencesSnapshot.docs.isNotEmpty) {
        for (var doc in geoFencesSnapshot.docs) {
          final data = doc.data();
          final points = List<GeoPoint>.from(data['points']);
          final polygonPoints = points.map((point) =>
              LatLng(point.latitude, point.longitude)).toList();

          if (polygonPoints.length >= 3) {
            final polygonId = 'polygon_${_polygonIdCounter++}';
            final markerId = 'marker_${_polygonIdCounter++}';

            setState(() {
              // Add marker for the label
              _markers.add(
                Marker(
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta),
                  markerId: MarkerId(markerId),
                  position: calculateCentroid(polygonPoints),
                  infoWindow: InfoWindow(title: data['name']),
                  //onTap: ()=> _onMarkerTap(polygonId, doc.id, data['name'], polygonPoints),
                ),
              );

              // Add polygon
              _polygons.add(
                Polygon(
                  polygonId: PolygonId(polygonId),
                  points: polygonPoints,
                  strokeWidth: 2,
                  strokeColor: Colors.blue,
                  fillColor: Colors.blue.withOpacity(0.2),
                  consumeTapEvents: true,
                ),
              );

              _geoFenceList.add(FenceData(
                  points: polygonPoints,
                  name: data['name'],
                  firestoreId: doc.id
              ));
            });
          }
        }
      }
      // Focus map on user's location if available
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (userDoc.exists && userDoc.data()!.containsKey('location')) {
        final location = userDoc.data()!['location'] as GeoPoint;
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading geo fences: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  Future<void> _loadTrackingPath() async {
    if (_trackSessionPoints.isEmpty || _geoFenceList.isEmpty) return;

    Set<Polyline> polylineSet = {};
    List<LatLng> trackingPathRed = [];
    List<LatLng> trackingPathGreen = [];

    for(LatLng position in _trackSessionPoints){
      bool insideAny = false;

      for (var geofence in _geoFenceList) {
        final bool isInside = isPointInsidePolygon(position, geofence.points);

        if(isInside) {
          trackingPathGreen.add(position);
        } else {
          trackingPathRed.add(position);
        }

        insideAny = insideAny || isInside;

        // Check if status changed (entered or exited geofence)
        if (isInside != _insideGeofence[geofence.firestoreId]) {

          _insideGeofence[geofence.firestoreId] = isInside;

          polylineSet = {
            Polyline(
              polylineId: const PolylineId('tracking_path_red'),
              points: trackingPathRed,
              color: Colors.red,
              width: 5,
            ),
            Polyline(
              polylineId: const PolylineId('tracking_path_green'),
              points: trackingPathGreen,
              color: Colors.green,
              width: 5,
            ),
          };
        }
      }
    }

    setState(() {
      _pathPolyline = polylineSet;
    });

    if(_mapController != null && (trackingPathRed.length > 1 || trackingPathGreen.length > 1)) {
      if(trackingPathGreen.length > 1){
        _mapController?.animateCamera
          (CameraUpdate.newLatLngZoom(trackingPathGreen[0], 18),
        );
      }
      else{
        _mapController?.animateCamera
          (CameraUpdate.newLatLngZoom(trackingPathRed[0], 18),
        );
      }
    }
  }
  void _addPointMarkers() {
    Set<Marker> pointMarkers = {};

    for (int i = 0; i < _trackSessionPoints.length; i++) {
      final point = _trackSessionPoints[i];
      pointMarkers.add(
        Marker(
          markerId: MarkerId('point_$i'),
          position: point,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure, // Or use red, green, etc.
          ),
          infoWindow: InfoWindow(
            title: 'Point $i',
            snippet: '${point.latitude}, ${point.longitude}',
          ),
        ),
      );
    }

    setState(() {
      _markers.addAll(pointMarkers);
    });
  }
  void _nextFence() {
    if (_markers.isEmpty) return;

    setState(() {
      if (_fencePntr == _markers.length) {
        _fencePntr = 0;
      } else {
        _fencePntr++;
      }

      int ptr = 0;

      for (Marker mark in _markers) {
        if (ptr == _fencePntr) {
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(mark.position.latitude, mark.position.longitude)),
          );
          print(mark.infoWindow.title);
          return;
        }
        else{
          ptr++;
        }
      }
    });
  }
  void _onBotBarTap(index) {
    if(index == 0){
      _nextFence();
    }
    if(index == 1){
    }
    if(index == 2){
      if(!markersOn) {
        _addPointMarkers();
        markersOn = true;
      }
      else {
        markersOn = false;
        setState(() {
          _markers.removeWhere((val) => val.markerId.value.startsWith('point_'));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: MyAppbarTitle('Track History') ,
        backgroundColor: APP_BAR_COLOR,
        foregroundColor: Colors.white,
      ) ,
      bottomNavigationBar: BottomNavigationBar(
          onTap: _onBotBarTap,
          backgroundColor: APP_BAR_COLOR,
          unselectedItemColor: Colors.grey,
          selectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(
              label: "GeoFence",
              icon: Icon(
                Icons.search,
                size: 35,
              ),
            ),

            BottomNavigationBarItem(
            label: "Refresh",
            icon: Icon(
                Icons.refresh,
                size: 35,
              ),
            ),

            BottomNavigationBarItem(
              label: "Markers",
              icon: Icon(
                Icons.location_on,
                size: 35,
              ),
            ),

          ]
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: GoogleMap(
                  initialCameraPosition: _initialPosition,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  mapType: MapType.normal,
                  markers: _markers,
                  polygons: _polygons,
                  polylines: _pathPolyline ?? {},
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                ),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: APP_BACKGROUND_COLOR,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
