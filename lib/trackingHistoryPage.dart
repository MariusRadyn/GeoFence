
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'trackingHistoryMap.dart';
import 'package:provider/provider.dart';

class TrackingHistoryPage extends StatefulWidget {
  const TrackingHistoryPage({super.key});

  @override
  State<TrackingHistoryPage> createState() => _TrackingHistoryPageState();
}

class _TrackingHistoryPageState extends State<TrackingHistoryPage> {
  late SettingsService settings;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final nrFormatter = NumberFormat('0.00', 'en_US');
  List<Map<String, dynamic>>? _vehicles = [];
  DateTime _selectedDateFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDateTo = DateTime(DateTime.now().year, DateTime.now().month + 1, 0, );
  double _totalRebate = 0.0;
  double _totalKM = 0.0;
  double _totalLiters = 0.0;


  @override
  void initState() {
    super.initState();
    fetchVehicles();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      User? user = _auth.currentUser;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = context.read<SettingsService>();
  }

  Future<void> fetchVehicles() async {
    _vehicles = await getVehicles();
    setState(() {}); // Refresh UI after fetching data

    print(jsonEncode(_vehicles)); // Pretty-print JSON format
  }
  Future<List<Map<String, dynamic>>> getVehicles() async {
    final QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection(CollectionUsers)
        .doc(_auth.currentUser!.uid)
        .collection(CollectionMonitors)
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
              "",
              //"${DateFormat('yyyy-MM-dd – kk:mm').format(session['start_time'].toDate())}\n${vehicle}\n${reg}\n\nAre you sure?",
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
  double? _getVehicleFuelConsumptiomById(String vehicleId) {
    dynamic fuel = _vehicles?.firstWhere(
          (vehicle) => vehicle['vehicle_id'] == vehicleId,
      orElse: () => {'fuelConsumption': 0}, // Default if not found
    )['fuelConsumption'];

    if(fuel is double){
      return fuel;
    }
    else if(fuel is int){
      return fuel.toDouble();
    }
    else{
      throw Exception("Value from firestore not double or int");
    }
  }
  Future<void> _pickDateFrom() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateFrom ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && picked != _selectedDateFrom) {
      setState(() {
        _selectedDateFrom = picked;
      });
    }
  }
  Future<void> _pickDateTo() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTo ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && picked != _selectedDateTo) {
      setState(() {
        _selectedDateTo = picked;
      });
    }
  }
  Future<void> _sendReportToEmail (String email) async{
    final subject = Uri.encodeComponent('Tracking Report');
    final body = Uri.encodeComponent('Here is your requested tracking report.');
    final uri = Uri.parse('mailto:$email?subject=$subject&body=$body');

    // if (await canLaunchUrl(uri)) {
    // await launchUrl(uri);
    // } else {
    // throw 'Could not launch $uri';
    // }
    MyGlobalSnackBar.show('Email sent');
  }
  void emailReport(BuildContext context) {
    final TextEditingController emailTextController = TextEditingController();

    showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(
              color: Colors.blue, // Border color
              width: 2, // Border width
            ),
          ),
          backgroundColor: APP_TILE_COLOR,
          shadowColor: Colors.black,
          title: Text('Email Address',
            style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: emailTextController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Enter Email Address',
              hintText: 'example@email.com'
            ),
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              child:
              Text('Cancel',style:
                TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: Text('Send',
                style: TextStyle(color: Colors.grey),),
              onPressed: (){
                Navigator.pop(context);
                _sendReportToEmail(emailTextController.text.trim());
              }
            ),
          ],
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
        foregroundColor: Colors.white,

        actions: [
          Row(
            children: [
              // Date from
              Text(_selectedDateFrom.toLocal().toString().split(' ')[0]),
              IconButton(
                icon: const Icon(
                  Icons.date_range,
                  size: 30,
                  color: Colors.grey,
                ),
                onPressed: () {
                  _pickDateFrom();
                },
              ),

              SizedBox(width: 2),

              // Date To
              Text(_selectedDateTo.toLocal().toString().split(' ')[0]),
              IconButton(
                icon: const Icon(
                  Icons.date_range,
                  size: 30,
                  color: Colors.grey,
                ),
                onPressed: () {
                  _pickDateTo();
                },
              ),
            ],
          )
        ],
      ),
      body: Container(
        color: APP_BACKGROUND_COLOR,
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection(CollectionUsers)
              .doc(_auth.currentUser!.uid)
              .collection(CollectionTrackingSessions)
              .where('start_time', isGreaterThanOrEqualTo: Timestamp.fromDate(_selectedDateFrom))
              .where('start_time', isLessThanOrEqualTo: Timestamp.fromDate(_selectedDateTo))
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

            // Calculate totals
            for (var session in sessions) {
              final vehicleId = session['vehicle_id'];
              final distanceInside = (session['distance_inside'] ?? 0).toDouble();
              final vehicleConsumption = _getVehicleFuelConsumptiomById(vehicleId) ?? 0;
              final rebate = settings.fireSettings?.rebateValuePerLiter ?? 0;
              double litersUsed = 0.0;
              double thisRebate = 0;

              if (vehicleConsumption > 0) {
                litersUsed = distanceInside / vehicleConsumption;
                thisRebate = litersUsed * rebate;
              }

              _totalRebate += thisRebate;
              _totalKM += distanceInside;
              _totalLiters += litersUsed;
            }

            return _vehicles == null
                ? Center(child: CircularProgressIndicator())
                :

            Column(
              children: [
                MyTextTileWithEditDelete(
                  text: 'Total',
                  subtext:
                      'Total Rebate: R${nrFormatter.format(_totalRebate)}\n'
                      'Total Distance: ${nrFormatter.format(_totalKM)}km\n'
                      'Total Liters: ${nrFormatter.format(_totalLiters)}L',

                  onTapReport: (){
                     emailReport(context);
                  },
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {

                        var session = sessions[index];
                        String vehicleName = _getVehicleNameById(session['vehicle_id']) ?? "Unknown Vehicle";
                        String vehicleReg = _getVehicleRegById(session['vehicle_id']) ?? "Unknown";
                        double vehicleConsumption = _getVehicleFuelConsumptiomById(session['vehicle_id']) ?? 0;
                        double rebate = settings.fireSettings?.rebateValuePerLiter ?? 0;
                        double insideKM = session['distance_inside'];
                        double outsideKM = session['distance_outside'];
                        double litersUsed = 0.0;

                        if(vehicleConsumption > 0){
                          litersUsed =  insideKM / vehicleConsumption;
                        }

                          return Column(
                            children: [
                              SizedBox(height: 20),

                              MyTextTileWithEditDelete(
                                text: DateFormat('yyyy-MM-dd (kk:mm) ').format(session['start_time'].toDate()),
                                subtext:
                                  //'ID: ${session.id}\n'
                                  'Vehicle: $vehicleName\n'
                                  'Reg: $vehicleReg\n'
                                  'Inside: ${nrFormatter.format(insideKM)} km\n'
                                  'Outside: ${nrFormatter.format(outsideKM)} km\n'
                                  'Liters Used: ${nrFormatter.format(litersUsed)} L\n'
                                  'Rebate: R${nrFormatter.format(litersUsed * rebate)}\n',

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

                              SizedBox(height: 1)
                            ],
                          );
                        },
                                  ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
