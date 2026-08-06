import 'package:cloud_firestore/cloud_firestore.dart';
//import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
//import 'package:flutter_tts/flutter_tts.dart';
import 'package:geofence/utils.dart';
//import 'package:geolocator/geolocator.dart';
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
  State<TrackingHistoryMap> createState() => TrackingHistoryMapState();
}

class TrackingHistoryMapState extends State<TrackingHistoryMap> {
  GoogleMapController? _mapController;
  //Position? _currentPosition;
  //final Set<Polygon> _geofences = {};
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};
  //final LatLng _currentLocation = const LatLng(-29.6, 30.3);
  bool _isLoading = false;
  int _polygonIdCounter = 0;
  Set<Polyline> _pathPolyline = {};
  bool markersOn = false;
  int _fencePntr = 0;

  List<LatLng> _trackSessionPoints = [];
  List<Map<String, dynamic>> _trackSessionCrossings = [];
  //final List<Map<String, dynamic>> _geofenceData = [];
  //final FirebaseAuth _auth = FirebaseAuth.instance;
  //final FlutterTts _flutterTts = FlutterTts();
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

  Future<void> _getTrackSessionPoints() async {
    final points = <LatLng>[];
    final crossings = <Map<String, dynamic>>[];

    try {
      final locationsSnapshot = await firestore
          .collection(collectionUsers)
          .doc(widget.userId)
          .collection(collectionTrackingSessions)
          .doc(widget.trackSessionId)
          .collection(collectionLocations)
          .orderBy('timestamp')
          .get();

      for (final doc in locationsSnapshot.docs) {
        final data = doc.data();
        points.add(LatLng(data['latitude'], data['longitude']));
        crossings.add(data);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tracking locations: $e')),
        );
      }
    } finally {
      setState(() {
        _trackSessionPoints = points;
        _trackSessionCrossings = crossings;
      });
    }
  }
  Future<void> _initializeTracking() async {
    printDebugMsg("_loadGeoFences");
    await _loadGeoFences(context);
    printDebugMsg("DONE");

    printDebugMsg("_getTrackSessionPoints");
    await _getTrackSessionPoints();
    printDebugMsg("DONE");

    printDebugMsg("_loadTrackingPath");
    await _loadTrackingPath();
    printDebugMsg("DONE");
  }
  Future<void> _loadGeoFences(BuildContext context) async {

    setState(() {
      _isLoading = true;
      _polygons.clear();
      _markers.clear();
      _geoFenceList.clear();
    });
    try {
      final userId = widget.userId;
      final geoFencesSnapshot = await firestore
          .collection(collectionUsers)
          .doc(userId)
          .collection(collectionGeoFences)
          .get();

      final newMarkers = <Marker>{};
      final newPolygons = <Polygon>{};
      final newFences = <FenceData>[];

      for (var doc in geoFencesSnapshot.docs) {
        final data = doc.data();
        final points = List<GeoPoint>.from(data[fireGeoPoints]);
        final polygonPoints = points
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();

        if (polygonPoints.length < 3) continue;

        final polygonId = '$geoFencePolygon${_polygonIdCounter++}';
        final markerId = '$geoFenceMarker${_polygonIdCounter++}';
        final name = '${data[fireGeoName] ?? data['name'] ?? ''}';
        final labelIcon = await fenceNameLabelIcon(name);

        newMarkers.add(
          Marker(
            icon: labelIcon,
            anchor: const Offset(0.5, 0.5),
            markerId: MarkerId(markerId),
            position: calculateCentroid(polygonPoints),
            infoWindow: InfoWindow(title: name),
          ),
        );

        newPolygons.add(
          Polygon(
            polygonId: PolygonId(polygonId),
            points: polygonPoints,
            strokeWidth: 2,
            strokeColor: Colors.blue,
            fillColor: Colors.blue.withValues(alpha: 0.2),
            consumeTapEvents: true,
          ),
        );

        newFences.add(FenceData(
          points: polygonPoints,
          name: name,
          firestoreId: doc.id,
        ));
      }

      if (!mounted) return;
      setState(() {
        _markers.addAll(newMarkers);
        _polygons.addAll(newPolygons);
        _geoFenceList.addAll(newFences);
      });

      // Focus map on user's location if available
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (userDoc.exists && userDoc.data()!.containsKey('location')) {
        final location = userDoc.data()!['location'] as GeoPoint;
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude)),
        );
      }
    } catch (e) {
      if(mounted){
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading geo fences: $e')),
        );
      }
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
        final bool isInside = isPointInsideGeofence(position, geofence);

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
      final data = i < _trackSessionCrossings.length
          ? _trackSessionCrossings[i]
          : const <String, dynamic>{};
      final event = '${data[fireGeoCrossingEvent] ?? ''}';
      final fenceName = '${data[fireGeoCrossingFenceName] ?? ''}';
      final isEnter = event == fireGeoCrossingEnter;
      final title = event.isEmpty
          ? 'Point $i'
          : '${isEnter ? 'Enter' : 'Exit'}${fenceName.isEmpty ? '' : ': $fenceName'}';

      pointMarkers.add(
        Marker(
          markerId: MarkerId('$geoFencePoint$i'),
          position: point,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            event.isEmpty
                ? BitmapDescriptor.hueAzure
                : isEnter
                    ? BitmapDescriptor.hueGreen
                    : BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: title,
            snippet: '${point.latitude.toStringAsFixed(5)}, '
                '${point.longitude.toStringAsFixed(5)}',
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
          printDebugMsg('${mark.infoWindow.title}');
          return;
        }
        else{
          ptr++;
        }
      }
    });
  }
  void _onBotBarTap(int index) {
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
          _markers.removeWhere((val) => val.markerId.value.startsWith(geoFencePoint));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: myAppbarTitle('Track History') ,
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
      ) ,
      bottomNavigationBar: BottomNavigationBar(
          onTap: _onBotBarTap,
          backgroundColor: colorAppBar,
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
                  polylines: _pathPolyline,
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                ),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: colorAppBackground,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
