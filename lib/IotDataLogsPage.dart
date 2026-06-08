
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class IotDataLogsPage extends StatefulWidget {
  final String? userDocId;
  //final String? monDocId;
  //final String monitorName;
  //final String image;
  final MonitorSettings monitor;
  final List<QueryDocumentSnapshot<Object?>> snapshot;

  const IotDataLogsPage({
    required this.userDocId,
    //required this.monDocId,
    //required this.monitorName,
    //required this.image,
    required this.snapshot,
    required this.monitor,
    super.key
  });


  @override
  State<IotDataLogsPage> createState() => _IotDataLogsPageState();
}

class _IotDataLogsPageState extends State<IotDataLogsPage> {
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
                    // Total size remains ~20 with the border
                    backgroundColor: colorIceBlue,
                    backgroundImage: widget.monitor.imageURL != null
                        ? CachedNetworkImageProvider(widget.monitor.imageURL!)
                        : getMonitorImage(widget.monitor),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        color: colorAppBackground,
        child:  StreamBuilder<QuerySnapshot>(
          stream: _firestore
            .collection(collectionUsers).doc(FirebaseAuth.instance.currentUser?.uid)
            .collection(collectionMonitors).doc(widget.monitor.monDocId)
            .collection(collectionIotData)
            .snapshots(),

          builder: (context, monitorSnapshot) {
            if (monitorSnapshot.connectionState == ConnectionState.waiting ) {
            return Center(child: MyProgressCircle());
          }
            var docs = monitorSnapshot.data!.docs;

            return Column(
              children: [
                // Stack(
                //   children: [
                //     // Backdrop
                //     Container(
                //       alignment: Alignment.topCenter,
                //       height: 120,
                //       decoration: const BoxDecoration(
                //         gradient: LinearGradient(
                //           begin: Alignment.topLeft,
                //           end: Alignment.bottomRight,
                //           stops: [0.3, 0.9],
                //           colors: [Colors.blueGrey, colorAppBackground],
                //         ),
                //         borderRadius: BorderRadius.only(
                //           bottomLeft: Radius.circular(100),
                //           bottomRight: Radius.circular(100),
                //         ),
                //       ),
                //     ),
                //
                //     // Avatar
                //     Padding(
                //       padding: const EdgeInsets.only(top: 8.0),
                //       child: Center(
                //         child: Column(
                //           mainAxisAlignment: MainAxisAlignment.center,
                //           crossAxisAlignment: CrossAxisAlignment.center,
                //           children: [
                //             GestureDetector(
                //               onTap: () {
                //                 // Navigation logic could go here
                //               },
                //               child: CircleAvatar(
                //                 radius: 35,
                //                 backgroundColor: Colors.white,
                //                 child: CircleAvatar(
                //                   backgroundImage: AssetImage(widget.image),
                //                   radius: 34,
                //                 ),
                //               ),
                //             ),
                //           ],
                //         ),
                //       ),
                //     ),
                //
                //     // Heading
                //     Center(
                //       child: Container(
                //         padding: const EdgeInsets.only(top: 80),
                //         child: MyText(
                //           text:widget.monitorName,
                //           fontsize: 20,
                //           color: Colors.grey,
                //         ),
                //       ),
                //     ),
                //   ],
                // ),

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

                      String image;
                      String img = widget.monitor.imageURL ?? '';
                      img.isEmpty ? image = iconWheel : image = img;

                      return Column(
                        children: [
                          SizedBox(height: 20),

                          MyTextTileWithEditDelete(
                            header: date,
                            subtext: 'Operator: $operator\nSupervisor: $sup\nLines: $nrOfItems\nDistance: $dist m',
                            headerColor: Colors.white,
                            textColor: Colors.white,
                            gradient: LinearGradient(colors: [Colors.blueGrey,colorAppBackground]),
                            height: 130,

                            onTapDelete: (){
                               _delete('${widget.monitor.monitorName}\n$date', widget.userDocId, widget.monitor.monDocId, monitorData.id);
                            },
                          ),

                          SizedBox(height: 1)
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
