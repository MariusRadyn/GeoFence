
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
            Container(
              color: colorAppBackground,
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                  .collectionGroup(collectionIotData)
                  .where(mqttJsonUserDocId, isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                  .where(
                      fireIotTimestamp, isGreaterThanOrEqualTo: Timestamp.fromDate(
                      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
                    )
                  )
                  .where(
                      fireIotTimestamp, isLessThanOrEqualTo: Timestamp.fromDate(
                      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59)
                    )
                  )
                  .orderBy(fireIotTimestamp, descending: true)
                  .snapshots(),

                builder: (context, iotSnapshot) {
                  if (iotSnapshot.connectionState == ConnectionState.waiting ) {
                    return Center(child: MyProgressCircle());
                  }

                  if (!iotSnapshot.hasData || iotSnapshot.data!.docs.isEmpty) {
                    return Column(
                      children: [
                        _buildDateSelector(),
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

                  var iotData = iotSnapshot.data!.docs;
                  // if (monitors.isEmpty) {
                  //   return const Center(
                  //     child: MyText(
                  //       text: "No Data",
                  //       color: Colors.grey,
                  //     ),
                  //   );
                  // }

                  return  Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: iotData.length,
                          itemBuilder: (context, index) {
                            var iot = iotData[index];

                                // Get Summary
                                double total = 0;
                                //double distance = 0;
                                num totalLines = 0;

                                // iotData.forEach((doc) {
                                //   double dist = doc.get(fireMonitorLogDistance) ?? 0.0;
                                //   num lines = doc.get(fireMonitorLogLines) ?? 0;
                                //
                                //   total += dist * lines;
                                //   totalLines += lines;
                                // });

                                String iotName = iot.get(fireIotMonName);
                                String nrOfItems = iotData.length.toString();
                                //String date = DateFormat('yyyy-MM-dd (kk:mm) ').format(monitorData[fireMonitorLastLogTimestamp].toDate());

                                String image;
                                String img = iot.get(fireMonitorImage);
                                img.isEmpty ? image = iconWheel : image = img;

                                return Column(
                                  children: [
                                    SizedBox(height: 20),

                                    MyTextTileWithEditDelete(
                                      image: image,
                                      header: '$iotName',
                                      subtext: 'Logs: $nrOfItems\nLines: $totalLines\nTotal: ${total.toInt()} m',
                                      headerColor: Colors.white,
                                      textColor: Colors.grey,
                                      gradient: LinearGradient(colors: [Colors.blueGrey,Colors.grey]),

                                      onTapTile: (){
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => IotDataLogsPage(
                                            monitorName: iot[fireMonitorName],
                                            image: image,
                                            snapshot: iotData,
                                            userDocId: FirebaseAuth.instance.currentUser?.uid ,
                                            monDocId: iot.id,
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
                },
              ),
            ),

            Container(
              child: Text('Hi'),
            )
            // Container(
            //   color: colorAppBackground,
            //   child: StreamBuilder<QuerySnapshot>(
            //     stream:
            //     _firestore
            //         .collectionGroup(collectionIotData)
            //         .where(mqttJsonUserDocId, isEqualTo: FirebaseAuth.instance.currentUser?.uid) // <--- Filter by User
            //         .where(fireMonitorLogTimestamp, isGreaterThanOrEqualTo: Timestamp.fromDate(
            //         DateTime(_selectedDateFrom.year, _selectedDateFrom.month, _selectedDateFrom.day)
            //     ))
            //         .where(fireMonitorLogTimestamp, isLessThanOrEqualTo: Timestamp.fromDate(
            //         DateTime(_selectedDateTo.year, _selectedDateTo.month, _selectedDateTo.day, 23, 59, 59)
            //     ))
            //         .orderBy(fireMonitorLogTimestamp, descending: true)
            //         .snapshots(),
            //
            //     builder: (context, monitorSnapshot) {
            //       if (monitorSnapshot.connectionState == ConnectionState.waiting ) {
            //         return Center(child: MyProgressCircle());
            //       }
            //
            //       if (!monitorSnapshot.hasData || monitorSnapshot.data!.docs.isEmpty) {
            //         return Column(
            //           children: [
            //             _buildDateSelector(),
            //             const Expanded(
            //               child: Center(
            //                 child: MyText(
            //                   text: "No Data",
            //                   color: Colors.grey,
            //                 ),
            //               ),
            //             ),
            //           ],
            //         );
            //       }
            //
            //       var iotdata = monitorSnapshot.data!.docs;
            //
            //       return  Column(
            //         children: [
            //           _buildDateSelector(),
            //
            //           Expanded(
            //             child: ListView.builder(
            //               itemCount: iotdata.length,
            //               itemBuilder: (context, index) {
            //                 var monitorData = iotdata[index];
            //
            //                 //return StreamBuilder<QuerySnapshot>(
            //                 //     stream: monitorData.reference
            //                 //         .collection(collectionIotData)
            //                 //         .snapshots(),
            //                 //     builder: (context, iotSnapshot){
            //
            //                       // if (!iotSnapshot.hasData) {
            //                       //   return ListTile(title: Text("Loading..."));
            //                       // }
            //                       //
            //                       // final iotData = iotSnapshot.data!.docs;
            //
            //                       // Get Summary
            //                       double total = 0;
            //                       num totalLines = 0;
            //
            //                       iotdata.forEach((doc) {
            //                         double dist = doc.get(fireMonitorLogDistance) ?? 0.0;
            //                         num lines = doc.get(fireMonitorLogLines) ?? 0;
            //
            //                         total += dist * lines;
            //                         totalLines += lines;
            //                       });
            //
            //                       //String iotName = monitorData.get(fireMonitorLogName);
            //                 String monId = monitorData.get([fireMonitorId]);
            //                 String nrOfItems = iotdata.length.toString();
            //                 String date = DateFormat('yyyy-MM-dd (kk:mm) ').format(monitorData[fireMonitorLastLogTimestamp].toDate());
            //
            //                       String image;
            //                       String img = monitorData.get(fireMonitorImage);
            //                       img.isEmpty ? image = iconWheel : image = img;
            //
            //                       return Column(
            //                         children: [
            //                           SizedBox(height: 20),
            //
            //                           MyTextTileWithEditDelete(
            //                             image: image,
            //                             header: 'iot name',
            //                             subtext: 'Logs: $nrOfItems\nLines: $totalLines\nTotal: ${total.toInt()} m',
            //                             headerColor: Colors.white,
            //                             textColor: Colors.grey,
            //                             gradient: LinearGradient(colors: [Colors.blueGrey,Colors.grey]),
            //
            //                             onTapTile: (){
            //                               Navigator.push(
            //                                 context,
            //                                 MaterialPageRoute(builder: (context) => IotDataLogsPage(
            //                                   monitorName: 'monitor name',
            //                                   image: image,
            //                                   snapshot: iotdata,
            //                                   userDocId: FirebaseAuth.instance.currentUser?.uid ,
            //                                   monDocId: monId,
            //                                 )),
            //                               );
            //                             },
            //                           ),
            //
            //                           SizedBox(height: 1)
            //                      ],
            //                 );
            //               }
            //             ),
            //           ),
            //         ],
            //       );
            //     },
            //   ),
            // ),

          ]
        ),
      ),
    );
  }
}
