import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

import 'gpsServices.dart';

class TrackingPage extends StatefulWidget {
  final String userId;

  const TrackingPage({
    Key? key,
    required this.userId}
      ) : super(key: key);

  @override
  _TrackingPageState createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  Set<Polygon> _geofences = {};
  Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};
  int _polygonIdCounter = 0;
  StreamSubscription<Position>? _positionStream;
  String _statusMessage = "Not tracking";
  List<Map<String, dynamic>> _geofenceData = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isLoading = false;
  bool _isTracking = false;
  Map<String, bool> _insideGeofence = {};
  String? _selectedVehicleId;
  List<Map<String, dynamic>> _vehicles = [];
  String? _trackingSessionId;
  List<LatLng> _trackingPath = [];
  Polyline? _pathPolyline;
  LatLng _currentLocation = const LatLng(-29.6, 30.3);
  int _fencePntr = 0;
  int _distanceFilter = 0;

  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(-29.0, 24.0), // Default to South Africa
    zoom: 6.0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeTracking();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // This executes after the first frame is built, when context is fully valid
      if (!mounted) return;

      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

      settingsProvider.LoadSettings(widget.userId).then((_) {
        if (!mounted) return;

        setState(() {
          _distanceFilter = settingsProvider.LogPointPerMeter;
        });
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTracking();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app state changes
    if (state == AppLifecycleState.resumed) {
      // Resume tracking when app is resumed
      if (_trackingSessionId != null && _positionStream == null) {
        _startPositionTracking();
      }
    } else if (state == AppLifecycleState.paused) {
      // Keep tracking in background
    }
  }

  Future<void> _initializeTracking() async {
    await _loadGeoFences(context);
    await _loadVehicles();
    _initTts();
    _getLocation();
  }
  Future<void> _loadGeoFences(BuildContext context) async {
    final _userData = Provider.of<UserData>(context, listen: false);

    setState(() {
      _isLoading = true;
      _polygons.clear();
      _markers.clear();
    });
    try {
      final userId = _userData.userID;// firebaseAuthService. _auth.currentUser!.uid;
      final geoFencesSnapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('geofences')
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
                  position: _calculateCentroid(polygonPoints),
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
  Future<void> _getLocation() async {
    writeLog('GetLocation');
    Position pos = await determinePosition();

    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
      GlobalSnackBar.show('Got Location');

      _markers.add(
        Marker(
          markerId: MarkerId("myLocation"),
          position: LatLng(pos.latitude, pos.longitude),
        ),
      );
    });

    if(_mapController != null) {
      _mapController?.animateCamera
        (CameraUpdate.newLatLngZoom(_currentLocation!, 18),
      );
    }
  }
  Future<void> _loadVehicles() async {
    try {
      final userId = _auth.currentUser!.uid;
      final vehiclesSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('vehicles')
          .get();

      List<Map<String, dynamic>> vehicles = [];

      for (var doc in vehiclesSnapshot.docs) {
        final data = doc.data();
        vehicles.add({
          'id': doc.id,
          'name': data['name'] ?? 'Unknown Vehicle',
          'registrationNumber': data['registrationNumber'] ?? '',
          'fuelConsumption': data['fuelConsumption'] ?? 0.0,
        });
      }

      setState(() {
        _vehicles = vehicles;
        _selectedVehicleId = vehicles[0]['id'];
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading vehicles: $e')),
      );
    }
  }
  void _initTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }
  LatLng _calculateCentroid(List<LatLng> points) {
    double latitude = 0;
    double longitude = 0;

    for (var point in points) {
      latitude += point.latitude;
      longitude += point.longitude;
    }

    return LatLng(latitude / points.length, longitude / points.length);
  }
  Future<void> _startTracking() async {
    if (_selectedVehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a vehicle first')),
      );
      return;
    }

    setState(() {
      _isTracking = true;
      _trackingPath = [];
    });

    print("_isTracking = true");

    try {
      // Check location permissions
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requestPermission = await Geolocator.requestPermission();
        if (requestPermission == LocationPermission.denied ||
            requestPermission == LocationPermission.deniedForever) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
          return;
        }
      }

      // Create tracking session in Firebase
      final userId = _auth.currentUser!.uid;
      final sessionRef = await _firestore
          .collection('users')
          .doc(userId)
          .collection('tracking_sessions')
          .add({
        'vehicle_id': _selectedVehicleId,
        'start_time': FieldValue.serverTimestamp(),
        'is_active': true,
        'distance_inside': 0.0,
        'distance_outside': 0.0,
      });

      _trackingSessionId = sessionRef.id;

      // Start position tracking
      _startPositionTracking();

      setState(() {
        _statusMessage = "Tracking active";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracking started')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting tracking: $e')),
      );
    } finally {

    }
  }
  void _startPositionTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilter, // Update every 10 meters
      ),
    ).listen(_onPositionUpdate);
  }
  void _onPositionUpdate(Position position) async {
    if (_trackingSessionId == null) return;

    setState(() {
      _currentPosition = position;
    });

    final currentLatLng = LatLng(position.latitude, position.longitude);

    // Add to tracking path
    _trackingPath.add(currentLatLng);

    // Update polyline on map
    setState(() {
      _pathPolyline = Polyline(
        polylineId: const PolylineId('tracking_path'),
        points: _trackingPath,
        color: Colors.red,
        width: 5,
      );
    });

    // Move camera to current position
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(currentLatLng),
    );

    // Calculate distances and check if inside any geofence
    if (_trackingPath.length >= 2) {
      final previousPosition = _trackingPath[_trackingPath.length - 2];
      final distance = Geolocator.distanceBetween(
        previousPosition.latitude,
        previousPosition.longitude,
        currentLatLng.latitude,
        currentLatLng.longitude,
      ) / 1000; // Convert to kilometers

      // Check if inside any geofence
      bool insideAny = false;
      for (var geofence in _geofenceData) {
        final bool isInside = _isPointInPolygon(
          currentLatLng,
          geofence['points'] as List<LatLng>,
        );

        insideAny = insideAny || isInside;

        // Check if status changed (entered or exited geofence)
        if (isInside != _insideGeofence[geofence['id']]) {
          _insideGeofence[geofence['id']] = isInside;

          // Announce entry/exit via TTS
          _checkSettings().then((voicePromptEnabled) {
            if (voicePromptEnabled) {
              if (isInside) {
                _flutterTts.speak('Entering ${geofence['name']}');
              } else {
                _flutterTts.speak('Exiting ${geofence['name']}');
              }
            }
          });
        }
      }

      // Update tracking session with new data
      final userId = _auth.currentUser!.uid;
      final trackingRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('tracking_sessions')
          .doc(_trackingSessionId);

      // Save location data
      await trackingRef.collection('locations').add({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'inside_geofence': insideAny,
      });

      // Update session with distance
      await trackingRef.update({
        insideAny ? 'distance_inside' : 'distance_outside':
        FieldValue.increment(distance),
      });

      // Update status message
      setState(() {
        _statusMessage = insideAny
            ? "Inside geofence"
            : "Outside geofence";
      });
    }
  }
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    // Ray casting algorithm to determine if point is in polygon
    bool isInside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].longitude > point.longitude) != (polygon[j].longitude > point.longitude) &&
          (point.latitude < (polygon[j].latitude - polygon[i].latitude) *
              (point.longitude - polygon[i].longitude) /
              (polygon[j].longitude - polygon[i].longitude) +
              polygon[i].latitude)) {
        isInside = !isInside;
      }
      j = i;
    }

    return isInside;
  }
  Future<bool> _checkSettings() async {
    final userId = _auth.currentUser!.uid;
    final settingsDoc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('app_settings')
        .get();

    if (settingsDoc.exists) {
      final settings = settingsDoc.data() ?? {};
      return settings[SettingIsVoicePromptOn] ?? true; // Default to true
    }

    return true; // Default to enabled if no settings found
  }
  Future<void> _stopTracking() async {
    if (_trackingSessionId == null) return;

    setState(() {
      _isTracking = false;
      _isLoading = true;
    });

    try {
      // Stop position updates
      await _positionStream?.cancel();
      _positionStream = null;

      // Mark tracking session as inactive
      final userId = _auth.currentUser!.uid;
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('tracking_sessions')
          .doc(_trackingSessionId)
          .update({
        'is_active': false,
        'end_time': FieldValue.serverTimestamp(),
      });

      setState(() {
        _trackingSessionId = null;
        _statusMessage = "Tracking stopped";
        _trackingPath = [];
        _pathPolyline = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracking stopped')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error stopping tracking: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  Widget _buildVehicleSelector() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            _vehicles.isEmpty
                ? const Text('No vehicles found. Please add a vehicle first.')
                : DropdownButton<String>(
              isExpanded: true,
              value: _selectedVehicleId,
              hint: const Text('Select a vehicle'),
              onChanged: (newValue) {
                setState(() {
                  _selectedVehicleId = newValue;
                });
              },
              items: _vehicles.map((vehicle) {
                return DropdownMenuItem<String>(
                  value: vehicle['id'],
                  child: Text('${vehicle['name']} (${vehicle['registrationNumber']})'),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
  void _nextFence() {
    if (_markers.length == 0) return;

    setState(() {
      if (_fencePntr == _markers.length)
        _fencePntr = 0;
      else
        _fencePntr++;

      int _ptr = 0;

      for (Marker mark in _markers) {
        if (_ptr == _fencePntr) {
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(mark.position.latitude, mark.position.longitude)),
          );
          print(mark.infoWindow.title);
          return;
        }
        else{
          _ptr++;
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
    if(index == 2) {
      _isTracking ? _stopTracking() : _startTracking();
    }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: APP_BAR_COLOR,
        title: MyAppbarTitle('$_statusMessage'),
      ),
      bottomNavigationBar: BottomNavigationBar(
        onTap: _onBotBarTap,
        backgroundColor: APP_BAR_COLOR,
        unselectedItemColor: Colors.grey,
          selectedItemColor: Colors.purple,
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.search, size: 35),label: "GeoFence"),
            BottomNavigationBarItem(icon: Icon(Icons.refresh, size: 35),label: "Refresh" ),
            BottomNavigationBarItem(
                icon: _isTracking
                    ? Icon(Icons.location_off, size: 35, color: Colors.red)
                    : Icon(Icons.location_on, size: 35, color: Colors.blue),
                label: (_trackingSessionId == null) ? "Track" : "Stop" ),
          ]
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildVehicleSelector(),

              Expanded(
                child: GoogleMap(
                  initialCameraPosition: _initialPosition,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  mapType: MapType.normal,
                  markers: _markers,
                  polygons: _polygons,
                  polylines: _pathPolyline != null
                      ? {_pathPolyline!}
                      : {},
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                ),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
