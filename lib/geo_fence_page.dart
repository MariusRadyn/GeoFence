// Geo Fence Screen
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geofence/gps_services.dart';
import 'package:geofence/utils.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

enum BottomBarMode { normal, addingGeoFence, selectedFence }
enum GeoFenceDrawShape { polygon, circle }

class _GeoFenceDrawSnapshot {
  final List<LatLng> points;
  final LatLng? circleCenter;
  final double circleRadiusMeters;
  final bool circleCenterPlaced;

  const _GeoFenceDrawSnapshot({
    required this.points,
    this.circleCenter,
    required this.circleRadiusMeters,
    required this.circleCenterPlaced,
  });
}

class GeoFencePage extends StatefulWidget {
  const GeoFencePage({super.key});

  @override
  GeoFencePageState createState() => GeoFencePageState();
}

class GeoFencePageState extends State<GeoFencePage> {
  GoogleMapController? _mapController;
  final Set<Marker> _savedMarkers = {};
  final Set<Polygon> _savedPolygons = {};
  final Set<Circle> _savedCircles = {};
  final Set<Marker> _geoMarkers = {};
  final Map<String, FenceData> _loadedFences = {};

  final List<LatLng> _currentPolygonPoints = [];
  final TextEditingController _geoFenceNameController = TextEditingController();
  BottomBarMode _bottomBarMode = BottomBarMode.normal;

  bool _isDrawing = false;
  bool _isEditing = false;
  String? _editingFenceId;
  bool _isLoading = false;
  int _polygonIdCounter = 0;
  LatLng _currentLocation = const LatLng(-29.6, 30.3);
  bool _isStreetView = true;
  bool _isFirstOpen = true;
  bool _pendingInitialLocationZoom = false;
  int _fencePntr = 0;
  String _appBarTitle = 'GeoFence';
  FenceData fenceData = FenceData();

  GeoFenceDrawShape _drawShape = GeoFenceDrawShape.polygon;
  LatLng? _circleCenter;
  double _circleRadiusMeters = 100;
  bool _circleCenterPlaced = false;
  final List<_GeoFenceDrawSnapshot> _undoStack = [];

  @override
  void initState() {
    super.initState();

    if (mounted) {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    await _loadGeoFences();
    if (!mounted) return;
    await _getLocation(initial: true);
    _isFirstOpen = false;
  }

  @override
  void dispose() {
    _geoFenceNameController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(-29.0, 24.0),
    zoom: 6.0,
  );

  Set<Marker> get _mapMarkers =>
      {..._savedMarkers, ..._buildDrawMarkers(), ..._geoMarkers};

  Set<Polygon> get _mapPolygons => {..._savedPolygons, ..._buildDrawPolygons()};

  Set<Circle> get _mapCircles => {..._savedCircles, ..._buildDrawCircles()};

  Future<void> _getLocation({bool initial = false}) async {
    writeLog('GetLocation');
    final pos = await determinePosition();
    if (!mounted) return;

    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
      _geoMarkers
        ..clear()
        ..add(
          Marker(
            markerId: const MarkerId('myLocation'),
            position: LatLng(pos.latitude, pos.longitude),
          ),
        );
    });

    if (_mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_currentLocation, 18),
      );
      _pendingInitialLocationZoom = false;
    } else if (initial) {
      _pendingInitialLocationZoom = true;
    }
  }

  Future<BitmapDescriptor> _fenceNameLabelIcon(String name) =>
      fenceNameLabelIcon(name);

  Future<void> _loadGeoFences() async {
    final userData = context.read<UserDataService>().userdata;
    if (userData == null) return;

    final preserveDraw = _isDrawing;

    setState(() {
      _isLoading = true;
      if (!preserveDraw) {
        _savedPolygons.clear();
        _savedMarkers.clear();
        _savedCircles.clear();
        _loadedFences.clear();
      } else {
        _savedPolygons.clear();
        _savedMarkers.clear();
        _savedCircles.clear();
        _loadedFences.clear();
      }
    });

    try {
      final userId = userData.userID;
      final geoFencesSnapshot = await firestore
          .collection(collectionUsers)
          .doc(userId)
          .collection(collectionGeoFences)
          .get();

      final newMarkers = <Marker>{};
      final newPolygons = <Polygon>{};
      final newCircles = <Circle>{};
      final newFences = <String, FenceData>{};

      for (final doc in geoFencesSnapshot.docs) {
        final data = doc.data();
        final type = '${data[fireGeoType] ?? geoFenceTypePolygon}';
        final isCircle = type == geoFenceTypeCircle;
        final pointsRaw = data[fireGeoPoints];
        if (pointsRaw is! List || pointsRaw.isEmpty) continue;

        final polygonPoints = List<GeoPoint>.from(pointsRaw)
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();
        if (polygonPoints.length < 3) continue;

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

        final polygonId = '$geoFencePolygon$_polygonIdCounter';
        final markerId = '$geoFenceMarker${_polygonIdCounter++}';
        final labelPos = isCircle && center != null
            ? center
            : calculateCentroid(polygonPoints);
        final name = '${data[fireGeoName] ?? ''}';

        final fence = FenceData(
          polygonId: polygonId,
          firestoreId: doc.id,
          name: name,
          points: polygonPoints,
          type: isCircle ? geoFenceTypeCircle : geoFenceTypePolygon,
          center: center,
          radiusMeters: radiusMeters,
        );
        newFences[doc.id] = fence;

        final labelIcon = await _fenceNameLabelIcon(name);
        newMarkers.add(
          Marker(
            icon: labelIcon,
            anchor: const Offset(0.5, 0.5),
            markerId: MarkerId(markerId),
            position: labelPos,
            infoWindow: InfoWindow(
              title: name,
              snippet: isCircle && radiusMeters != null
                  ? 'Circle · ${radiusMeters.round()} m'
                  : 'Polygon',
            ),
            onTap: () => _onFenceLabelTap(fence),
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

        if (isCircle && center != null && radiusMeters != null) {
          newCircles.add(
            Circle(
              circleId: CircleId('$geoFenceSavedCircle$doc.id'),
              center: center,
              radius: radiusMeters,
              strokeWidth: 2,
              strokeColor: Colors.blue,
              fillColor: Colors.blue.withValues(alpha: 0.15),
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _savedMarkers
          ..clear()
          ..addAll(newMarkers);
        _savedPolygons
          ..clear()
          ..addAll(newPolygons);
        _savedCircles
          ..clear()
          ..addAll(newCircles);
        _loadedFences
          ..clear()
          ..addAll(newFences);
      });

      if (!_isDrawing && !_isFirstOpen) {
        final userDoc =
            await firestore.collection(collectionUsers).doc(userId).get();
        if (userDoc.exists && userDoc.data()!.containsKey('location')) {
          final location = userDoc.data()!['location'] as GeoPoint;
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(location.latitude, location.longitude),
            ),
          );
        }
      }
    } catch (e) {
      MyGlobalMessage.show('Error', '$e', MyMessageType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onFenceLabelTap(FenceData fence) {
    printDebugMsg('On Marker Tap: ${fence.name}');
    _selectFence(fence, zoom: false);
  }

  void _selectFence(FenceData fence, {bool zoom = true}) {
    setState(() {
      _bottomBarMode = BottomBarMode.selectedFence;
      fenceData = fence;
      _appBarTitle = 'Fence: ${fence.name}';
    });
    if (zoom) {
      _zoomToFence(fence);
    }
  }

  void _zoomToFence(FenceData fence) {
    _scheduleZoomToSavedFence(
      points: fence.points,
      center: fence.center,
      radiusMeters: fence.radiusMeters,
      isCircle: fence.isCircle,
    );
  }

  Future<void> _openGeoFenceList() async {
    if (_loadedFences.isEmpty) {
      MyGlobalSnackBar.show('No geo fences saved yet');
      return;
    }

    final fences = _loadedFences.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colorAppBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Geo Fences',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: fences.length,
                    itemBuilder: (context, index) {
                      final fence = fences[index];
                      final subtitle = fence.isCircle
                          ? 'Circle · ${(fence.radiusMeters ?? 0).round()} m'
                          : 'Polygon · ${fence.points.length} points';
                      return ListTile(
                        leading: Icon(
                          fence.isCircle
                              ? Icons.circle_outlined
                              : Icons.pentagon_outlined,
                          color: Colors.white,
                        ),
                        title: Text(
                          fence.name.isEmpty ? 'Unnamed fence' : fence.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          subtitle,
                          style: const TextStyle(color: Colors.white54),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (_bottomBarMode == BottomBarMode.addingGeoFence) {
                            _zoomToFence(fence);
                          } else {
                            _selectFence(fence);
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _clearFenceSelection() {
    if (_bottomBarMode != BottomBarMode.selectedFence) return;
    setState(() {
      _bottomBarMode = BottomBarMode.normal;
      _appBarTitle = 'GeoFence';
    });
  }

  Set<Marker> _buildDrawMarkers() {
    if (!_isDrawing) return {};

    final markers = <Marker>{};

    if (_drawShape == GeoFenceDrawShape.polygon) {
      for (var i = 0; i < _currentPolygonPoints.length; i++) {
        final idx = i;
        markers.add(
          Marker(
            markerId: MarkerId('$geoFencePoint$idx'),
            position: _currentPolygonPoints[i],
            draggable: true,
            onDrag: (pos) => _onVertexDrag(idx, pos),
          onDragEnd: (pos) => _onVertexDragEnd(idx, pos),
          ),
        );
      }
    } else if (_circleCenterPlaced && _circleCenter != null) {
      markers.add(
        Marker(
          markerId: const MarkerId(geoFenceCircleCenter),
          position: _circleCenter!,
          draggable: true,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          onDrag: (pos) => _onCircleCenterDrag(pos),
          onDragEnd: (pos) => _onCircleCenterDragEnd(pos),
        ),
      );
      final handle = destinationFromLatLng(
        _circleCenter!,
        _circleRadiusMeters,
        90,
      );
      markers.add(
        Marker(
          markerId: const MarkerId(geoFenceCircleRadius),
          position: handle,
          draggable: true,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          onDrag: (pos) => _onRadiusHandleDrag(pos),
          onDragEnd: (pos) => _onRadiusHandleDragEnd(pos),
        ),
      );
    }

    return markers;
  }

  Set<Polygon> _buildDrawPolygons() {
    if (!_isDrawing || _currentPolygonPoints.length < 3) return {};
    return {
      Polygon(
        polygonId: const PolygonId(geoFenceDrawingPolygon),
        points: _currentPolygonPoints,
        strokeWidth: 2,
        strokeColor: Colors.red,
        fillColor: Colors.red.withValues(alpha: 0.3),
      ),
    };
  }

  Set<Circle> _buildDrawCircles() {
    if (!_isDrawing ||
        _drawShape != GeoFenceDrawShape.circle ||
        !_circleCenterPlaced ||
        _circleCenter == null) {
      return {};
    }
    return {
      Circle(
        circleId: const CircleId(geoFenceDrawingCircle),
        center: _circleCenter!,
        radius: _circleRadiusMeters,
        strokeWidth: 2,
        strokeColor: Colors.red,
        fillColor: Colors.red.withValues(alpha: 0.25),
      ),
    };
  }

  _GeoFenceDrawSnapshot _captureDrawSnapshot() {
    return _GeoFenceDrawSnapshot(
      points: _currentPolygonPoints
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList(),
      circleCenter: _circleCenter == null
          ? null
          : LatLng(_circleCenter!.latitude, _circleCenter!.longitude),
      circleRadiusMeters: _circleRadiusMeters,
      circleCenterPlaced: _circleCenterPlaced,
    );
  }

  void _restoreDrawSnapshot(_GeoFenceDrawSnapshot snap) {
    _currentPolygonPoints
      ..clear()
      ..addAll(snap.points);
    _circleCenter = snap.circleCenter;
    _circleRadiusMeters = snap.circleRadiusMeters;
    _circleCenterPlaced = snap.circleCenterPlaced;
  }

  void _resetUndoHistory() {
    _undoStack
      ..clear()
      ..add(_captureDrawSnapshot());
  }

  void _recordDrawState() {
    _undoStack.add(_captureDrawSnapshot());
  }

  void _onVertexDrag(int index, LatLng pos) {
    setState(() {
      _currentPolygonPoints[index] = pos;
    });
  }

  void _onVertexDragEnd(int index, LatLng pos) {
    setState(() {
      _currentPolygonPoints[index] = pos;
    });
    _recordDrawState();
  }

  void _onCircleCenterDrag(LatLng pos) {
    setState(() {
      _circleCenter = pos;
      _rebuildCircleRing();
    });
  }

  void _onCircleCenterDragEnd(LatLng pos) {
    setState(() {
      _circleCenter = pos;
      _rebuildCircleRing();
    });
    _recordDrawState();
  }

  void _onRadiusHandleDrag(LatLng pos) {
    if (_circleCenter == null) return;
    final dist = Geolocator.distanceBetween(
      _circleCenter!.latitude,
      _circleCenter!.longitude,
      pos.latitude,
      pos.longitude,
    );
    setState(() {
      _circleRadiusMeters = dist.clamp(10, 50000);
      _rebuildCircleRing();
    });
  }

  void _onRadiusHandleDragEnd(LatLng pos) {
    _onRadiusHandleDrag(pos);
    _recordDrawState();
  }

  void _rebuildCircleRing() {
    if (_circleCenter == null) return;
    _currentPolygonPoints
      ..clear()
      ..addAll(circlePolygonRing(_circleCenter!, _circleRadiusMeters));
  }

  void _onMapTap(LatLng position) {
    if (_bottomBarMode == BottomBarMode.selectedFence) {
      _clearFenceSelection();
      return;
    }
    if (!_isDrawing) return;

    if (_drawShape == GeoFenceDrawShape.circle) {
      if (!_circleCenterPlaced) {
        setState(() {
          _circleCenter = position;
          _circleCenterPlaced = true;
          _circleRadiusMeters = 100;
          _rebuildCircleRing();
        });
        _recordDrawState();
        MyGlobalSnackBar.show(
          'Drag the orange handle to set radius, then Save',
        );
      }
      return;
    }

    setState(() {
      _currentPolygonPoints.add(position);
    });
    _recordDrawState();
  }

  void _nextFence() {
    if (_savedMarkers.isEmpty) return;

    setState(() {
      _fencePntr = (_fencePntr + 1) % _savedMarkers.length;
      final marker = _savedMarkers.elementAt(_fencePntr);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(marker.position, 18),
      );
    });
  }

  Future<GeoFenceDrawShape?> _pickDrawShape() async {
    return showModalBottomSheet<GeoFenceDrawShape>(
      context: context,
      backgroundColor: colorAppBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose fence shape',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.pentagon_outlined, color: Colors.white),
                  title: const Text(
                    'Polygon',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Tap corners on the map',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(ctx, GeoFenceDrawShape.polygon),
                ),
                ListTile(
                  leading: const Icon(Icons.circle_outlined, color: Colors.white),
                  title: const Text(
                    'Circle',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Tap center, drag handle for radius',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(ctx, GeoFenceDrawShape.circle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _beginAddFence() async {
    final shape = await _pickDrawShape();
    if (shape == null || !mounted) return;
    _startDrawing(shape);
    setState(() {
      _bottomBarMode = BottomBarMode.addingGeoFence;
      _appBarTitle = 'Add Fence';
    });
  }

  void _startDrawing(GeoFenceDrawShape shape) {
    setState(() {
      _isDrawing = true;
      _isEditing = false;
      _editingFenceId = null;
      _drawShape = shape;
      _currentPolygonPoints.clear();
      _circleCenter = null;
      _circleCenterPlaced = false;
      _circleRadiusMeters = 100;
    });
    _resetUndoHistory();

    if (shape == GeoFenceDrawShape.polygon) {
      MyGlobalSnackBar.show('Tap the map to add corners (need 3+)');
    } else {
      MyGlobalSnackBar.show('Tap the map to place the circle center');
    }
  }

  bool get _canSaveDrawnFence {
    if (_drawShape == GeoFenceDrawShape.circle) {
      return _circleCenterPlaced &&
          _circleCenter != null &&
          _circleRadiusMeters >= 10 &&
          _currentPolygonPoints.length >= 3;
    }
    return _currentPolygonPoints.length >= 3;
  }

  void _undoLastDrawAction() {
    if (!_isDrawing || _undoStack.length <= 1) return;

    setState(() {
      _undoStack.removeLast();
      _restoreDrawSnapshot(_undoStack.last);
    });
  }

  Future<bool> _saveGeoFence() async {
    if (!_canSaveDrawnFence) {
      final msg = _drawShape == GeoFenceDrawShape.circle
          ? 'Place the center and set a radius first'
          : 'You need at least 3 points to create a geofence';
      MyGlobalMessage.show('Warning', msg, MyMessageType.warning);
      return false;
    }

    _geoFenceNameController.text =
        _isEditing ? fenceData.name : _geoFenceNameController.text;

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colorAppTitle,
        title: const Text('Name your Geo Fence', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _geoFenceNameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Name',
            labelStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              if (_geoFenceNameController.text.trim().isEmpty) {
                MyGlobalSnackBar.show('Please enter a name for your geo fence');
                return;
              }
              Navigator.pop(dialogContext, _geoFenceNameController.text.trim());
            },
            child: const Text('Save', style: TextStyle(color: colorOrange)),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return false;

    final savedPoints = _currentPolygonPoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
    final savedCenter = _circleCenter == null
        ? null
        : LatLng(_circleCenter!.latitude, _circleCenter!.longitude);
    final savedRadius = _circleRadiusMeters;
    final savedIsCircle = _drawShape == GeoFenceDrawShape.circle;

    final ok = await _saveGeoFenceToFirebase(name);
    if (ok && mounted) {
      await _loadGeoFences();
      if (!mounted) return ok;
      _scheduleZoomToSavedFence(
        points: savedPoints,
        center: savedCenter,
        radiusMeters: savedRadius,
        isCircle: savedIsCircle,
      );
      MyGlobalSnackBar.show('Geo fence "$name" saved');
    }
    return ok;
  }

  LatLngBounds _boundsForPoints(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _zoomToSavedFence({
    required List<LatLng> points,
    LatLng? center,
    double? radiusMeters,
    required bool isCircle,
  }) async {
    if (!mounted || _mapController == null) return;

    List<LatLng> focusPoints = points;
    if (isCircle && center != null && radiusMeters != null) {
      focusPoints = circlePolygonRing(center, radiusMeters);
    }
    if (focusPoints.isEmpty) return;

    try {
      if (focusPoints.length == 1) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(focusPoints.first, 18),
        );
        return;
      }

      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsForPoints(focusPoints), 56),
      );
    } catch (e) {
      printDebugMsg('Zoom to saved fence: $e');
      if (!mounted || _mapController == null) return;
      try {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(calculateCentroid(focusPoints), 17),
        );
      } catch (_) {}
    }
  }

  void _scheduleZoomToSavedFence({
    required List<LatLng> points,
    LatLng? center,
    double? radiusMeters,
    required bool isCircle,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _zoomToSavedFence(
        points: points,
        center: center,
        radiusMeters: radiusMeters,
        isCircle: isCircle,
      );
    });
  }

  Future<bool> _saveGeoFenceToFirebase(String name) async {
    final userData = context.read<UserDataService>().userdata;
    if (userData == null) return false;

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = userData.userID;
      final geoPointsList = _currentPolygonPoints
          .map((p) => GeoPoint(p.latitude, p.longitude))
          .toList();

      if (geoPointsList.length < 3) {
        MyGlobalMessage.show(
          'Warning',
          'Not enough points to save',
          MyMessageType.warning,
        );
        return false;
      }

      final isCircle = _drawShape == GeoFenceDrawShape.circle;
      final docRef = _editingFenceId != null
          ? firestore
              .collection(collectionUsers)
              .doc(userId)
              .collection(collectionGeoFences)
              .doc(_editingFenceId)
          : firestore
              .collection(collectionUsers)
              .doc(userId)
              .collection(collectionGeoFences)
              .doc();

      final payload = <String, dynamic>{
        fireGeoName: name,
        fireGeoPoints: geoPointsList,
        fireGeoType: isCircle ? geoFenceTypeCircle : geoFenceTypePolygon,
        fireGeoUpdateDate: FieldValue.serverTimestamp(),
      };

      if (isCircle && _circleCenter != null) {
        payload[fireGeoCenter] = GeoPoint(
          _circleCenter!.latitude,
          _circleCenter!.longitude,
        );
        payload[fireGeoRadiusMeters] = _circleRadiusMeters;
      } else {
        payload[fireGeoCenter] = FieldValue.delete();
        payload[fireGeoRadiusMeters] = FieldValue.delete();
      }

      if (_editingFenceId != null) {
        await docRef.set(payload, SetOptions(merge: true));
      } else {
        payload[fireGeoCreateDate] = FieldValue.serverTimestamp();
        await docRef.set(payload);
      }

      if (mounted) {
        setState(() {
          _isDrawing = false;
          _isEditing = false;
          _editingFenceId = null;
          _currentPolygonPoints.clear();
          _circleCenter = null;
          _circleCenterPlaced = false;
          _bottomBarMode = BottomBarMode.normal;
          _appBarTitle = 'GeoFence';
        });
      }
      return true;
    } catch (e) {
      MyGlobalMessage.show('Error', '$e', MyMessageType.error);
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _cancelDrawing() {
    setState(() {
      _isDrawing = false;
      _isEditing = false;
      _editingFenceId = null;
      _currentPolygonPoints.clear();
      _circleCenter = null;
      _circleCenterPlaced = false;
      _bottomBarMode = BottomBarMode.normal;
      _appBarTitle = 'GeoFence';
      _undoStack.clear();
    });
  }

  void _editGeoFence(FenceData fence) {
    setState(() {
      _isEditing = true;
      _isDrawing = true;
      _editingFenceId = fence.firestoreId;
      fenceData = fence;
      _geoFenceNameController.text = fence.name;
      _bottomBarMode = BottomBarMode.addingGeoFence;

      if (fence.isCircle && fence.center != null) {
        _drawShape = GeoFenceDrawShape.circle;
        _circleCenter = fence.center;
        _circleRadiusMeters = fence.radiusMeters ?? 100;
        _circleCenterPlaced = true;
        _currentPolygonPoints
          ..clear()
          ..addAll(fence.points);
      } else {
        _drawShape = GeoFenceDrawShape.polygon;
        _circleCenter = null;
        _circleCenterPlaced = false;
        _currentPolygonPoints
          ..clear()
          ..addAll(fence.points);
      }
    });
    _resetUndoHistory();

    MyGlobalSnackBar.show(
      fence.isCircle
          ? 'Drag center or orange handle to adjust the circle'
          : 'Drag vertices or tap the map to add points',
    );
  }

  Future<void> _deleteGeoFence(String firestoreId, String name) async {
    final userData = context.read<UserDataService>().userdata;

    if (firestoreId.isEmpty) {
      MyGlobalMessage.show('Warning', 'Please select a Fence', MyMessageType.warning);
      return;
    }
    if (userData == null) {
      MyGlobalMessage.show('Error', 'User not loaded', MyMessageType.error);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await firestore
          .collection(collectionUsers)
          .doc(userData.userID)
          .collection(collectionGeoFences)
          .doc(firestoreId)
          .delete();

      if (!mounted) return;
      MyGlobalSnackBar.show('Geofence "$name" deleted');
      await _loadGeoFences();
      if (!mounted) return;
      _nextFence();
    } catch (e) {
      if (!mounted) return;
      MyGlobalSnackBar.show('Error deleting GEO Fence: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _bottomBarMode = BottomBarMode.normal;
          _appBarTitle = 'GeoFence';
        });
      }
    }
  }

  void _toggleStreetView() {
    setState(() => _isStreetView = !_isStreetView);
  }

  String get _drawStatusLabel {
    if (!_isDrawing) return '';
    if (_drawShape == GeoFenceDrawShape.circle) {
      if (!_circleCenterPlaced) return 'Tap map for circle center';
      return 'Radius: ${_circleRadiusMeters.round()} m';
    }
    return 'Points: ${_currentPolygonPoints.length} (need 3+)';
  }

  Widget _drawStatusChip() {
    if (!_isDrawing || _drawStatusLabel.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Material(
        color: colorAppBar.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            _drawStatusLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  BottomNavigationBar buildBottomBar() {
    switch (_bottomBarMode) {
      case BottomBarMode.normal:
        return BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          onTap: _onNormalBarTap,
          backgroundColor: colorAppBar,
          unselectedItemColor: Colors.white,
          selectedItemColor: Colors.white,
          items: [
            MyBottomNavItem(icon: Icons.map, label: 'Street'),
            MyBottomNavItem(icon: Icons.add, label: 'Add'),
            MyBottomNavItem(icon: Icons.navigate_next, label: 'GeoFence'),
            MyBottomNavItem(icon: Icons.refresh, label: 'Refresh'),
          ],
        );

      case BottomBarMode.addingGeoFence:
        return BottomNavigationBar(
          onTap: _onAddingBarTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: colorAppBar,
          unselectedItemColor: Colors.white,
          selectedItemColor: Colors.white,
          items: [
            MyBottomNavItem(icon: Icons.undo, label: 'Undo'),
            MyBottomNavItem(icon: Icons.save, label: 'Save'),
            MyBottomNavItem(
              icon: _isStreetView ? Icons.map : Icons.streetview,
              label: 'Street',
            ),
            MyBottomNavItem(icon: Icons.close, label: 'Cancel'),
          ],
        );

      case BottomBarMode.selectedFence:
        return BottomNavigationBar(
          onTap: _onSelectedFenceBarTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: colorAppBar,
          unselectedItemColor: Colors.white,
          selectedItemColor: Colors.white,
          items: [
            MyBottomNavItem(icon: Icons.edit_note, label: 'Edit'),
            MyBottomNavItem(icon: Icons.delete_forever, label: 'Delete'),
          ],
        );
    }
  }

  void _onSelectedFenceBarTap(int index) {
    if (index == 0) {
      _editGeoFence(fenceData);
      return;
    }
    if (index == 1) {
      myQuestionAlertBox(
        context: context,
        header: 'Delete Fence',
        message: 'Delete: ${fenceData.name}\nAre you Sure?',
        onPress: () {
          _deleteGeoFence(fenceData.firestoreId, fenceData.name);
        },
      );
    }
  }

  void _onNormalBarTap(int index) async {
    if (index == 0) _toggleStreetView();
    if (index == 1) await _beginAddFence();
    if (index == 2) _nextFence();
    if (index == 3) {
      await _loadGeoFences();
      await _getLocation();
    }
  }

  void _onAddingBarTap(int index) async {
    if (index == 0) {
      _undoLastDrawAction();
      return;
    }
    if (index == 1) {
      await _saveGeoFence();
      return;
    }
    if (index == 2) {
      _toggleStreetView();
      return;
    }
    if (index == 3) {
      _cancelDrawing();
      await _loadGeoFences();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: colorAppBar,
        title: myAppbarTitle(_appBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.format_list_bulleted, size: 28),
            tooltip: 'Geo fence list',
            onPressed: _openGeoFenceList,
          ),
        ],
      ),
      bottomNavigationBar: buildBottomBar(),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialPosition,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _mapMarkers,
            polygons: _mapPolygons,
            circles: _mapCircles,
            mapType: _isStreetView ? MapType.satellite : MapType.normal,
            onMapCreated: (controller) {
              _mapController = controller;
              if (_pendingInitialLocationZoom) {
                _pendingInitialLocationZoom = false;
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(_currentLocation, 18),
                );
              }
            },
            onTap: _onMapTap,
          ),
          if (_isLoading)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.25),
              child: Center(child: myProgressCircle()),
            ),
          _drawStatusChip(),
        ],
      ),
    );
  }
}
