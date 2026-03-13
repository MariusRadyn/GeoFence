import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'gpsServices.dart';

class TrackingPage extends StatefulWidget {

  const TrackingPage({
    super.key
  });

  @override
  _TrackingPageState createState() => _TrackingPageState();
}
class _TrackingPageState extends State<TrackingPage> with WidgetsBindingObserver {
  late SettingsService settings;
  GoogleMapController? _mapController;
  Position? _currentPosition;
  final Set<Polygon> _geofences = {};
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};
  int _polygonIdCounter = 0;
  StreamSubscription<Position>? _positionStream;
  String _statusMessage = "Not tracking";
  final List<FenceData> _geofenceList = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  //final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isLoading_Geofence = true;
  bool _isLoading_Vehicles = true;
  bool _isTracking = false;
  bool _newTrackingStarted = false;
  final Map<String, bool> _insideGeofence = {};
  String? _selectedVehicleId;
  List<Map<String, dynamic>> _vehicles = [];
  String? _trackingSessionId;
  List<LatLng> _trackingPathRed = [];
  List<LatLng> _trackingPathGreen = [];
  Set<Polyline> _pathPolyline = {};
  LatLng _currentLocation = const LatLng(-29.6, 30.3);
  int _fencePntr = 0;
  int _distanceFilter = 0;
  bool _isVoicePromptOn = false;

  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(-29.0, 24.0), // Default to South Africa
    zoom: 6.0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_vehicles.isEmpty && !_isLoading_Vehicles) {
        MyAlertDialog(
          context,
          "Vehicle Not Found",
          "No Vehicles Found.\nPlease set one in 'IOT Monitors'",
        );
      }

      _initializeTracking();
    });
  }

  Future<void> _initializeTracking() async {
    await _loadGeoFences();
    if (!mounted) return;

    await _loadVehicles();
    if (!mounted) return;

    _initTts();
    if (!mounted) return;

    _getLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = context.read<SettingsService>();

    if(settings.fireSettings != null){
      _distanceFilter = settings.fireSettings!.logPointPerMeter;
      _isVoicePromptOn = settings.fireSettings!.isVoicePromptOn;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTracking(fromDispose: true);
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {

    if (state == AppLifecycleState.resumed) {
      // Resume tracking when app is resumed
      if (_trackingSessionId != null && _positionStream == null) {
        _startPositionTracking();
      }
    } else if (state == AppLifecycleState.paused) {
      // Keep tracking in background
    }
  }

  Future<void> _loadGeoFences() async {
    _geofenceList.clear();

    setState(() {
      _isLoading_Geofence = true;
      _polygons.clear();
      _markers.clear();
    });

    try {
      final user = context.read<UserDataService>();

      final geoFencesSnapshot = await firestore
          .collection(CollectionUsers)
          .doc(user.userdata!.userID)
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
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueMagenta),
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

              _geofenceList.add(FenceData(
                  points: polygonPoints,
                  name: data['name'],
                  firestoreId: doc.id
              ));
            });
          }
        }
      }

      // Focus map on user's location if available
      final userDoc = await firestore
          .collection(CollectionUsers)
          .doc(user.userdata!.userID)
          .get();

      if (userDoc.exists && userDoc.data()!.containsKey('location')) {
        final location = userDoc.data()!['location'] as GeoPoint;
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude)),
        );
      }
    } catch (e) {
      MyGlobalSnackBar.show('Error loading GEO Fences: $e');
    } finally {
      setState(() {
        _isLoading_Geofence = false;
      });
    }
  }
  Future<void> _getLocation() async {
    if(_vehicles.isEmpty)return;

    writeLog('GetLocation');
    Position pos = await determinePosition();

    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
      MyGlobalSnackBar.show('Got Location');

      _markers.add(
        Marker(
          markerId: MarkerId("myLocation"),
          position: LatLng(pos.latitude, pos.longitude),
        ),
      );
    });

    if (_mapController != null) {
      _mapController?.animateCamera
        (CameraUpdate.newLatLngZoom(_currentLocation, 18),
      );
    }
  }
  Future<void> _loadVehicles() async {
    String userId = "";
    try {
      userId = context.read<UserDataService>().userdata!.userID;

      setState(() {
        _isLoading_Vehicles = true;
      });

      final vehiclesSnapshot = await _firestore
          .collection(CollectionUsers)
          .doc(userId)
          .collection(CollectionMonitors)
          .where('type',isEqualTo: MonTypeVehicle)
          .get();

      if(vehiclesSnapshot.docs.isNotEmpty){
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
          _isLoading_Vehicles = false;
        });
      }
      else{
        setState(() {
          _isLoading_Vehicles = false;
        });
      }

    } catch (e) {
      setState(() {
        _isLoading_Vehicles = false;
      });
      MyGlobalSnackBar.show('Error loading vehicles: $e\nUserID: $userId');
    }
  }
  void _initTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }
  Future<void> _startTracking() async {
    if (_selectedVehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a vehicle first')),
      );
      return;
    }

    try {
      await LocationService.requestPermissions();
      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        final requestPermission = await Geolocator.requestPermission();
        if (requestPermission == LocationPermission.denied ||
            requestPermission == LocationPermission.deniedForever) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
          _isTracking = false;
          return;
        }
      }

      setState(() {
        _isTracking = true;
        _trackingPathRed = [];
        _trackingPathGreen = [];
        _newTrackingStarted = true;
        _pathPolyline = {};
      });


      // Start position tracking Listener
      // This will fire onPostionUpdate every 5m traveled
      //await LocationService.startLocationTracking();
      _startPositionTracking();

      if(_isVoicePromptOn)  _flutterTts.speak('Tracking Started. Waiting for First Movement');

      setState(() {
        _statusMessage = "Tracking";
      });

      MyGlobalSnackBar.show('Tracking started');

    } catch (e) {
      MyGlobalSnackBar.show('Error Starting Tracking: $e');

    }
  }
  void _startPositionTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilter, // Update every 10 meters (Set in Settings)
      ),
    ).listen(_onPositionUpdate);

    // FlutterBackgroundService().on('locationUpdate').listen((event) {
    //   if (event != null) {
    //     final latitude = event['latitude'] as double?;
    //     final longitude = event['longitude'] as double?;
    //     final timestamp = event['timestamp'] as String?;
    //
    //     if (latitude != null && longitude != null) {
    //       _onPositionUpdate(latLngToPosition(LatLng(latitude, longitude)));
    //     }
    //   }
    // });
  }
  void _onPositionUpdate(Position position) async {
    bool insideAny = false;
    LatLng previousPosition;
    double distance = 0;

    setState(() {
      _currentPosition = position;
    });

    // Add to tracking path
    final currentLatLng = LatLng(position.latitude, position.longitude);

    // Move camera to current position
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(currentLatLng),
    );

    // Check if inside any geofence
    for (var geofence in _geofenceList) {
      final bool isInside = isPointInsidePolygon(
          currentLatLng, geofence.points);

      if (isInside) {
        _trackingPathGreen.add(currentLatLng);
      } else {
        _trackingPathRed.add(currentLatLng);
      }
      insideAny = insideAny || isInside;

      // Calculate distances and check if inside any geofence
      if (_trackingPathRed.length >= 2 ||  _trackingPathGreen.length >= 2) {

        if(insideAny){
          // Inside
          previousPosition = _trackingPathGreen[_trackingPathGreen.length - 2];
          distance = Geolocator.distanceBetween(
            previousPosition.latitude,
            previousPosition.longitude,
            currentLatLng.latitude,
            currentLatLng.longitude,
          ) / 1000; // Convert to kilometers
        }else{
          // Outside
          previousPosition = _trackingPathRed[_trackingPathRed.length - 2];
          distance = Geolocator.distanceBetween(
            previousPosition.latitude,
            previousPosition.longitude,
            currentLatLng.latitude,
            currentLatLng.longitude,
          ) / 1000; // Convert to kilometers
        }

        // Create tracking session in Firebase only
        // once first movement was detected
        if (_newTrackingStarted) {
          if(distance == 0) return;

          _newTrackingStarted = false;
          if(_isVoicePromptOn) _flutterTts.speak('Movement Detected');

          final userId = context.read<UserDataService>().userdata!.userID;

          final sessionRef = await _firestore
              .collection(CollectionUsers)
              .doc(userId)
              .collection(CollectionTrackingSessions)
              .add({
            'vehicle_id': _selectedVehicleId,
            'start_time': FieldValue.serverTimestamp(),
            'is_active': true,
            'distance_inside': 0.0,
            'distance_outside': 0.0,
          });
          _trackingSessionId = sessionRef.id;
        }

        if (_trackingSessionId == null) return;
        // Changed barriers (in or our fences)
        // Check if status changed (entered or exited geofence)
        if (isInside != _insideGeofence[geofence.firestoreId]) {
          _insideGeofence[geofence.firestoreId] = isInside;

          // Update polyline on map
          setState(() {
            _pathPolyline = {
              Polyline(
                polylineId: const PolylineId('tracking_path_red'),
                points: _trackingPathRed,
                color: Colors.red,
                width: 5,
              ),
              Polyline(
                polylineId: const PolylineId('tracking_path_green'),
                points: _trackingPathGreen,
                color: Colors.green,
                width: 5,
              ),
            };
          });

          // Voice Prompt
          if (_isVoicePromptOn) {
            if (isInside) {
              _flutterTts.speak('Entering ${geofence.name}');
            } else {
              _flutterTts.speak('Exiting ${geofence.name}');
            }
          }
        }
      }

      // Update tracking session with new data
      final userId = context.read<UserDataService>().userdata!.userID;

      final batch = _firestore.batch();
      final trackingRef = _firestore
          .collection(CollectionUsers)
          .doc(userId)
          .collection(CollectionTrackingSessions)
          .doc(_trackingSessionId);

      final locationRef = trackingRef.collection('locations').doc();

      // Ensure the session exists
      await trackingRef.set({
        'distance_inside': 0,
        'distance_outside': 0,
        'started_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(locationRef, {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'inside_geofence': insideAny,
        'distance_from_last': distance,
      });

      batch.update(trackingRef, {
        insideAny ? 'distance_inside' : 'distance_outside':
        FieldValue.increment(distance),
      });

      await batch.commit();

      // Update status message
      setState(() {
        _statusMessage = insideAny
            ? "Inside geofence"
            : "Outside geofence";
      });
    }
  }
  Future<void> _stopTracking({bool fromDispose = false}) async {

    if (_trackingSessionId == null) {
      if (!fromDispose && mounted) {
        setState(() {
          _isTracking = false;
          _statusMessage = "Stop";
        });
      }
      return;
    }

    if (!fromDispose && mounted) {
      setState(() {
        _isTracking = false;
        _statusMessage = "Stop";
      });
    }

    try {
      await LocationService.stopLocationTracking();
      final userId = context.read<UserDataService>().userdata!.userID;

      await _firestore
          .collection(CollectionUsers)
          .doc(userId)
          .collection(CollectionTrackingSessions)
          .doc(_trackingSessionId)
          .update({
        'is_active': false,
        'end_time': FieldValue.serverTimestamp(),
      });

      if (!fromDispose && mounted) {
        setState(() {
          _trackingSessionId = null;
          _statusMessage = "Tracking stopped";
        });

        if (_isVoicePromptOn) {
          _flutterTts.speak('Tracking Stopped');
        }
        MyGlobalSnackBar.show('Tracking stopped');
      }
    } catch (e) {
      if (!fromDispose && mounted) {
        MyGlobalSnackBar.show('Error stopping tracking: $e');
      }

    // } finally {
    //   if (!fromDispose && mounted) {
    //     setState(() {
    //       _isLoading_Geofence = false;
    //     });
    //   }
    }
  }
  Widget _buildVehicleSelector() {
    return Card(
      color: APP_TILE_COLOR,
      margin: const EdgeInsets.all(5.0),
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            _vehicles.isEmpty
                ? const Text('No vehicles found. Please add a vehicle',
                    style: TextStyle(color: Colors.grey),
                )

                : DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedVehicleId,
                  hint: const Text(
                  'Select a vehicle',
                  style: TextStyle(color: Colors.grey),
                ),

              onChanged: (newValue) {
                setState(() {
                  _selectedVehicleId = newValue;
                });
              },
              items: _vehicles.map((vehicle) {
                return DropdownMenuItem<String>(
                  value: vehicle['id'],
                  child: Text('${vehicle['name']} (${vehicle['registrationNumber']})',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
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
    if(index == 2) {
      _isTracking ? _stopTracking() : _startTracking();
    }
}

  @override
  Widget build(BuildContext context) {

    if(_isLoading_Vehicles || _isLoading_Geofence){
      return MyProgressCircle();
    }

    // if (_vehicles.isEmpty) {
    //   return Center(
    //     child: MyText(
    //       text: "No Vehicles Found",
    //       color: Colors.grey,
    //     ),
    //   );
    // }

    return Scaffold(
      backgroundColor: APP_BACKGROUND_COLOR,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: _isTracking ? Colors.redAccent : APP_BAR_COLOR,
        title: MyAppbarTitle(_statusMessage),
      ),
      bottomNavigationBar: BottomNavigationBar(
          onTap: _onBotBarTap,
          backgroundColor: APP_BAR_COLOR,
          unselectedItemColor: Colors.grey,
          selectedItemColor: Colors.grey,
          items: [
            MyBottomNavItem(icon: Icons.navigate_next,label: "GeoFence"),
            MyBottomNavItem(icon: Icons.refresh,label: "Refresh" ),
            BottomNavigationBarItem(
                icon: _isTracking
                ? Icon(Icons.location_off, size: 35, color: Colors.red)
                : Icon(Icons.location_on, size: 35, color: Colors.white),
            label: (_trackingSessionId == null) ? "Track" : "Stop"
            ),
          ]
      ),
      body: _vehicles.isEmpty
          ? MyCenterMsg('No Vehicles Found')
          : Stack(
        children: [
          Column(
            children: [
              _buildVehicleSelector(),
              SizedBox(height: 5),

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
        ],
      ),
    );
  }
}
