
//import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
//import 'package:geofence/iot_data_logs_page.dart';
import 'package:geofence/utils.dart';
import 'package:geofence/wages_logs_page.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class WagesPage extends StatefulWidget {
  const WagesPage({super.key});

  @override
  State<WagesPage> createState() => WagesPageState();
}

class WagesPageState extends State<WagesPage> {
  late SettingsService settings;
  late OperatorService operators;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
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

  // Summaries
  Map<String, Map<String, dynamic>> summaryWages = {};
  
  @override
  void initState() {
    super.initState();
    _loadSavedDateRange();
  }

  Future<void> _loadSavedDateRange() async {
    final saved = await DateRangePreferences.load(prefDateRangeWages);
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
      prefDateRangeWages,
      _selectedDateFrom,
      _selectedDateTo,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    settings = context.read<SettingsService>();
    operators = context.read<OperatorService>();
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
  void createSummaryWages(QueryDocumentSnapshot doc, MonitorSettings monitor) {
    double dist = 0.0;
    num lines = 0;
    num ticks = 0;
    double total = 0;

    final operator = operators.getOperatorById(doc.get(fireIotOperatorDocId) ?? '');

    try {
      lines = doc.get(fireIotLines) ?? 0;
      ticks = doc.get(fireIotTicks) ?? 0;
      dist = lines * (ticks / monitor.ticksPerM);
      final rate = operator?.rate ?? 0;
      total = dist * rate;
    } catch (e) {
      printDebugMsg('$e');
    }

    if(monitor.monitorType == null) return;

    if (!summaryWages.containsKey(monitor.monitorType)) {
      summaryWages[monitor.monitorType!] = {
        'logs': 0,
        'totalDistance': 0.0,
        'cost': 0.0,
      };
    }

    summaryWages[monitor.monitorType!]!['logs']++;
    summaryWages[monitor.monitorType!]!['totalDistance'] += dist;
    summaryWages[monitor.monitorType!]!['cost'] += total;
  }


  Widget _buildWheelWages(List<MonitorSettings> lstMonitorSettings,DateTime fromDate, DateTime toDate){
  
    // Convert map values to a list for the ListView
    var summaryList = summaryWages.values.toList();

     return  Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: summaryList.length,
            itemBuilder: (context, index) {
              var iotSummary = summaryList[index];

              var actualMonitor = lstMonitorSettings.firstWhere(
                      (m) => m.monitorType == monitorTypeWheel,
                  orElse: () => lstMonitorSettings.first // Fallback to first if not found
              );

              return Column(
                children: [
                  SizedBox(height: 20),

                  MyTextTileWithEditDelete(
                    image: AssetImage(iconWheel),
                    header: 'Distance Wheel',
                    subtext:
                      'Distance: ${iotSummary['totalDistance'].toInt()} m\n'
                      'Logs: ${iotSummary['logs'].toInt()}\n'
                      'Total: R${nrFormatter.format(iotSummary['cost'])}',
                    headerColor: Colors.white,
                    textColor: Colors.grey,
                    backgroundColor: colorAppBar,
                    
                    onTapTile: (){
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => WagesLogsPage(
                          monitor: actualMonitor,
                          streamIotData: _iotDataStream(fromDate, toDate),
                          userDocId: FirebaseAuth.instance.currentUser?.uid ,
                        )),
                      );
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
    summaryWages.clear();
    for (var doc in iotSnapshot.data!.docs) {
      String monId = doc.get(fireIotMonDocId);

      MonitorSettings? monitor;
      try {
        monitor = lstMonitorSettings.firstWhere((x) => x.monDocId == monId);
      } 
      catch (e) {
        continue; // Skip logs for monitors that don't exist in settings
      }
      
      if(monitor.monitorType == monitorTypeWheel) createSummaryWages(doc, monitor);
    }

    // Distance Wheel Monitor
    if(summaryWages.isNotEmpty){
         return _buildWheelWages(lstMonitorSettings, fromDate, toDate);
    }
    // Nothing
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
              myAppbarTitle('Wages'),
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
