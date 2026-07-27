import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/network_avatar.dart';
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
                    
                      final String img = (iotData['image'] as String?) ?? '';
                      final bool hasOperatorPhoto = img.isNotEmpty;

                      return Column(
                        children: [
                          SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: MyTextTileWithEditDelete(
                              // Android: CachedNetworkImageProvider via [image]
                              // Web: NetworkAvatar via [imageWidget]
                              image: kIsWeb
                                  ? null
                                  : (hasOperatorPhoto
                                      ? CachedNetworkImageProvider(img)
                                          as ImageProvider
                                      : getMonitorImage(widget.monitor)),
                              imageWidget: kIsWeb
                                  ? (hasOperatorPhoto
                                      ? NetworkAvatar(
                                          imageUrl: img,
                                          size: 80,
                                        )
                                      : Image(
                                          image: getMonitorImage(widget.monitor),
                                          fit: BoxFit.cover,
                                        ))
                                  : null,
                              header: opName,
                              subtext:
                                'Distance: ${nrFormatter.format(totalDistance)} m\n'
                                'Rate: R${nrFormatter.format(rate)}\n'
                                'Logs: $logs\n'
                                'Total: R${nrFormatter.format(cost)}',
                              headerColor: Colors.white,
                              textColor: Colors.grey,
                              backgroundColor: colorAppBar,
                              onTapTile: (){},
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
