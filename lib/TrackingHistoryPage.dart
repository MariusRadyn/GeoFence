
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'TrackingHistoryMap.dart';

class TrackingHistoryPage extends StatefulWidget {
  const TrackingHistoryPage({super.key});

  @override
  State<TrackingHistoryPage> createState() => _TrackingHistoryPageState();
}

class _TrackingHistoryPageState extends State<TrackingHistoryPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final nrFormatter = NumberFormat('0.00', 'en_US');
  List<Map<String, dynamic>>? _vehicles = [];

  @override
  void initState() {
    super.initState();
    fetchVehicles();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      User? user = _auth.currentUser;
      //Provider.of<SettingsProvider>(context, listen: false).LoadSettings(user?.uid);
    });
  }

  Future<void> fetchVehicles() async {
    _vehicles = await getVehicles();
    setState(() {}); // Refresh UI after fetching data

    print(jsonEncode(_vehicles)); // Pretty-print JSON format
  }
  Future<List<Map<String, dynamic>>> getVehicles() async {
    if(_auth.currentUser! == null) return List<Map<String, dynamic>>.empty();

    final QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(_auth.currentUser!.uid)
        .collection(CollectionVehicles)
        .get();

    return snapshot.docs.map((doc) {
      return {
        'vehicle_id': doc.id, // Add document ID manually
        ...doc.data() as Map<String, dynamic>, // Merge Firestore fields
      };
    }).toList();

  }
  void _deleteSession(QueryDocumentSnapshot session, String vehicle, String reg) async {
    showDialog(
        context: context,
        builder: (context){
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(
                color: Colors.blue, // Border color
                width: 2, // Border width
              ),
            ),
            backgroundColor: APP_TILE_COLOR,
            shadowColor: Colors.black,
            title: const Text(
              "Delete",
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              "${DateFormat('yyyy-MM-dd – kk:mm').format(session['start_time'].toDate())}\n${vehicle}\n${reg}\n\nAre you sure?",
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 18,
              ),
            ),
            actions: [
              TextButton(
                child: const Text(
                  'No',
                  style: TextStyle(
                    color:  Colors.white,
                    fontFamily: "Poppins",
                    fontSize: 20,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                  child: const Text(
                    'Yes',
                    style: TextStyle(
                      color:  Colors.white,
                      fontFamily: "Poppins",
                      fontSize: 20,
                    ),
                  ),
                  onPressed: () async {
                    User? user = _auth.currentUser;
                    _deleteSessionWithLocations(user?.uid, session.id);
                    Navigator.pop(context);
                  }
              ),
            ],
          );
        }
    );
  }
  Future<void> _deleteSessionWithLocations(String? userId, String sessionId) async {
    final sessionRef = _firestore
        .collection(CollectionUsers)
        .doc(userId)
        .collection(CollectionTrackingSessions)
        .doc(sessionId);

    // Delete all documents in the CollectionLocations subcollection
    final locations = await sessionRef.collection(CollectionLocations).get();
    for (var doc in locations.docs) {
      await doc.reference.delete();
    }

    // Now delete the session itself
    await sessionRef.delete();
  }
  String? _getVehicleNameById(String vehicleId) {
    return _vehicles?.firstWhere(
          (vehicle) => vehicle['vehicle_id'] == vehicleId,
      orElse: () => {'name': 'Unknown'}, // Default if not found
    )['name'] as String;
  }
  String? _getVehicleRegById(String vehicleId) {
    return _vehicles?.firstWhere(
          (vehicle) => vehicle['vehicle_id'] == vehicleId,
      orElse: () => {'registrationNumber': 'Unknown'}, // Default if not found
    )['registrationNumber'] as String;
  }

  @override
  Widget build(BuildContext context) {


    return Scaffold(
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
        foregroundColor: Colors.white,
        title: MyAppbarTitle('History'),
      ),
      body: Container(
        color: APP_BACKGROUND_COLOR,
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection(CollectionUsers)
              .doc(_auth.currentUser!.uid)
              .collection(CollectionTrackingSessions)
              .orderBy('start_time', descending: true)
              .snapshots(),

          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }

            var sessions = snapshot.data!.docs;
            if (sessions.isEmpty) {
              return const Center(
                child: Text(
                  "No tracking history found",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 20,
                  ),
                ),
              );
            }

            return _vehicles == null
                ? Center(child: CircularProgressIndicator())
                :   ListView.builder(

                itemCount: sessions.length,
                itemBuilder: (context, index) {
                var session = sessions[index];
                String vehicleName = _getVehicleNameById(session['vehicle_id']) ?? "Unknown Vehicle";
                String vehicleReg = _getVehicleRegById(session['vehicle_id']) ?? "Unknown";

                return Column(
                  children: [
                    SizedBox(height: 20,),

                    MyTextTileWithEditDelete(
                      text: DateFormat('yyyy-MM-dd (kk:mm) ').format(session['start_time'].toDate()),
                      subtext:
                      'ID: ${session.id}\n'
                      'Vehicle: ${vehicleName}\n'
                      'Reg: ${vehicleReg}\n'
                      'Inside: ${nrFormatter.format(session['distance_inside'])} km\n'
                      'Outside: ${nrFormatter.format(session['distance_outside'])} km\n'
                      ,

                      onTapDelete: (){
                        _deleteSession(session, vehicleName, vehicleReg);
                      } ,

                      onTapTile: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => TrackingHistoryMap(
                            userId: _auth.currentUser?.uid,
                            trackSessionId: session.id,
                          )),
                        );
                      },
                    ),
                    SizedBox(height: 1,)
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
