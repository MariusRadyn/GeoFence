//import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
//import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/network_avatar.dart';
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
  final nrFormatter = NumberFormat('0.00', 'en_US');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = context.read<SettingsService>();
  }

  String _operatorLabel(OperatorService operators, dynamic rawId) {
    final op = operators.getOperatorById('${rawId ?? ''}');
    if (op == null) return '';
    return '${op.name} ${op.surname}'.trim();
  }

  bool _belongsToMonitor(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    final monId = '${data?[fireIotMonDocId] ?? ''}';
    if (monId != widget.monitor.monDocId) return false;

    final monitorBaseId = widget.monitor.baseStationDocId;
    if (monitorBaseId.isEmpty) return true;

    final docBaseId = '${data?[fireIotBaseStationDocId] ?? ''}';
    final pathBaseId = baseStationDocIdFromMonitorPath(doc.reference.path);
    if (docBaseId.isNotEmpty && docBaseId != monitorBaseId) return false;
    if (pathBaseId != null &&
        pathBaseId.isNotEmpty &&
        pathBaseId != monitorBaseId) {
      return false;
    }
    return true;
  }

  void _delete(String desc, DocumentReference docRef) async {
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
                  await docRef.delete();
                  if (context.mounted) Navigator.pop(context);
                }
              ),
            ],
          );
        }
    );
  }

  Widget _monitorAppBarAvatar() {
    final hasPhoto = widget.monitor.imageURL != null &&
        widget.monitor.imageURL!.isNotEmpty;
    if (kIsWeb) {
      return hasPhoto
          ? NetworkCircleAvatar(
              imageUrl: widget.monitor.imageURL,
              version: widget.monitor.imageFilename,
              radius: 18,
              backgroundColor: Colors.white,
            )
          : CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              backgroundImage: getMonitorImage(widget.monitor),
            );
    }
    final url = resolvedNetworkImageUrl(
      widget.monitor.imageURL,
      version: widget.monitor.imageFilename,
    );
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.white,
      backgroundImage: hasPhoto
          ? CachedNetworkImageProvider(url) as ImageProvider
          : getMonitorImage(widget.monitor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final operatorService = context.watch<OperatorService>();
    final hasPhoto = widget.monitor.imageURL != null &&
        widget.monitor.imageURL!.isNotEmpty;
    final imgUrl = widget.monitor.imageURL ?? '';
    final imgFile = widget.monitor.imageFilename ?? '';
    final displayUrl = resolvedNetworkImageUrl(imgUrl, version: imgFile);

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
              Padding(
                padding: const EdgeInsets.only( right: 10, top: 2, bottom: 2),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white,
                        width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _monitorAppBarAvatar(),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        color: colorAppBackground,
        child:  StreamBuilder<QuerySnapshot>(
          stream: widget.streamIotData,
          builder: (context, iotSnapshot) {
            if (iotSnapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: MyText(
                    text: 'Could not load IoT data:\n${iotSnapshot.error}',
                    color: Colors.orangeAccent,
                  ),
                ),
              );
            }
            if (iotSnapshot.connectionState == ConnectionState.waiting ||
                operatorService.isLoading) {
              return Center(child: myProgressCircle());
            }
            if (!iotSnapshot.hasData) {
              return const Center(
                child: MyText(text: 'No Data', color: Colors.grey),
              );
            }
            final docs = iotSnapshot.data!.docs
                .whereType<QueryDocumentSnapshot>()
                .where(_belongsToMonitor)
                .toList();
            if (docs.isEmpty) {
              return const Center(
                child: MyText(text: 'No Data', color: Colors.grey),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var iotData = docs[index];

                      final operatorLabel = _operatorLabel(
                        operatorService,
                        iotData.get(fireIotOperatorDocId),
                      );
                      final supervisorLabel = _operatorLabel(
                        operatorService,
                        iotData.get(fireIotSupervisorDocId),
                      );
                    
                      num lines = iotData.get(fireIotLines) ?? 0;
                      String date = DateFormat('yyyy-MM-dd (kk:mm) ').format(iotData.get(fireIotTimestamp)?.toDate() ?? DateTime.now());
                      String dist = (lines * (iotData.get(fireIotTicks) / widget.monitor.ticksPerM)).toStringAsFixed(2);

                      return Column(
                        children: [
                          SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: MySlidableTile(
                              // Android: CachedNetworkImageProvider; Web: NetworkAvatar
                              image: kIsWeb
                                  ? null
                                  : (hasPhoto
                                      ? CachedNetworkImageProvider(displayUrl)
                                          as ImageProvider
                                      : getMonitorImage(widget.monitor)),
                              imageWidget: kIsWeb
                                  ? (hasPhoto
                                      ? NetworkAvatar(
                                          imageUrl: imgUrl,
                                          version: imgFile,
                                          size: 56,
                                        )
                                      : Image(
                                          image: getMonitorImage(widget.monitor),
                                          fit: BoxFit.cover,
                                        ))
                                  : null,
                              header: date,
                              subtext: 'Operator: $operatorLabel\nSupervisor: $supervisorLabel\nLines: $lines\nDistance: $dist m',
                              onTapDelete: () {
                                _delete(
                                  '${widget.monitor.monitorName}\n$date',
                                  iotData.reference,
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
