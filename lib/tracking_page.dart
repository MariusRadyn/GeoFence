import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'gps_services.dart';

class TrackingPage extends StatefulWidget {

  const TrackingPage({
    super.key
  });

  @override
  TrackingPageState createState() => TrackingPageState();
}
class TrackingPageState extends State<TrackingPage> with WidgetsBindingObserver {
  late SettingsService settings;
  GoogleMapController? _mapController;
  // ignore: unused_field
  Position? _currentPosition;
  //final Set<Polygon> _geofences = {};
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};
  int _polygonIdCounter = 0;
  StreamSubscription<Position>? _positionStream;
  String _statusMessage = "Not tracking";
  final List<FenceData> _geofenceList = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  //final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isLoadingGeofence = true;
  bool _isLoadingVehicles = true;
  bool _isTracking = false;
  final Map<String, bool> _insideGeofence = {};
  String? _selectedVehicleId;
  List<Map<String, dynamic>> _vehicles = [];
  String? _trackingSessionId;
  List<LatLng> _trackingPathRed = [];
  List<LatLng> _trackingPathGreen = [];
  Set<Polyline> _pathPolyline = {};
  LatLng? _lastTrackedLatLng;
  bool _wasInsideAny = false;
  double _pendingInsideKm = 0;
  double _pendingOutsideKm = 0;
  LatLng _currentLocation = const LatLng(-29.6, 30.3);
  int _fencePntr = 0;
  int _distanceFilter = 0;
  bool _isVoicePromptOn = false;
  /// When true, map uses satellite imagery (same toggle as GeoFence "Street").
  bool _isStreetView = false;

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

      if (_vehicles.isEmpty && !_isLoadingVehicles) {
        MyGlobalMessage.show(
          "Vehicle Not Found",
          "No Vehicles Found.\nPlease set one in 'IOT Devices'",
            MyMessageType.warning
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
      _isLoadingGeofence = true;
      _polygons.clear();
      _markers.clear();
    });

    try {
      final user = context.read<UserDataService>();

      final geoFencesSnapshot = await firestore
          .collection(collectionUsers)
          .doc(user.userdata!.userID)
          .collection(collectionGeoFences)
          .get();

      final newMarkers = <Marker>{};
      final newPolygons = <Polygon>{};
      final newFences = <FenceData>[];

      for (var doc in geoFencesSnapshot.docs) {
        final data = doc.data();
        final type = '${data[fireGeoType] ?? geoFenceTypePolygon}';
        final isCircle = type == geoFenceTypeCircle;
        final pointsRaw = data[fireGeoPoints];
        if (pointsRaw is! List || pointsRaw.isEmpty) continue;

        final polygonPoints = List<GeoPoint>.from(pointsRaw)
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();

        if (polygonPoints.length < 3) continue;

        final polygonId = '$geoFencePolygon$_polygonIdCounter';
        final markerId = '$geoFenceMarker${_polygonIdCounter++}';

        LatLng? center;
        double? radiusMeters;
        if (isCircle) {
          final c = data[fireGeoCenter];
          if (c is GeoPoint) {
            center = LatLng(c.latitude, c.longitude);
          }
          final r = data[fireGeoRadiusMeters];
          if (r is num) radiusMeters = r.toDouble();
        }

        final name = '${data[fireGeoName] ?? data['name'] ?? ''}';
        final labelPos = isCircle && center != null
            ? center
            : calculateCentroid(polygonPoints);
        final labelIcon = await fenceNameLabelIcon(name);

        newMarkers.add(
          Marker(
            icon: labelIcon,
            anchor: const Offset(0.5, 0.5),
            markerId: MarkerId(markerId),
            position: labelPos,
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
          type: isCircle ? geoFenceTypeCircle : geoFenceTypePolygon,
          center: center,
          radiusMeters: radiusMeters,
        ));
      }

      if (!mounted) return;
      setState(() {
        _markers.addAll(newMarkers);
        _polygons.addAll(newPolygons);
        _geofenceList.addAll(newFences);
      });

      // Focus map on user's location if available
      final userDoc = await firestore
          .collection(collectionUsers)
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
      if (mounted) {
        setState(() {
          _isLoadingGeofence = false;
        });
      }
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
        _isLoadingVehicles = true;
      });

      final basesSnapshot = await _firestore
          .collection(collectionUsers)
          .doc(userId)
          .collection(collectionBaseStations)
          .get();

      List<Map<String, dynamic>> vehicles = [];

      for (final baseDoc in basesSnapshot.docs) {
        final vehiclesSnapshot = await baseDoc.reference
            .collection(collectionMonitors)
            .where(fireMonitorType, isEqualTo: monitorTypeVehicle)
            .get();

        for (var doc in vehiclesSnapshot.docs) {
          final data = doc.data();
          vehicles.add({
            'id': doc.id,
            'name': data[fireMonitorName] ?? 'Unknown Vehicle',
            'registrationNumber': data[fireMonitorReg] ?? '',
            'fuelConsumption': data[fireMonitorFuelConsumption] ?? 0.0,
          });
        }
      }

      if (vehicles.isNotEmpty) {
        setState(() {
          _vehicles = vehicles;
          _selectedVehicleId = vehicles[0]['id'];
          _isLoadingVehicles = false;
        });
      } else {
        setState(() {
          _isLoadingVehicles = false;
        });
      }

    } catch (e) {
      setState(() {
        _isLoadingVehicles = false;
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
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        MyGlobalMessage.show(
          'Location off',
          'Turn on GPS / location services, then try again.',
          MyMessageType.warning,
        );
        return;
      }

      await LocationService.requestPermissions();
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        MyGlobalMessage.show(
          'Location permission',
          permission == LocationPermission.deniedForever
              ? 'Location is blocked. Enable it in Android Settings → Apps → Limitless → Permissions.'
              : 'Location permission is required to track.',
          MyMessageType.warning,
        );
        return;
      }

      // Refresh distance filter from latest settings.
      if (mounted && settings.fireSettings != null) {
        _distanceFilter = settings.fireSettings!.logPointPerMeter;
        _isVoicePromptOn = settings.fireSettings!.isVoicePromptOn;
      }
      // Avoid a zero/negative filter that can behave oddly on some devices.
      if (_distanceFilter < 0) _distanceFilter = 0;

      setState(() {
        _isTracking = true;
        _trackingPathRed = [];
        _trackingPathGreen = [];
        _pathPolyline = {};
        _lastTrackedLatLng = null;
        _insideGeofence.clear();
        _wasInsideAny = false;
        _pendingInsideKm = 0;
        _pendingOutsideKm = 0;
        _statusMessage = 'Starting…';
      });

      if (!mounted) return;
      final userId = context.read<UserDataService>().userdata!.userID;
      final sessionRef = await _firestore
          .collection(collectionUsers)
          .doc(userId)
          .collection(collectionTrackingSessions)
          .add({
        fireTrackingVehicleDocId: _selectedVehicleId,
        fireTrackingStartTime: FieldValue.serverTimestamp(),
        fireTrackingIsActive: true,
        fireTrackingDistanceInside: 0.0,
        fireTrackingDistanceOutside: 0.0,
      });
      _trackingSessionId = sessionRef.id;

      // Seed immediately so the path/camera update without waiting for movement.
      try {
        final first = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        _onPositionUpdate(first);
      } catch (e) {
        printDebugMsg('Initial GPS fix failed: $e');
      }

      _startPositionTracking();

      if (_isVoicePromptOn) {
        _flutterTts.speak('Tracking started. Watching for geofence crossings');
      }

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Tracking';
      });

      MyGlobalSnackBar.show('Tracking started');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTracking = false;
          _trackingSessionId = null;
          _statusMessage = 'Not tracking';
        });
      }
      MyGlobalSnackBar.show('Error Starting Tracking: $e');
    }
  }

  LocationSettings _trackingLocationSettings() {
    final filter = _distanceFilter < 0 ? 0 : _distanceFilter;

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: filter,
        intervalDuration: const Duration(seconds: 3),
        forceLocationManager: false,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: filter,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: filter,
    );
  }

  void _startPositionTracking() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: _trackingLocationSettings(),
    ).listen(
      _onPositionUpdate,
      onError: (Object e) {
        printDebugMsg('Position stream error: $e');
        if (!mounted) return;
        setState(() {
          _statusMessage = 'GPS error';
        });
        MyGlobalSnackBar.show('GPS error: $e');
      },
    );
  }

  Future<void> _flushPendingDistance() async {
    if (_trackingSessionId == null || !mounted) return;

    if (_pendingInsideKm <= 0 && _pendingOutsideKm <= 0) return;

    final userId = context.read<UserDataService>().userdata!.userID;
    final updates = <String, dynamic>{};
    if (_pendingInsideKm > 0) {
      updates[fireTrackingDistanceInside] =
          FieldValue.increment(_pendingInsideKm);
      _pendingInsideKm = 0;
    }
    if (_pendingOutsideKm > 0) {
      updates[fireTrackingDistanceOutside] =
          FieldValue.increment(_pendingOutsideKm);
      _pendingOutsideKm = 0;
    }

    await _firestore
        .collection(collectionUsers)
        .doc(userId)
        .collection(collectionTrackingSessions)
        .doc(_trackingSessionId)
        .update(updates);
  }

  Future<void> _saveGeofenceCrossing({
    required Position position,
    required FenceData geofence,
    required String event,
    required bool insideAny,
    double? distanceKm,
  }) async {
    if (_trackingSessionId == null || !mounted) return;

    final userId = context.read<UserDataService>().userdata!.userID;
    final payload = <String, dynamic>{
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': FieldValue.serverTimestamp(),
      fireGeoCrossingFenceId: geofence.firestoreId,
      fireGeoCrossingFenceName: geofence.name,
      fireGeoCrossingEvent: event,
      'inside_geofence': insideAny,
    };
    if (distanceKm != null && distanceKm > 0) {
      payload[fireGeoCrossingDistanceKm] = distanceKm;
    }

    await _firestore
        .collection(collectionUsers)
        .doc(userId)
        .collection(collectionTrackingSessions)
        .doc(_trackingSessionId)
        .collection(collectionLocations)
        .add(payload);
  }
  Set<Polyline> _buildPathPolylines() {
    return {
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
  }

  void _onPositionUpdate(Position position) async {
    if (!mounted) return;

    final currentLatLng = LatLng(position.latitude, position.longitude);

    setState(() {
      _currentPosition = position;
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLng(currentLatLng),
    );

    final fenceInside = <String, bool>{};
    var insideAny = false;
    for (final geofence in _geofenceList) {
      final inside = isPointInsideGeofence(currentLatLng, geofence);
      fenceInside[geofence.firestoreId] = inside;
      insideAny = insideAny || inside;
    }

    if (insideAny) {
      _trackingPathGreen.add(currentLatLng);
    } else {
      _trackingPathRed.add(currentLatLng);
    }

    if (_lastTrackedLatLng == null) {
      for (final geofence in _geofenceList) {
        _insideGeofence[geofence.firestoreId] =
            fenceInside[geofence.firestoreId]!;
      }
      _wasInsideAny = insideAny;
      _lastTrackedLatLng = currentLatLng;

      setState(() {
        _pathPolyline = _buildPathPolylines();
        _statusMessage =
            insideAny ? 'Inside geofence' : 'Outside geofence';
      });
      return;
    }

    final stepKm = Geolocator.distanceBetween(
      _lastTrackedLatLng!.latitude,
      _lastTrackedLatLng!.longitude,
      currentLatLng.latitude,
      currentLatLng.longitude,
    ) / 1000;

    if (stepKm > 0) {
      if (_wasInsideAny) {
        _pendingInsideKm += stepKm;
      } else {
        _pendingOutsideKm += stepKm;
      }
    }

    final transitionedInside = insideAny != _wasInsideAny;
    final exitingAllFences = _wasInsideAny && !insideAny;
    final insideSegmentKm = exitingAllFences ? _pendingInsideKm : null;
    _lastTrackedLatLng = currentLatLng;

    if (_trackingSessionId == null) {
      _wasInsideAny = insideAny;
      setState(() {
        _pathPolyline = _buildPathPolylines();
        _statusMessage = insideAny ? 'Inside geofence' : 'Outside geofence';
      });
      return;
    }

    for (final geofence in _geofenceList) {
      final isInside = fenceInside[geofence.firestoreId]!;
      final wasInside = _insideGeofence[geofence.firestoreId] ?? isInside;
      if (isInside == wasInside) continue;

      _insideGeofence[geofence.firestoreId] = isInside;
      final event =
          isInside ? fireGeoCrossingEnter : fireGeoCrossingExit;

      if (_isVoicePromptOn) {
        if (isInside) {
          _flutterTts.speak('Entering ${geofence.name}');
        } else {
          _flutterTts.speak('Exiting ${geofence.name}');
        }
      }

      await _saveGeofenceCrossing(
        position: position,
        geofence: geofence,
        event: event,
        insideAny: insideAny,
        distanceKm: event == fireGeoCrossingExit && !insideAny
            ? insideSegmentKm
            : null,
      );
    }

    if (transitionedInside) {
      await _flushPendingDistance();
    }

    _wasInsideAny = insideAny;

    if (!mounted) return;
    setState(() {
      _pathPolyline = _buildPathPolylines();
      _statusMessage = insideAny ? 'Inside geofence' : 'Outside geofence';
    });
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
      await _positionStream?.cancel();
      _positionStream = null;
      await LocationService.stopLocationTracking();
      if(!mounted) return;
      await _flushPendingDistance();
      if(!mounted) return;
      final userId = context.read<UserDataService>().userdata!.userID;

      await _firestore
          .collection(collectionUsers)
          .doc(userId)
          .collection(collectionTrackingSessions)
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
  Widget _buildVehicleDropdown() {
    if (_vehicles.isEmpty) {
      return const SizedBox.shrink();
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        isExpanded: true,
        isDense: true,
        value: _selectedVehicleId,
        dropdownColor: colorAppBar,
        hint: const Text(
          'Select a vehicle',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        iconEnabledColor: Colors.white,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontFamily: 'Poppins',
        ),
        onChanged: _isTracking
            ? null
            : (newValue) {
                setState(() {
                  _selectedVehicleId = newValue;
                });
              },
        items: _vehicles.map((vehicle) {
          return DropdownMenuItem<String>(
            value: vehicle['id'],
            child: Text(
              '${vehicle['name']} (${vehicle['registrationNumber']})',
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }

  PreferredSizeWidget _buildTrackingAppBar() {
    return AppBar(
      foregroundColor: Colors.white,
      backgroundColor: _isTracking ? Colors.redAccent : colorAppBar,
      title: _vehicles.isEmpty
          ? myAppbarTitle(_statusMessage)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildVehicleDropdown(),
                const SizedBox(height: 2),
                Text(
                  _statusMessage,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontFamily: 'Poppins',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
    );
  }
  void _toggleStreetView() {
    setState(() => _isStreetView = !_isStreetView);
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
    if (index == 0) {
      _toggleStreetView();
      return;
    }
    if (index == 1) {
      _nextFence();
      return;
    }
    if (index == 2) {
      // Refresh geofences + location
      _loadGeoFences();
      _getLocation();
      return;
    }
    if (index == 3) {
      _isTracking ? _stopTracking() : _startTracking();
    }
  }

  @override
  Widget build(BuildContext context) {

    if(_isLoadingVehicles || _isLoadingGeofence){
      return myProgressCircle();
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
      backgroundColor: colorAppBackground,
      appBar: _buildTrackingAppBar(),
      bottomNavigationBar: BottomNavigationBar(
          onTap: _onBotBarTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: colorAppBar,
          unselectedItemColor: Colors.grey,
          selectedItemColor: Colors.grey,
          items: [
            MyBottomNavItem(
              icon: _isStreetView ? Icons.map : Icons.streetview,
              label: 'Street',
            ),
            MyBottomNavItem(icon: Icons.navigate_next, label: 'GeoFence'),
            MyBottomNavItem(icon: Icons.refresh, label: 'Refresh'),
            BottomNavigationBarItem(
                icon: _isTracking
                ? Icon(Icons.location_off, size: 35, color: Colors.red)
                : Icon(Icons.location_on, size: 35, color: Colors.white),
            label: (_trackingSessionId == null) ? "Track" : "Stop"
            ),
          ]
      ),
      body: _vehicles.isEmpty
          ? myCenterMsg('No Vehicles Found')
          : GoogleMap(
              initialCameraPosition: _initialPosition,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              mapType: _isStreetView ? MapType.satellite : MapType.normal,
              markers: _markers,
              polygons: _polygons,
              polylines: _pathPolyline,
              onMapCreated: (controller) {
                _mapController = controller;
              },
            ),
    );
  }
}
