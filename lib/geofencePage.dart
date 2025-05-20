// Geo Fence Screen
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geofence/firebase.dart';
import 'package:geofence/gpsServices.dart';
import 'package:geofence/utils.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

const double DRAW_WIDTH = 60;
double _sheetPosition = 0.25;
final double _dragSensitivity = 600;

class GeoFencePage extends StatefulWidget {
  const GeoFencePage({super.key});

  @override
  _GeoFencePageState createState() => _GeoFencePageState();
}

class _GeoFencePageState extends State<GeoFencePage> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};
  final Set<Marker> _geoMarkers = {};
  final List<LatLng> _currentPolygonPoints = [];
  final TextEditingController _geoFenceNameController = TextEditingController();
  final DraggableScrollableController _controller = DraggableScrollableController();
  bool _isDrawing = false;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _editingFenceId;
  bool _isLoading = false;
  int _polygonIdCounter = 0;
  LatLng _currentLocation = const LatLng(-29.6, 30.3);
  bool isGeoFenceSet = false;
  int _currentIndex = 0;
  bool _isStreetView = false;
  bool _isDrawerVisible = true;
  bool _isBotScrolDrawerVisible = false;
  int _fencePntr = 0;
  String _appBarTitle = "GeoFence";
  FenceData fenceData = FenceData();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Drawer Pointers
  int _drawerPntr = 0;
  static int _showMainDrawer = 0;
  static int _showAddMarkerDrawer = 1;
  static int _showDeleteMarkerDrawer = 2;
  static int _showEditFenceDrawer = 3;

  @override
  void initState() {
    super.initState();

    if(mounted){
      _loadGeoFences();
      _getLocation();
    }
  }

  @override
  void dispose() {
    _geoFenceNameController.dispose();
    _mapController?.dispose();
    super.dispose();
  }
  Future<Position>? currentPosition;

  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(-29.0, 24.0), // Default to South Africa
    zoom: 6.0,
  );
  Future<void> _getLocation() async {
    writeLog('GetLocation');
    Position pos = await determinePosition();

    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
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
          (CameraUpdate.newLatLngZoom(_currentLocation!, 18),
        );
    }
  }
  Future<void> _loadGeoFences() async {
    UserData? _userData = UserDataService().userdata;

    setState(() {
      _isLoading = true;
      _polygons.clear();
      _markers.clear();
    });
    try {
      final userId = _userData!.userID;// firebaseAuthService. _auth.currentUser!.uid;
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
                  position: _calculateCentroid(polygonPoints),
                  infoWindow: InfoWindow(title: data['name']),
                  onTap: ()=> _onMarkerTap(polygonId, doc.id, data['name'], polygonPoints),
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
      // final userDoc = await firestore.collection(CollectionUsers).doc(userId).get();
      // if (userDoc.exists && userDoc.data()!.containsKey('location')) {
      //   final location = userDoc.data()!['location'] as GeoPoint;
      //   _mapController?.animateCamera(
      //     CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude)),
      //   );
      // }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading geofences: $e')),
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
    print('On map Tap');

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
  void _onMarkerTap(String polygonId, String firestoreId, String name, List<LatLng> points) {
    print('On Marker Tap: $name');

    setState(() {
      _isBotScrolDrawerVisible = true;
      _drawerPntr = _showEditFenceDrawer;
      fenceData.polygonId = polygonId;
      fenceData.firestoreId = firestoreId;
      fenceData.name = name;
      fenceData.points = points;
      _appBarTitle = 'Fence: $name';
    });

    _controller.animateTo(
      0.25,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
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
      const SnackBar(
        content: Text('Tap on the map to add points to your geo fence'),
        duration: Duration(seconds:  10),
        showCloseIcon: true,
      ),
    );
  }
  void _saveGeoFence() async {
    if (_currentPolygonPoints.length < 3) {
      myMessageBox(context, 'You need at least 3 points to create a geofence' );
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
              await _saveGeoFenceToFirebase(context, _geoFenceNameController.text);
              await _loadGeoFences();

              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Saved'),
                  showCloseIcon: true,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  Future<void> _saveGeoFenceToFirebase(BuildContext context, String name) async {
    //final _userData = Provider.of<UserData>(context, listen: false);
    final _userData = UserDataService().userdata;

    setState(() {
      _isLoading = true;
      _isSaving = true;
    });

    try {
      final userId = _userData!.userID; // _auth.currentUser!.uid;
      final geoPointsList = _currentPolygonPoints
          .map((point) => GeoPoint(point.latitude, point.longitude))
          .toList();

      if (geoPointsList.length == 0){
        myMessageBox(context, 'No Geofence points found');
      }
      else{
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
      }

    } catch (e) {
        myMessageBox(context, 'Error saving geo fence: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _isSaving = false;
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
  void _editGeoFence(String firestoreId, String name, List<LatLng> points) {
    setState(() {
      _isEditing = true;
      _isDrawing = true;
      _editingFenceId = firestoreId;
      _currentPolygonPoints.clear();
      _currentPolygonPoints.addAll(points);
      _geoFenceNameController.text = name;

      _markers.removeWhere((marker) => marker.markerId.value.startsWith('marker_'));
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
  Future<void> _deleteGeoFence(BuildContext context, String firestoreId, String name) async {
    //final _userData = Provider.of<UserData>(context, listen: false);
    UserData? _userData = UserDataService().userdata;

    if(firestoreId == ""){
      myMessageBox(context, "Please select a Fence");
      return;
    }
    final bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Fence "$name"?'),
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
        final userId = _userData!.userID;// _auth.currentUser!.uid;
        await firestore
            .collection('users')
            .doc(userId)
            .collection('geofences')
            .doc(firestoreId)
            .delete();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Geofence "$name" deleted')),
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
  void _toggleStreetView() {
    setState(() {
      _isStreetView = !_isStreetView;
    });
  }
  List<Widget> GetFencePoints() {
    List<Text> lst = fenceData.points.map((point) {
      return Text(
        'Lat: ${point.latitude}, Long: ${point.longitude}',
        style: const TextStyle(
            fontSize: 10,
            color: Colors.blueGrey
        ),
      );
    }).toList();

    return lst;
  }


  // Drawers -------------------------------------------------------------------
  void _setDrawerPointer(int pntr){
    setState(() {
      _drawerPntr = pntr;
    });
  }
  Widget MenuDrawer(){
    return AnimatedContainer(
      width: _isDrawerVisible ? DRAW_WIDTH : 0, // Animate width
      duration: Duration(milliseconds: 300),
      decoration: const BoxDecoration(
        color: DRAWER_COLOR,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          bottomLeft: Radius.circular(10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.teal,
            blurRadius: 10,
            spreadRadius: 1,
            offset: Offset(-5, 0),
          ),
        ],
      ),
      child: _isDrawerVisible
          ? Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 5),

          // Street view
          MyIcon(
            text: 'Street View',
            icon:  Icons.streetview,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: _toggleStreetView,
          ),
          const SizedBox(height: 5),

          // Add Fence
          MyIcon(
            text: 'Add Fence',
            icon:  Icons.add,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: () => {
              _setDrawerPointer(_showAddMarkerDrawer),
            },
          ),
          const SizedBox(height: 5),

          //Next Fence
          MyIcon(
            text: 'Next Fence',
            icon:Icons.navigate_next,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: ()  => {
              _nextFence(),
            },
          ),
          const SizedBox(height: 5),

          // Refresh
          MyIcon(
            text: 'Refresh',
            icon: Icons.refresh,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: () => {
              _loadGeoFences(),
            },
          ),
          const SizedBox(height: 5),

        ],
      )

      // Drawer Hidden
          : SizedBox(), // Empty container when hidden
  );
}
  Widget AddMarkerDrawer(){
    setState(() {
      _appBarTitle = "Add Fence";
    });
    return AnimatedContainer(
      width: _isDrawerVisible ? DRAW_WIDTH : 0, // Animate width
      duration: Duration(milliseconds: 300),
      decoration: const BoxDecoration(
        color: DRAWER_COLOR,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.teal,
            blurRadius: 10,
            spreadRadius: 1,
            offset: Offset(-5, 0),
          ),
        ],
      ),
      child: _isDrawerVisible
          ? Column(
        mainAxisAlignment: MainAxisAlignment.start,

        children: [
          const SizedBox(height: 5),

          // Add
          MyIcon(
            text: 'Add',
            icon:  Icons.add,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: _startDrawing,
          ),
          const SizedBox(height: 5),

          //Save
          MyIcon(
            text: 'Save',
            icon: Icons.save,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: () => {
              _saveGeoFence(),
              ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            },
          ),
          const SizedBox(height: 5),

          // Refresh
          MyIcon(
            text: 'Refresh',
            icon: Icons.refresh,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: () => {
              _loadGeoFences(),
            },
          ),

          const SizedBox(height: 5),

          // Back
          MyIcon(
            text: 'Back',
            icon:Icons.arrow_back,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: () => {
              _cancelDrawing(),
              _setDrawerPointer(_showMainDrawer),
              ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            },
          ),
        ],
      )

      // Drawer Hidden
          : SizedBox(), // Empty container when hidden
    );
  }
  Widget EditFenceDrawer(){
    setState(() {
      _appBarTitle = "Edit Fence";
    });

    return AnimatedContainer(
      width: _isDrawerVisible ? DRAW_WIDTH : 0, // Animate width
      duration: Duration(milliseconds: 300),
      decoration: const BoxDecoration(
        color: DRAWER_COLOR,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.teal,
            blurRadius: 10,
            spreadRadius: 1,
            offset: Offset(-5, 0),
          ),
        ],
      ),
      child: _isDrawerVisible
          ? Column(
        mainAxisAlignment: MainAxisAlignment.start,

        children: [
          const SizedBox(height: 5),

          //Edit Fence
          MyIcon(
            text: 'Edit Fence',
            icon:Icons.edit_note,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: () =>{
              _editGeoFence(fenceData.firestoreId,fenceData.name,fenceData.points),
            }
          ),
          const SizedBox(height: 5),

          // Delete Fence
          MyIcon(
            text: 'Delete Fence',
            icon: Icons.delete,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: () => {
              _deleteGeoFence(context, fenceData.firestoreId, fenceData.name),
              ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            },
          ),
          const SizedBox(height: 5),

          // Refesh
          MyIcon(
            text: 'Refresh',
            icon: Icons.refresh,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: () => {
              _loadGeoFences(),
            },
          ),
          const SizedBox(height: 5),

          // Back
          MyIcon(
            text: 'Back',
            icon:Icons.arrow_back,
            iconColor: Colors.white,
            textColor: Colors.white,
            onTap: () => {
              _cancelDrawing(),
              _setDrawerPointer(_showMainDrawer),
              ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            },
          ),
        ],
      )

      // Drawer Hidden
          : SizedBox(), // Empty container when hidden
    );
  }
  Widget FenceBottomScrollDraw(){


    return DraggableScrollableSheet(
      snap: true,
      initialChildSize: _sheetPosition,
      minChildSize: 0, // Minimum height
      maxChildSize: 0.9, // Can be dragged to full screen
      snapSizes: [0.25, 0.9], // Snap points
      expand: true,
      controller: _controller,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 15),

              // Scroll Handle
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Scroll Control (Desktop only)
              Grabber(
                isOnDesktopAndWeb: isOnDesktop(),

                onVerticalDragUpdate: (DragUpdateDetails details) {
                  _controller.animateTo(
                      _sheetPosition,
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeInOut
                  );

                  setState(() {
                    _sheetPosition -= details.delta.dy / _dragSensitivity;
                    if (_sheetPosition < 0.25) {
                      _sheetPosition = 0.25;
                    }
                    if (_sheetPosition > 1.0) {
                      _sheetPosition = 1.0;
                    }
                  });
                },
              ),

              // Scrollable
              Flexible(
                child: ListView(
                  controller: scrollController,
                  physics: AlwaysScrollableScrollPhysics(),
                  children:[
                    Container(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10, right: 10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children:[
                            SizedBox(height: 2),

                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${fenceData.name}',
                                    textAlign: TextAlign.left,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        color: Colors.black
                                    ),
                                  ),
                                ),

                                MyIcon(
                                  text: 'Edit',
                                  icon: Icons.edit_note,
                                  iconColor: Colors.blue,
                                  textColor: Colors.black,
                                  iconSize: 20,
                                  onTap: () {

                                  },
                                ),

                                SizedBox(width: 10),

                                MyIcon(
                                  text: 'Delete',
                                  icon: Icons.delete_forever,
                                  iconColor: Colors.red,
                                  textColor: Colors.black,
                                  iconSize: 20,
                                  onTap: () {
                                    _deleteGeoFence(
                                      context,
                                        fenceData.firestoreId,
                                        fenceData.name,
                                    );
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 5),
                            const Divider(
                              thickness: 2,
                              color: Colors.grey,
                              endIndent: 10,
                            ),
                            const SizedBox(height: 10),

                            const Text(
                                'Points',
                              style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey
                              ),
                            ),
                            const SizedBox(height: 3),

                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: fenceData.points.isEmpty
                                    ? [Text('No Points')]
                                    : GetFencePoints()
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: APP_BAR_COLOR,
        title: MyAppbarTitle(_appBarTitle),
        actions: [
          IconButton(
            icon: Icon(Icons.more_horiz),
            onPressed: () {
              setState(() {
                _isDrawerVisible = !_isDrawerVisible;
              });
            },
          ),
        ],
      ),
      body: Row(
        children:[

          // Map
          Expanded(
            child: Stack(
              children: [

                // Loading
                if (_isLoading)
                  Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),

                GoogleMap(
                  initialCameraPosition: _initialPosition,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  markers: _markers,
                  polygons: _polygons,
                  mapType: _isStreetView ? MapType.satellite : MapType.normal,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    for (Marker marker in _markers) {
                      _mapController?.showMarkerInfoWindow(marker.markerId);
                    }
                  },
                  onTap: _onMapTap,
                ),

                if(_isBotScrolDrawerVisible)
                  FenceBottomScrollDraw(),
              ],
            ),
          ),

          _drawerPntr == _showMainDrawer ? MenuDrawer() : SizedBox(),
          _drawerPntr == _showAddMarkerDrawer ? AddMarkerDrawer() : SizedBox(),
          //_drawerPntr == _showEditFenceDrawer ? EditFenceDrawer() : SizedBox(),
        ],
      ),
    );
  }
}