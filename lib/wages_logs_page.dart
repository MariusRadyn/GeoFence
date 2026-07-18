import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class WagesLogsPage extends StatefulWidget {
  final String? userDocId;
  final MonitorSettings monitor;
  final Stream<QuerySnapshot> streamIotData;

  const WagesLogsPage({
    required this.userDocId,
    required this.streamIotData,
    required this.monitor,
    super.key
  });


  @override
  State<WagesLogsPage> createState() => WagesLogsPageState();
}

class WagesLogsPageState extends State<WagesLogsPage> {
  late SettingsService settings;
  //final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final nrFormatter = NumberFormat('0.00', 'en_US');
  late OperatorService operatorService;
  Map<String, Map<String, dynamic>> summary = {};

  @override
  void initState() {
    super.initState(); 
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = context.read<SettingsService>();
    operatorService = context.read<OperatorService>();
  }

  // void _delete(String desc, String? userDocId, String? monDocId, String iotDocId) async {
  //   showDialog(
  //       context: context,
  //       builder: (context){
  //         return AlertDialog(
  //           shape: RoundedRectangleBorder(
  //             borderRadius: BorderRadius.circular(10),
  //             side: const BorderSide(
  //               color: Colors.blue, // Border color
  //               width: 2, // Border width
  //             ),
  //           ),
  //           backgroundColor: colorAppTitle,
  //           shadowColor: Colors.black,
  //           title: const Text(
  //             "Delete",
  //             style: TextStyle(color: Colors.white),
  //           ),
  //           content: Text(
  //             desc,
  //             //"${DateFormat('yyyy-MM-dd – kk:mm').format(session['start_time'].toDate())}\n${vehicle}\n${reg}\n\nAre you sure?",
  //             style: const TextStyle(
  //               color: Colors.grey,
  //               fontSize: 18,
  //             ),
  //           ),
  //           actions: [
  //             TextButton(
  //               child: const Text(
  //                 'No',
  //                 style: TextStyle(
  //                   color:  Colors.white,
  //                   fontFamily: "Poppins",
  //                   fontSize: 20,
  //                 ),
  //               ),
  //               onPressed: () => Navigator.pop(context),
  //             ),
  //             TextButton(
  //               child: const Text(
  //                 'Yes',
  //                 style: TextStyle(
  //                   color:  Colors.white,
  //                   fontFamily: "Poppins",
  //                   fontSize: 20,
  //                 ),
  //               ),
  //               onPressed: () async {
  //               _firestore
  //                 .collection(collectionUsers)
  //                 .doc(userDocId)
  //                 .collection(collectionMonitors)
  //                 .doc(monDocId)
  //                 .collection(collectionIotData)
  //                 .doc(iotDocId)
  //                 .delete();

  //                 Navigator.pop(context);
  //               }
  //             ),
  //           ],
  //         );
  //       }
  //   );
  // }
  
  // Summaries
  void createSummaryWages(QueryDocumentSnapshot doc) {
    double dist = 0.0;
    num lines = 0;
    num ticks = 0;
    double total = 0;

    final operator = operatorService.getOperatorById(doc.get(fireIotOperatorDocId) ?? '');
    final monitor = context.read<MonitorSettingsService>().getMonitorById(doc.get(fireIotMonDocId) ?? '');
    if (operator == null || monitor == null) return;

    try {
      lines = doc.get(fireIotLines) ?? 0;
      ticks = doc.get(fireIotTicks) ?? 0;
      dist = lines * (ticks / monitor.ticksPerM);
      final rate = operator.rate;
      total = dist * rate;
    } catch (e) {
      printDebugMsg('$e');
    }

    String monType = monitor.monitorType ?? "";
    String opName = operator.name;
    String opSurname = operator.surname;
    
    if (!summary.containsKey(operator.docId)) {
      summary[operator.docId] = {
          'name': '$opName $opSurname',
          'monitor': monType,
          'totalDistance': 0.0,
          'cost': 0.0,
          'logs': 0,
          'rate':operator.rate,
          'image': operator.imageURL ?? '',
      };
    }

    summary[operator.docId]!['totalDistance'] += dist;
    summary[operator.docId]!['cost'] += total;
    summary[operator.docId]!['logs'] ++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        title: MyText(text: 'Wages Logs', fontsize: 18,),
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
       
      ),
   
      body: Container(
        color: colorAppBackground,
        child:  StreamBuilder<QuerySnapshot>(
          stream: widget.streamIotData,
          builder: (context, iotSnapshot) {
            if (iotSnapshot.connectionState == ConnectionState.waiting ) {
              return Center(child: myProgressCircle());
            }

            //var docs = iotSnapshot.data!.docs;
            
            var lstMonitorSettings = context.watch<MonitorSettingsService>().lstMonitors;
            if (lstMonitorSettings.isEmpty) {
              return Center(child: myProgressCircle());
            }
 
            // Create Summary
            summary.clear();
            
            for (var doc in iotSnapshot.data!.docs) {
              if(doc.exists) {       
                try {
                  final MonitorSettings? monitor = context.read<MonitorSettingsService>().getMonitorById(doc.get(fireIotMonDocId) ?? '');
      
                  if(monitor != null && monitor.monitorType == monitorTypeWheel) createSummaryWages(doc);
                } 
                catch (e) {
                  continue; // Skip logs for monitors that don't exist in settings
                }
              }
            }
             
            var summaryList = summary.values.toList();

            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: summary.length,
                    itemBuilder: (context, index) {
                      var iotData = summaryList[index];

                      String opName = iotData['name'] ?? '';
                      double totalDistance =  iotData['totalDistance'].toDouble();
                      int logs = iotData['logs'] ?? 0;
                      double cost = iotData['cost'] ?? 0.0;
                      double rate = iotData['rate'] ?? 0.0;
                    
                      // ignore: unused_local_variable
                      String image;
                      String img = iotData['image'] ?? '';
                      img.isEmpty ? image = iconWheel : image = img;

                      return Column(
                        children: [
                          SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child:    MyTextTileWithEditDelete(
                            image: image.isNotEmpty
                                ? CachedNetworkImageProvider(image)
                                : getMonitorImage(widget.monitor),
                            header: opName,
                            subtext:
                              'Distance: ${nrFormatter.format(totalDistance)} m\n'
                              'Rate: R${nrFormatter.format(rate)}\n'
                              'Logs: $logs\n'
                              'Total: R${nrFormatter.format(cost)}',
                            headerColor: Colors.white,
                            textColor: Colors.grey,
                            backgroundColor: colorAppBar,
                          
                            onTapTile: (){
                              
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
