
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/IotDataLogsPage.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'trackingHistoryMap.dart';
import 'package:provider/provider.dart';

class IotDataPage extends StatefulWidget {
  const IotDataPage({super.key});

  @override
  State<IotDataPage> createState() => _IotDataPageState();
}

class _IotDataPageState extends State<IotDataPage> {
  late SettingsService settings;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final nrFormatter = NumberFormat('0.00', 'en_US');
  List<Map<String, dynamic>>? _vehicles = [];
  DateTime _selectedDateFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDateTo = DateTime(DateTime.now().year, DateTime.now().month + 1, 0, );


  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = context.read<SettingsService>();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorAppBar,
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
        color: colorAppBackground,
        child: StreamBuilder<QuerySnapshot>(
          stream:
          _firestore
              .collection(collectionUsers).doc(FirebaseAuth.instance.currentUser?.uid)
              .collection(collectionMonitors)
              .where(fireMonitorLastLogTimestamp, isGreaterThanOrEqualTo: Timestamp.fromDate(_selectedDateFrom))
              .where(fireMonitorLastLogTimestamp, isLessThanOrEqualTo: Timestamp.fromDate(_selectedDateTo))
              .orderBy(fireMonitorLastLogTimestamp, descending: true)
              .snapshots(),

          builder: (context, monitorSnapshot) {
            if (monitorSnapshot.connectionState == ConnectionState.waiting ) {
              return Center(child: MyProgressCircle());
            }

            if (!monitorSnapshot.hasData || monitorSnapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text(
                  "No IOT History Data",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 20,
                  ),
                ),
              );
            }

            var monitors = monitorSnapshot.data!.docs;
            if (monitors.isEmpty) {
              return const Center(
                child: Text(
                  "No IOT History Data",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 20,
                  ),
                ),
              );
            }

            return  Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: monitors.length,
                    itemBuilder: (context, index) {
                      var monitorData = monitors[index];

                      return StreamBuilder<QuerySnapshot>(
                        stream: monitorData.reference
                            .collection(collectionMonitorData)
                            .snapshots(),
                        builder: (context, iotSnapshot){

                          if (!iotSnapshot.hasData) {
                            return ListTile(title: Text("Loading..."));
                          }

                          final iotData = iotSnapshot.data!.docs;

                          // Get Summary
                          double distance = 0;
                          num lines = 0;

                          iotData.forEach((doc) {
                            distance += doc.get(fireMonitorLogDistance) ?? 0.0;
                            lines += doc.get(fireMonitorLogLines) ?? 0;
                          });

                          String iotName = monitorData[fireMonitorLogName];
                          String nrOfItems = iotData.length.toString();
                          String date = DateFormat('yyyy-MM-dd (kk:mm) ').format(monitorData[fireMonitorLastLogTimestamp].toDate());
                          String dist = distance.toStringAsFixed(2);

                          String image;
                          String img = monitorData[fireMonitorImage];
                          img.isEmpty ? image = imageWheel : image = img;

                          return Column(
                            children: [
                              SizedBox(height: 20),

                              MyTextTileWithEditDelete(
                                image: image,
                                header: '$iotName',
                                subtext: 'Logs: $nrOfItems\nDistance: $dist m\nLines: $lines',
                                headerColor: Colors.white,
                                textColor: Colors.white,
                                gradient: LinearGradient(colors: [Colors.blueGrey,Colors.grey]),
                                height: 150,

                                onTapTile: (){
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => IotDataLogsPage(
                                      monitorName: monitorData[fireMonitorName],
                                      image: image,
                                      snapshot: iotData,
                                      userDocId: FirebaseAuth.instance.currentUser?.uid ,
                                      monDocId: monitorData.id,
                                    )),
                                  );
                                },
                              ),

                              SizedBox(height: 1)
                            ],
                          );
                        }
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
