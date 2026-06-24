
//import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
//import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class IotDataLogsPage extends StatefulWidget {
  final String? userDocId;
  final MonitorSettings monitor;
  final Stream<QuerySnapshot> streamIotData;

  const IotDataLogsPage({
    required this.userDocId,
    required this.streamIotData,
    required this.monitor,
    super.key
  });


  @override
  State<IotDataLogsPage> createState() => IotDataLogsPageState();
}

class IotDataLogsPageState extends State<IotDataLogsPage> {
  late SettingsService settings;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final nrFormatter = NumberFormat('0.00', 'en_US');
  
  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = context.read<SettingsService>();
  }

  void _delete(String desc, String? userDocId, String? monDocId, String iotDocId) async {
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
            backgroundColor: colorAppTitle,
            shadowColor: Colors.black,
            title: const Text(
              "Delete",
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              desc,
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
                _firestore
                  .collection(collectionUsers)
                  .doc(userDocId)
                  .collection(collectionMonitors)
                  .doc(monDocId)
                  .collection(collectionIotData)
                  .doc(iotDocId)
                  .delete();

                  Navigator.pop(context);
                }
              ),
            ],
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        title: MyText(text: widget.monitor.monitorName, fontsize: 18,),
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Profile Pic
              Padding(
                padding: const EdgeInsets.only( right: 10, top: 2, bottom: 2),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white,
                        width: 0.5),
                    // Clean white border
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white,
                    backgroundImage: widget.monitor.imageURL != null && widget.monitor.imageURL!.isNotEmpty
                        ? CachedNetworkImageProvider(widget.monitor.imageURL!)
                        : getMonitorImage(widget.monitor),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      // body: Container(
      //   color: colorAppBackground,
      //   child:  ListView.builder(
      //     itemCount: widget.snapshot.length,
      //     itemBuilder: (context, index) {
      //       var monitorData = widget.snapshot[index];
      //       return Column(
      //         children: [
      //           MyTextTileWithEditDelete(
      //             header: monitorData[fireIotTimestamp].toDate().toString(),
      //             subtext: 'Operator: ${monitorData[fireIotOperator]}\nSupervisor: ${monitorData[fireIotSupervisor]}\nLines: ${monitorData[fireIotLines]}\nDistance: ${monitorData[fireIotDistance]} m',
      //             headerColor: Colors.white,
      //             textColor: Colors.white,
      //             backgroundColor: colorAppBar,
      //             onTapDelete: () {
      //               _delete('${widget.monitor.monitorName}\n${monitorData[fireIotTimestamp].toDate().toString()}', widget.userDocId, widget.monitor.monDocId, monitorData.id);
      //             },
      //           ),
      //         ],
          // stream: 
          // _firestore
          //   .collection(collectionUsers).doc(FirebaseAuth.instance.currentUser?.uid)
          //   .collection(collectionMonitors).doc(widget.monitor.monDocId)
          //   .collection(collectionIotData)
          //   .snapshots(),
      // builder: (context, monitorSnapshot) {
          //   if (monitorSnapshot.connectionState == ConnectionState.waiting ) {
          //   return Center(child: MyProgressCircle());
          // }
           // var docs = monitorSnapshot.data!.docs;

      body: Container(
        color: colorAppBackground,
        child:  StreamBuilder<QuerySnapshot>(
          stream: widget.streamIotData,
          builder: (context, monitorSnapshot) {
            if (monitorSnapshot.connectionState == ConnectionState.waiting ) {
            return Center(child: MyProgressCircle());
          }
            var docs = monitorSnapshot.data!.docs;

            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var monitorData = docs[index];

                      String operator = monitorData[fireIotOperator];
                      String sup = monitorData[fireIotSupervisor];
                      num nrOfItems = monitorData[fireIotLines];
                      String date = DateFormat('yyyy-MM-dd (kk:mm) ').format(monitorData[fireMonitorTimestamp].toDate());
                      String dist = monitorData[fireIotDistance].toStringAsFixed(2);

                      // ignore: unused_local_variable
                      String image;
                      String img = widget.monitor.imageURL ?? '';
                      img.isEmpty ? image = iconWheel : image = img;

                      return Column(
                        children: [
                          SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: MySlidableTile(
                              header: date,
                              subtext: 'Operator: $operator\nSupervisor: $sup\nLines: $nrOfItems\nDistance: $dist m',
                              onTapDelete: () {
                                _delete(
                                  '${widget.monitor.monitorName}\n$date', 
                                  widget.userDocId, 
                                  widget.monitor.monDocId, 
                                  monitorData.id
                                );
                              },
                         
                            ),
                          ),
                     
                          
                        ],
                      );
                    }
                  ),
                ),
              ],
            );
          }
        ),
      ),  
    );
  } 
}
