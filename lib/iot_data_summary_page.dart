
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geofence/iot_data_logs_page.dart';
import 'package:geofence/network_avatar.dart';
import 'package:geofence/utils.dart';
import 'package:intl/intl.dart';
//import 'trackingHistoryMap.dart';
import 'package:provider/provider.dart';

class IotDataPage extends StatefulWidget {
  const IotDataPage({super.key});

  @override
  State<IotDataPage> createState() => IotDataPageState();
}

class IotDataPageState extends State<IotDataPage> {
  late SettingsService settings;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final nrFormatter = NumberFormat('0.00', 'en_US');
  DateTime _selectedDateFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDateTo = DateTime.now();

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  DateTime _endOfDayExclusive(DateTime date) =>
      _startOfDay(date).add(const Duration(days: 1));
  Stream<QuerySnapshot> _iotDataStream(DateTime from, DateTime to) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    final DateTime rangeStart = _startOfDay(from);
    final DateTime rangeEndExclusive = _endOfDayExclusive(to);

    return _firestore
        .collectionGroup(collectionIotData)
        .where(mqttJsonUserDocId, isEqualTo: uid)
        .where(
          fireIotTimestamp,
          isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
        )
        .where(
          fireIotTimestamp,
          isLessThan: Timestamp.fromDate(rangeEndExclusive),
        )
        .orderBy(fireIotTimestamp, descending: true)
        .snapshots();
  }

  /// Logs for one monitor only (used when opening [IotDataLogsPage]).
  Stream<QuerySnapshot> _iotDataStreamForMonitor(
    DateTime from,
    DateTime to,
    MonitorSettings monitor,
  ) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || monitor.baseStationDocId.isEmpty) {
      return const Stream.empty();
    }
    final DateTime rangeStart = _startOfDay(from);
    final DateTime rangeEndExclusive = _endOfDayExclusive(to);

    return userMonitorRef(uid, monitor.baseStationDocId, monitor.monDocId)
        .collection(collectionIotData)
        .where(
          fireIotTimestamp,
          isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
        )
        .where(
          fireIotTimestamp,
          isLessThan: Timestamp.fromDate(rangeEndExclusive),
        )
        .orderBy(fireIotTimestamp, descending: true)
        .snapshots();
  }

  // Summaries
  Map<String, Map<String, dynamic>> summaryWheel = {};
  
  @override
  void initState() {
    super.initState();
    _loadSavedDateRange();
  }

  Future<void> _loadSavedDateRange() async {
    final saved = await DateRangePreferences.load(prefDateRangeIotData);
    if (!mounted) return;
    if (saved.from != null && saved.to != null) {
      setState(() {
        _selectedDateFrom = saved.from!;
        _selectedDateTo = saved.to!;
      });
    }
  }

  Future<void> _saveDateRange() async {
    await DateRangePreferences.save(
      prefDateRangeIotData,
      _selectedDateFrom,
      _selectedDateTo,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = context.read<SettingsService>();
  }

  Future<void> _pickDateFrom() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateFrom,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && picked != _selectedDateFrom) {
      setState(() {
        _selectedDateFrom = picked;
        if (_selectedDateFrom.isAfter(_selectedDateTo)) {
          _selectedDateTo = picked;
        }
      });
      await _saveDateRange();
    }
  }
  Future<void> _pickDateTo() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTo,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && picked != _selectedDateTo) {
      setState(() {
        _selectedDateTo = picked;
        if (_selectedDateTo.isBefore(_selectedDateFrom)) {
          _selectedDateFrom = picked;
        }
      });
      await _saveDateRange();
    }
  }
  
  // Summaries
  void createSummaryWheel(QueryDocumentSnapshot doc, MonitorSettings monitor){
      double dist = 0.0;
      num lines = 0;
      num ticks = 0;

      try {
        lines = doc.get(fireIotLines) ?? 0;
        ticks = doc.get(fireIotTicks) ?? 0;
        dist = lines * (ticks / monitor.ticksPerM);
      } 
      catch (e) {
        printDebugMsg('$e');
      }

      if (!summaryWheel.containsKey(monitor.monDocId)) {
        summaryWheel[monitor.monDocId] = {
          'name': monitor.monitorName,
          'totalDistance': 0.0,
          'totalLines': 0,
          'logCount': 0,
                      'image': monitor.imageURL  ?? "",
          'imageFilename': monitor.imageFilename ?? "",
        };
      }

      summaryWheel[monitor.monDocId]!['totalDistance'] += (dist);
      summaryWheel[monitor.monDocId]!['totalLines'] += lines;
      summaryWheel[monitor.monDocId]!['logCount'] += 1;
  }

  Widget _buildWheelMonitorLog(List<MonitorSettings> lstMonitorSettings,DateTime fromDate, DateTime toDate){

    // Convert map values to a list for the ListView
    var summaryList = summaryWheel.values.toList();

     return  Column(
      children: [
        Expanded(
          child: ListView.builder(
              itemCount: summaryList.length,
              itemBuilder: (context, index) {
                var iotSummary = summaryList[index];
                String image = iotSummary['image'] ?? "";
                String imageFilename = iotSummary['imageFilename'] ?? "";
                String monId = summaryWheel.keys.elementAt(index);

                var actualMonitor = lstMonitorSettings.firstWhere(
                        (m) => m.monDocId == monId,
                    orElse: () => lstMonitorSettings.first // Fallback to first if not found
                );

                final displayUrl = resolvedNetworkImageUrl(
                  image,
                  version: imageFilename,
                );

                return Column(
                  children: [
                    SizedBox(height: 20),

                    MyTextTileWithEditDelete(
                      // Android: CachedNetworkImageProvider; Web: NetworkAvatar
                      image: kIsWeb
                          ? null
                          : (displayUrl.isNotEmpty
                              ? CachedNetworkImageProvider(displayUrl)
                                  as ImageProvider
                              : getMonitorImage(actualMonitor)),
                      imageWidget: kIsWeb
                          ? (displayUrl.isNotEmpty
                              ? NetworkAvatar(
                                  imageUrl: image,
                                  version: imageFilename,
                                  size: 80,
                                )
                              : Image(
                                  image: getMonitorImage(actualMonitor),
                                  fit: BoxFit.cover,
                                ))
                          : null,
                      header: iotSummary['name'],
                      subtext:
                        'Logs: ${iotSummary['logCount']}\n'
                        'Lines: ${iotSummary['totalLines']}\n'
                        'Total: ${iotSummary['totalDistance'].toInt()} m',
                      headerColor: Colors.white,
                      textColor: Colors.grey,
                      backgroundColor: colorAppBar,
                     
                      onTapTile: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => IotDataLogsPage(
                            monitor: actualMonitor,
                            streamIotData: _iotDataStreamForMonitor(
                              fromDate,
                              toDate,
                              actualMonitor,
                            ),
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
  Widget _buildBody(AsyncSnapshot<QuerySnapshot<Object?>> iotSnapshot, DateTime fromDate, DateTime toDate){
    if (iotSnapshot.connectionState == ConnectionState.waiting ) {
      return Center(child: myProgressCircle());
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

    var lstMonitorSettings = context.watch<MonitorSettingsService>().lstMonitors;
    if (lstMonitorSettings.isEmpty) {
      return Center(child: myProgressCircle());
    }
 
    // Create Summary  
    summaryWheel.clear();
    
    for (var doc in iotSnapshot.data!.docs) {
      String monId = doc.get(fireIotMonDocId);

      MonitorSettings? monitor;
      try {
        monitor = lstMonitorSettings.firstWhere((x) => x.monDocId == monId);
      } 
      catch (e) {
        continue; // Skip logs for monitors that don't exist in settings
      }
      
      if(monitor.monitorType == monitorTypeWheel) createSummaryWheel(doc, monitor);
    }

      // Distance Wheel Monitor
      if(summaryWheel.isNotEmpty){
         return _buildWheelMonitorLog(lstMonitorSettings, fromDate, toDate);
      }
      else{
        return Container();
      }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateTime.now();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              myAppbarTitle('iOT Data'),
              MyText(text: DateTime.now().toLocal().toString().split(' ')[0]),
            ],
          ),
          backgroundColor: colorAppBar,
          foregroundColor: Colors.white,
          bottom: TabBar(
              labelColor: Colors.white,
              indicatorColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: "Today"),
                Tab(text: "Month"),
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
                key: const ValueKey('iot-data-today'),
                stream: _iotDataStream(today, today),
                builder: (context, iotSnapshot) => _buildBody(iotSnapshot, today, today),
              ),
            ),

            // Month
            Container(
              color: colorAppBackground,
              child: StreamBuilder<QuerySnapshot>(
                key: const ValueKey('iot-data-month'),
                stream: _iotDataStream(DateTime(today.year, today.month, 1), today),
                builder: (context, iotSnapshot) => _buildBody(iotSnapshot, DateTime(today.year, today.month, 1), today),
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
                      key: ValueKey(
                        'iot-data-range-'
                        '${_selectedDateFrom.year}-${_selectedDateFrom.month}-${_selectedDateFrom.day}-'
                        '${_selectedDateTo.year}-${_selectedDateTo.month}-${_selectedDateTo.day}',
                      ),
                      stream: _iotDataStream(_selectedDateFrom, _selectedDateTo),
                      builder: (context, iotSnapshot) => _buildBody(iotSnapshot, _selectedDateFrom, _selectedDateTo),
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
