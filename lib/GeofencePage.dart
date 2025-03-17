// Geo Fence Screen
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geofence/firebase.dart';
import 'package:geofence/gpsServices.dart';
import 'package:geofence/utils.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


class GeoFenceScreen extends StatefulWidget {
  const GeoFenceScreen({Key? key}) : super(key: key);

  @override
  _GeoFenceScreenState createState() => _GeoFenceScreenState();
}

class _GeoFenceScreenState extends State<GeoFenceScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};
  Set<Marker> _geoMarkers = {};
  final List<LatLng> _currentPolygonPoints = [];
  final TextEditingController _geoFenceNameController = TextEditingController();
  bool _isDrawing = false;
  bool _isEditing = false;
  String? _editingFenceId;
  bool _isLoading = false;
  int _polygonIdCounter = 0;
  LatLng currentLocation = LatLng(-29.6, 30.3);

  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(-29.0, 24.0), // Default to South Africa
    zoom: 6.0,
  );

  @override
  void initState() {
    super.initState();
    _loadGeoFences();
    _getLocation();
  }

  @override
  void dispose() {
    _geoFenceNameController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

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

    if(_mapController != null) {
        _mapController?.animateCamera
          (CameraUpdate.newLatLngZoom(currentLocation!, 16),
        );
    }
  }

  Future<void> _loadGeoFences() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = userData.userID;// firebaseAuthService. _auth.currentUser!.uid;
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

            setState(() {
              // Add marker for the label
              _markers.add(
                Marker(
                  markerId: MarkerId('marker_$polygonId'),
                  position: _calculateCentroid(polygonPoints),
                  infoWindow: InfoWindow(title: data['name']),
                ),
              );

              // Add polygon
              _polygons.add(
                Polygon(
                  polygonId: PolygonId(polygonId),
                  points: polygonPoints,
                  strokeWidth: 2,
                  strokeColor: Colors.blue,
                  fillColor: Colors.blue.withOpacity(0.3),
                  consumeTapEvents: true,
                  onTap: () => _showPolygonOptions(polygonId, doc.id, data['name'], polygonPoints),
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

  LatLng _calculateCentroid(List<LatLng> points) {
    double latitude = 0;
    double longitude = 0;

    for (var point in points) {
      latitude += point.latitude;
      longitude += point.longitude;
    }

    return LatLng(latitude / points.length, longitude / points.length);
  }

  void _onMapTap(LatLng position) {
    if (!_isDrawing) return;

    setState(() {
      _currentPolygonPoints.add(position);
      _markers.add(
        Marker(
          markerId: MarkerId('point_${_currentPolygonPoints.length}'),
          position: position,

        ),
      );

      // If more than one point, draw lines
      if (_currentPolygonPoints.length > 1) {
        _polygons.removeWhere(
              (polygon) => polygon.polygonId.value == 'drawing_polygon',
        );

        _polygons.add(
          Polygon(
            polygonId: const PolygonId('drawing_polygon'),
            points: _currentPolygonPoints,
            strokeWidth: 2,
            strokeColor: Colors.red,
            fillColor: Colors.red.withOpacity(0.3),
          ),
        );
      }
    });
  }

  void _startDrawing() {
    setState(() {
      _isDrawing = true;
      _isEditing = false;
      _editingFenceId = null;
      _currentPolygonPoints.clear();
      _markers.removeWhere((marker) =>
          marker.markerId.value.startsWith('point_'));
      _polygons.removeWhere((polygon) =>
      polygon.polygonId.value == 'drawing_polygon');
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tap on the map to add points to your geo fence')),
    );
  }

  void _saveGeoFence() async {
    if (_currentPolygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least 3 points to create a geo fence')),
      );
      return;
    }

    _geoFenceNameController.text = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name your Geo Fence'),
        content: TextField(
          controller: _geoFenceNameController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_geoFenceNameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a name for your geo fence')),
                );
                return;
              }

              Navigator.pop(context);
              await _saveGeoFenceToFirebase(_geoFenceNameController.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveGeoFenceToFirebase(String name) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = userData.userID; // _auth.currentUser!.uid;
      final geoPointsList = _currentPolygonPoints
          .map((point) => GeoPoint(point.latitude, point.longitude))
          .toList();

      // Get the document to update or create new one
      final docRef = _editingFenceId != null
          ? firestore.collection('users').doc(userId).collection('geofences').doc(_editingFenceId)
          : firestore.collection('users').doc(userId).collection('geofences').doc();

      await docRef.set({
        'name': name,
        'points': geoPointsList,
        'createdAt': _editingFenceId != null ? FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Geo fence "$name" saved successfully')),
      );

      setState(() {
        _isDrawing = false;
        _isEditing = false;
        _editingFenceId = null;
        _currentPolygonPoints.clear();
        _markers.removeWhere((marker) => marker.markerId.value.startsWith('point_'));
        _polygons.removeWhere((polygon) => polygon.polygonId.value == 'drawing_polygon');
      });

      // Reload all geo fences
      await _loadGeoFences();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving geo fence: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _cancelDrawing() {
    setState(() {
      _isDrawing = false;
      _isEditing = false;
      _editingFenceId = null;
      _currentPolygonPoints.clear();
      _markers.removeWhere((marker) => marker.markerId.value.startsWith('point_'));
      _polygons.removeWhere((polygon) => polygon.polygonId.value == 'drawing_polygon');
    });
  }

  void _showPolygonOptions(String polygonId, String firestoreId, String name, List<LatLng> points) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit Geo Fence'),
            onTap: () {
              Navigator.pop(context);
              _editGeoFence(firestoreId, name, points);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete Geo Fence'),
            onTap: () {
              Navigator.pop(context);
              _deleteGeoFence(firestoreId, name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.streetview),
            title: const Text('Switch to Street View'),
            onTap: () {
              Navigator.pop(context);
              _openStreetView(_calculateCentroid(points));
            },
          ),
        ],
      ),
    );
  }

  void _editGeoFence(String firestoreId, String name, List<LatLng> points) {
    setState(() {
      _isEditing = true;
      _isDrawing = true;
      _editingFenceId = firestoreId;
      _currentPolygonPoints.clear();
      _currentPolygonPoints.addAll(points);
      _geoFenceNameController.text = name;

      _markers.removeWhere((marker) => marker.markerId.value.startsWith('point_'));
      _polygons.removeWhere((polygon) => polygon.polygonId.value == 'drawing_polygon');

      // Add markers for each point
      for (int i = 0; i < points.length; i++) {
        _markers.add(
          Marker(
            markerId: MarkerId('point_${i + 1}'),
            position: points[i],
          ),
        );
      }

      // Add polygon
      _polygons.add(
        Polygon(
          polygonId: const PolygonId('drawing_polygon'),
          points: _currentPolygonPoints,
          strokeWidth: 2,
          strokeColor: Colors.red,
          fillColor: Colors.red.withOpacity(0.3),
        ),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tap on the map to add or modify points')),
    );
  }

  Future<void> _deleteGeoFence(String firestoreId, String name) async {
    final bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      setState(() {
        _isLoading = true;
      });

      try {
        final userId = userData.userID;// _auth.currentUser!.uid;
        await firestore
            .collection('users')
            .doc(userId)
            .collection('geofences')
            .doc(firestoreId)
            .delete();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Geo fence "$name" deleted successfully')),
        );

        // Reload all geo fences
        await _loadGeoFences();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting geo fence: $e')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openStreetView(LatLng location) async {
    // final url = 'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${location.latitude},${location.longitude}';
    // if (await canLaunch(url)) {
    //   await launch(url);
    // } else {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(content: Text('Could not open Street View')),
    //   );
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geo Fence'),
        actions: [
          if (_isDrawing && _currentPolygonPoints.length >= 3)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveGeoFence,
            ),
          if (_isDrawing)
            IconButton(
              icon: const Icon(Icons.cancel),
              onPressed: _cancelDrawing,
            ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialPosition,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
            markers: _markers,
            polygons: _polygons,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onTap: _onMapTap,
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
      floatingActionButton: !_isDrawing
          ? FloatingActionButton(
        onPressed: _startDrawing,
        child: const Icon(Icons.edit),
      )
          : null,
    );
  }
}