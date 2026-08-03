import 'package:cloud_firestore/cloud_firestore.dart';
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
    super.key,
  });

  @override
  State<WagesLogsPage> createState() => WagesLogsPageState();
}

class WagesLogsPageState extends State<WagesLogsPage> {
  late SettingsService settings;
  final nrFormatter = NumberFormat('0.00', 'en_US');
  Map<String, Map<String, dynamic>> summary = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = context.read<SettingsService>();
  }

  void createSummaryWages(
    QueryDocumentSnapshot doc,
    OperatorService operatorService,
    MonitorSettingsService monitors,
  ) {
    final monId = '${doc.get(fireIotMonDocId) ?? ''}';
    final monitor = monitors.getMonitorById(monId);
    if (monitor == null || monitor.monitorType != monitorTypeWheel) return;

    final opId = '${doc.get(fireIotOperatorDocId) ?? ''}';
    final operator = operatorService.getOperatorById(opId);

    double dist = 0.0;
    num lines = 0;
    num ticks = 0;
    final double rate = operator?.rate ?? 0.0;
    double total = 0;

    try {
      lines = doc.get(fireIotLines) ?? 0;
      ticks = doc.get(fireIotTicks) ?? 0;
      if (monitor.ticksPerM != 0) {
        dist = lines * (ticks / monitor.ticksPerM);
      }
      total = dist * rate;
    } catch (e) {
      printDebugMsg('$e');
    }

    final String key = operator?.docId.isNotEmpty == true
        ? operator!.docId
        : (opId.isNotEmpty ? opId : 'unknown');
    final String opName = operator == null
        ? 'Unknown Operator'
        : '${operator.name} ${operator.surname}'.trim();

    if (!summary.containsKey(key)) {
      summary[key] = {
        'name': opName.isEmpty ? 'Unknown Operator' : opName,
        'monitor': monitor.monitorType ?? '',
        'totalDistance': 0.0,
        'cost': 0.0,
        'logs': 0,
        'rate': rate,
        'image': operator?.imageURL ?? '',
        'imageFilename': operator?.imageFilename ?? '',
      };
    } else {
      // Keep photo in sync when OperatorService gets a live Firestore update.
      summary[key]!['image'] = operator?.imageURL ?? summary[key]!['image'];
      summary[key]!['imageFilename'] =
          operator?.imageFilename ?? summary[key]!['imageFilename'];
      summary[key]!['rate'] = rate;
      if (opName.isNotEmpty) summary[key]!['name'] = opName;
    }

    summary[key]!['totalDistance'] += dist;
    summary[key]!['cost'] += total;
    summary[key]!['logs']++;
  }

  @override
  Widget build(BuildContext context) {
    final operatorService = context.watch<OperatorService>();
    final monitorService = context.watch<MonitorSettingsService>();

    return Scaffold(
      backgroundColor: colorAppBackground,
      appBar: AppBar(
        title: MyText(text: 'Wages Logs', fontsize: 18),
        backgroundColor: colorAppBar,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: colorAppBackground,
        child: StreamBuilder<QuerySnapshot>(
          stream: widget.streamIotData,
          builder: (context, iotSnapshot) {
            if (iotSnapshot.hasError) {
              return Center(
                child: MyText(
                  text: 'Error loading wages',
                  color: Colors.grey,
                ),
              );
            }

            if (iotSnapshot.connectionState == ConnectionState.waiting) {
              return Center(child: myProgressCircle());
            }

            if (monitorService.lstMonitors.isEmpty) {
              return Center(child: myProgressCircle());
            }

            summary.clear();
            for (final doc in iotSnapshot.data?.docs ?? const []) {
              if (!doc.exists) continue;
              try {
                createSummaryWages(doc, operatorService, monitorService);
              } catch (e) {
                printDebugMsg('$e');
              }
            }

            final summaryList = summary.values.toList()
              ..sort((a, b) =>
                  '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));

            if (summaryList.isEmpty) {
              return const Center(
                child: MyText(
                  text: 'No Data',
                  color: Colors.grey,
                ),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: summaryList.length,
                    itemBuilder: (context, index) {
                      final iotData = summaryList[index];

                      final String opName = iotData['name'] ?? '';
                      final double totalDistance =
                          (iotData['totalDistance'] as num).toDouble();
                      final int logs = (iotData['logs'] as num?)?.toInt() ?? 0;
                      final double cost =
                          (iotData['cost'] as num?)?.toDouble() ?? 0.0;
                      final double rate =
                          (iotData['rate'] as num?)?.toDouble() ?? 0.0;

                      final String img = '${iotData['image'] ?? ''}';
                      final String imgFile =
                          '${iotData['imageFilename'] ?? ''}';
                      final bool hasOperatorPhoto = img.isNotEmpty;

                      return Column(
                        children: [
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: MyTextTileWithEditDelete(
                              image: null,
                              imageWidget: hasOperatorPhoto
                                  ? NetworkAvatar(
                                      imageUrl: img,
                                      version: imgFile,
                                      size: 80,
                                    )
                                  : Image.asset(
                                      iconProfile,
                                      fit: BoxFit.cover,
                                      width: 80,
                                      height: 80,
                                    ),
                              header: opName,
                              subtext:
                                  'Distance: ${nrFormatter.format(totalDistance)} m\n'
                                  'Rate: R${nrFormatter.format(rate)}\n'
                                  'Logs: $logs\n'
                                  'Total: R${nrFormatter.format(cost)}',
                              headerColor: Colors.white,
                              textColor: Colors.grey,
                              backgroundColor: colorAppBar,
                              onTapTile: () {},
                            ),
                          ),
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
