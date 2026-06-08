
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
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

  Widget _buildBody(AsyncSnapshot<QuerySnapshot<Object?>> iotSnapshot){
    if (iotSnapshot.connectionState == ConnectionState.waiting ) {
      return Center(child: MyProgressCircle());
    }

    if (!iotSnapshot.hasData || iotSnapshot.data!.docs.isEmpty) {
      return Column(
        children: [
          const Expanded(
            child: Center(
              child: MyText(
                text: "No Data",
                color: Colors.grey,
              ),
            ),
          ),
        ],
      );
    }

    Map<String, Map<String, dynamic>> summaries = {};

    var monitorSettings = context.watch<MonitorSettingsService>().lstMonitors;
    if (monitorSettings.isEmpty) {
      return Center(child: MyProgressCircle());
    }

    for (var doc in iotSnapshot.data!.docs) {
      String monId = doc.get(fireIotMonDocId);

      MonitorSettings? monitor;
      try {
        monitor = monitorSettings.firstWhere((x) => x.monDocId == monId);
      } catch (e) {
        continue; // Skip logs for monitors that don't exist in settings
      }

      double dist = 0.0;
      num lines = 0;
      try {
        dist = doc.get(fireIotDistance) ?? 0.0;
        lines = doc.get(fireIotLines) ?? 0;
      } catch (e) {
        printMsg('$e');
      }

      if (!summaries.containsKey(monId)) {
        summaries[monId] = {
          'name': monitor.monitorName,
          'totalDistance': 0.0,
          'totalLines': 0,
          'logCount': 0,
          'image': monitor.imageURL  ?? "",
          'logs': [], // Store logs if you want to pass them to the next page
        };
      }

      summaries[monId]!['totalDistance'] += (dist * lines);
      summaries[monId]!['totalLines'] += lines;
      summaries[monId]!['logCount'] += 1;
      summaries[monId]!['logs'].add(doc);
    }

    // Convert map values to a list for the ListView
    var summaryList = summaries.values.toList();

    return  Column(
      children: [
        Expanded(
          child: ListView.builder(
              itemCount: summaryList.length,
              itemBuilder: (context, index) {
                var iotSummary = summaryList[index];

                String image = iotSummary['image'] ?? "";
                String monId = summaries.keys.elementAt(index);

                var actualMonitor = monitorSettings.firstWhere(
                        (m) => m.monDocId == monId,
                    orElse: () => monitorSettings.first // Fallback to first if not found
                );

                return Column(
                  children: [
                    SizedBox(height: 20),

                    MyTextTileWithEditDelete(
                      image: image.isNotEmpty
                          ? CachedNetworkImageProvider(image)
                          : getMonitorImage(actualMonitor),
                      header: iotSummary['name'],
                      subtext:
                      'Logs: ${iotSummary['logCount']}\n'
                          'Lines: ${iotSummary['totalLines']}\n'
                          'Total: ${iotSummary['totalDistance'].toInt()} m',
                      headerColor: Colors.white,
                      textColor: Colors.grey,
                      gradient: LinearGradient(colors: [Colors.blueGrey,Colors.grey]),

                      onTapTile: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => IotDataLogsPage(
                            monitor: actualMonitor,
                            snapshot: iotSummary['logs'].cast<QueryDocumentSnapshot>(),
                            userDocId: FirebaseAuth.instance.currentUser?.uid ,
                          )),
                        );
                      },
                    ),

                    SizedBox(height: 1)
                  ],
                );
              }
            //);
            //},
          ),
        ),
      ],
    );
  }
  Widget _buildDateSelector(){
    return  Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Date from
            MyText(text: _selectedDateFrom.toLocal().toString().split(' ')[0]),
            IconButton(
              icon: const Icon(
                Icons.date_range,
                size: 30,
                color: Colors.white,
              ),
              onPressed: () {
                _pickDateFrom();
              },
            ),

            SizedBox(width: 10),

            // Date To
            MyText(text: _selectedDateTo.toLocal().toString().split(' ')[0]),
            IconButton(
              icon: const Icon(
                Icons.date_range,
                size: 30,
                color: Colors.white,
              ),
              onPressed: () {
                _pickDateTo();
              },
            ),
          ],
        ),
      ),
    );
}

  @override
  Widget build(BuildContext context) {
    var dateFromToday = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    var dateToToday = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: MyAppbarTitle('iOT Data'),
          backgroundColor: colorAppBar,
          foregroundColor: Colors.white,
          bottom: TabBar(
              labelColor: Colors.white,
              indicatorColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: "Today"),
                Tab(text: "By Date"),
              ]
          ),
        ),
        body: TabBarView(
          children: [

            // Today
            Container(
              color: colorAppBackground,
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                  .collectionGroup(collectionIotData)
                  .where(mqttJsonUserDocId, isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                  .where(fireIotTimestamp, isGreaterThanOrEqualTo: Timestamp.fromDate(dateFromToday))
                  .where(fireIotTimestamp, isLessThanOrEqualTo: Timestamp.fromDate(dateToToday))
                  .orderBy(fireIotTimestamp, descending: true)
                  .snapshots(),

              builder: (context, iotSnapshot) {
                 return _buildBody(iotSnapshot);
                },
              ),
            ),

            // By Date
            Container(
              color: colorAppBackground,
              child: Column(
                children: [
                  _buildDateSelector(),

                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream:_firestore
                          .collectionGroup(collectionIotData)
                          .where(mqttJsonUserDocId, isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                          .where(
                            fireIotTimestamp, isGreaterThanOrEqualTo: Timestamp.fromDate(
                            DateTime(_selectedDateFrom.year, _selectedDateFrom.month, _selectedDateFrom.day))
                          )
                          .where(
                            fireIotTimestamp, isLessThanOrEqualTo: Timestamp.fromDate(
                            DateTime(_selectedDateTo.year, _selectedDateTo.month, _selectedDateTo.day, 23, 59, 59))
                          )
                          .orderBy(fireIotTimestamp, descending: true)
                          .snapshots(),

                      builder: (context, iotSnapshot) => _buildBody(iotSnapshot)
                    ),
                  ),
                ],
              ),
            ),
          ]
        ),
      ),
    );
  }
}
