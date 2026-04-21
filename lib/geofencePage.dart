// Geo Fence Screen
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geofence/gpsServices.dart';
import 'package:geofence/utils.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

const double DRAW_WIDTH = 60;
double _sheetPosition = 0.25;
final double _dragSensitivity = 600;
enum BottomBarMode { normal, addingGeoFence }

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
  final DraggableScrollableController _scrollController = DraggableScrollableController();
  BottomBarMode _bottomBarMode = BottomBarMode.normal;

  bool _isDrawing = false;
  String? _editingFenceId;
  bool _isLoading = false;
  bool _isSaving = false;
  int _polygonIdCounter = 0;
  LatLng _currentLocation = const LatLng(-29.6, 30.3);
  bool isGeoFenceSet = false;
  bool _isStreetView = false;
  bool _isDrawerVisible = true;
  bool _isBotScrolDrawerVisible = false;
  bool  _isEditing = false;
  int _fencePntr = 0;
  String _appBarTitle = "GeoFence";
  FenceData fenceData = FenceData();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Future<Position>? currentPosition;

  // Drawer Pointers
  int _drawerPntr = 0;
  static final int _showMainDrawer = 0;
  static final int _showAddMarkerDrawer = 1;
  static final int _showDeleteMarkerDrawer = 2;
  static final int _showEditFenceDrawer = 3;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(() {
      double size = _scrollController.size;

      if (_scrollController.size <= 0.25) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        ).then((_) {
          if (!mounted) return;
          setState(() {
            _isBotScrolDrawerVisible = false;
          });
        });
      }
    });

    if(mounted){
      _initialize();
    }
  }

  Future<void> _initialize() async {
    await _loadGeoFences();
    if (!mounted) return;
    _getLocation();
  }

  @override
  void dispose() {
    _geoFenceNameController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(-29.0, 24.0), // Default to South Africa
    zoom: 6.0,
  );
  Future<void> _getLocation() async {
    writeLog('GetLocation');
    Position pos = await determinePosition();

    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
      _geoMarkers.add(
        Marker(
          markerId: MarkerId("myLocation"),
          position: LatLng(pos.latitude, pos.longitude),
        ),
      );
    });

    if(_mapController != null) {
        _mapController?.animateCamera
          (CameraUpdate.newLatLngZoom(_currentLocation, 18),
        );
    }
  }
  Future<void> _loadGeoFences() async {
    UserData? userData = context.read<UserDataService>().userdata;

    setState(() {
      _isLoading = true;
      _polygons.clear();
      _markers.clear();
    });
    try {
      final userId = userData!.userID;// firebaseAuthService. _auth.currentUser!.uid;
      final geoFencesSnapshot = await firestore
          .collection(collectionUsers)
          .doc(userId)
          .collection(collectionGeoFences)
          .get();

      if (geoFencesSnapshot.docs.isNotEmpty) {
        for (var doc in geoFencesSnapshot.docs) {
          final data = doc.data();
          final points = List<GeoPoint>.from(data['points']);
          final polygonPoints = points.map((point) =>
              LatLng(point.latitude, point.longitude)).toList();

          if (polygonPoints.length >= 3) {
            final polygonId = '$geoFencePolygon$_polygonIdCounter';
            final markerId = '$geoFenceMarker${_polygonIdCounter++}';

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
      final userDoc = await firestore.collection(collectionUsers).doc(userId).get();
      if (userDoc.exists && userDoc.data()!.containsKey('location')) {
        final location = userDoc.data()!['location'] as GeoPoint;
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude)),
        );
      }
    } catch (e) {
      MyGlobalMessage.show('Error', "$e", MyMessageType.error);
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
          markerId: MarkerId('$geoFencePoint${_currentPolygonPoints.length}'),
          position: position,

        ),
      );

      // If more than one point, draw lines
      if (_currentPolygonPoints.length > 1) {
        _polygons.removeWhere(
              (polygon) => polygon.polygonId.value == geoFenceDrawingPolygon,
        );

        _polygons.add(
          Polygon(
            polygonId: const PolygonId(geoFenceDrawingPolygon),
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

    _scrollController.animateTo(
      0.25,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }
  void _nextFence() {
    if (_markers.isEmpty) return;

    setState(() {
      _fencePntr = (_fencePntr + 1) % _markers.length;
      final marker = _markers.elementAt(_fencePntr);

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(marker.position.latitude, marker.position.longitude),
          18,
        ),
      );
    });
  }
  void _startDrawing() {
    setState(() {
      _isDrawing = true;
      _isEditing = false;
      _editingFenceId = null;
      _currentPolygonPoints.clear();
      _markers.removeWhere((marker) =>
          marker.markerId.value.startsWith(geoFencePoint));
      _polygons.removeWhere((polygon) =>
      polygon.polygonId.value == geoFenceDrawingPolygon);
    });

    MyGlobalSnackBar.show('Tap on the map to add GEO points');
  }
  Future<void> _saveGeoFence() async {
    if (_currentPolygonPoints.length < 3) {
      MyGlobalMessage.show("Warning", 'You need at least 3 points to create a geofence', MyMessageType.warning);
      return;
    }

    _geoFenceNameController.text = '';
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name your Geo Fence'),
        content: TextField(
          controller: _geoFenceNameController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_geoFenceNameController.text.isEmpty) {
                MyGlobalSnackBar.show('Please enter a name for your geo fence');
                return;
              }

              Navigator.pop(dialogContext);
              await _saveGeoFenceToFirebase(_geoFenceNameController.text);
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
  Future<void> _saveGeoFenceToFirebase(String name) async {
    final userData = context.read<UserDataService>().userdata;

    setState(() {
      _isLoading = true;
      _isSaving = true;
    });

    try {
      final userId = userData!.userID; // _auth.currentUser!.uid;
      final geoPointsList = _currentPolygonPoints
          .map((point) => GeoPoint(point.latitude, point.longitude))
          .toList();

      if (geoPointsList.isEmpty){
        MyGlobalMessage.show("Warning", 'No Geofence points found', MyMessageType.warning);
      }
      else{
        // Get the document to update or create new one
        final docRef = _editingFenceId != null
            ? firestore.collection(collectionUsers).doc(userId).collection(collectionGeoFences).doc(_editingFenceId)
            : firestore.collection(collectionUsers).doc(userId).collection(collectionGeoFences).doc();

        await docRef.set({
          fireGeoName: name,
          fireGeoPoints: geoPointsList,
          fireGeoCreateDate: _editingFenceId != null ? FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
          fireGeoUpdateDate: _editingFenceId != null ? FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
        });
        MyGlobalSnackBar.show('Geo fence "$name" saved successfully');

        setState(() {
          _isDrawing = false;
          _isEditing = false;
          _editingFenceId = null;
          _currentPolygonPoints.clear();
          _markers.removeWhere((marker) => marker.markerId.value.startsWith(geoFencePoint));
          _polygons.removeWhere((polygon) => polygon.polygonId.value == geoFenceDrawingPolygon);
        });
      }

    } catch (e) {
      MyGlobalMessage.show("Error", "$e", MyMessageType.error);
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
      _markers.removeWhere((marker) => marker.markerId.value.startsWith(geoFencePoint));
      _polygons.removeWhere((polygon) => polygon.polygonId.value == geoFenceDrawingPolygon);
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

      _markers.removeWhere((marker) => marker.markerId.value.startsWith(geoFenceMarker));
      _polygons.removeWhere((polygon) => polygon.polygonId.value == geoFenceDrawingPolygon);

      // Add markers for each point
      for (int i = 0; i < points.length; i++) {
        _markers.add(
          Marker(
            markerId: MarkerId('$geoFencePoint${i + 1}'),
            position: points[i],
          ),
        );
      }

      // Add polygon
      _polygons.add(
        Polygon(
          polygonId: const PolygonId(geoFenceDrawingPolygon),
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
    UserData? userData = context.read<UserDataService>().userdata;

    if(firestoreId.isEmpty){
      MyGlobalMessage.show("Warning", "Please select a Fence", MyMessageType.warning);
      return;
    }

    if (userData == null) {
      MyGlobalMessage.show("Error", "User not loaded", MyMessageType.error);
      return;
    }

    setState(() {
        _isLoading = true;
      });

      try {
        final userId = userData!.userID;
        await firestore
            .collection(collectionUsers)
            .doc(userId)
            .collection(collectionGeoFences)
            .doc(firestoreId)
            .delete();

        if (!context.mounted) return;
        MyGlobalSnackBar.show('Geofence "$name" deleted');

        // Reload all geo fences
        await _loadGeoFences();
        if (!context.mounted) return;
        _nextFence();

      } catch (e) {
        if (!context.mounted) return;
        MyGlobalSnackBar.show('Error deleting GEO Fence: $e');

      } finally {
        setState(() {
          _isLoading = false;
          _isBotScrolDrawerVisible = false;
        });
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

  // Bottom Nav Buttons ---------------------------------
  BottomNavigationBar buildBottomBar() {
    switch (_bottomBarMode) {
      case BottomBarMode.normal:
        return BottomNavigationBar(
          type: BottomNavigationBarType.fixed, // Force Background color
          onTap: _onNormalBarTap,
          backgroundColor: colorAppBar,
          unselectedItemColor: Colors.white,
          selectedItemColor: Colors.white,
          items: [
            MyBottomNavItem(icon: Icons.map, label: "Street"),
            MyBottomNavItem(icon: Icons.add, label: "Add"),
            MyBottomNavItem(icon: Icons.navigate_next, label: "GeoFence"),
            MyBottomNavItem(icon: Icons.refresh, label: "Refresh"),
          ],
        );

      case BottomBarMode.addingGeoFence:
        return BottomNavigationBar(
          onTap: _onAddingBarTap,
          type: BottomNavigationBarType.fixed, // Force Background color
          backgroundColor: colorAppBar,
          unselectedItemColor: Colors.white,
          selectedItemColor: Colors.white,
          items: [
            MyBottomNavItem(icon: Icons.save, label: "Save"),
            MyBottomNavItem(icon: Icons.refresh, label: "Refresh"),
            MyBottomNavItem(icon: Icons.arrow_back, label: "Back"),
          ],
        );
    }
  }
  void _onNormalBarTap(index) async {
    // Street
    if(index == 0){
      _toggleStreetView();
    }

    // Add Fence
    if(index == 1){
      _startDrawing();
      _bottomBarMode = BottomBarMode.addingGeoFence;
    }

    // Next
    if(index == 2) {
      _nextFence();
    }

    // Refresh
    if(index == 3) {
      await _loadGeoFences();
      await _getLocation();
    }
  }
  void _onAddingBarTap(index) async {

    // Save
    if(index == 0){
      await _saveGeoFence();
      await _loadGeoFences();
      await _getLocation();
      _bottomBarMode = BottomBarMode.normal;
    }

    // Refresh
    if(index == 1) {
      await _loadGeoFences();
      await _getLocation();
    }

    // Back
    if(index == 2) {
      _cancelDrawing();
      await _loadGeoFences();
      await _getLocation();
      _bottomBarMode = BottomBarMode.normal;
    }
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
      duration: Duration(milliseconds: 1000),
      decoration: const BoxDecoration(
        color: colorDrawer,
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
        color: colorDrawer,
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
        color: colorDrawer,
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
              _deleteGeoFence(fenceData.firestoreId, fenceData.name),
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
  Widget FenceBottomScrollDraw({required bool visible}){
    return Visibility(
      visible: visible,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: DraggableScrollableSheet(
        snap: true,
        initialChildSize: _sheetPosition,
        minChildSize: 0.25, // Minimum height
        maxChildSize: 0.9, // Can be dragged to full screen
        snapSizes: [0.25, 0.9], // Snap points
        expand: true,
        controller: _scrollController,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow( color: Colors.black26, blurRadius: 10, spreadRadius: 2,
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
                // Grabber(
                //   isOnDesktopAndWeb: isOnDesktop(),
                //
                //   onVerticalDragUpdate: (DragUpdateDetails details) {
                //    _scrollController.animateTo(
                //        _sheetPosition,
                //        duration: Duration(milliseconds: 300),
                //        curve: Curves.easeInOut
                //    );
                //
                //     setState(() {
                //       _sheetPosition -= details.delta.dy / _dragSensitivity;
                //       if (_sheetPosition < 0.25) {
                //         _sheetPosition = 0.25;
                //       }
                //       if (_sheetPosition > 1.0) {
                //         _sheetPosition = 1.0;
                //       }
                //     });
                //   },
                // ),
      
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
                                      fenceData.name,
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
                                      MyQuestionAlertBox(
                                        context: context,
                                        header: "Delete Fence",
                                        message: "Delete: ${fenceData.name}\nAre you Sure?",
                                        onPress: (){
                                          _deleteGeoFence(fenceData.firestoreId,fenceData.name);
                                        });
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
      ),
    );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: colorAppBar,
        title: MyAppbarTitle(_appBarTitle),
        actions: [
          IconButton(
            icon: Icon(Icons.more_horiz),
            onPressed: () {
              setState(() {
                _isDrawerVisible = !_isDrawerVisible;
                _isBotScrolDrawerVisible = false;
                _setDrawerPointer(_showMainDrawer);
              });
            },
          ),
        ],
      ),
      bottomNavigationBar: buildBottomBar(),
      body: Row(
        children:[

          // Map
          Expanded(
            child: Stack(
              children: [

                // Loading
                if (_isLoading == true)
                  MyProgressCircle(),

                if(_isLoading == false)
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

                FenceBottomScrollDraw(
                  visible: _isBotScrolDrawerVisible,
                ),

              ],
            ),
          ),

          // Visibility(
          //   visible: _drawerPntr == _showMainDrawer,
          //   child: AnimatedSwitcher(
          //     duration: Duration(microseconds: 3000),
          //     child: MenuDrawer(),
          //   ) ,
          // ),

          Visibility(
            visible: _drawerPntr == _showAddMarkerDrawer,
            child: AnimatedSwitcher(
              duration: Duration(microseconds: 3000),
              child: AddMarkerDrawer(),
            ) ,
          ),

          //_drawerPntr == _showMainDrawer ? MenuDrawer() : SizedBox(),
          //_drawerPntr == _showAddMarkerDrawer ? AddMarkerDrawer() : SizedBox(),
          //_drawerPntr == _showEditFenceDrawer ? EditFenceDrawer() : SizedBox(),
        ],
      ),
    );
  }
}